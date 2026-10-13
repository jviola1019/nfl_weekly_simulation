/**
 * The offline local app (A8): `npm run local` starts it, `npm run local:stop` stops the database.
 *
 * Idempotent, and needs no network once `npm ci` has run:
 *   1. a private PostgreSQL cluster in <repo>/.local/pgdata (NFL_LOCAL_PGDATA), on
 *      127.0.0.1 only, port 5434 (NFL_LOCAL_PGPORT), scram auth with a random password;
 *   2. DATABASE_URL and a random AUTH_SECRET appended to web/.env.local only if absent;
 *   3. the cluster started, the nfl_local database created, the migrations applied;
 *   4. every bundle under <repo>/bundles (NFL_LOCAL_BUNDLES) ingested, oldest first, so the
 *      newest weekly run is the one published (ingest is idempotent on the bundle sha).
 *      run_week.R writes the weekly bundles; `Rscript scripts/write_backtest_bundle.R`
 *      writes the backtest bundle the evidence page reads;
 *   5. next build only when there is no build or a source is newer; then
 *      next start -H 127.0.0.1 -p 3000.
 * The password lives in the cluster directory and web/.env.local (both gitignored) and is
 * never printed. PG_BIN points at PostgreSQL's bin directory (default on Windows:
 * C:/Program Files/PostgreSQL/17/bin; elsewhere: PATH).
 */
import { spawn, spawnSync, type SpawnSyncOptions } from "node:child_process";
import { randomBytes } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";
import * as schema from "../src/db/schema";
import { BundleRejected, ingestBundle, loadBundle } from "../src/lib/ingest/ingest";
import {
  APP_HOST,
  APP_PORT,
  databaseUrl,
  envAdditions,
  missingPointers,
  needsBuild,
  parseCredentials,
  parseEnvFile,
  pgExecutable,
  redactUrl,
  resolveLocalConfig,
  runPgTool,
  selectBundleDirs
} from "./local/config";
import { discoverBundles } from "./local/discover";

const WEB = fileURLToPath(new URL("..", import.meta.url));
const cfg = resolveLocalConfig(process.env, process.platform, join(WEB, ".."));
const pg = (name: string) => pgExecutable(cfg.pgBin, name, process.platform);
const nextBin = () => createRequire(import.meta.url).resolve("next/dist/bin/next");

function run(file: string, args: string[], opts: SpawnSyncOptions = {}): number {
  const r = spawnSync(file, args, { stdio: "inherit", ...opts });
  if (r.error) throw new Error(`${file}: ${r.error.message}`);
  return r.status ?? 1;
}

/** Run a PostgreSQL tool; a missing executable is reported as such (runPgTool). */
const pgTool = (tool: string, args: string[], opts: SpawnSyncOptions) => runPgTool((f, a, o) => spawnSync(f, a, o as SpawnSyncOptions), tool, pg(tool), args, opts);

/** pg_ctl status: 0 = running, 3 = stopped, 4 = no cluster */
const clusterStatus = () => pgTool("pg_ctl", ["status", "-D", cfg.pgData], { stdio: "ignore" });

/** Create the cluster on first use; return its password. */
function ensureCluster(): string {
  if (existsSync(join(cfg.pgData, "PG_VERSION"))) {
    if (!existsSync(cfg.credentialsFile)) {
      throw new Error(
        `${cfg.pgData} holds a cluster that npm run local did not create (no nfl_local_credentials.json). ` +
          "Set NFL_LOCAL_PGDATA to another directory, or delete that one: every bundle is ingested again."
      );
    }
    return parseCredentials(readFileSync(cfg.credentialsFile, "utf8"), cfg.credentialsFile);
  }
  mkdirSync(dirname(cfg.pgData), { recursive: true });
  const password = randomBytes(24).toString("base64url");
  const pwfile = join(tmpdir(), `nfl-local-${process.pid}-${randomBytes(4).toString("hex")}`);
  writeFileSync(pwfile, password, { mode: 0o600 });
  try {
    const r = spawnSync(pg("initdb"), ["-D", cfg.pgData, "-U", cfg.dbUser, `--pwfile=${pwfile}`, "--auth=scram-sha-256", "-E", "UTF8", "--no-locale"], { encoding: "utf8" });
    runPgTool(() => r, "initdb", pg("initdb"), []);
    if (r.status !== 0) throw new Error(`initdb failed (exit ${r.status}):\n${r.stderr}`);
  } finally {
    rmSync(pwfile, { force: true });
  }
  appendFileSync(join(cfg.pgData, "postgresql.conf"), "\n# npm run local: loopback only, no Unix socket\nlisten_addresses = '127.0.0.1'\nunix_socket_directories = ''\n");
  writeFileSync(cfg.credentialsFile, JSON.stringify({ user: cfg.dbUser, password }), { mode: 0o600 });
  console.log(`created a local PostgreSQL cluster in ${cfg.pgData}`);
  return password;
}

/** Append DATABASE_URL and AUTH_SECRET to web/.env.local if absent; return the AUTH_SECRET to use. */
function ensureEnvLocal(url: string): string {
  const text = existsSync(cfg.envFile) ? readFileSync(cfg.envFile, "utf8") : "";
  const existing = parseEnvFile(text);
  const authSecret = existing.AUTH_SECRET ?? randomBytes(32).toString("base64");
  const add = envAdditions(existing, { DATABASE_URL: url, AUTH_SECRET: authSecret });
  if (add.length) {
    appendFileSync(cfg.envFile, `${text && !text.endsWith("\n") ? "\n" : ""}# written by npm run local\n${add.join("\n")}\n`, { mode: 0o600 });
    console.log(`web/.env.local: added ${add.map((l) => l.split("=")[0]).join(" and ")}`);
  }
  if (existing.DATABASE_URL && existing.DATABASE_URL !== url) {
    console.log(`note: web/.env.local sets its own DATABASE_URL; npm run local serves from ${redactUrl(url)}`);
  }
  return authSecret;
}

function startCluster() {
  if (clusterStatus() === 0) return console.log(`PostgreSQL already running (127.0.0.1:${cfg.pgPort})`);
  // stdio ignored: on Windows an inherited pipe would keep this process waiting on the server
  const code = pgTool("pg_ctl", ["start", "-D", cfg.pgData, "-l", cfg.serverLog, "-w", "-t", "60", "-o", `-p ${cfg.pgPort}`], { stdio: "ignore" });
  if (code !== 0) {
    const tail = existsSync(cfg.serverLog) ? readFileSync(cfg.serverLog, "utf8").split(/\r?\n/).slice(-15).join("\n") : "";
    throw new Error(`pg_ctl start failed (exit ${code}). Is port ${cfg.pgPort} free? NFL_LOCAL_PGPORT changes it.\n${tail}`);
  }
  console.log(`PostgreSQL started on 127.0.0.1:${cfg.pgPort}`);
}

async function ensureDatabase(password: string) {
  const admin = postgres(databaseUrl(cfg, password, "postgres"), { max: 1, onnotice: () => {} });
  try {
    const found = await admin`select 1 from pg_database where datname = ${cfg.dbName}`;
    if (!found.length) {
      await admin.unsafe(`create database ${cfg.dbName}`);
      console.log(`created database ${cfg.dbName}`);
    }
  } finally {
    await admin.end({ timeout: 5 });
  }
}

async function migrateAndIngest(url: string) {
  const client = postgres(url, { max: 1, onnotice: () => {} });
  try {
    await migrate(drizzle(client), { migrationsFolder: join(WEB, "drizzle") });
    console.log("migrations applied");
    const db = drizzle(client, { schema });
    const found = discoverBundles(cfg.bundlesDir);
    if (found.strayManifest) {
      console.log(`note: ${join(cfg.bundlesDir, "manifest.json")} is a bundle outside a cycle directory and is not ingested; move its files into ${join(cfg.bundlesDir, "<cycle_id>")}`);
    }
    const { ingest, skipped } = selectBundleDirs(found.entries);
    for (const name of skipped) console.log(`skipped    ${name}: no readable manifest.json`);
    if (!ingest.length) console.log(`no bundles in ${cfg.bundlesDir}`);
    let rejected = 0;
    for (const name of ingest) {
      try {
        const bundle = loadBundle(join(cfg.bundlesDir, name));
        const res = await ingestBundle(db, bundle);
        console.log(`${res.status.padEnd(10)} ${name}`);
        if (res.status === "qa_failed") console.log(`           QA failures: ${bundle.manifest.qa.failures.join("; ")}`);
      } catch (e) {
        if (!(e instanceof BundleRejected)) throw e;
        rejected += 1;
        console.log(`rejected   ${name}: ${e.message}`);
      }
    }
    if (rejected) console.log(`${rejected} bundle(s) rejected (see above); the app serves the others`);
    const published = await db.select({ pointer: schema.publishPointers.pointer }).from(schema.publishPointers);
    for (const m of missingPointers(published.map((p) => p.pointer))) console.log(m.hint);
  } finally {
    await client.end({ timeout: 5 });
  }
}

function newestMtime(path: string): number {
  const st = statSync(path);
  if (!st.isDirectory()) return st.mtimeMs;
  return Math.max(st.mtimeMs, ...readdirSync(path).map((n) => newestMtime(join(path, n))));
}

function buildIfNeeded(env: NodeJS.ProcessEnv) {
  const buildId = join(WEB, ".next", "BUILD_ID");
  const sources = ["src", "public", "next.config.mjs", "package.json", "package-lock.json", "postcss.config.mjs", "tsconfig.json"]
    .map((p) => join(WEB, p))
    .filter((p) => existsSync(p));
  if (!needsBuild(existsSync(buildId) ? statSync(buildId).mtimeMs : null, Math.max(...sources.map(newestMtime)))) {
    return console.log("the build is current");
  }
  console.log("building the app (next build)...");
  const code = run(process.execPath, [nextBin(), "build"], { cwd: WEB, env });
  if (code !== 0) throw new Error(`next build failed (exit ${code})`);
}

function serve(env: NodeJS.ProcessEnv) {
  console.log(`\nBroadcast Line, offline: http://${APP_HOST}:${APP_PORT}\nCtrl+C stops the web server; npm run local:stop stops the database.\n`);
  const child = spawn(process.execPath, [nextBin(), "start", "-H", APP_HOST, "-p", String(APP_PORT)], { cwd: WEB, stdio: "inherit", env });
  for (const signal of ["SIGINT", "SIGTERM"] as const) process.on(signal, () => child.kill(signal));
  child.on("exit", (code) => process.exit(code ?? 0));
}

async function start() {
  const password = ensureCluster();
  const url = databaseUrl(cfg, password);
  const authSecret = ensureEnvLocal(url);
  startCluster();
  await ensureDatabase(password);
  await migrateAndIngest(url);
  const env = { ...process.env, DATABASE_URL: url, AUTH_SECRET: authSecret, NEXT_TELEMETRY_DISABLED: "1" };
  buildIfNeeded(env);
  serve(env);
}

function stop() {
  const status = clusterStatus();
  if (status === 4 || !existsSync(join(cfg.pgData, "PG_VERSION"))) return console.log(`no local cluster in ${cfg.pgData}`);
  if (status !== 0) return console.log("PostgreSQL is not running");
  const code = pgTool("pg_ctl", ["stop", "-D", cfg.pgData, "-m", "fast", "-w"], { stdio: "ignore" });
  if (code !== 0) throw new Error(`pg_ctl stop failed (exit ${code})`);
  console.log("PostgreSQL stopped");
}

const command = process.argv[2] ?? "start";
try {
  if (command === "start") await start();
  else if (command === "stop") stop();
  else {
    console.error("usage: tsx scripts/local.ts [start|stop]");
    process.exit(2);
  }
} catch (e) {
  console.error(`npm run local: ${(e as Error).message}`);
  process.exit(1);
}

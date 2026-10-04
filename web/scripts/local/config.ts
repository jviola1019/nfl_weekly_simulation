/**
 * Pure parts of the offline runner (npm run local, A8): configuration, the database URL,
 * .env.local additions, which bundles to ingest and whether to rebuild. No I/O here, so
 * every rule is unit-tested (config.test.ts); scripts/local.ts does the work.
 */
import { join } from "node:path";

export const DEFAULT_WINDOWS_PG_BIN = "C:/Program Files/PostgreSQL/17/bin";
export const DEFAULT_PG_PORT = 5434;
export const APP_HOST = "127.0.0.1";
export const APP_PORT = 3000;

export interface LocalConfig {
  repoRoot: string;
  webDir: string;
  /** null: find the PostgreSQL executables on PATH */
  pgBin: string | null;
  pgData: string;
  pgPort: number;
  dbName: string;
  dbUser: string;
  bundlesDir: string;
  envFile: string;
  credentialsFile: string;
  serverLog: string;
}

export function resolveLocalConfig(env: Record<string, string | undefined>, platform: string, repoRoot: string): LocalConfig {
  const rawPort = env.NFL_LOCAL_PGPORT?.trim();
  const pgPort = rawPort ? Number(rawPort) : DEFAULT_PG_PORT;
  if (!Number.isInteger(pgPort) || pgPort < 1024 || pgPort > 65535) {
    throw new Error(`NFL_LOCAL_PGPORT must be a whole number from 1024 to 65535 (got "${rawPort}")`);
  }
  const pgData = env.NFL_LOCAL_PGDATA?.trim() || join(repoRoot, ".local", "pgdata");
  const webDir = join(repoRoot, "web");
  return {
    repoRoot,
    webDir,
    pgBin: env.PG_BIN?.trim() || (platform === "win32" ? DEFAULT_WINDOWS_PG_BIN : null),
    pgData,
    pgPort,
    dbName: "nfl_local",
    dbUser: "nfl_local",
    bundlesDir: env.NFL_LOCAL_BUNDLES?.trim() || join(repoRoot, "bundles"),
    envFile: join(webDir, ".env.local"),
    credentialsFile: join(pgData, "nfl_local_credentials.json"),
    serverLog: join(pgData, "nfl_local_server.log")
  };
}

export function pgExecutable(pgBin: string | null, name: string, platform: string): string {
  const file = platform === "win32" ? `${name}.exe` : name;
  return pgBin ? join(pgBin, file) : file;
}

export function databaseUrl(cfg: Pick<LocalConfig, "dbUser" | "pgPort" | "dbName">, password: string, db: string = cfg.dbName): string {
  return `postgres://${cfg.dbUser}:${encodeURIComponent(password)}@127.0.0.1:${cfg.pgPort}/${db}`;
}

/** The URL with its password masked, for messages (secrets are never printed). */
export function redactUrl(url: string): string {
  return url.replace(/^(postgres(?:ql)?:\/\/[^:/@]+:)[^@]*@/, "$1***@");
}

/** KEY=value lines of a dotenv file (comments, `export` and surrounding quotes allowed). */
export function parseEnvFile(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const line of text.split(/\r?\n/)) {
    if (/^\s*#/.test(line)) continue;
    const m = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (m) out[m[1]!] = m[2]!.replace(/^(['"])(.*)\1$/, "$2");
  }
  return out;
}

/** Lines to append to .env.local: only the keys it does not already set. */
export function envAdditions(existing: Record<string, string>, wanted: Record<string, string>): string[] {
  return Object.entries(wanted)
    .filter(([key]) => !(key in existing))
    .map(([key, value]) => `${key}=${value}`);
}

export interface BundleEntry {
  name: string;
  manifest: unknown;
}

/**
 * Bundle directories to ingest, oldest first by manifest generated_utc, so the newest
 * weekly bundle is ingested last and ends up published. Directories without a readable
 * manifest are skipped and reported.
 */
export function selectBundleDirs(entries: BundleEntry[]): { ingest: string[]; skipped: string[] } {
  const stamp = (m: unknown): string | null => {
    if (typeof m !== "object" || m === null) return null;
    const r = m as Record<string, unknown>;
    return typeof r.generated_utc === "string" && typeof r.bundle_kind === "string" ? r.generated_utc : null;
  };
  const ok = entries.filter((e) => stamp(e.manifest) !== null);
  ok.sort((a, b) => stamp(a.manifest)!.localeCompare(stamp(b.manifest)!) || a.name.localeCompare(b.name));
  return {
    ingest: ok.map((e) => e.name),
    skipped: entries.filter((e) => stamp(e.manifest) === null).map((e) => e.name).sort()
  };
}

/** Publish pointers the pages read: "weekly" fills the slate and game pages, "backtest_games" /evidence. */
export const APP_POINTERS = ["weekly", "backtest_games"] as const;

const POINTER_HINTS: Record<(typeof APP_POINTERS)[number], string> = {
  weekly: "no weekly run published yet: `Rscript run_week.R <week> <season>` writes one to bundles/",
  backtest_games: "no backtest published yet, so /evidence is empty: `Rscript scripts/write_backtest_bundle.R` writes one to bundles/"
};

/**
 * What the database does not publish yet, and what writes it. Read from the database, not
 * from bundles/: the cluster keeps every run ingested in earlier sessions.
 */
export function missingPointers(published: readonly string[]): { pointer: string; hint: string }[] {
  return APP_POINTERS.filter((p) => !published.includes(p)).map((pointer) => ({ pointer, hint: POINTER_HINTS[pointer] }));
}

/** next build is needed when there is no build or any source is newer than it. */
export function needsBuild(buildIdMtimeMs: number | null, newestSourceMtimeMs: number): boolean {
  return buildIdMtimeMs === null || newestSourceMtimeMs > buildIdMtimeMs;
}

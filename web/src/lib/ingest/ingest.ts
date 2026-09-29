/**
 * Bundle ingest (spec §3 "Ingest"):
 *   1. verify every file's sha256 and row count against the manifest, and the
 *      manifest's schema major version; zod-parse every row;
 *   2. upsert in ONE transaction, idempotent on bundle_sha256 (a second ingest of
 *      the same bundle changes nothing);
 *   3. a bundle whose QA failed is stored as qa_failed and the publish pointer stays
 *      on the last known good run (NBA publish_policy);
 *   4. pages render dynamically from the database, so a committed ingest is live on
 *      the next request (no cache to revalidate).
 */
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { eq, getTableColumns, sql, type Table } from "drizzle-orm";
import type { PgTable } from "drizzle-orm/pg-core";
import type { Db } from "../../db";
import * as s from "../../db/schema";
import {
  BUNDLE_KINDS,
  BUNDLE_TABLES,
  manifestSchema,
  ROW_SCHEMAS,
  SCHEMA_MAJOR,
  schemaMajor,
  type BundleTableName,
  type Manifest
} from "../contracts/bundle";

export class BundleRejected extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BundleRejected";
  }
}

export interface LoadedBundle {
  sha256: string;
  manifest: Manifest;
  rows: Partial<Record<BundleTableName, Record<string, unknown>[]>>;
}

export interface IngestResult {
  status: "published" | "qa_failed" | "duplicate";
  runId: string;
  bundleSha256: string;
  rowsWritten: number;
}

const sha256 = (buf: Buffer | string) => createHash("sha256").update(buf).digest("hex");

/** Read and fully validate a bundle directory without touching the database. */
export function loadBundle(dir: string): LoadedBundle {
  const manifestBytes = readFileSync(join(dir, "manifest.json"));
  const parsed = manifestSchema.safeParse(JSON.parse(manifestBytes.toString("utf8")));
  if (!parsed.success) throw new BundleRejected(`manifest invalid: ${parsed.error.issues[0]?.path.join(".")} ${parsed.error.issues[0]?.message}`);
  const manifest = parsed.data;
  if (schemaMajor(manifest.schema_version) !== SCHEMA_MAJOR) {
    throw new BundleRejected(`schema major ${manifest.schema_version} is not supported (expected ${SCHEMA_MAJOR}.x)`);
  }
  const spec = BUNDLE_KINDS[manifest.bundle_kind];
  const allowed = new Set<string>([...spec.required, ...spec.optional]);
  const present = new Set(manifest.files.map((f) => f.name.replace(/\.json$/, "")));
  for (const need of spec.required) if (!present.has(need)) throw new BundleRejected(`required file ${need}.json missing`);

  const rows: LoadedBundle["rows"] = {};
  for (const file of manifest.files) {
    const name = file.name.replace(/\.json$/, "") as BundleTableName;
    if (!allowed.has(name)) throw new BundleRejected(`${file.name} is not allowed in a ${manifest.bundle_kind} bundle`);
    const bytes = readFileSync(join(dir, file.name));
    if (sha256(bytes) !== file.sha256) throw new BundleRejected(`${file.name}: sha256 does not match the manifest`);
    const data: unknown = JSON.parse(bytes.toString("utf8"));
    if (!Array.isArray(data)) throw new BundleRejected(`${file.name}: not a JSON array`);
    if (data.length !== file.rows) throw new BundleRejected(`${file.name}: ${data.length} rows, manifest says ${file.rows}`);
    const schema = ROW_SCHEMAS[name];
    rows[name] = data.map((row, i) => {
      const r = schema.safeParse(row);
      if (!r.success) {
        const issue = r.error.issues[0];
        throw new BundleRejected(`${file.name} row ${i + 1}: ${issue?.path.join(".")} ${issue?.message}`);
      }
      return r.data as Record<string, unknown>;
    });
  }
  return { sha256: sha256(manifestBytes), manifest, rows };
}

/** snake_case bundle keys -> Drizzle property names */
function toProps(table: Table, row: Record<string, unknown>, extra: Record<string, unknown> = {}) {
  const out: Record<string, unknown> = { ...extra };
  for (const [prop, column] of Object.entries(getTableColumns(table))) {
    if (column.name in row) out[prop] = row[column.name];
  }
  return out;
}

const RUN_SCOPED: BundleTableName[] = ["game_predictions", "score_distributions", "recommendations", "source_status"];
const APPEND_ONLY: BundleTableName[] = ["eval_windows", "backtest_runs", "backtest_metrics", "calibration_bins", "promotion_gates", "clv_picks"];
const UPSERT: Array<[BundleTableName, PgTable, string[]]> = [
  ["teams", s.teams, ["teamId"]],
  ["games", s.games, ["gameId"]],
  ["venues", s.venues, ["venueId"]],
  ["markets", s.markets, ["marketId"]],
  ["evidence_ledger", s.evidenceLedger, ["claimId"]]
];

export const POINTER_BY_KIND = { weekly: "weekly", backtest: "backtest_games" } as const;

export async function ingestBundle(db: Db, bundle: LoadedBundle, now: Date = new Date()): Promise<IngestResult> {
  const { manifest, sha256: bundleSha256 } = bundle;
  const runId = `${manifest.bundle_kind}:${manifest.cycle_id}:${bundleSha256.slice(0, 12)}`;

  const seen = await db.select().from(s.bundleIngests).where(eq(s.bundleIngests.bundleSha256, bundleSha256));
  if (seen.length) return { status: "duplicate", runId: seen[0]!.runId, bundleSha256, rowsWritten: 0 };

  const status = manifest.qa.ok ? "published" : "qa_failed";
  let rowsWritten = 0;
  await db.transaction(async (tx) => {
    for (const [name, table, keys] of UPSERT) {
      const rows = bundle.rows[name];
      if (!rows?.length) continue;
      const cols = getTableColumns(table);
      const set = Object.fromEntries(
        Object.keys(cols).filter((k) => !keys.includes(k)).map((k) => [k, sqlExcluded(cols[k]!.name)])
      );
      for (const chunk of chunks(rows.map((r) => toProps(table, r)), 500)) {
        await tx.insert(table).values(chunk).onConflictDoUpdate({ target: keys.map((k) => cols[k]!), set });
        rowsWritten += chunk.length;
      }
    }

    await tx.insert(s.modelRuns).values({
      runId, kind: manifest.bundle_kind, cycleId: manifest.cycle_id, season: manifest.season, week: manifest.week,
      modelLabel: manifest.model_label, codeGitSha: manifest.code_git_sha, codeDirty: manifest.code_dirty,
      configHash: manifest.config_hash, config: manifest.config, seed: manifest.seed, nSims: manifest.n_sims,
      bundleSha256, generatedUtc: manifest.generated_utc, dataAsofUtc: manifest.data_asof_utc,
      qaOk: manifest.qa.ok, qaFailures: manifest.qa.failures, status
    });
    rowsWritten += 1;

    for (const name of RUN_SCOPED) {
      const rows = bundle.rows[name];
      if (!rows?.length) continue;
      const table = BUNDLE_TABLES[name];
      for (const chunk of chunks(rows.map((r) => toProps(table, r, { runId })), 500)) {
        await tx.insert(table).values(chunk);
        rowsWritten += chunk.length;
      }
    }

    for (const name of APPEND_ONLY) {
      const rows = bundle.rows[name];
      if (!rows?.length) continue;
      const table = BUNDLE_TABLES[name];
      const extra = name === "backtest_runs" ? { runId } : {};
      for (const chunk of chunks(rows.map((r) => toProps(table, r, extra)), 500)) {
        const res = await tx.insert(table).values(chunk).onConflictDoNothing().returning();
        rowsWritten += res.length;
      }
    }

    if (status === "published") {
      const pointer = POINTER_BY_KIND[manifest.bundle_kind];
      const prev = await tx.select().from(s.publishPointers).where(eq(s.publishPointers.pointer, pointer));
      if (prev[0]) await tx.update(s.modelRuns).set({ status: "superseded" }).where(eq(s.modelRuns.runId, prev[0].runId));
      await tx
        .insert(s.publishPointers)
        .values({ pointer, runId, updatedAt: now.toISOString() })
        .onConflictDoUpdate({ target: s.publishPointers.pointer, set: { runId, updatedAt: now.toISOString() } });
    }
    await tx.insert(s.bundleIngests).values({
      bundleSha256, cycleId: manifest.cycle_id, kind: manifest.bundle_kind, runId, status, ingestedAt: now.toISOString()
    });
  });
  return { status, runId, bundleSha256, rowsWritten };
}

function* chunks<T>(xs: T[], n: number): Generator<T[]> {
  for (let i = 0; i < xs.length; i += n) yield xs.slice(i, i + n);
}

function sqlExcluded(column: string) {
  return sql.raw(`excluded."${column}"`);
}

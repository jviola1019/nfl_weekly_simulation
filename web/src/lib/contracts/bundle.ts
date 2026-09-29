/**
 * The R -> web bundle contract (spec §3). A bundle is a directory:
 *
 *   bundles/<cycle_id>/manifest.json   provenance, file hashes, QA
 *   bundles/<cycle_id>/<table>.json    an array of rows, keys = DB column names
 *
 * Row schemas are DERIVED from the Drizzle tables (drizzle-zod), never written by
 * hand, and exported to contracts/schema/*.json for the R validator. The bundle's
 * identity is the sha256 of its manifest bytes; the manifest pins every file's
 * sha256, so the hash covers the whole bundle.
 */
import { getTableColumns, type Table } from "drizzle-orm";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod";
import * as s from "../../db/schema";

export const SCHEMA_VERSION = "1.0.0";
export const SCHEMA_MAJOR = 1;

/** Tables a bundle may carry, by file name, and the ingest order (FK-safe). */
export const BUNDLE_TABLES = {
  teams: s.teams,
  games: s.games,
  venues: s.venues,
  markets: s.markets,
  game_predictions: s.gamePredictions,
  score_distributions: s.scoreDistributions,
  recommendations: s.recommendations,
  source_status: s.sourceStatus,
  eval_windows: s.evalWindows,
  backtest_runs: s.backtestRuns,
  backtest_metrics: s.backtestMetrics,
  calibration_bins: s.calibrationBins,
  promotion_gates: s.promotionGates,
  clv_picks: s.clvPicks,
  evidence_ledger: s.evidenceLedger
} as const satisfies Record<string, Table>;

export type BundleTableName = keyof typeof BUNDLE_TABLES;

/** Files each bundle kind must (and may) carry. */
export const BUNDLE_KINDS = {
  weekly: { required: ["teams", "games", "game_predictions", "source_status"], optional: ["venues", "markets", "score_distributions", "recommendations"] },
  backtest: {
    required: ["teams", "games", "eval_windows", "backtest_runs", "backtest_metrics", "calibration_bins", "promotion_gates", "evidence_ledger"],
    optional: ["clv_picks"]
  }
} as const satisfies Record<string, { required: readonly BundleTableName[]; optional: readonly BundleTableName[] }>;

export type BundleKind = keyof typeof BUNDLE_KINDS;

/**
 * drizzle-zod keys rows by the TypeScript property name (camelCase); bundles use the
 * database column name (snake_case), which is what R writes. Re-key the shape.
 * run_id is omitted: the ingest assigns it from the manifest, so R cannot forge it.
 */
const ISO_UTC = z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/, "ISO-8601 UTC");

/** Domain rules the column types cannot express, by column name. */
const PROBABILITY_COLUMNS = new Set([
  "p_home_raw", "p_home_final", "p_home_mkt_novig", "p_model", "p_mkt_novig", "p_mean", "y_mean", "p_over", "p_push"
]);
const ENUM_COLUMNS: Record<string, readonly [string, ...string[]]> = {
  tier: ["bet", "lean", "pass"],
  side: ["home", "away", "none", "over", "under", "yes", "no"],
  kind: ["sportsbook", "exchange", "consensus", "margin", "total"],
  status: ["complete", "void", "ok", "stale", "failed", "unavailable", "validated", "reproducible", "unvalidated", "withdrawn"],
  game_type: ["REG", "WC", "DIV", "CON", "SB"]
};

export function rowSchema(table: Table) {
  const insert = createInsertSchema(table) as unknown as z.ZodObject<z.ZodRawShape>;
  const columns = getTableColumns(table);
  const shape: Record<string, z.ZodType> = {};
  for (const [prop, column] of Object.entries(columns)) {
    if (column.name === "run_id") continue;
    let field = insert.shape[prop] as z.ZodType | undefined;
    if (!field) continue;
    const optional = !column.notNull || column.hasDefault;
    if (column.columnType === "PgTimestampString") {
      field = optional ? ISO_UTC.nullable().optional() : ISO_UTC;
    } else if (PROBABILITY_COLUMNS.has(column.name)) {
      const base = z.number().min(0).max(1);
      field = column.notNull ? base : base.nullable().optional();
    } else if (ENUM_COLUMNS[column.name]) {
      const base = z.enum(ENUM_COLUMNS[column.name]!);
      field = optional ? base.nullable().optional() : base;
    }
    shape[column.name] = field;
  }
  return z.strictObject(shape);
}

export const ROW_SCHEMAS = Object.fromEntries(
  Object.entries(BUNDLE_TABLES).map(([name, table]) => [name, rowSchema(table)])
) as unknown as Record<BundleTableName, z.ZodObject<z.ZodRawShape>>;

const sha256 = z.string().regex(/^[0-9a-f]{64}$/, "sha256 hex");
const isoUtc = ISO_UTC;

export const manifestSchema = z.strictObject({
  schema_version: z.string().regex(/^\d+\.\d+\.\d+$/),
  bundle_kind: z.enum(["weekly", "backtest"]),
  cycle_id: z.string().regex(/^[A-Za-z0-9_.-]{3,80}$/),
  season: z.number().int().nullable(),
  week: z.number().int().nullable(),
  model_label: z.string().min(1),
  generated_utc: isoUtc,
  data_asof_utc: isoUtc,
  code_git_sha: z.string().regex(/^[0-9a-f]{7,40}$/),
  code_dirty: z.boolean(),
  config_hash: sha256,
  config: z.record(z.string(), z.unknown()),
  seed: z.number().int().nullable(),
  n_sims: z.number().int().nullable(),
  renv_lock_sha256: sha256,
  files: z
    .array(z.strictObject({ name: z.string().regex(/^[a-z_]+\.json$/), sha256, rows: z.number().int().nonnegative() }))
    .min(1),
  qa: z.strictObject({ ok: z.boolean(), failures: z.array(z.string()) })
});

export type Manifest = z.infer<typeof manifestSchema>;

export function schemaMajor(version: string): number {
  return Number.parseInt(version.split(".")[0] ?? "", 10);
}

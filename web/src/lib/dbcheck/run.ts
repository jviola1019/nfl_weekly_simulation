/**
 * Runs the SQL data checks (./checks.ts) and reports them. Each check's query returns one
 * `detail` row per violation; the runner counts them and keeps a few sorted samples. A check
 * whose SQL fails is an error named by its id, never a silent skip.
 */
import { sql } from "drizzle-orm";
import type { Db } from "../../db";
import { DB_CHECKS, type DbCheck, type Severity } from "./checks";

/** Anything that can run a query: the database or a transaction on it. */
export type Queryable = Pick<Db, "execute">;

export interface CheckResult {
  id: string;
  severity: Severity;
  what: string;
  count: number;
  samples: string[];
}

export async function runDbChecks(db: Queryable, checks: readonly DbCheck[] = DB_CHECKS, sampleSize = 5): Promise<CheckResult[]> {
  const out: CheckResult[] = [];
  for (const check of checks) {
    let rows: Array<{ n: number; samples: string[] | null }>;
    try {
      rows = await db.execute<{ n: number; samples: string[] | null }>(
        sql`SELECT count(*)::int AS n, (array_agg(q.detail ORDER BY q.detail))[1:${Math.trunc(sampleSize)}::int] AS samples
            FROM (${check.query}) q`
      );
    } catch (e) {
      throw new Error(`db-check ${check.id}: ${e instanceof Error ? e.message : String(e)}`, { cause: e });
    }
    const row = rows[0];
    out.push({ id: check.id, severity: check.severity, what: check.what, count: row?.n ?? 0, samples: row?.samples ?? [] });
  }
  return out;
}

export function formatReport(results: CheckResult[]): { text: string; errors: number; warnings: number } {
  const violated = results.filter((r) => r.count > 0);
  const errors = violated.filter((r) => r.severity === "error").length;
  const warnings = violated.filter((r) => r.severity === "warning").length;
  const lines: string[] = [];
  for (const r of violated) {
    lines.push(`${r.severity.toUpperCase()} ${r.id} (${r.count}): ${r.what}`);
    for (const s of r.samples) lines.push(`    ${s}`);
  }
  lines.push(`db-check: ${results.length} checks, ${errors} error(s), ${warnings} warning(s)`);
  return { text: `${lines.join("\n")}\n`, errors, warnings };
}

/** Runs every check, logs the report, and returns the counts of violated error and warning checks. */
export async function reportDbChecks(db: Queryable, log: (line: string) => void = console.log): Promise<{ errors: number; warnings: number }> {
  const { text, errors, warnings } = formatReport(await runDbChecks(db));
  log(text.trimEnd());
  return { errors, warnings };
}

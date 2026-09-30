import { cpSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { eq, sql } from "drizzle-orm";
import type postgres from "postgres";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Db } from "../../db";
import * as s from "../../db/schema";
import { FIXTURE_BUNDLES, freshDb, hasDb } from "../../test/pg";
import { BundleRejected, ingestBundle, loadBundle } from "./ingest";

const WEEKLY = join(FIXTURE_BUNDLES, "weekly-2026-w04");
const BACKTEST = join(FIXTURE_BUNDLES, "backtest-nfl-games-v1");

/** Copy a bundle to a temp dir and let the caller edit it. */
function variant(src: string, edit: (dir: string) => void): string {
  const dir = mkdtempSync(join(tmpdir(), "bundle-"));
  cpSync(src, dir, { recursive: true });
  edit(dir);
  return dir;
}
const editJson = (path: string, f: (x: any) => any) => writeFileSync(path, JSON.stringify(f(JSON.parse(readFileSync(path, "utf8")))));

const COUNTED = ["teams", "games", "model_runs", "game_predictions", "recommendations", "source_status", "eval_windows",
  "backtest_runs", "backtest_metrics", "calibration_bins", "promotion_gates", "clv_picks", "evidence_ledger", "bundle_ingests"];

describe.skipIf(!hasDb)("bundle ingest (Postgres)", () => {
  let db: Db;
  let client: postgres.Sql;
  let weeklyRun = "";
  const counts = async () =>
    Object.fromEntries(await Promise.all(COUNTED.map(async (t) => [t, Number((await client.unsafe(`select count(*)::int n from "${t}"`))[0]!.n)])));
  const pointer = async (p: string) => (await db.select().from(s.publishPointers).where(eq(s.publishPointers.pointer, p)))[0]?.runId;

  beforeAll(async () => {
    ({ db, client } = await freshDb());
  });
  afterAll(async () => {
    await client?.end({ timeout: 5 });
  });

  it("publishes a weekly bundle and moves the weekly pointer", async () => {
    const r = await ingestBundle(db, loadBundle(WEEKLY));
    expect(r.status).toBe("published");
    expect(r.rowsWritten).toBeGreaterThan(100);
    weeklyRun = r.runId;
    expect(await pointer("weekly")).toBe(weeklyRun);
  });

  it("is idempotent: a second ingest of the same bundle changes 0 rows", async () => {
    const before = await counts();
    const r = await ingestBundle(db, loadBundle(WEEKLY));
    expect(r).toMatchObject({ status: "duplicate", rowsWritten: 0, runId: weeklyRun });
    expect(await counts()).toEqual(before);
  });

  it("publishes the backtest bundle on its own pointer", async () => {
    const r = await ingestBundle(db, loadBundle(BACKTEST));
    expect(r.status).toBe("published");
    expect(await pointer("backtest_games")).toBe(r.runId);
    expect(await pointer("weekly")).toBe(weeklyRun);
  });

  it("stores a QA-failed bundle as qa_failed and leaves the pointer on the last good run", async () => {
    const dir = variant(WEEKLY, (d) => editJson(join(d, "manifest.json"), (m) => ({ ...m, qa: { ok: false, failures: ["games.kickoff_utc: test failure"] } })));
    const r = await ingestBundle(db, loadBundle(dir));
    expect(r.status).toBe("qa_failed");
    expect(await pointer("weekly")).toBe(weeklyRun);
    const [run] = await db.select().from(s.modelRuns).where(eq(s.modelRuns.runId, r.runId));
    expect(run?.status).toBe("qa_failed");
  });

  it("a newer good bundle takes the pointer and supersedes the old run", async () => {
    const dir = variant(WEEKLY, (d) => editJson(join(d, "manifest.json"), (m) => ({ ...m, generated_utc: "2026-09-30T12:00:00Z" })));
    const r = await ingestBundle(db, loadBundle(dir));
    expect(r.status).toBe("published");
    expect(await pointer("weekly")).toBe(r.runId);
    const [old] = await db.select().from(s.modelRuns).where(eq(s.modelRuns.runId, weeklyRun));
    expect(old?.status).toBe("superseded");
    weeklyRun = r.runId;
  });

  it("rejects tampered bundles before touching the database", async () => {
    const before = await counts();
    const tampered = variant(WEEKLY, (d) => editJson(join(d, "games.json"), (rows) => rows.map((g: any, i: number) => (i ? g : { ...g, week: 5 }))));
    expect(() => loadBundle(tampered)).toThrow(/sha256 does not match/);
    const miscounted = variant(WEEKLY, (d) => editJson(join(d, "manifest.json"), (m) => ({ ...m, files: m.files.map((f: any) => ({ ...f, rows: f.rows + 1 })) })));
    expect(() => loadBundle(miscounted)).toThrow(/rows, manifest says/);
    const major = variant(WEEKLY, (d) => editJson(join(d, "manifest.json"), (m) => ({ ...m, schema_version: "2.0.0" })));
    expect(() => loadBundle(major)).toThrow(BundleRejected);
    const missing = variant(WEEKLY, (d) => editJson(join(d, "manifest.json"), (m) => ({ ...m, files: m.files.filter((f: any) => f.name !== "games.json") })));
    expect(() => loadBundle(missing)).toThrow(/required file games.json missing/);
    expect(await counts()).toEqual(before);
  });

  it("append-only tables refuse UPDATE and DELETE", async () => {
    for (const t of ["backtest_metrics", "eval_windows", "calibration_bins", "promotion_gates", "clv_picks", "backtest_runs"]) {
      const [{ n }] = (await client.unsafe(`select count(*)::int n from "${t}"`)) as unknown as [{ n: number }];
      expect(n, `${t} has rows to protect`).toBeGreaterThan(0);
      const [{ col }] = (await client.unsafe(
        `select column_name col from information_schema.columns where table_name = '${t}' order by ordinal_position limit 1`
      )) as unknown as [{ col: string }];
      await expect(client.unsafe(`update "${t}" set "${col}" = "${col}"`), t).rejects.toThrow(/append-only/);
      await expect(client.unsafe(`delete from "${t}"`), t).rejects.toThrow(/append-only/);
    }
  });

  it("CHECK: a recommendation is a bet exactly when it carries a stake", async () => {
    const [g] = await db.select().from(s.games).limit(1);
    const base = { runId: weeklyRun, gameId: g!.gameId, candidate: "C2", side: "home", pModel: 0.6, pMktNovig: 0.5 };
    await expect(db.insert(s.recommendations).values({ ...base, recId: "t1", tier: "bet", stakePct: 0 })).rejects.toThrow();
    await expect(db.insert(s.recommendations).values({ ...base, recId: "t2", tier: "lean", stakePct: 0.01 })).rejects.toThrow();
    await expect(db.insert(s.recommendations).values({ ...base, recId: "t3", tier: "lean", stakePct: 0 })).resolves.toBeDefined();
    await db.execute(sql`delete from recommendations where rec_id = 't3'`);
  });
});

import { join } from "node:path";
import { sql } from "drizzle-orm";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Db } from "../../db";
import { FIXTURE_BUNDLES, freshDb, hasDb } from "../../test/pg";
import { ingestBundle, loadBundle } from "../ingest/ingest";
import { DB_CHECKS, type DbCheck } from "./checks";
import { formatReport, runDbChecks, type Queryable } from "./run";

/**
 * SQL data checks (C2): on the three fixture bundles every check returns zero rows, and a row
 * planted to break one rule is reported by that rule's check. Each planted row lives in a
 * transaction that is rolled back, so the tests do not see each other's rows.
 */
const ROLLBACK = new Error("rollback");

describe.skipIf(!hasDb)("SQL data checks (Postgres)", () => {
  let db: Db;
  let end: () => Promise<void>;
  let weeklyRun: string;
  let simRun: string;
  let btRunId: string;

  beforeAll(async () => {
    const { db: tdb, client } = await freshDb();
    for (const b of ["weekly-2026-w04", "backtest-nfl-games-v1", "weekly-sim-2024-w15"]) {
      await ingestBundle(tdb, loadBundle(join(FIXTURE_BUNDLES, b)));
    }
    db = tdb;
    end = () => client.end({ timeout: 5 });
    const runs = await db.execute<{ run_id: string; cycle_id: string }>(sql`SELECT run_id, cycle_id FROM model_runs`);
    // fixture cycle ids: weekly-2026-w04 is "2026-w04-<stamp>", the simulator's is "weekly-sim-2024-w15"
    weeklyRun = runs.find((r) => r.cycle_id.startsWith("2026-w04"))!.run_id;
    simRun = runs.find((r) => r.cycle_id === "weekly-sim-2024-w15")!.run_id;
    btRunId = (await db.execute<{ bt_run_id: string }>(sql`SELECT bt_run_id FROM backtest_runs`))[0]!.bt_run_id;
  }, 60_000);
  afterAll(async () => {
    await end?.();
  });

  /** Plant rows inside a transaction, run the checks there, then roll it back. */
  async function withPlanted(plant: (tx: Queryable) => Promise<unknown>, checks: readonly DbCheck[] = DB_CHECKS) {
    let results: Awaited<ReturnType<typeof runDbChecks>> = [];
    try {
      await db.transaction(async (tx) => {
        await plant(tx);
        results = await runDbChecks(tx, checks);
        throw ROLLBACK;
      });
    } catch (e) {
      if (e !== ROLLBACK) throw e;
    }
    return results;
  }
  const count = (results: Awaited<ReturnType<typeof runDbChecks>>, id: string) => {
    const r = results.find((x) => x.id === id);
    if (!r) throw new Error(`no check ${id}`);
    return r;
  };

  it("the three fixture bundles violate no check", async () => {
    const results = await runDbChecks(db);
    expect(results.filter((r) => r.count > 0)).toEqual([]);
    expect(results.map((r) => r.id)).toEqual(DB_CHECKS.map((c) => c.id));
  });

  it("every check id is unique", () => {
    expect(new Set(DB_CHECKS.map((c) => c.id)).size).toBe(DB_CHECKS.length);
  });

  it("a distribution covering the stated mass passes, one below it fails (F7 is by design)", async () => {
    // one bin carrying all of a sum s: x 0 with p s
    const setTotal = (s: number) => (tx: Queryable) =>
      tx.execute(sql`UPDATE score_distributions SET bins = ${JSON.stringify([{ x: 0, p: s }])}::jsonb
                     WHERE run_id = ${simRun} AND game_id = '2024_15_LA_SF' AND kind = 'total'`);
    expect(count(await withPlanted(setTotal(0.9991)), "score_distributions.mass").count).toBe(0);
    const low = count(await withPlanted(setTotal(0.998)), "score_distributions.mass");
    expect(low.count).toBe(1);
    expect(low.samples[0]).toContain("2024_15_LA_SF");
    expect(low.samples[0]).toContain("total");
  });

  it("NaN and Infinity are outside [0, 1]", async () => {
    const r = await withPlanted((tx) =>
      tx.execute(sql`INSERT INTO game_predictions (run_id, game_id, candidate, p_home_final)
                     VALUES (${weeklyRun}, '2026_04_DEN_SF', 'CX', 'NaN'), (${weeklyRun}, '2026_04_DEN_SF', 'CY', 'Infinity')`)
    );
    expect(count(r, "prob.game_predictions").count).toBe(2);
  });

  it("a recommendation probability above 1 is reported", async () => {
    const r = await withPlanted((tx) =>
      tx.execute(sql`INSERT INTO recommendations (rec_id, run_id, game_id, candidate, side, p_model, stake_pct, tier)
                     VALUES ('planted', ${weeklyRun}, '2026_04_DEN_SF', 'C2', 'home', 1.5, 0, 'pass')`)
    );
    const c = count(r, "prob.recommendations");
    expect(c.count).toBe(1);
    expect(c.samples[0]).toContain("planted");
  });

  it("a prop line whose over and push sum above 1 is reported", async () => {
    const r = await withPlanted(async (tx) => {
      await tx.execute(sql`INSERT INTO players (player_id, full_name) VALUES ('00-planted', 'Planted Player')`);
      await tx.execute(sql`INSERT INTO markets (market_id, scope, outcome_kind, grading_rule) VALUES ('rec_yds', 'player', 'line', 'over_under')`);
      await tx.execute(sql`INSERT INTO prop_line_probs (run_id, player_id, market_id, line, p_over, p_push)
                           VALUES (${weeklyRun}, '00-planted', 'rec_yds', 55.5, 0.7, 0.4)`);
    });
    expect(count(r, "prob.prop_line_probs").count).toBe(1);
  });

  it("a calibration bin with a negative mean is reported", async () => {
    const r = await withPlanted((tx) =>
      tx.execute(sql`INSERT INTO calibration_bins (bt_run_id, split, candidate, bin, p_mean, y_mean, n)
                     VALUES (${btRunId}, 'tune', 'CX', 99, 0.5, -0.1, 10)`)
    );
    expect(count(r, "prob.calibration_bins").count).toBe(1);
  });

  const metricRow = (tx: Queryable, candidate: string, brier: number, slope: number, slopeLo: number, slopeHi: number) =>
    tx.execute(sql`INSERT INTO backtest_metrics (bt_run_id, split, phase, candidate, n, brier, logloss, accuracy, ece,
                                                 slope, slope_lo, slope_hi, skill, skill_lo, skill_hi)
                   VALUES (${btRunId}, 'tune', 'pooled', ${candidate}, 100, ${brier}, 0.61, 0.66, 0.02, ${slope}, ${slopeLo}, ${slopeHi}, 0.01, -0.01, 0.03)`);

  it("a Brier score above 1 or an interval whose bounds are crossed is an error", async () => {
    const r = await withPlanted(async (tx) => {
      await metricRow(tx, "CX", 1.2, 1, 0.9, 1.1);
      await metricRow(tx, "CY", 0.21, 1, 1.1, 0.9);
    });
    expect(count(r, "backtest_metrics.ranges").count).toBe(2);
    expect(count(r, "backtest_metrics.interval").count).toBe(1); // CY's slope is not inside its crossed bounds either
  });

  it("a slope outside its own bootstrap interval is a warning, not an error (a percentile interval need not contain it)", async () => {
    const r = await withPlanted((tx) => metricRow(tx, "CX", 0.21, 1.5, 0.9, 1.1));
    expect(count(r, "backtest_metrics.ranges").count).toBe(0);
    const w = count(r, "backtest_metrics.interval");
    expect([w.count, w.severity]).toEqual([1, "warning"]);
  });

  it("a distribution whose run states no mass is reported", async () => {
    const r = await withPlanted((tx) =>
      tx.execute(sql`INSERT INTO score_distributions (run_id, game_id, kind, bins)
                     VALUES (${weeklyRun}, '2026_04_DEN_SF', 'margin', ${JSON.stringify([{ x: 0, p: 1 }])}::jsonb)`)
    );
    expect(count(r, "score_distributions.mass").count).toBe(1);
  });

  it("bins with a gap in x are reported", async () => {
    const r = await withPlanted((tx) =>
      tx.execute(sql`UPDATE score_distributions SET bins = ${JSON.stringify([{ x: 0, p: 0.5 }, { x: 2, p: 0.4999 }])}::jsonb
                     WHERE run_id = ${simRun} AND game_id = '2024_15_LA_SF' AND kind = 'margin'`)
    );
    expect(count(r, "score_distributions.shape").count).toBe(1);
  });

  it("a second game id for the same matchup is reported", async () => {
    const r = await withPlanted((tx) =>
      tx.execute(sql`INSERT INTO games (game_id, season, week, game_type, home_team_id, away_team_id, kickoff_utc)
                     SELECT 'planted_dup', season, week, game_type, home_team_id, away_team_id, kickoff_utc
                     FROM games WHERE game_id = '2026_04_DEN_SF'`)
    );
    const c = count(r, "games.natural_key");
    expect(c.count).toBe(1);
    expect(c.samples[0]).toContain("planted_dup");
  });

  it("a game with one score and not the other is reported", async () => {
    const r = await withPlanted((tx) =>
      tx.execute(sql`UPDATE games SET home_score = 24, away_score = NULL WHERE game_id = '2026_04_DEN_SF'`)
    );
    expect(count(r, "games.scores").count).toBe(1);
  });

  it("a second published weekly run and an ingest log row for an unknown run are reported", async () => {
    const r = await withPlanted(async (tx) => {
      await tx.execute(sql`UPDATE model_runs SET status = 'published' WHERE kind = 'weekly'`);
      await tx.execute(sql`INSERT INTO bundle_ingests (bundle_sha256, cycle_id, kind, run_id, status, ingested_at)
                           VALUES ('planted', 'x', 'weekly', 'weekly:x:planted', 'published', now())`);
    });
    expect(count(r, "model_runs.publication").count).toBe(2);
  });

  it("a second backtest run for one model run is reported (the B2 Task 3 minor)", async () => {
    const r = await withPlanted((tx) =>
      tx.execute(sql`INSERT INTO backtest_runs (bt_run_id, window_id, run_id, status, result_sha256, code_git_sha, generated_utc, controls)
                     SELECT 'planted_bt', window_id, run_id, status, result_sha256, code_git_sha, generated_utc, controls
                     FROM backtest_runs WHERE bt_run_id = ${btRunId}`)
    );
    expect(count(r, "backtest_runs.run_key").count).toBe(1);
  });

  it("an unknown source status is reported", async () => {
    const r = await withPlanted((tx) =>
      tx.execute(sql`INSERT INTO source_status (run_id, source, status) VALUES (${weeklyRun}, 'planted', 'unknown')`)
    );
    const c = count(r, "enum.values");
    expect(c.count).toBe(1);
    expect(c.samples[0]).toContain("unknown");
  });

  it("a check whose SQL fails is reported by id, not skipped", async () => {
    const broken: readonly DbCheck[] = [{ id: "test.broken", severity: "error", what: "x", query: sql`SELECT no_such_column AS detail FROM games` }];
    await expect(runDbChecks(db, broken)).rejects.toThrow(/^db-check test\.broken: /);
  });
});

describe("formatReport", () => {
  it("counts violated checks and ends with the summary line", () => {
    const r = formatReport([
      { id: "a", severity: "error", what: "A", count: 2, samples: ["x", "y"] },
      { id: "b", severity: "warning", what: "B", count: 1, samples: ["z"] },
      { id: "c", severity: "error", what: "C", count: 0, samples: [] }
    ]);
    expect([r.errors, r.warnings]).toEqual([1, 1]);
    expect(r.text.trim().split("\n").at(-1)).toBe("db-check: 3 checks, 1 error(s), 1 warning(s)");
    expect(r.text).toContain("ERROR a (2): A");
    expect(r.text).toContain("WARNING b (1): B");
    expect(r.text).not.toContain(" c (");
  });
});

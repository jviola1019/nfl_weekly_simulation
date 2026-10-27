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
                     VALUES (${simRun}, '2024_15_LA_SF', 'CX', 'NaN'), (${simRun}, '2024_15_LA_SF', 'CY', 'Infinity')`)
    );
    expect(count(r, "prob.game_predictions").count).toBe(2);
  });

  it("a recommendation probability above 1 is reported", async () => {
    const r = await withPlanted((tx) =>
      tx.execute(sql`INSERT INTO recommendations (rec_id, run_id, game_id, candidate, side, p_model, stake_pct, tier)
                     VALUES ('planted', ${simRun}, '2024_15_LA_SF', 'C2', 'home', 1.5, 0, 'pass')`)
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
                           VALUES (${simRun}, '00-planted', 'rec_yds', 55.5, 0.7, 0.4)`);
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

  it("a served run whose config states no distribution_mass has every distribution reported", async () => {
    const n = (await db.execute<{ n: number }>(sql`SELECT count(*)::int AS n FROM score_distributions WHERE run_id = ${simRun}`))[0]!.n;
    const r = await withPlanted((tx) =>
      tx.execute(sql`UPDATE model_runs SET config = config - 'distribution_mass' WHERE run_id = ${simRun}`)
    );
    expect(n).toBeGreaterThan(0);
    expect(count(r, "score_distributions.mass").count).toBe(n);
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

  it("an unknown source status is a warning (the contract's vocabularies are wider, so it must not block an ingest)", async () => {
    const r = await withPlanted((tx) =>
      tx.execute(sql`INSERT INTO source_status (run_id, source, status) VALUES (${simRun}, 'planted', 'unknown')`)
    );
    const c = count(r, "enum.values");
    expect([c.count, c.severity]).toEqual([1, "warning"]);
    expect(c.samples[0]).toContain("unknown");
  });

  it("a violation in a run no pointer serves is not reported, so it cannot block the next ingest (final review C-1)", async () => {
    // weekly-2026-w04 was superseded when the simulator run was ingested
    const r = await withPlanted((tx) =>
      tx.execute(sql`INSERT INTO game_predictions (run_id, game_id, candidate, p_home_final) VALUES (${weeklyRun}, '2026_04_DEN_SF', 'CX', 1.5)`)
    );
    expect(count(r, "prob.game_predictions").count).toBe(0);
    expect(formatReport(r).errors).toBe(0);
  });

  it("an interval bound that is NaN or Infinity is an error (final review I-1)", async () => {
    const r = await withPlanted(async (tx) => {
      await tx.execute(sql`INSERT INTO backtest_metrics (bt_run_id, split, phase, candidate, n, brier, logloss, accuracy, ece,
                                                         slope, slope_lo, slope_hi, skill, skill_lo, skill_hi) VALUES
        (${btRunId}, 'tune', 'pooled', 'CN', 100, 0.21, 0.61, 0.66, 0.02, 1, 0.9, 'NaN', 0.01, -0.01, 0.03),
        (${btRunId}, 'tune', 'pooled', 'CI', 100, 0.21, 0.61, 0.66, 0.02, 1, 0.9, 1.1, 0.01, -0.01, 'Infinity')`);
    });
    expect(count(r, "backtest_metrics.ranges").count).toBe(2);
  });

  it("a score more than a day before its kickoff is an error; a few hours is not (an assumed 1 PM ET kickoff can be late)", async () => {
    const soon = await withPlanted((tx) =>
      tx.execute(sql`UPDATE games SET home_score = 24, away_score = 17, kickoff_utc = now() + interval '3 hours' WHERE game_id = '2026_04_DEN_SF'`)
    );
    expect(count(soon, "games.scores").count).toBe(0);
    const later = await withPlanted((tx) =>
      tx.execute(sql`UPDATE games SET home_score = 24, away_score = 17, kickoff_utc = now() + interval '3 days' WHERE game_id = '2026_04_DEN_SF'`)
    );
    expect(count(later, "games.scores").count).toBe(1);
  });

  it("a check whose SQL fails is reported by id, not skipped", async () => {
    const broken: readonly DbCheck[] = [{ id: "test.broken", severity: "error", what: "x", query: sql`SELECT no_such_column AS detail FROM games` }];
    await expect(runDbChecks(db, broken)).rejects.toThrow(/^db-check test\.broken: /);
  });

  // --- odds checks (Task 2): quotes planted on fixture game 2026_04_DEN_SF ---
  const GAME = "2026_04_DEN_SF";
  const AT = "2026-09-20T15:00:00Z";
  async function oddsBase(tx: Queryable, venues: string[]) {
    for (const v of venues) await tx.execute(sql`INSERT INTO venues (venue_id, display_name, kind) VALUES (${v}, ${v}, 'sportsbook') ON CONFLICT DO NOTHING`);
    await tx.execute(sql`INSERT INTO markets (market_id, scope, outcome_kind, grading_rule) VALUES
      ('ml', 'game', 'line', 'moneyline'), ('spread', 'game', 'line', 'spread'), ('td_yes', 'player', 'yes_no', 'scores_td')
      ON CONFLICT DO NOTHING`);
  }
  const quote = (tx: Queryable, venue: string, market: string, side: string, price: number | null, line: number | null = null, at = AT) =>
    tx.execute(sql`INSERT INTO odds_snapshots (game_id, market_id, venue_id, side, line, price_american, captured_at)
                   VALUES (${GAME}, ${market}, ${venue}, ${side}, ${line}, ${price}, ${at}) RETURNING snapshot_id`);

  it("a two-way price whose implied probabilities sum outside [1.00, 1.15] is reported; spreads pair by |line|", async () => {
    const r = await withPlanted(async (tx) => {
      await oddsBase(tx, ["bkA", "bkB", "bkC", "bkD", "exK"]);
      await quote(tx, "bkA", "ml", "home", -110); await quote(tx, "bkA", "ml", "away", -110); // 1.0476: fine
      await quote(tx, "bkB", "ml", "home", 150); await quote(tx, "bkB", "ml", "away", 150); // 0.80: reported
      await quote(tx, "bkC", "spread", "home", -110, -3.5); await quote(tx, "bkC", "spread", "away", -110, 3.5); // one pair, fine
      await quote(tx, "bkD", "ml", "home", -120); // one side only: not a pair
      await tx.execute(sql`INSERT INTO odds_snapshots (game_id, market_id, venue_id, side, bid, ask, captured_at)
                           VALUES (${GAME}, 'ml', 'exK', 'home', 0.55, 0.57, ${AT})`); // exchange quote, no price
    });
    const c = count(r, "odds.overround");
    expect(c.count).toBe(1);
    expect(c.samples[0]).toContain("bkB");
  });

  it("a quote with an impossible shape is reported", async () => {
    const r = await withPlanted(async (tx) => {
      await oddsBase(tx, ["bkA", "exK"]);
      await quote(tx, "bkA", "ml", "home", 50); // American odds cannot lie in (-100, 100)
      await tx.execute(sql`INSERT INTO odds_snapshots (game_id, market_id, venue_id, side, bid, ask, captured_at) VALUES
        (${GAME}, 'td_yes', 'exK', 'yes', 0.30, 1.2, ${AT}),
        (${GAME}, 'ml', 'exK', 'away', 0.6, 0.5, ${AT}),
        (${GAME}, 'ml', 'exK', 'home', NULL, NULL, ${AT})`);
    });
    expect(count(r, "odds.quote_shape").count).toBe(4);
  });

  it("a closing line captured after kickoff is reported, one captured before it is not", async () => {
    const kickoff = (await db.execute<{ k: string }>(sql`SELECT kickoff_utc::text AS k FROM games WHERE game_id = ${GAME}`))[0]!.k;
    const shift = (min: number) => new Date(new Date(kickoff).getTime() + min * 60_000).toISOString();
    const r = await withPlanted(async (tx) => {
      await oddsBase(tx, ["bkA", "bkB"]);
      const after = (await quote(tx, "bkA", "ml", "home", -110, null, shift(5)))[0] as { snapshot_id: number };
      const before = (await quote(tx, "bkB", "ml", "home", -110, null, shift(-5)))[0] as { snapshot_id: number };
      await tx.execute(sql`INSERT INTO closing_lines (game_id, market_id, venue_id, side, snapshot_id, rule_version) VALUES
        (${GAME}, 'ml', 'bkA', 'home', ${after.snapshot_id}, 'test'), (${GAME}, 'ml', 'bkB', 'home', ${before.snapshot_id}, 'test')`);
    });
    const c = count(r, "odds.close_after_kickoff");
    expect(c.count).toBe(1);
    expect(c.samples[0]).toContain("bkA");
  });

  it("a closing line pointing at another player's snapshot is reported (final review I-3)", async () => {
    const r = await withPlanted(async (tx) => {
      await oddsBase(tx, ["bkA"]);
      await tx.execute(sql`INSERT INTO players (player_id, full_name) VALUES ('P1', 'Player One'), ('P2', 'Player Two')`);
      const s = (await tx.execute(sql`INSERT INTO odds_snapshots (game_id, market_id, venue_id, player_id, side, price_american, captured_at)
                                       VALUES (${GAME}, 'td_yes', 'bkA', 'P2', 'yes', 150, ${AT}) RETURNING snapshot_id`))[0] as { snapshot_id: number };
      await tx.execute(sql`INSERT INTO closing_lines (game_id, market_id, venue_id, player_key, side, snapshot_id, rule_version)
                           VALUES (${GAME}, 'td_yes', 'bkA', 'P1', 'yes', ${s.snapshot_id}, 'test')`);
    });
    expect(count(r, "odds.close_snapshot_mismatch").count).toBe(1);
  });

  it("a closing line pointing at another venue's snapshot is reported", async () => {
    const r = await withPlanted(async (tx) => {
      await oddsBase(tx, ["bkA", "bkB"]);
      const s = (await quote(tx, "bkB", "ml", "home", -110))[0] as { snapshot_id: number };
      await tx.execute(sql`INSERT INTO closing_lines (game_id, market_id, venue_id, side, snapshot_id, rule_version)
                           VALUES (${GAME}, 'ml', 'bkA', 'home', ${s.snapshot_id}, 'test')`);
    });
    expect(count(r, "odds.close_snapshot_mismatch").count).toBe(1);
  });

  it("a venue more than 8 points from the median of three is a warning, reported once per quote", async () => {
    const r = await withPlanted(async (tx) => {
      await oddsBase(tx, ["v1", "v2", "v3"]);
      // no-vig home 0.600, 0.611 and 0.750 (median 0.611)
      await quote(tx, "v1", "ml", "home", -166); await quote(tx, "v1", "ml", "away", 140);
      await quote(tx, "v2", "ml", "home", -174); await quote(tx, "v2", "ml", "away", 147);
      await quote(tx, "v3", "ml", "home", -355); await quote(tx, "v3", "ml", "away", 285);
    });
    const w = count(r, "odds.cross_venue");
    expect([w.count, w.severity]).toEqual([1, "warning"]);
    expect(w.samples[0]).toContain("v3");
    expect(formatReport(r).errors).toBe(0);
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

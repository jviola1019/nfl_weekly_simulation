/**
 * SQL data checks (Track C2): each query returns one `detail` row per violation, so a clean
 * database returns zero rows from every one. They run after every ingest (`npm run db-check`,
 * CI, the deployed ingest and the local app). The invariants the schema itself enforces
 * (keys, foreign keys, drizzle/0001_invariants.sql) are not repeated here.
 *
 * "Outside [0, 1]" is written NOT (x BETWEEN 0 AND 1): Postgres double precision accepts NaN
 * and Infinity, and NaN sorts above every number, so a plain x < 0 OR x > 1 would be true for
 * NaN only by that accident.
 */
import { sql, type SQL } from "drizzle-orm";

export type Severity = "error" | "warning";

export interface DbCheck {
  id: string;
  severity: Severity;
  /** What a violation means, in a sentence. */
  what: string;
  /** Selects one text column, `detail`: one row per violation, naming the table, the key and the value. */
  query: SQL;
}

/**
 * Two-way priced quotes: one row per (game, market, venue, player, |line|, capture time) whose two
 * sides both carry an American price. The pair is keyed by |line| because a spread is quoted as
 * home -3.5 against away +3.5. `side` is the pair's first side by name (the canonical side, so a
 * venue is compared once per quote), and `p_side` is that side's proportionally devigged probability.
 * American odds a: a >= 100 gives 100 / (a + 100); a <= -100 gives -a / (-a + 100).
 */
const PRICED_PAIRS = sql`
  SELECT game_id, market_id, venue_id, coalesce(player_id, '') AS player_key, abs(coalesce(line, 0)) AS aline, captured_at,
         min(side) AS side, sum(implied) AS total,
         (array_agg(implied ORDER BY side))[1] / sum(implied) AS p_side
  FROM (
    SELECT s.*, CASE WHEN s.price_american >= 100 THEN 100.0 / (s.price_american + 100)
                     WHEN s.price_american <= -100 THEN (-s.price_american)::float8 / (-s.price_american + 100) END AS implied
    FROM odds_snapshots s WHERE s.price_american IS NOT NULL
  ) q
  GROUP BY game_id, market_id, venue_id, coalesce(player_id, ''), abs(coalesce(line, 0)), captured_at
  HAVING count(*) = 2 AND count(DISTINCT side) = 2 AND count(implied) = 2`;

export const DB_CHECKS: readonly DbCheck[] = [
  {
    id: "prob.game_predictions",
    severity: "error",
    what: "a game probability is outside [0, 1]",
    query: sql`SELECT format('game_predictions run=%s game=%s candidate=%s %s=%s', g.run_id, g.game_id, g.candidate, v.col, v.val) AS detail
      FROM game_predictions g
      CROSS JOIN LATERAL (VALUES ('p_home_raw', g.p_home_raw), ('p_home_final', g.p_home_final), ('p_home_mkt_novig', g.p_home_mkt_novig)) v(col, val)
      WHERE v.val IS NOT NULL AND NOT (v.val BETWEEN 0 AND 1)`
  },
  {
    id: "prob.recommendations",
    severity: "error",
    what: "a recommendation probability is outside [0, 1]",
    query: sql`SELECT format('recommendations run=%s rec=%s %s=%s', r.run_id, r.rec_id, v.col, v.val) AS detail
      FROM recommendations r
      CROSS JOIN LATERAL (VALUES ('p_model', r.p_model), ('p_mkt_novig', r.p_mkt_novig)) v(col, val)
      WHERE v.val IS NOT NULL AND NOT (v.val BETWEEN 0 AND 1)`
  },
  {
    id: "prob.prop_line_probs",
    severity: "error",
    what: "a prop line's over or push probability is outside [0, 1], or the two sum above 1",
    query: sql`SELECT format('prop_line_probs run=%s player=%s market=%s line=%s p_over=%s p_push=%s', run_id, player_id, market_id, line, p_over, p_push) AS detail
      FROM prop_line_probs
      WHERE NOT (p_over BETWEEN 0 AND 1) OR NOT (p_push BETWEEN 0 AND 1) OR p_over + p_push > 1 + 1e-9`
  },
  {
    id: "prob.calibration_bins",
    severity: "error",
    what: "a calibration bin's mean is outside [0, 1] or its count is negative",
    query: sql`SELECT format('calibration_bins bt_run=%s split=%s candidate=%s bin=%s p_mean=%s y_mean=%s n=%s', bt_run_id, split, candidate, bin, p_mean, y_mean, n) AS detail
      FROM calibration_bins
      WHERE NOT (p_mean BETWEEN 0 AND 1) OR NOT (y_mean BETWEEN 0 AND 1) OR n < 0`
  },
  {
    id: "backtest_metrics.ranges",
    severity: "error",
    what: "a backtest metric is out of its range, or an interval's lower bound is above its upper",
    query: sql`SELECT format('backtest_metrics bt_run=%s split=%s phase=%s candidate=%s n=%s brier=%s logloss=%s accuracy=%s ece=%s slope=[%s, %s] skill=[%s, %s]',
                     bt_run_id, split, phase, candidate, n, brier, logloss, accuracy, ece, slope_lo, slope_hi, skill_lo, skill_hi) AS detail
      FROM backtest_metrics
      WHERE NOT (brier BETWEEN 0 AND 1) OR NOT (accuracy BETWEEN 0 AND 1) OR NOT (ece BETWEEN 0 AND 1)
         OR NOT (logloss >= 0 AND logloss < 'Infinity'::float8) OR n <= 0
         OR slope_lo > slope_hi OR skill_lo > skill_hi`
  },
  {
    // a percentile-bootstrap interval need not contain its point estimate, so this is a warning
    id: "backtest_metrics.interval",
    severity: "warning",
    what: "a slope or skill lies outside its own bootstrap interval",
    query: sql`SELECT format('backtest_metrics bt_run=%s split=%s phase=%s candidate=%s slope=%s in [%s, %s] skill=%s in [%s, %s]',
                     bt_run_id, split, phase, candidate, slope, slope_lo, slope_hi, skill, skill_lo, skill_hi) AS detail
      FROM backtest_metrics
      WHERE NOT (slope BETWEEN slope_lo AND slope_hi) OR NOT (skill BETWEEN skill_lo AND skill_hi)`
  },
  {
    // the bins cover the central distribution_mass (0.999) of the draws, so they sum to at least
    // that, not to 1 (R/sim_bundle.R sb_bins; output audit F7)
    id: "score_distributions.mass",
    severity: "error",
    what: "a score distribution covers less than its run's stated distribution_mass, more than 1, or its run states no mass",
    query: sql`SELECT format('score_distributions run=%s game=%s kind=%s sum=%s mass=%s', d.run_id, d.game_id, d.kind,
                     round(s.total::numeric, 6), coalesce(m.config->>'distribution_mass', 'none')) AS detail
      FROM score_distributions d
      JOIN model_runs m ON m.run_id = d.run_id
      CROSS JOIN LATERAL (
        SELECT sum(CASE WHEN jsonb_typeof(b->'p') = 'number' THEN (b->>'p')::float8 END) AS total,
               bool_or(CASE WHEN jsonb_typeof(b->'p') = 'number' THEN NOT ((b->>'p')::float8 BETWEEN 0 AND 1) ELSE true END) AS bad_bin
        FROM jsonb_array_elements(CASE WHEN jsonb_typeof(d.bins) = 'array' THEN d.bins ELSE '[]'::jsonb END) b
      ) s
      WHERE CASE WHEN jsonb_typeof(m.config->'distribution_mass') = 'number'
                 THEN coalesce(s.total, 0) < (m.config->>'distribution_mass')::float8 - 1e-9
                      OR s.total > 1 + 1e-9 OR coalesce(s.bad_bin, false)
                 ELSE true END`
  },
  {
    id: "score_distributions.shape",
    severity: "error",
    what: "a score distribution is not a margin or total histogram over consecutive integer outcomes",
    query: sql`SELECT format('score_distributions run=%s game=%s kind=%s: %s', run_id, game_id, kind, problem) AS detail
      FROM (
        SELECT d.run_id, d.game_id, d.kind,
          CASE
            WHEN d.kind NOT IN ('margin', 'total') THEN 'kind is not margin or total'
            WHEN jsonb_typeof(d.bins) <> 'array' THEN 'bins is not an array'
            WHEN jsonb_array_length(d.bins) = 0 THEN 'bins is empty'
            WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(d.bins) b
                         WHERE jsonb_typeof(b->'x') IS DISTINCT FROM 'number' OR jsonb_typeof(b->'p') IS DISTINCT FROM 'number')
              THEN 'a bin without a numeric x and p'
            WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(d.bins) WITH ORDINALITY e(b, i)
                         WHERE (b->>'x')::float8 <> trunc((b->>'x')::float8)
                            OR (b->>'x')::float8 <> (d.bins->0->>'x')::float8 + (i - 1))
              THEN 'x is not consecutive ascending integers'
          END AS problem
        FROM score_distributions d
      ) t
      WHERE problem IS NOT NULL`
  },
  {
    id: "games.natural_key",
    severity: "error",
    what: "two game ids share a season, week and matchup, or a team plays itself",
    query: sql`SELECT format('games season=%s week=%s %s at %s: game ids %s', season, week, away_team_id, home_team_id, string_agg(game_id, ', ' ORDER BY game_id)) AS detail
      FROM games GROUP BY season, week, home_team_id, away_team_id HAVING count(*) > 1
      UNION ALL
      SELECT format('games %s: home and away are both %s', game_id, home_team_id) FROM games WHERE home_team_id = away_team_id`
  },
  {
    id: "games.scores",
    severity: "error",
    what: "a game has one score without the other, a negative score, or a score before its kickoff",
    query: sql`SELECT format('games %s: home_score=%s away_score=%s kickoff=%s: %s', game_id, coalesce(home_score::text, 'null'),
                     coalesce(away_score::text, 'null'), kickoff_utc, problem) AS detail
      FROM (
        SELECT g.*, CASE
          WHEN (home_score IS NULL) <> (away_score IS NULL) THEN 'one score without the other'
          WHEN home_score < 0 OR away_score < 0 THEN 'a negative score'
          WHEN home_score IS NOT NULL AND kickoff_utc > now() THEN 'a score before kickoff'
        END AS problem
        FROM games g
      ) t
      WHERE problem IS NOT NULL`
  },
  {
    id: "model_runs.publication",
    severity: "error",
    what: "publication is inconsistent: two published runs of a kind, a pointer to a run that is not published, or a run and its ingest log disagree",
    query: sql`SELECT format('model_runs kind=%s: %s runs are published (%s)', kind, count(*), string_agg(run_id, ', ' ORDER BY run_id)) AS detail
      FROM model_runs WHERE status = 'published' GROUP BY kind HAVING count(*) > 1
      UNION ALL
      SELECT format('publish_pointers %s -> %s: run status %s, qa_ok %s, kind %s', p.pointer, p.run_id, m.status, m.qa_ok, m.kind)
      FROM publish_pointers p JOIN model_runs m ON m.run_id = p.run_id
      WHERE m.status <> 'published' OR NOT m.qa_ok
         OR m.kind IS DISTINCT FROM CASE p.pointer WHEN 'weekly' THEN 'weekly' WHEN 'backtest_games' THEN 'backtest' END
      UNION ALL
      SELECT format('model_runs %s: no bundle_ingests row', m.run_id) FROM model_runs m
      WHERE NOT EXISTS (SELECT 1 FROM bundle_ingests b WHERE b.run_id = m.run_id)
      UNION ALL
      SELECT format('bundle_ingests %s: run %s is not in model_runs', b.bundle_sha256, b.run_id) FROM bundle_ingests b
      WHERE NOT EXISTS (SELECT 1 FROM model_runs m WHERE m.run_id = b.run_id)`
  },
  {
    // backtest_runs.run_id carries no unique constraint (B2 Task 3 minor): evidence() reads the
    // first row and publicGates() reads every row, so two rows for one run would disagree
    id: "backtest_runs.run_key",
    severity: "error",
    what: "a model run has more than one backtest run, or a backtest run belongs to a run that is not a backtest",
    query: sql`SELECT format('backtest_runs run %s has %s rows (%s)', run_id, count(*), string_agg(bt_run_id, ', ' ORDER BY bt_run_id)) AS detail
      FROM backtest_runs GROUP BY run_id HAVING count(*) > 1
      UNION ALL
      SELECT format('backtest_runs %s: run %s is of kind %s', b.bt_run_id, b.run_id, m.kind)
      FROM backtest_runs b JOIN model_runs m ON m.run_id = b.run_id WHERE m.kind <> 'backtest'`
  },
  {
    id: "enum.values",
    severity: "error",
    what: "a coded column holds a value outside its vocabulary",
    query: sql`SELECT format('source_status run=%s source=%s status=%s', run_id, source, status) AS detail
        FROM source_status WHERE status NOT IN ('ok', 'stale', 'failed', 'unavailable')
      UNION ALL SELECT format('recommendations run=%s rec=%s side=%s', run_id, rec_id, side)
        FROM recommendations WHERE side NOT IN ('home', 'away', 'none')
      UNION ALL SELECT format('games %s game_type=%s', game_id, game_type)
        FROM games WHERE game_type NOT IN ('REG', 'WC', 'DIV', 'CON', 'SB')
      UNION ALL SELECT format('markets %s scope=%s outcome_kind=%s', market_id, scope, outcome_kind)
        FROM markets WHERE scope NOT IN ('game', 'player') OR outcome_kind NOT IN ('line', 'yes_no')
      UNION ALL SELECT format('backtest_metrics bt_run=%s candidate=%s split=%s phase=%s', bt_run_id, candidate, split, phase)
        FROM backtest_metrics WHERE split NOT IN ('tune', 'confirm', 'holdout') OR phase NOT IN ('pooled', 'REG', 'POST')
      UNION ALL SELECT format('bet_grades run=%s rec=%s grader=%s outcome=%s', run_id, rec_id, grader_version, outcome)
        FROM bet_grades WHERE outcome NOT IN ('win', 'loss', 'push', 'void')`
  },
  // --- odds (no bundle writes these tables yet; the K3 odds bundle will) ---
  {
    id: "odds.quote_shape",
    severity: "error",
    what: "a quote has no price and no bid, ask or last, an American price in (-100, 100), a bid above its ask, or a yes/no quote outside [0, 1]",
    query: sql`SELECT format('odds_snapshots %s game=%s market=%s venue=%s side=%s: %s', snapshot_id, game_id, market_id, venue_id, side, problem) AS detail
      FROM (
        SELECT s.snapshot_id, s.game_id, s.market_id, s.venue_id, s.side, CASE
          WHEN s.price_american IS NULL AND s.bid IS NULL AND s.ask IS NULL AND s.last IS NULL THEN 'no price and no quote'
          WHEN s.price_american > -100 AND s.price_american < 100 THEN format('American price %s is between -100 and 100', s.price_american)
          WHEN s.bid > s.ask THEN format('bid %s above ask %s', s.bid, s.ask)
          WHEN m.outcome_kind = 'yes_no' AND (NOT (coalesce(s.bid, 0) BETWEEN 0 AND 1) OR NOT (coalesce(s.ask, 0) BETWEEN 0 AND 1)
                                              OR NOT (coalesce(s.last, 0) BETWEEN 0 AND 1))
            THEN format('a yes/no quote outside [0, 1]: bid %s ask %s last %s', s.bid, s.ask, s.last)
        END AS problem
        FROM odds_snapshots s JOIN markets m ON m.market_id = s.market_id
      ) t
      WHERE problem IS NOT NULL`
  },
  {
    id: "odds.overround",
    severity: "error",
    what: "a two-way price's implied probabilities sum outside [1.00, 1.15]",
    query: sql`SELECT format('odds game=%s market=%s venue=%s line=%s captured=%s: implied sum %s', game_id, market_id, venue_id, aline, captured_at, round(total::numeric, 4)) AS detail
      FROM (${PRICED_PAIRS}) p
      WHERE total < 1 - 1e-9 OR total > 1.15 + 1e-9`
  },
  {
    id: "odds.close_after_kickoff",
    severity: "error",
    what: "a closing line was captured after its game's kickoff",
    query: sql`SELECT format('closing_lines game=%s market=%s venue=%s side=%s: snapshot %s captured %s, kickoff %s', c.game_id, c.market_id, c.venue_id, c.side, c.snapshot_id, s.captured_at, g.kickoff_utc) AS detail
      FROM closing_lines c
      JOIN odds_snapshots s ON s.snapshot_id = c.snapshot_id
      JOIN games g ON g.game_id = c.game_id
      WHERE s.captured_at > g.kickoff_utc`
  },
  {
    id: "odds.close_snapshot_mismatch",
    severity: "error",
    what: "a closing line points at a snapshot of another game, market, venue or side",
    query: sql`SELECT format('closing_lines game=%s market=%s venue=%s side=%s -> snapshot %s is game=%s market=%s venue=%s side=%s',
                     c.game_id, c.market_id, c.venue_id, c.side, s.snapshot_id, s.game_id, s.market_id, s.venue_id, s.side) AS detail
      FROM closing_lines c JOIN odds_snapshots s ON s.snapshot_id = c.snapshot_id
      WHERE s.game_id <> c.game_id OR s.market_id <> c.market_id OR s.venue_id <> c.venue_id OR s.side <> c.side`
  },
  {
    // a venue's latest pair in each UTC hour against the median of the venues quoting the same
    // game, market, player and |line| in that hour; flagged, not failed: a venue can be right
    id: "odds.cross_venue",
    severity: "warning",
    what: "a venue's no-vig probability is more than 8 points from the median of at least three venues in the same hour",
    query: sql`WITH pairs AS (SELECT *, date_trunc('hour', captured_at) AS hour FROM (${PRICED_PAIRS}) p),
      latest AS (
        SELECT DISTINCT ON (game_id, market_id, player_key, aline, hour, venue_id) *
        FROM pairs ORDER BY game_id, market_id, player_key, aline, hour, venue_id, captured_at DESC
      ),
      med AS (
        SELECT game_id, market_id, player_key, aline, hour, side, count(*) AS n_venues,
               percentile_cont(0.5) WITHIN GROUP (ORDER BY p_side) AS median
        FROM latest GROUP BY game_id, market_id, player_key, aline, hour, side
      )
      SELECT format('odds game=%s market=%s line=%s hour=%s venue=%s %s=%s, median %s over %s venues', l.game_id, l.market_id, l.aline, l.hour,
                    l.venue_id, l.side, round(l.p_side::numeric, 3), round(m.median::numeric, 3), m.n_venues) AS detail
      FROM latest l JOIN med m USING (game_id, market_id, player_key, aline, hour, side)
      WHERE m.n_venues >= 3 AND abs(l.p_side - m.median) > 0.08`
  }
];

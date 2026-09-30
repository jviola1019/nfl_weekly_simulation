/**
 * Database schema: the single source of truth for the R -> web contract
 * (docs/superpowers/specs/2026-09-28-nfl-overhaul-design.md §3). drizzle-zod derives
 * the zod schemas from these tables, and scripts/export-contracts.ts writes them to
 * contracts/schema/*.json, which the R bundle writer validates against.
 *
 * Invariants that SQL enforces (drizzle/0001_invariants.sql):
 *   - recommendations: (tier = 'bet') = (stake_pct > 0)            audit P2
 *   - append-only triggers on odds_snapshots, source_fetches, closing_lines,
 *     eval_windows, backtest_*, bet_grades (a re-grade is a new grader_version)
 *
 * Extensions to the spec ERD, each needed by a page or the ingest:
 *   - game_predictions / recommendations carry `candidate`, so one run can hold
 *     several registered models (the shootout candidates) side by side.
 *   - model_runs carries cycle_id, season, week, kind, qa, generated_utc.
 *   - bundle_ingests logs every ingest (idempotency on bundle_sha256).
 *   - clv_picks holds per-pick CLV rows for the evidence page's distribution.
 *   - auth_throttle backs the login rate limit (ported from the FF app).
 */
import { sql } from "drizzle-orm";
import {
  bigserial,
  boolean,
  doublePrecision,
  foreignKey,
  index,
  integer,
  jsonb,
  numeric,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex
} from "drizzle-orm/pg-core";

const ts = (name: string) => timestamp(name, { withTimezone: true, mode: "string" });

// ---------------------------------------------------------------------------
// Reference entities
// ---------------------------------------------------------------------------

export const teams = pgTable("teams", {
  teamId: text("team_id").primaryKey(), // nflverse code
  fullName: text("full_name").notNull(),
  division: text("division"),
  tz: text("tz")
});

export const teamAliases = pgTable(
  "team_aliases",
  {
    source: text("source").notNull(),
    alias: text("alias").notNull(),
    teamId: text("team_id").notNull().references(() => teams.teamId)
  },
  (t) => [primaryKey({ columns: [t.source, t.alias] })]
);

export const players = pgTable("players", {
  playerId: text("player_id").primaryKey(), // gsis_id
  fullName: text("full_name").notNull(),
  position: text("position")
});

export const playerAliases = pgTable(
  "player_aliases",
  {
    source: text("source").notNull(),
    alias: text("alias").notNull(), // name variant, ESPN athlete id, Kalshi uuid
    playerId: text("player_id").notNull().references(() => players.playerId)
  },
  (t) => [primaryKey({ columns: [t.source, t.alias] })]
);

export const rosterWeeks = pgTable(
  "roster_weeks",
  {
    playerId: text("player_id").notNull().references(() => players.playerId),
    teamId: text("team_id").notNull().references(() => teams.teamId),
    season: integer("season").notNull(),
    week: integer("week").notNull(),
    status: text("status")
  },
  (t) => [primaryKey({ columns: [t.playerId, t.season, t.week] })]
);

export const games = pgTable(
  "games",
  {
    gameId: text("game_id").primaryKey(),
    season: integer("season").notNull(),
    week: integer("week").notNull(),
    gameType: text("game_type").notNull().default("REG"),
    homeTeamId: text("home_team_id").notNull().references(() => teams.teamId),
    awayTeamId: text("away_team_id").notNull().references(() => teams.teamId),
    kickoffUtc: ts("kickoff_utc").notNull(),
    roof: text("roof"),
    neutral: boolean("neutral").notNull().default(false),
    homeScore: integer("home_score"),
    awayScore: integer("away_score")
  },
  (t) => [index("games_season_week_idx").on(t.season, t.week)]
);

export const venues = pgTable("venues", {
  venueId: text("venue_id").primaryKey(),
  displayName: text("display_name").notNull(),
  kind: text("kind").notNull() // sportsbook | exchange | consensus
});

export const markets = pgTable("markets", {
  marketId: text("market_id").primaryKey(),
  scope: text("scope").notNull(), // game | player
  outcomeKind: text("outcome_kind").notNull(), // line | yes_no
  gradingRule: text("grading_rule").notNull()
});

// ---------------------------------------------------------------------------
// Odds (append-only)
// ---------------------------------------------------------------------------

export const sourceFetches = pgTable("source_fetches", {
  fetchId: bigserial("fetch_id", { mode: "number" }).primaryKey(),
  source: text("source").notNull(),
  endpointRedacted: text("endpoint_redacted").notNull(),
  httpStatus: integer("http_status").notNull(),
  fetchedAt: ts("fetched_at").notNull(),
  rawSha256: text("raw_sha256").notNull()
});

export const oddsSnapshots = pgTable(
  "odds_snapshots",
  {
    snapshotId: bigserial("snapshot_id", { mode: "number" }).primaryKey(),
    fetchId: integer("fetch_id").references(() => sourceFetches.fetchId),
    gameId: text("game_id").notNull().references(() => games.gameId),
    marketId: text("market_id").notNull().references(() => markets.marketId),
    venueId: text("venue_id").notNull().references(() => venues.venueId),
    playerId: text("player_id").references(() => players.playerId),
    side: text("side").notNull(),
    line: numeric("line"),
    priceAmerican: integer("price_american"),
    bid: numeric("bid"),
    ask: numeric("ask"),
    last: numeric("last"),
    volume: numeric("volume"),
    capturedAt: ts("captured_at").notNull()
  },
  (t) => [index("odds_game_market_idx").on(t.gameId, t.marketId, t.venueId, t.capturedAt)]
);

export const closingLines = pgTable(
  "closing_lines",
  {
    gameId: text("game_id").notNull().references(() => games.gameId),
    marketId: text("market_id").notNull().references(() => markets.marketId),
    venueId: text("venue_id").notNull().references(() => venues.venueId),
    playerKey: text("player_key").notNull().default(""),
    side: text("side").notNull(),
    snapshotId: integer("snapshot_id").notNull().references(() => oddsSnapshots.snapshotId),
    closeGapMin: doublePrecision("close_gap_min"),
    ruleVersion: text("rule_version").notNull()
  },
  (t) => [primaryKey({ columns: [t.gameId, t.marketId, t.venueId, t.playerKey, t.side] })]
);

// ---------------------------------------------------------------------------
// Model runs and outputs
// ---------------------------------------------------------------------------

export const modelRuns = pgTable(
  "model_runs",
  {
    runId: text("run_id").primaryKey(),
    kind: text("kind").notNull(), // weekly | backtest
    cycleId: text("cycle_id").notNull(),
    season: integer("season"),
    week: integer("week"),
    modelLabel: text("model_label").notNull(),
    codeGitSha: text("code_git_sha").notNull(),
    codeDirty: boolean("code_dirty").notNull(),
    configHash: text("config_hash").notNull(),
    config: jsonb("config").notNull(),
    seed: integer("seed"),
    nSims: integer("n_sims"),
    bundleSha256: text("bundle_sha256").notNull(),
    generatedUtc: ts("generated_utc").notNull(),
    dataAsofUtc: ts("data_asof_utc").notNull(),
    qaOk: boolean("qa_ok").notNull(),
    qaFailures: jsonb("qa_failures").notNull().default(sql`'[]'::jsonb`),
    status: text("status").notNull() // published | qa_failed | superseded
  },
  (t) => [uniqueIndex("model_runs_bundle_sha_uk").on(t.bundleSha256)]
);

export const gamePredictions = pgTable(
  "game_predictions",
  {
    runId: text("run_id").notNull().references(() => modelRuns.runId, { onDelete: "cascade" }),
    gameId: text("game_id").notNull().references(() => games.gameId),
    candidate: text("candidate").notNull(),
    pHomeRaw: doublePrecision("p_home_raw"),
    pHomeFinal: doublePrecision("p_home_final"),
    pHomeMktNovig: doublePrecision("p_home_mkt_novig"),
    marginQ50: doublePrecision("margin_q50"),
    totalQ50: doublePrecision("total_q50")
  },
  (t) => [primaryKey({ columns: [t.runId, t.gameId, t.candidate] })]
);

export const scoreDistributions = pgTable(
  "score_distributions",
  {
    runId: text("run_id").notNull().references(() => modelRuns.runId, { onDelete: "cascade" }),
    gameId: text("game_id").notNull().references(() => games.gameId),
    kind: text("kind").notNull(), // margin | total
    bins: jsonb("bins").notNull() // [{x0, x1, p}]
  },
  (t) => [primaryKey({ columns: [t.runId, t.gameId, t.kind] })]
);

export const propProjections = pgTable(
  "prop_projections",
  {
    runId: text("run_id").notNull().references(() => modelRuns.runId, { onDelete: "cascade" }),
    gameId: text("game_id").notNull().references(() => games.gameId),
    playerId: text("player_id").notNull().references(() => players.playerId),
    marketId: text("market_id").notNull().references(() => markets.marketId),
    distFamily: text("dist_family").notNull(),
    distParams: jsonb("dist_params").notNull()
  },
  (t) => [primaryKey({ columns: [t.runId, t.gameId, t.playerId, t.marketId] })]
);

export const propLineProbs = pgTable(
  "prop_line_probs",
  {
    runId: text("run_id").notNull().references(() => modelRuns.runId, { onDelete: "cascade" }),
    playerId: text("player_id").notNull().references(() => players.playerId),
    marketId: text("market_id").notNull().references(() => markets.marketId),
    line: numeric("line").notNull(),
    pOver: doublePrecision("p_over").notNull(),
    pPush: doublePrecision("p_push").notNull().default(0)
  },
  (t) => [primaryKey({ columns: [t.runId, t.playerId, t.marketId, t.line] })]
);

// rec_id is unique within a run, not globally: every re-run of a week (Wed/Sat/Sun,
// or a re-publish after a QA failure) carries the same rec_ids under a new run_id.
export const recommendations = pgTable(
  "recommendations",
  {
    recId: text("rec_id").notNull(),
    runId: text("run_id").notNull().references(() => modelRuns.runId, { onDelete: "cascade" }),
    snapshotId: integer("snapshot_id").references(() => oddsSnapshots.snapshotId),
    gameId: text("game_id").notNull().references(() => games.gameId),
    candidate: text("candidate").notNull(),
    side: text("side").notNull(), // home | away | none
    priceAmerican: integer("price_american"),
    pModel: doublePrecision("p_model").notNull(),
    pMktNovig: doublePrecision("p_mkt_novig"),
    ev: doublePrecision("ev"),
    stakePct: doublePrecision("stake_pct").notNull(),
    tier: text("tier").notNull(), // bet | lean | pass
    passReason: text("pass_reason")
  },
  (t) => [primaryKey({ columns: [t.runId, t.recId] })]
);

export const betGrades = pgTable(
  "bet_grades",
  {
    runId: text("run_id").notNull(),
    recId: text("rec_id").notNull(),
    graderVersion: text("grader_version").notNull(),
    outcome: text("outcome").notNull(), // win | loss | push | void
    clvBps: doublePrecision("clv_bps"),
    units: doublePrecision("units")
  },
  (t) => [
    primaryKey({ columns: [t.runId, t.recId, t.graderVersion] }),
    foreignKey({ columns: [t.runId, t.recId], foreignColumns: [recommendations.runId, recommendations.recId] })
  ]
);

export const playerGameStats = pgTable(
  "player_game_stats",
  {
    gameId: text("game_id").notNull().references(() => games.gameId),
    playerId: text("player_id").notNull().references(() => players.playerId),
    stat: text("stat").notNull(),
    value: doublePrecision("value").notNull()
  },
  (t) => [primaryKey({ columns: [t.gameId, t.playerId, t.stat] })]
);

export const tdEvents = pgTable(
  "td_events",
  {
    gameId: text("game_id").notNull().references(() => games.gameId),
    seq: integer("seq").notNull(),
    playerId: text("player_id").references(() => players.playerId),
    teamId: text("team_id").references(() => teams.teamId)
  },
  (t) => [primaryKey({ columns: [t.gameId, t.seq] })]
);

export const sourceStatus = pgTable(
  "source_status",
  {
    runId: text("run_id").notNull().references(() => modelRuns.runId, { onDelete: "cascade" }),
    source: text("source").notNull(),
    status: text("status").notNull(), // ok | stale | failed | unavailable
    lastSuccessUtc: ts("last_success_utc"),
    detail: text("detail")
  },
  (t) => [primaryKey({ columns: [t.runId, t.source] })]
);

export const publishPointers = pgTable("publish_pointers", {
  pointer: text("pointer").primaryKey(), // weekly | backtest_games
  runId: text("run_id").notNull().references(() => modelRuns.runId),
  updatedAt: ts("updated_at").notNull()
});

export const bundleIngests = pgTable("bundle_ingests", {
  bundleSha256: text("bundle_sha256").primaryKey(),
  cycleId: text("cycle_id").notNull(),
  kind: text("kind").notNull(),
  runId: text("run_id").notNull(),
  status: text("status").notNull(), // published | qa_failed
  ingestedAt: ts("ingested_at").notNull()
});

// ---------------------------------------------------------------------------
// Backtests and evidence (append-only)
// ---------------------------------------------------------------------------

export const evalWindows = pgTable("eval_windows", {
  windowId: text("window_id").primaryKey(),
  folds: jsonb("folds").notNull(),
  protocolSha256: text("protocol_sha256").notNull(),
  frozenAtUtc: ts("frozen_at_utc").notNull()
});

export const backtestRuns = pgTable("backtest_runs", {
  btRunId: text("bt_run_id").primaryKey(),
  windowId: text("window_id").notNull().references(() => evalWindows.windowId),
  runId: text("run_id").notNull().references(() => modelRuns.runId),
  status: text("status").notNull(), // complete | void
  resultSha256: text("result_sha256").notNull(),
  codeGitSha: text("code_git_sha").notNull(),
  generatedUtc: ts("generated_utc").notNull(),
  controls: jsonb("controls").notNull(),
  clvSummary: jsonb("clv_summary") // per-candidate n, mean_clv_bps, clv_ci, roi, roi_ci (descriptive)
});

export const backtestMetrics = pgTable(
  "backtest_metrics",
  {
    btRunId: text("bt_run_id").notNull().references(() => backtestRuns.btRunId),
    split: text("split").notNull(), // tune | confirm | holdout
    phase: text("phase").notNull(), // pooled | REG | POST
    candidate: text("candidate").notNull(),
    n: integer("n").notNull(),
    brier: doublePrecision("brier").notNull(),
    logloss: doublePrecision("logloss").notNull(),
    accuracy: doublePrecision("accuracy").notNull(),
    ece: doublePrecision("ece").notNull(),
    slope: doublePrecision("slope").notNull(),
    slopeLo: doublePrecision("slope_lo").notNull(),
    slopeHi: doublePrecision("slope_hi").notNull(),
    skill: doublePrecision("skill").notNull(),
    skillLo: doublePrecision("skill_lo").notNull(),
    skillHi: doublePrecision("skill_hi").notNull(),
    dmPBetterBh: doublePrecision("dm_p_better_bh")
  },
  (t) => [primaryKey({ columns: [t.btRunId, t.split, t.phase, t.candidate] })]
);

export const calibrationBins = pgTable(
  "calibration_bins",
  {
    btRunId: text("bt_run_id").notNull().references(() => backtestRuns.btRunId),
    split: text("split").notNull(),
    candidate: text("candidate").notNull(),
    bin: integer("bin").notNull(),
    pMean: doublePrecision("p_mean").notNull(),
    yMean: doublePrecision("y_mean").notNull(),
    n: integer("n").notNull()
  },
  (t) => [primaryKey({ columns: [t.btRunId, t.split, t.candidate, t.bin] })]
);

export const promotionGates = pgTable(
  "promotion_gates",
  {
    btRunId: text("bt_run_id").notNull().references(() => backtestRuns.btRunId),
    candidate: text("candidate").notNull(),
    g1: boolean("g1").notNull(),
    g2: boolean("g2").notNull(),
    g3: boolean("g3").notNull(),
    g4: boolean("g4").notNull(),
    brierStatus: text("brier_status").notNull(),
    bettingValueStatus: text("betting_value_status").notNull()
  },
  (t) => [primaryKey({ columns: [t.btRunId, t.candidate] })]
);

export const clvPicks = pgTable(
  "clv_picks",
  {
    btRunId: text("bt_run_id").notNull().references(() => backtestRuns.btRunId),
    candidate: text("candidate").notNull(),
    gameId: text("game_id").notNull().references(() => games.gameId),
    side: text("side").notNull(),
    clvBps: doublePrecision("clv_bps").notNull(),
    units: doublePrecision("units").notNull()
  },
  (t) => [primaryKey({ columns: [t.btRunId, t.candidate, t.gameId] })]
);

export const evidenceLedger = pgTable("evidence_ledger", {
  claimId: text("claim_id").primaryKey(),
  claim: text("claim").notNull(),
  status: text("status").notNull(), // validated | reproducible | unvalidated | withdrawn
  reason: text("reason").notNull(),
  evidencePath: text("evidence_path").notNull(),
  supersedes: text("supersedes")
});

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

export const users = pgTable("users", {
  id: text("id").primaryKey(),
  email: text("email").notNull().unique(),
  passwordHash: text("password_hash").notNull(),
  sessionVersion: integer("session_version").notNull().default(1),
  createdAt: ts("created_at").notNull().default(sql`now()`)
});

export const authThrottle = pgTable("auth_throttle", {
  key: text("key").primaryKey(), // sha256 of dimension + identifier
  failures: integer("failures").notNull().default(0),
  windowStart: ts("window_start").notNull(),
  lockedUntil: ts("locked_until")
});

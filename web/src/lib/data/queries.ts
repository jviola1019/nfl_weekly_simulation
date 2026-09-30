/**
 * Read-side queries. Every public function selects explicit public columns: no
 * stake, EV or recommendation column is reachable from a public page (tested in
 * queries.test.ts and e2e/public-no-stakes.spec.ts). Desk functions are separate and
 * are called only after requireUser().
 */
import { and, asc, desc, eq, inArray } from "drizzle-orm";
import { alias } from "drizzle-orm/pg-core";
import { getDb } from "../../db";
import * as s from "../../db/schema";

export async function pointerRun(pointer: "weekly" | "backtest_games") {
  const db = getDb();
  const rows = await db
    .select({ run: s.modelRuns })
    .from(s.publishPointers)
    .innerJoin(s.modelRuns, eq(s.modelRuns.runId, s.publishPointers.runId))
    .where(eq(s.publishPointers.pointer, pointer));
  return rows[0]?.run ?? null;
}

export interface SlateGame {
  gameId: string;
  season: number;
  week: number;
  kickoffUtc: string;
  homeTeamId: string;
  awayTeamId: string;
  homeName: string;
  awayName: string;
  homeTz: string | null;
  neutral: boolean;
  homeScore: number | null;
  awayScore: number | null;
  pMarket: number | null;
}

/** Public slate: games of the published weekly run with the no-vig market only. */
export async function publicSlate(): Promise<{ run: Awaited<ReturnType<typeof pointerRun>>; games: SlateGame[] }> {
  const run = await pointerRun("weekly");
  if (!run) return { run: null, games: [] };
  const db = getDb();
  const home = aliasTeams("home");
  const away = aliasTeams("away");
  const rows = await db
    .select({
      gameId: s.games.gameId, season: s.games.season, week: s.games.week, kickoffUtc: s.games.kickoffUtc,
      homeTeamId: s.games.homeTeamId, awayTeamId: s.games.awayTeamId, neutral: s.games.neutral,
      homeScore: s.games.homeScore, awayScore: s.games.awayScore,
      homeName: home.fullName, awayName: away.fullName, homeTz: home.tz,
      pMarket: s.gamePredictions.pHomeMktNovig
    })
    .from(s.gamePredictions)
    .innerJoin(s.games, eq(s.games.gameId, s.gamePredictions.gameId))
    .innerJoin(home, eq(home.teamId, s.games.homeTeamId))
    .innerJoin(away, eq(away.teamId, s.games.awayTeamId))
    .where(and(eq(s.gamePredictions.runId, run.runId), eq(s.gamePredictions.candidate, "C0")))
    .orderBy(asc(s.games.kickoffUtc), asc(s.games.gameId));
  return { run, games: rows };
}

/** Candidate probabilities for games of the published weekly run (restricted list). */
export async function candidateLines(runId: string, candidates: string[], gameIds?: string[]) {
  if (!candidates.length) return [];
  const db = getDb();
  const conds = [eq(s.gamePredictions.runId, runId), inArray(s.gamePredictions.candidate, candidates)];
  if (gameIds?.length) conds.push(inArray(s.gamePredictions.gameId, gameIds));
  return db
    .select({ gameId: s.gamePredictions.gameId, candidate: s.gamePredictions.candidate, p: s.gamePredictions.pHomeFinal })
    .from(s.gamePredictions)
    .where(and(...conds));
}

export async function publicGame(gameId: string) {
  const { run, games } = await publicSlate();
  const game = games.find((g) => g.gameId === gameId) ?? null;
  return { run, game };
}

export async function evidence() {
  const db = getDb();
  const run = await pointerRun("backtest_games");
  if (!run) return null;
  const bt = (await db.select().from(s.backtestRuns).where(eq(s.backtestRuns.runId, run.runId)))[0];
  if (!bt) return null;
  const [window] = await db.select().from(s.evalWindows).where(eq(s.evalWindows.windowId, bt.windowId));
  const metrics = await db.select().from(s.backtestMetrics).where(eq(s.backtestMetrics.btRunId, bt.btRunId));
  const bins = await db
    .select()
    .from(s.calibrationBins)
    .where(eq(s.calibrationBins.btRunId, bt.btRunId))
    .orderBy(asc(s.calibrationBins.candidate), asc(s.calibrationBins.bin));
  const gates = await db.select().from(s.promotionGates).where(eq(s.promotionGates.btRunId, bt.btRunId));
  const clv = await db
    .select({ candidate: s.clvPicks.candidate, clvBps: s.clvPicks.clvBps, units: s.clvPicks.units })
    .from(s.clvPicks)
    .where(eq(s.clvPicks.btRunId, bt.btRunId));
  return { run, bt, window: window ?? null, metrics, bins, gates, clv };
}

export async function ledger() {
  return getDb().select().from(s.evidenceLedger).orderBy(asc(s.evidenceLedger.claimId));
}

export async function dataHealth() {
  const db = getDb();
  const run = await pointerRun("weekly");
  const sources = run ? await db.select().from(s.sourceStatus).where(eq(s.sourceStatus.runId, run.runId)).orderBy(asc(s.sourceStatus.source)) : [];
  const ingests = await db.select().from(s.bundleIngests).orderBy(desc(s.bundleIngests.ingestedAt)).limit(10);
  const runs = await db
    .select({ runId: s.modelRuns.runId, kind: s.modelRuns.kind, status: s.modelRuns.status, qaOk: s.modelRuns.qaOk,
              qaFailures: s.modelRuns.qaFailures, generatedUtc: s.modelRuns.generatedUtc, dataAsofUtc: s.modelRuns.dataAsofUtc,
              codeGitSha: s.modelRuns.codeGitSha, codeDirty: s.modelRuns.codeDirty, modelLabel: s.modelRuns.modelLabel })
    .from(s.modelRuns)
    .orderBy(desc(s.modelRuns.generatedUtc))
    .limit(10);
  return { run, sources, ingests, runs };
}

// ---------------------------------------------------------------------------
// Desk (private): call only after requireUser()
// ---------------------------------------------------------------------------

export async function deskSlate() {
  const { run, games } = await publicSlate();
  if (!run) return { run, games, lines: [], recs: [] };
  const lines = await candidateLines(run.runId, ["C1", "C2", "E1", "B1[E1]", "B2[E1]", "K[E1]"]);
  const recs = await getDb().select().from(s.recommendations).where(eq(s.recommendations.runId, run.runId));
  return { run, games, lines, recs };
}

function aliasTeams(name: string) {
  return alias(s.teams, name);
}

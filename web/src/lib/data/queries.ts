/**
 * Read-side queries. Every public function selects explicit public columns: no
 * stake, EV or recommendation column is reachable from a public page (tested in
 * queries.test.ts and e2e/public-no-stakes.spec.ts). Desk functions are separate and
 * are called only after requireUser().
 */
import { and, asc, desc, eq, inArray } from "drizzle-orm";
import { alias } from "drizzle-orm/pg-core";
import { cache } from "react";
import { getDb } from "../../db";
import * as s from "../../db/schema";
import { deskCandidate, type GateRow } from "../policy";

/*
 * React cache() makes a query that several parts of one page render ask for (the layout, the
 * page and its generateMetadata) run once per request. Outside a server render it is a plain
 * call, so the tests below see every query.
 */
export const pointerRun = cache(async (pointer: "weekly" | "backtest_games") => {
  const db = getDb();
  const rows = await db
    .select({ run: s.modelRuns })
    .from(s.publishPointers)
    .innerJoin(s.modelRuns, eq(s.modelRuns.runId, s.publishPointers.runId))
    .where(eq(s.publishPointers.pointer, pointer));
  return rows[0]?.run ?? null;
});

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
export const publicSlate = cache(async (): Promise<{ run: Awaited<ReturnType<typeof pointerRun>>; games: SlateGame[] }> => {
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
});

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

/** Candidate ids a run carries (public: ids only), for the field-line policy. */
export async function runCandidates(runId: string): Promise<string[]> {
  const rows = await getDb()
    .selectDistinct({ candidate: s.gamePredictions.candidate })
    .from(s.gamePredictions)
    .where(eq(s.gamePredictions.runId, runId))
    .orderBy(asc(s.gamePredictions.candidate));
  return rows.map((r) => r.candidate);
}

/** One game's simulated score distributions in a run (public: outcomes and shares only). */
export async function gameDistributions(runId: string, gameId: string): Promise<{ margin: unknown; total: unknown }> {
  const rows = await getDb()
    .select({ kind: s.scoreDistributions.kind, bins: s.scoreDistributions.bins })
    .from(s.scoreDistributions)
    .where(and(eq(s.scoreDistributions.runId, runId), eq(s.scoreDistributions.gameId, gameId)));
  return {
    margin: rows.find((r) => r.kind === "margin")?.bins ?? null,
    total: rows.find((r) => r.kind === "total")?.bins ?? null
  };
}

export const publicGame = cache(async (gameId: string) => {
  const { run, games } = await publicSlate();
  const game = games.find((g) => g.gameId === gameId) ?? null;
  return { run, game };
});

/**
 * The promotion gates of the published backtest, as far as the public field-line policy reads
 * them (candidate and Brier status), in one query. The home and game pages need only this,
 * not the seven queries of evidence(); with no published backtest it is empty, as
 * evidence() being null was.
 */
export const publicGates = cache(async (): Promise<GateRow[]> => {
  return getDb()
    .select({ candidate: s.promotionGates.candidate, brierStatus: s.promotionGates.brierStatus })
    .from(s.publishPointers)
    .innerJoin(s.backtestRuns, eq(s.backtestRuns.runId, s.publishPointers.runId))
    .innerJoin(s.promotionGates, eq(s.promotionGates.btRunId, s.backtestRuns.btRunId))
    .where(eq(s.publishPointers.pointer, "backtest_games"))
    .orderBy(asc(s.promotionGates.candidate));
});

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
  if (!run) return { run, games, candidate: null as string | null, lines: [], recs: [] };
  const candidate = deskCandidate(await runCandidates(run.runId));
  const lines = candidate ? await candidateLines(run.runId, [candidate]) : [];
  const recs = await getDb().select().from(s.recommendations).where(eq(s.recommendations.runId, run.runId));
  return { run, games, candidate, lines, recs };
}

function aliasTeams(name: string) {
  return alias(s.teams, name);
}

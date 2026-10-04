/**
 * A simulator run (A8): the probabilities the pages read are the bundle's numbers,
 * exactly. Ingests the committed fixtures with the simulator bundle last, so it is the
 * published weekly run, as after `Rscript run_week.R` and `npm run local`.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { FIXTURE_BUNDLES, freshDb, hasDb, TEST_DATABASE_URL } from "../../test/pg";
import { ingestBundle, loadBundle } from "../ingest/ingest";

const SIM = join(FIXTURE_BUNDLES, "weekly-sim-2024-w15");
type Pred = { game_id: string; candidate: string; p_home_final?: number; p_home_mkt_novig?: number };
const preds = JSON.parse(readFileSync(join(SIM, "game_predictions.json"), "utf8")) as Pred[];
const row = (gameId: string, candidate: string) => preds.find((p) => p.game_id === gameId && p.candidate === candidate);
const PRIVATE_KEY = /stake|^ev$|recommend|kelly|pass_?reason/i;

function keys(v: unknown, out = new Set<string>()): Set<string> {
  if (Array.isArray(v)) v.forEach((x) => keys(x, out));
  else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) { out.add(k); keys(x, out); }
  return out;
}

describe.skipIf(!hasDb)("a published simulator run (Postgres)", () => {
  let q: typeof import("./queries");
  let db: typeof import("../../db");

  beforeAll(async () => {
    const { db: tdb, client } = await freshDb();
    for (const b of ["weekly-2026-w04", "backtest-nfl-games-v1", "weekly-sim-2024-w15"]) {
      await ingestBundle(tdb, loadBundle(join(FIXTURE_BUNDLES, b)));
    }
    await client.end({ timeout: 5 });
    process.env.DATABASE_URL = TEST_DATABASE_URL;
    db = await import("../../db");
    q = await import("./queries");
  });
  afterAll(async () => {
    await db?.closeDb();
  });

  it("is the published weekly run and carries the market (C0) and the simulator (C3)", async () => {
    const { run, games } = await q.publicSlate();
    expect(run?.modelLabel).toBe("Game simulator C3 (unvalidated)");
    expect(games.map((g) => g.gameId).sort()).toEqual(["2024_15_BAL_NYG", "2024_15_BUF_DET", "2024_15_LA_SF"]);
    expect(await q.runCandidates(run!.runId)).toEqual(["C0", "C3"]);
  });

  it("the market each page reads is the bundle's p_home_mkt_novig, exactly, and null without a line (M11)", async () => {
    const { games } = await q.publicSlate();
    for (const g of games) expect(g.pMarket, g.gameId).toBe(row(g.gameId, "C0")?.p_home_mkt_novig ?? null);
    expect(games.find((g) => g.gameId === "2024_15_BUF_DET")?.pMarket).toBeNull();
  });

  it("the simulator line each page reads is the bundle's C3 p_home_final, exactly", async () => {
    const { run } = await q.publicSlate();
    const lines = await q.candidateLines(run!.runId, ["C3"]);
    expect(lines).toHaveLength(3);
    for (const l of lines) expect(l.p, l.gameId).toBe(row(l.gameId, "C3")!.p_home_final!);
  });

  it("each game has margin and total distributions, and no public read carries a private field", async () => {
    const { run, games } = await q.publicSlate();
    for (const g of games) {
      const d = await q.gameDistributions(run!.runId, g.gameId);
      expect(Array.isArray(d.margin) && Array.isArray(d.total), g.gameId).toBe(true);
      expect([...keys(d)].filter((k) => PRIVATE_KEY.test(k))).toEqual([]);
    }
    expect([...keys(await q.runCandidates(run!.runId))].filter((k) => PRIVATE_KEY.test(k))).toEqual([]);
  });
});

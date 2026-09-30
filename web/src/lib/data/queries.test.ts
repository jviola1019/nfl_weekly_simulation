import { join } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { FIXTURE_BUNDLES, freshDb, hasDb, TEST_DATABASE_URL } from "../../test/pg";
import { ingestBundle, loadBundle } from "../ingest/ingest";

/** Every key anywhere in a value (objects and arrays, recursively). */
function keys(v: unknown, out = new Set<string>()): Set<string> {
  if (Array.isArray(v)) v.forEach((x) => keys(x, out));
  else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) { out.add(k); keys(x, out); }
  return out;
}
const PRIVATE_KEY = /stake|^ev$|recommend|kelly|pass_?reason/i;

describe.skipIf(!hasDb)("public queries never carry stakes (Postgres)", () => {
  let q: typeof import("./queries");
  let db: typeof import("../../db");

  beforeAll(async () => {
    const { db: tdb, client } = await freshDb();
    await ingestBundle(tdb, loadBundle(join(FIXTURE_BUNDLES, "weekly-2026-w04")));
    await ingestBundle(tdb, loadBundle(join(FIXTURE_BUNDLES, "backtest-nfl-games-v1")));
    await client.end({ timeout: 5 });
    process.env.DATABASE_URL = TEST_DATABASE_URL;
    db = await import("../../db");
    q = await import("./queries");
  });
  afterAll(async () => {
    await db?.closeDb();
  });

  it("the weekly fixture really has staked-shape recommendations to leak", async () => {
    const desk = await q.deskSlate();
    expect(desk.recs.length).toBeGreaterThan(0);
    expect([...keys(desk.recs)].some((k) => PRIVATE_KEY.test(k))).toBe(true);
  });

  it("publicSlate, publicGame, candidateLines, evidence, ledger and dataHealth expose no private field", async () => {
    const slate = await q.publicSlate();
    expect(slate.games.length).toBe(16);
    const results = {
      slate,
      game: await q.publicGame(slate.games[0]!.gameId),
      lines: await q.candidateLines(slate.run!.runId, ["C0"]),
      evidence: await q.evidence(),
      ledger: await q.ledger(),
      health: await q.dataHealth()
    };
    for (const [name, value] of Object.entries(results)) {
      const leaked = [...keys(value)].filter((k) => PRIVATE_KEY.test(k));
      expect(leaked, name).toEqual([]);
    }
  });
});

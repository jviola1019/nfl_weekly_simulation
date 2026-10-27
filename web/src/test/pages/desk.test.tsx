import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

// a signed-in desk whose run has a paper lean on a game the slate no longer lists (Ruling R2):
// the strict DataTable cell guard (Task 2) throws on an undefined cell, so the side must fall
// back to the stored side rather than to the team of a game that is not there
vi.mock("@/lib/auth", () => ({ signOut: async () => {} }));
vi.mock("@/lib/auth/requireUser", () => ({ requireUser: async () => ({ email: "desk@example.test" }) }));
vi.mock("@/lib/data/queries", () => ({
  deskSlate: async () => ({
    run: { season: 2026, week: 4, cycleId: "2026-w04-test", dataAsofUtc: "2026-09-27T12:00:00Z" },
    games: [],
    candidate: "C2",
    lines: [],
    recs: [
      {
        recId: "r1",
        gameId: "2026_04_GONE_AWAY",
        side: "home",
        tier: "lean",
        pModel: 0.61,
        pMktNovig: 0.55,
        priceAmerican: -120,
        stakePct: 0.004,
        passReason: null
      }
    ]
  })
}));

describe("the desk with a lean whose game is missing from the slate", () => {
  it("renders the stored side instead of throwing on a missing cell", async () => {
    const { default: DeskPage } = await import("../../app/desk/page");
    const html = renderToStaticMarkup(await DeskPage());
    expect(html).toContain('data-desk="recommendations"');
    expect(html).toContain("2026_04_GONE_AWAY");
    expect(html).toMatch(/<td[^>]*>home<\/td>/);
    expect(html).not.toMatch(/\bundefined\b|NaN/);
  }, 30_000);
});

import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

// the home page before anything has been ingested: the queries find no run and no backtest
vi.mock("@/lib/data/queries", () => ({
  publicSlate: async () => ({ run: null, games: [] }),
  publicGates: async () => [],
  runCandidates: async () => [],
  candidateLines: async () => []
}));

describe("the home page with nothing ingested", () => {
  // the first import of a page compiles its whole module graph; on a cold cache and a busy machine that takes longer than the 5 s default
  it("says there is no run, states that in its context line, and has one h1", async () => {
    const { default: ThisWeek } = await import("../../app/page");
    const html = renderToStaticMarkup(await ThisWeek({ searchParams: Promise.resolve({}) }));
    expect(html).toContain("No published weekly run");
    expect(html).toContain("none published (nothing has been ingested)");
    expect(html.match(/<h1/g)).toHaveLength(1);
    expect(html).not.toMatch(/\bnull\b|undefined|NaN/);
  }, 30_000);
});

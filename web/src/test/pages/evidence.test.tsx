import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

// the evidence page before any backtest has been ingested
vi.mock("@/lib/data/queries", () => ({
  evidence: async () => null,
  ledger: async () => []
}));

describe("the evidence page with no backtest ingested", () => {
  // the first import of a page compiles its whole module graph; on a cold cache and a busy machine that takes longer than the 5 s default
  it("says so, states that in its context line, and has one h1", async () => {
    const { default: EvidencePage } = await import("../../app/evidence/page");
    const html = renderToStaticMarkup(await EvidencePage({ searchParams: Promise.resolve({}) }));
    expect(html).toContain("No backtest ingested");
    expect(html).toContain("none published (no backtest has been ingested)");
    expect(html.match(/<h1/g)).toHaveLength(1);
    expect(html).not.toMatch(/\bnull\b|undefined|NaN/);
  }, 30_000);
});

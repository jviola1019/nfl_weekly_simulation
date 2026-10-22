import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

// data health before anything has been ingested
vi.mock("@/lib/data/queries", () => ({
  dataHealth: async () => ({ run: null, sources: [], ingests: [], runs: [] })
}));

describe("the data-health page with nothing ingested", () => {
  // the first import of a page compiles its whole module graph; on a cold cache and a busy machine that takes longer than the 5 s default
  it("says there is no run, states that in its context line, and still draws every section", async () => {
    const { default: DataHealthPage } = await import("../../app/data-health/page");
    const html = renderToStaticMarkup(await DataHealthPage());
    expect(html).toContain("No published weekly run");
    expect(html).toContain("none published (nothing has been ingested)");
    for (const title of ["Sources for this run", "Recent runs", "Ingest log", "Unmatched entities"]) expect(html, title).toContain(title);
    expect(html.match(/<h1/g)).toHaveLength(1);
    expect(html).not.toMatch(/\bnull\b|undefined|NaN/);
  }, 30_000);
});

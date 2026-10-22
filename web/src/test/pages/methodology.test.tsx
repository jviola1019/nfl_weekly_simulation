import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { TERM_IDS, termAnchor } from "../../lib/glossary";

// the methodology page before anything has been ingested: it is generated from runs, but it must still read
vi.mock("@/lib/data/queries", () => ({
  evidence: async () => null,
  pointerRun: async () => null,
  ledger: async () => []
}));

describe("the methodology page with nothing ingested", () => {
  // the first import of a page compiles its whole module graph; on a cold cache and a busy machine that takes longer than the 5 s default
  it("still defines every term, states that it has no run, and has one h1", async () => {
    const { default: MethodologyPage } = await import("../../app/methodology/page");
    const html = renderToStaticMarkup(await MethodologyPage());
    expect(html).toContain("none published (nothing has been ingested)");
    for (const id of TERM_IDS) expect(html, id).toContain(`id="${termAnchor(id)}"`);
    expect(html.match(/<h1/g)).toHaveLength(1);
    expect(html).not.toMatch(/\bnull\b|undefined|NaN/);
  }, 30_000);
});

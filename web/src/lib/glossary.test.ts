import { describe, expect, it } from "vitest";
import { TERM_IDS, TERMS, termAnchor, termHref } from "./glossary";

describe("glossary", () => {
  it("has a label and a one-sentence-or-two definition for every term, in plain words", () => {
    expect(TERM_IDS.length).toBe(13);
    for (const id of TERM_IDS) {
      const t = TERMS[id];
      expect(t.label.length, id).toBeGreaterThan(2);
      expect(t.definition.length, id).toBeGreaterThan(40);
      expect(t.definition.length, id).toBeLessThan(260);
      expect(t.definition.endsWith("."), id).toBe(true);
    }
  });

  it("anchors are the term ids, lower-case with hyphens, and link to the methodology page", () => {
    for (const id of TERM_IDS) {
      expect(id).toMatch(/^[a-z]+(-[a-z]+)*$/);
      expect(termAnchor(id)).toBe(`term-${id}`);
      expect(termHref(id)).toBe(`/methodology#term-${id}`);
    }
  });

  it("states the numbers the pages already state (shrinkage weight, bootstrap size, the 50% Brier floor)", () => {
    expect(TERMS.shrinkage.definition).toContain("70%");
    expect(TERMS.interval.definition).toContain("10,000");
    expect(TERMS.brier.definition).toContain("0.25");
  });

  it("defines the gap as the absolute difference the home page computes (Math.abs, B2 final review I2)", () => {
    expect(TERMS.gap.definition).toMatch(/absolute difference/);
    expect(TERMS.gap.definition).not.toMatch(/minus/);
  });
});

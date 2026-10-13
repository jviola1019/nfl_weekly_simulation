import { scaleLinear as visxLinear } from "@visx/scale";
import { describe, expect, it } from "vitest";
import { linearScale } from "./linearScale";

describe("linearScale (the score-distribution charts' scale, without d3-scale in the page bundle)", () => {
  it("maps a domain to a range and back", () => {
    const x = linearScale({ domain: [-10.5, 14.5], range: [44, 704] });
    expect(x(-10.5)).toBe(44);
    expect(x(14.5)).toBe(704);
    expect(x(2)).toBeCloseTo(374, 9);
    expect(x.invert(374)).toBeCloseTo(2, 9);
  });

  it("matches @visx/scale (d3-scale) for call, invert, nice and ticks over many domains", () => {
    const cases: [number, number][] = [[0, 0.0618], [0, 0.0114], [0, 1], [0, 0.5], [0, 0.0003], [0, 0.2499], [0, 0.0351], [0, 0.9], [0, 12], [0, 0.07]];
    for (const [lo, hi] of cases) {
      for (const range of [[260, 44], [196, 44], [9, 3]] as [number, number][]) {
        const mine = linearScale({ domain: [lo, hi], range, nice: true });
        const ref = visxLinear({ domain: [lo, hi], range, nice: true });
        expect(mine.domain()).toEqual(ref.domain());
        expect(mine.ticks(4)).toEqual(ref.ticks(4));
        for (const v of mine.ticks(4)) expect(mine(v)).toBeCloseTo(ref(v) as number, 9);
        expect(mine.invert(range[0] + 0.5 * (range[1] - range[0]))).toBeCloseTo(ref.invert(range[0] + 0.5 * (range[1] - range[0])), 9);
      }
    }
    for (const domain of [[-0.5, 30.5], [-35.5, 42.5], [18.5, 74.5]] as [number, number][]) {
      const mine = linearScale({ domain, range: [44, 704] });
      const ref = visxLinear({ domain, range: [44, 704] });
      for (const v of [domain[0], 0, 7, 21, domain[1]]) expect(mine(v)).toBeCloseTo(ref(v) as number, 9);
      expect(mine.invert(300)).toBeCloseTo(ref.invert(300), 9);
    }
  });
});

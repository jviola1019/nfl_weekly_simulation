import { describe, expect, it } from "vitest";
import {
  binQuantile,
  columnPath,
  coveredMass,
  distributionSummary,
  marginLabel,
  outcomeLabel,
  parseBins,
  stepPaths,
  ticksEvery
} from "./distribution";

const SYM = [
  { x: -1, p: 0.25 },
  { x: 0, p: 0.5 },
  { x: 1, p: 0.25 }
];

describe("parseBins", () => {
  it("accepts contiguous integer bins and sorts them", () => {
    expect(parseBins([{ x: 1, p: 0.25 }, { x: -1, p: 0.25 }, { x: 0, p: 0.5 }])).toEqual(SYM);
  });

  it("rejects anything that is not one share per integer outcome", () => {
    expect(parseBins(null)).toBeNull();
    expect(parseBins([])).toBeNull();
    expect(parseBins({ x: 0, p: 1 })).toBeNull();
    expect(parseBins([{ x: 0.5, p: 1 }])).toBeNull();                     // not an integer outcome
    expect(parseBins([{ x: 0, p: -0.1 }])).toBeNull();                    // negative share
    expect(parseBins([{ x: 0, p: 0.6 }, { x: 0, p: 0.4 }])).toBeNull();   // duplicate x
    expect(parseBins([{ x: 0, p: 0.5 }, { x: 2, p: 0.5 }])).toBeNull();   // a gap
    expect(parseBins([{ x: 0, p: 0.7 }, { x: 1, p: 0.7 }])).toBeNull();   // more than all the games
    expect(parseBins([{ x: 0, p: 0 }])).toBeNull();                       // nothing covered
  });
});

describe("quantiles and labels", () => {
  it("reads quantiles from the full distribution, splitting the uncovered share between the tails", () => {
    expect(coveredMass(SYM)).toBe(1);
    expect(binQuantile(SYM, 0.5)).toBe(0);
    expect(binQuantile(SYM, 0.05)).toBe(-1);
    expect(binQuantile(SYM, 0.95)).toBe(1);
    const covered = [{ x: 10, p: 0.4 }, { x: 11, p: 0.4 }];   // 20% uncovered: 10% in each tail
    expect(binQuantile(covered, 0.45)).toBe(10);
    expect(binQuantile(covered, 0.55)).toBe(11);
  });

  it("names a margin by the team it favours and a total in points", () => {
    expect(marginLabel(3, "SF", "LA")).toBe("SF by 3");
    expect(marginLabel(-7, "SF", "LA")).toBe("LA by 7");
    expect(marginLabel(0, "SF", "LA")).toBe("Tie");
    expect(outcomeLabel("total", 41, "SF", "LA")).toBe("41 points");
  });

  it("summarises the median, the central 90% and the result in words", () => {
    expect(distributionSummary("margin", SYM, 100000, "SF", "LA", -6)).toBe(
      "Simulator (unvalidated): median margin Tie. In 90% of the 100,000 simulated games the margin falls between LA by 1 and SF by 1. Final: LA by 6."
    );
    expect(distributionSummary("total", [{ x: 40, p: 0.5 }, { x: 41, p: 0.5 }], null, "SF", "LA", null)).toBe(
      "Simulator (unvalidated): median total 40 points. In 90% of the simulated games the total falls between 40 and 41 points."
    );
  });
});

describe("geometry", () => {
  it("draws each bin as a flat step from x - 0.5 to x + 0.5 and closes the area on the baseline", () => {
    const x = (v: number) => v * 10;
    const y = (v: number) => 100 - v * 100;
    const { line, area } = stepPaths([{ x: 1, p: 0.25 }, { x: 2, p: 0.5 }], x, y);
    expect(line).toBe("M5,75L15,75L15,50L25,50");
    expect(area).toBe("M5,100L5,75L15,75L15,50L25,50L25,100Z");
  });

  it("rounds a column's data end and keeps it square at the baseline, even when it is shorter than the radius", () => {
    expect(columnPath(10, 100, 40, 8, 2)).toBe("M6,100v-38q0,-2 2,-2h4q2,0 2,2v38z");
    expect(columnPath(10, 100, 1, 8, 2)).toBe("M6,100v0q0,-1 1,-1h6q1,0 1,1v0z");
  });

  it("puts ticks on football-sized steps", () => {
    expect(ticksEvery(-20.5, 14.5, 7)).toEqual([-14, -7, 0, 7, 14]);
    expect(ticksEvery(9.5, 80.5, 10)).toEqual([10, 20, 30, 40, 50, 60, 70, 80]);
  });
});

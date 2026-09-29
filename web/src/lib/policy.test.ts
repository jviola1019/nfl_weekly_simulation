import { describe, expect, it } from "vitest";
import { candidateLabel, publicModelCandidates } from "./policy";

describe("public display policy", () => {
  it("shows a model line only for candidates that passed Confirm", () => {
    const gates = [
      { candidate: "C1", brierStatus: "not better than market" },
      { candidate: "C2", brierStatus: "passes Confirm; Holdout pending" },
      { candidate: "E1", brierStatus: "failed controls" }
    ];
    expect(publicModelCandidates(gates)).toEqual(["C2"]);
  });

  it("with nfl_games_v1 (every candidate not better than market) nothing is public", () => {
    const gates = ["C1", "C2", "E1", "K[E1]", "B1[E1]", "B2[E1]"].map((candidate) => ({ candidate, brierStatus: "not better than market" }));
    expect(publicModelCandidates(gates)).toEqual([]);
  });

  it("labels registered candidates and passes unknown ids through", () => {
    expect(candidateLabel("B2[E1]")).toBe("95% market, 5% ensemble");
    expect(candidateLabel("Z9")).toBe("Z9");
  });
});

import { describe, expect, it } from "vitest";
import {
  candidateLabel,
  deskCandidate,
  deskLead,
  NO_LEANS_SIMULATOR,
  fieldLineNote,
  fieldLineNoun,
  fieldLineShortNote,
  publicFieldLine,
  publicModelCandidates,
  RESEARCH_LINE_CANDIDATE,
  SIMULATOR_CANDIDATE
} from "./policy";

const V1 = ["C0", "C1", "C2", "E1", "B1[E1]", "B2[E1]", "K[E1]"];   // a prospective nfl_games_v1 run
const SIM = ["C0", "C3"];                                          // a run_week.R simulator run (A8)
const failing = (cands: string[]) => cands.map((candidate) => ({ candidate, brierStatus: "not better than market" }));

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
    expect(publicModelCandidates(failing(["C1", "C2", "E1", "K[E1]", "B1[E1]", "B2[E1]"]))).toEqual([]);
  });

  it("the field shows a validated candidate when one passed its gates and the run carries it", () => {
    const gates = [
      { candidate: "E1", brierStatus: "not better than market" },
      { candidate: "C2", brierStatus: "passes Confirm; Holdout pending" }
    ];
    expect(publicFieldLine(gates, V1)).toEqual({ candidate: "C2", validated: true });
    expect(publicFieldLine(gates, SIM)).toEqual({ candidate: SIMULATOR_CANDIDATE, validated: false });
  });

  it("otherwise the research line E1, marked unvalidated (owner decision 2026-10-01)", () => {
    expect(publicFieldLine(failing(["C1", "C2", "E1"]), V1)).toEqual({ candidate: RESEARCH_LINE_CANDIDATE, validated: false });
    expect(publicFieldLine([], V1)).toEqual({ candidate: "E1", validated: false });
    expect(RESEARCH_LINE_CANDIDATE).toBe("E1");
  });

  it("a simulator run shows the simulator line, marked unvalidated (A8)", () => {
    expect(publicFieldLine([], SIM)).toEqual({ candidate: "C3", validated: false });
    expect(publicFieldLine(failing(["C1", "C2", "E1"]), SIM)).toEqual({ candidate: "C3", validated: false });
    expect(publicFieldLine([], [...SIM, "E1"])).toEqual({ candidate: "E1", validated: false });
  });

  it("a run with no model candidate shows the market alone", () => {
    expect(publicFieldLine([], ["C0"])).toBeNull();
    expect(publicFieldLine([], [])).toBeNull();
  });

  it("the copy names what the gold line is and how far to trust it", () => {
    const sim = { candidate: "C3", validated: false };
    const e1 = { candidate: "E1", validated: false };
    const ok = { candidate: "C2", validated: true };
    expect(fieldLineNoun(sim)).toBe("the game simulator");
    expect(fieldLineNoun(e1)).toBe("our research model");
    expect(fieldLineNoun(ok)).toBe("a validated model");
    expect(fieldLineNote(sim)).toContain("has not been through the pre-registered test");
    expect(fieldLineNote(e1)).toContain("570 games");
    expect(fieldLineNote(ok)).toContain("passed its pre-registered gates");
    expect(fieldLineNote(null)).toContain("market alone");
    expect(fieldLineShortNote(sim)).toBe(
      "Simulator (unvalidated): the simulation's win probability after the production pipeline's 70% weight on the no-vig market (SHRINKAGE). Games without a market show the unshrunk value. Not yet in the pre-registered test."
    );
    expect(fieldLineNote(sim)).toContain("after the production pipeline's 70% weight on the no-vig market");
    expect(fieldLineShortNote(e1)).toBe("No model beat the closing market in the pre-registered test.");
  });

  it("labels registered candidates and the simulator, and passes unknown ids through", () => {
    expect(candidateLabel("B2[E1]")).toBe("95% market, 5% ensemble");
    expect(candidateLabel("C3")).toBe("Simulator");
    expect(candidateLabel("Z9")).toBe("Z9");
  });
});

describe("desk candidate (final review I1)", () => {
  it("C2 when the run carries it, else the simulator C3, else none", () => {
    expect(deskCandidate(V1)).toBe("C2");
    expect(deskCandidate(SIM)).toBe("C3");
    expect(deskCandidate([...SIM, "C2"])).toBe("C2");
    expect(deskCandidate(["C0"])).toBeNull();
    expect(deskCandidate([])).toBeNull();
  });

  it("the nfl_games_v1 sentence appears only for the v1 candidates", () => {
    expect(deskLead("C2")).toContain("failed to beat the closing market (nfl_games_v1)");
    expect(deskLead("C3")).not.toContain("nfl_games_v1");
    expect(deskLead("C3")).toContain("simulator");
    expect(deskLead(null)).not.toContain("nfl_games_v1");
  });

  it("names where paper stakes live when a simulator run has no recommendations", () => {
    expect(NO_LEANS_SIMULATOR).toBe("No paper leans in a simulator run; paper stakes are in artifacts/baseline_games.csv.");
  });
});

/**
 * Public display policy (spec §4 "Public content follows the evidence"; shootout
 * design "Candidates that fail stay in the report ... the public site shows
 * market-equivalent probabilities for them, and no picks").
 *
 * A model line appears on public pages only for a candidate whose promotion gates
 * put it at "passes Confirm; Holdout pending" or better. Stakes are never public.
 * Checkpoint A7 confirms the final policy against actual results.
 */
export interface GateRow {
  candidate: string;
  brierStatus: string;
}

export function publicModelCandidates(gates: GateRow[]): string[] {
  return gates.filter((g) => g.brierStatus.startsWith("passes")).map((g) => g.candidate);
}

export const MARKET_CANDIDATE = "C0";

/** Short human labels for registered candidates (nfl_games_v1). */
export const CANDIDATE_LABELS: Record<string, string> = {
  C0: "Market (no-vig close)",
  C1: "Elo",
  C2: "EPA model",
  E1: "Elo + EPA ensemble",
  "B1[C1]": "Market stack with Elo",
  "B1[C2]": "Market stack with EPA",
  "B1[E1]": "Market stack with ensemble",
  "B2[E1]": "95% market, 5% ensemble",
  "K[E1]": "Calibrated ensemble"
};

export function candidateLabel(id: string): string {
  return CANDIDATE_LABELS[id] ?? id;
}

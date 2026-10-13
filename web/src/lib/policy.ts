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

/**
 * The gold line on public fields (owner decision 2026-10-01, with the Broadcast Line
 * redesign; extended at A8). A candidate that passed its gates is shown as validated.
 * Otherwise one research line, labelled unvalidated everywhere it appears: the Elo + EPA
 * ensemble when the published run has it, else the game simulator (run_week.R bundles).
 * Only candidates the run actually carries count. Stakes stay private.
 */
export const RESEARCH_LINE_CANDIDATE = "E1";
export const SIMULATOR_CANDIDATE = "C3";

/** What the simulator's number is (final review I2/O1): R/sim_bundle.R writes the shrunk probability. */
const SIMULATOR_LINE_BODY =
  "the simulation's win probability after the production pipeline's 70% weight on the no-vig market (SHRINKAGE). Games without a market show the unshrunk value.";
const SIMULATOR_LINE = `Its line is ${SIMULATOR_LINE_BODY}`;

export interface FieldLine {
  candidate: string;
  validated: boolean;
}

/** The gold line for a run with `available` candidates; null means the market alone. */
export function publicFieldLine(gates: GateRow[], available: readonly string[]): FieldLine | null {
  const have = new Set(available);
  const passed = publicModelCandidates(gates).find((c) => have.has(c));
  if (passed) return { candidate: passed, validated: true };
  const research = [RESEARCH_LINE_CANDIDATE, SIMULATOR_CANDIDATE].find((c) => have.has(c));
  return research ? { candidate: research, validated: false } : null;
}

/** What the gold line is, for "Blue is the market; gold is …". */
export function fieldLineNoun(line: FieldLine): string {
  if (line.validated) return "a validated model";
  return line.candidate === SIMULATOR_CANDIDATE ? "the game simulator" : "our research model";
}

/** How far to trust the gold line, in one or two sentences (home page). */
export function fieldLineNote(line: FieldLine | null): string {
  if (!line) return "This run has no model line, so the fields show the market alone.";
  if (line.validated) return "This model passed its pre-registered gates. It is still not betting advice.";
  if (line.candidate === RESEARCH_LINE_CANDIDATE) {
    return "In the pre-registered test on 2023–24 (570 games), no model or blend beat the closing market's Brier score. Read the gold line as research output, never as advice.";
  }
  if (line.candidate === SIMULATOR_CANDIDATE) {
    return `The game simulator has not been through the pre-registered test yet. ${SIMULATOR_LINE} Read the gold line as research output, never as advice.`;
  }
  return "This line has not been validated. Read it as research output, never as advice.";
}

/** The short form beside a model's number (game page). */
export function fieldLineShortNote(line: FieldLine): string {
  if (line.validated) return "Passed its pre-registered gates.";
  if (line.candidate === RESEARCH_LINE_CANDIDATE) return "No model beat the closing market in the pre-registered test.";
  if (line.candidate === SIMULATOR_CANDIDATE) return `Simulator (unvalidated): ${SIMULATOR_LINE_BODY} Not yet in the pre-registered test.`;
  return "Not validated.";
}

export const MARKET_CANDIDATE = "C0";

/** The desk's paper-lean candidate: the EPA model C2 when the run carries it, else the simulator C3. */
export function deskCandidate(available: readonly string[]): string | null {
  const have = new Set(available);
  return ["C2", SIMULATOR_CANDIDATE].find((c) => have.has(c)) ?? null;
}

/** The desk's one-paragraph lead; the nfl_games_v1 verdict is true only of the v1 candidates. */
export function deskLead(candidate: string | null): string {
  if (candidate === SIMULATOR_CANDIDATE) {
    return "The game simulator has not been through the pre-registered test. Leans are tracked on paper to test the prospective closing-line-value hypothesis; stakes are zero.";
  }
  if (candidate === null) return "This run has no model candidate. Leans are tracked on paper; stakes are zero.";
  return "Every candidate here failed to beat the closing market (nfl_games_v1). Leans are tracked on paper to test the prospective closing-line-value hypothesis; stakes are zero.";
}

export const NO_LEANS_SIMULATOR = "No paper leans in a simulator run; paper stakes are in artifacts/baseline_games.csv.";


/** Short human labels for registered candidates (nfl_games_v1) and the simulator (A8). */
export const CANDIDATE_LABELS: Record<string, string> = {
  C0: "Market (no-vig close)",
  C1: "Elo",
  C2: "EPA model",
  C3: "Simulator",
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

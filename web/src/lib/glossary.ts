/**
 * Plain-language definitions of the terms the pages use. A page links a term to its entry on
 * /methodology (the <Term> component) and the methodology page renders every entry, so a link
 * can never point at a missing definition. The sentences restate what the methodology and
 * evidence pages already say; none of them is a new claim.
 */
export const TERMS = {
  "no-vig": {
    label: "No-vig probability",
    definition:
      "The market's win probability with the bookmaker's margin removed. Each moneyline becomes an implied probability, and the two are rescaled in proportion so they add to 100%."
  },
  close: {
    label: "Closing line",
    definition:
      "The market's last price before kickoff. Here it is the nflverse consensus close, which carries no timestamp and no sportsbook name, so line movement cannot be drawn from it."
  },
  field: {
    label: "The field",
    definition:
      "A game drawn as a football field. The line splits it by win chance, so each team's side is its probability of winning. Blue is the no-vig market, gold is the model, and the hatched band is the gap between them."
  },
  gap: {
    label: "Model–market gap",
    definition: "The model's home win probability minus the no-vig market's, in percentage points (pts)."
  },
  unvalidated: {
    label: "Unvalidated",
    definition: "The line has not passed its pre-registered gates. Read it as research output, never as advice."
  },
  shrinkage: {
    label: "Shrinkage toward the market",
    definition:
      "The simulator's win probability after a 70% weight on the no-vig market (the pipeline's SHRINKAGE setting). A game without a market line shows the unshrunk value."
  },
  brier: {
    label: "Brier score",
    definition:
      "The average squared gap between a predicted win probability and the result (1 if the home team won, 0 if not). Lower is better. A forecast of 50% every time scores 0.25."
  },
  skill: {
    label: "Brier skill against the market",
    definition:
      "One minus the candidate's Brier score divided by the market's. Zero means the candidate scored exactly as well as the market; above zero is better and below zero is worse."
  },
  interval: {
    label: "95% interval",
    definition:
      "A 95% range from a paired week-block bootstrap: 10,000 resamples of whole weeks, with the candidate and the market scored on the same ones. An interval that includes zero cannot be told apart from no difference."
  },
  ece: {
    label: "Expected calibration error (ECE)",
    definition:
      "How far predicted probabilities sit from the share of games the home team actually won, averaged over ten bins that each hold the same number of games. Lower is better."
  },
  clv: {
    label: "Closing-line value (CLV)",
    definition:
      "How far the no-vig price moved toward a pick between the opener and the close, in basis points: 10,000 × (close − open), both no-vig at the same venue. Positive means the price moved toward the pick."
  },
  "walk-forward": {
    label: "Walk-forward",
    definition:
      "Each week is predicted with a model fit only on games that kicked off before that week. A guard rejects any input that finished after kickoff."
  },
  holdout: {
    label: "Sealed holdout",
    definition: "The 2025 games, kept unscored until the protocol allows one single look."
  }
} as const satisfies Record<string, { label: string; definition: string }>;

export type TermId = keyof typeof TERMS;
export const TERM_IDS = Object.keys(TERMS) as TermId[];

/** The element id of a term's definition on the methodology page. */
export function termAnchor(id: TermId): string {
  return `term-${id}`;
}

/** Where a term is defined. */
export function termHref(id: TermId): string {
  return `/methodology#${termAnchor(id)}`;
}

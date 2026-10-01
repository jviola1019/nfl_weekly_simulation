/**
 * Team identity colours for end zones and team chips. The values live as tokens in
 * globals.css (--team-<ID>, --team-<ID>-2, --team-<ID>-ink); unknown ids fall back to
 * a neutral team token, so a relocated or new code never renders without colour.
 */
const KNOWN = new Set([
  "ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE", "DAL", "DEN", "DET", "GB", "HOU", "IND", "JAX", "KC",
  "LV", "LAC", "LA", "MIA", "MIN", "NE", "NO", "NYG", "NYJ", "PHI", "PIT", "SF", "SEA", "TB", "TEN", "WAS"
]);

export function teamColors(id: string): { primary: string; accent: string; ink: string } {
  const key = KNOWN.has(id) ? id : "default";
  return { primary: `var(--team-${key})`, accent: `var(--team-${key}-2)`, ink: `var(--team-${key}-ink)` };
}

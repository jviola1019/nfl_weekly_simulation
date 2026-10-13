/**
 * Home-page orderings. A game without a market line has no gap and no closeness, so it
 * goes last in both the gap and the closest sorts (final review M1), never first.
 */
export type SlateSort = "kickoff" | "gap" | "closest";

interface Sortable {
  g: { pMarket: number | null };
  gap: number;
}

export function sortSlate<T extends Sortable>(rows: readonly T[], sort: SlateSort): T[] {
  if (sort === "kickoff") return [...rows];
  const noMarket = (r: T) => r.g.pMarket === null;
  const key = (r: T) => (sort === "gap" ? -r.gap : Math.abs((r.g.pMarket as number) - 0.5));
  return [...rows].sort((a, b) => Number(noMarket(a)) - Number(noMarket(b)) || (noMarket(a) ? 0 : key(a) - key(b)));
}

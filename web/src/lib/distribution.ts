/**
 * Simulated score distributions (A8). The bundle's score_distributions.bins are one row
 * per integer outcome, {x, p}, over the central 99.9% of the simulator's draws, with p
 * the share of ALL draws (R/sim_bundle.R). The column is free JSON, so it is parsed and
 * checked here before anything is drawn; an unreadable distribution is reported on the
 * page, never guessed at.
 */
import { z } from "zod";

export interface Bin {
  x: number;
  p: number;
}

export type DistKind = "margin" | "total";

const BinsSchema = z.array(z.object({ x: z.number().int(), p: z.number().min(0).max(1) })).min(1);

/** Sorted bins, or null unless every x is an integer one apart and the shares sum to at most 1. */
export function parseBins(raw: unknown): Bin[] | null {
  const r = BinsSchema.safeParse(raw);
  if (!r.success) return null;
  const bins = [...r.data].sort((a, b) => a.x - b.x);
  for (let i = 1; i < bins.length; i++) if (bins[i]!.x !== bins[i - 1]!.x + 1) return null;
  const mass = coveredMass(bins);
  return mass > 0 && mass <= 1 + 1e-9 ? bins : null;
}

/** The share of all simulated games the bins cover. */
export function coveredMass(bins: Bin[]): number {
  return bins.reduce((a, b) => a + b.p, 0);
}

/** Quantile q of the full distribution; the uncovered share is split evenly between the tails. */
export function binQuantile(bins: Bin[], q: number): number {
  let cum = (1 - coveredMass(bins)) / 2;
  for (const b of bins) {
    cum += b.p;
    if (cum >= q - 1e-12) return b.x;
  }
  return bins[bins.length - 1]!.x;
}

/** A home-minus-away margin in words. */
export function marginLabel(x: number, homeId: string, awayId: string): string {
  if (x > 0) return `${homeId} by ${x}`;
  if (x < 0) return `${awayId} by ${-x}`;
  return "Tie";
}

/** An outcome in words: a margin by the team it favours, a total in points. */
export function outcomeLabel(kind: DistKind, x: number, homeId: string, awayId: string): string {
  return kind === "margin" ? marginLabel(x, homeId, awayId) : `${x} points`;
}

/** The chart's text summary: median, the central 90% of simulated games, and the result once final. */
export function distributionSummary(
  kind: DistKind,
  bins: Bin[],
  nSims: number | null,
  homeId: string,
  awayId: string,
  result: number | null
): string {
  const label = (v: number) => outcomeLabel(kind, v, homeId, awayId);
  const games = nSims ? `the ${nSims.toLocaleString("en-US")} simulated games` : "the simulated games";
  const final = result === null ? "" : ` Final: ${label(result)}.`;
  const med = binQuantile(bins, 0.5);
  const lo = binQuantile(bins, 0.05);
  const hi = binQuantile(bins, 0.95);
  if (kind === "margin") {
    return `Simulator (unvalidated): median margin ${label(med)}. In at least 90% of ${games} the margin falls between ${label(lo)} and ${label(hi)}.${final}`;
  }
  return `Simulator (unvalidated): median total ${med} points. In at least 90% of ${games} the total falls between ${lo} and ${hi} points.${final}`;
}

const r2 = (v: number) => Math.round(v * 100) / 100;

/** SVG paths of a step outline and its filled area; each bin spans x - 0.5 to x + 0.5. */
export function stepPaths(bins: Bin[], x: (v: number) => number, y: (v: number) => number): { line: string; area: string } {
  const steps = bins.flatMap((b) => [`${r2(x(b.x - 0.5))},${r2(y(b.p))}`, `${r2(x(b.x + 0.5))},${r2(y(b.p))}`]);
  const first = bins[0]!;
  const last = bins[bins.length - 1]!;
  return {
    line: `M${steps.join("L")}`,
    area: `M${r2(x(first.x - 0.5))},${r2(y(0))}L${steps.join("L")}L${r2(x(last.x + 0.5))},${r2(y(0))}Z`
  };
}

/** A column grown from the baseline with a rounded data end of radius r (square at the base). */
export function columnPath(cx: number, base: number, h: number, w: number, r: number): string {
  const rr = Math.min(r, w / 2, h);
  return `M${r2(cx - w / 2)},${r2(base)}v${r2(-(h - rr))}q0,${r2(-rr)} ${r2(rr)},${r2(-rr)}h${r2(w - 2 * rr)}q${r2(rr)},0 ${r2(rr)},${r2(rr)}v${r2(h - rr)}z`;
}

/** Multiples of step between lo and hi: football-sized ticks (7 points for margins, 10 for totals). */
export function ticksEvery(lo: number, hi: number, step: number): number[] {
  const out: number[] = [];
  for (let t = Math.ceil(lo / step) * step; t <= hi; t += step) out.push(t === 0 ? 0 : t);
  return out;
}

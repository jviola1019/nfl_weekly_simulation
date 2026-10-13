import { z } from "zod";
import { type Bin, coveredMass } from "./distribution";

/**
 * Validation of a bundle's score_distributions.bins (see ./distribution). Server-side only:
 * keep this module out of client components, because zod would ship to the browser.
 */
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

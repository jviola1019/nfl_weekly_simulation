import { createHash } from "node:crypto";
import { eq } from "drizzle-orm";
import type { Db } from "../../db";
import * as s from "../../db/schema";

/**
 * Durable login throttle (pattern from the fantasy_football_dashboard): per account,
 * per IP and a global ceiling, each a rolling window with a short lock. Keys are
 * hashed so the table never stores an email or an IP. Lockouts are short on purpose:
 * a long per-account lockout would itself let anyone lock a user out.
 */
const MINUTE = 60_000;
export const THROTTLE_RULES = {
  account: { windowMs: 15 * MINUTE, max: 8, lockMs: 15 * MINUTE },
  ip: { windowMs: 15 * MINUTE, max: 30, lockMs: 15 * MINUTE },
  global: { windowMs: 5 * MINUTE, max: 300, lockMs: 5 * MINUTE }
} as const;
export type Dimension = keyof typeof THROTTLE_RULES;

export function throttleKey(dim: Dimension, id: string): string {
  return dim === "global" ? "global" : createHash("sha256").update(`${dim}:${id.toLowerCase()}`).digest("hex");
}

export async function isLocked(db: Db, keys: string[], now = new Date()): Promise<boolean> {
  for (const key of keys) {
    const [row] = await db.select().from(s.authThrottle).where(eq(s.authThrottle.key, key));
    if (row?.lockedUntil && new Date(row.lockedUntil) > now) return true;
  }
  return false;
}

export async function recordFailure(db: Db, dim: Dimension, key: string, now = new Date()): Promise<void> {
  const rule = THROTTLE_RULES[dim];
  const [row] = await db.select().from(s.authThrottle).where(eq(s.authThrottle.key, key));
  const inWindow = row && now.getTime() - new Date(row.windowStart).getTime() < rule.windowMs;
  const failures = inWindow ? row.failures + 1 : 1;
  const lockedUntil = failures >= rule.max ? new Date(now.getTime() + rule.lockMs).toISOString() : null;
  const windowStart = inWindow ? row.windowStart : now.toISOString();
  await db
    .insert(s.authThrottle)
    .values({ key, failures, windowStart, lockedUntil })
    .onConflictDoUpdate({ target: s.authThrottle.key, set: { failures, windowStart, lockedUntil } });
}

export async function clearKey(db: Db, key: string): Promise<void> {
  await db.delete(s.authThrottle).where(eq(s.authThrottle.key, key));
}

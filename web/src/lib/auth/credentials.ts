import { eq } from "drizzle-orm";
import type { Db } from "../../db";
import * as s from "../../db/schema";
import { DUMMY_HASH, verifyPassword } from "../passwords";
import { clearKey, isLocked, recordFailure, throttleKey } from "./throttle";

export interface AuthedUser {
  id: string;
  email: string;
  sessionVersion: number;
}

/**
 * Verify an email/password pair. Every attempt pays one scrypt derivation, including
 * unknown accounts, so response time does not reveal which accounts exist.
 */
export async function authenticate(db: Db, email: string, password: string, ip: string): Promise<AuthedUser | null> {
  const keys = { account: throttleKey("account", email), ip: throttleKey("ip", ip), global: throttleKey("global", "") };
  if (await isLocked(db, Object.values(keys))) return null;
  const [user] = await db.select().from(s.users).where(eq(s.users.email, email.toLowerCase()));
  const ok = await verifyPassword(password, user?.passwordHash ?? DUMMY_HASH);
  if (!user || !ok) {
    await recordFailure(db, "account", keys.account);
    await recordFailure(db, "ip", keys.ip);
    await recordFailure(db, "global", keys.global);
    return null;
  }
  await clearKey(db, keys.account);
  return { id: user.id, email: user.email, sessionVersion: user.sessionVersion };
}

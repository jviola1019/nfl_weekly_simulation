/**
 * Create or reset the desk user from environment variables (never from code):
 *   DESK_EMAIL=... DESK_PASSWORD=... npx tsx scripts/seed-user.ts
 * Resetting bumps session_version, which revokes every existing session.
 */
import { randomUUID } from "node:crypto";
import { sql } from "drizzle-orm";
import { closeDb, getDb } from "../src/db";
import * as s from "../src/db/schema";
import { hashPassword } from "../src/lib/passwords";

const email = process.env.DESK_EMAIL?.trim().toLowerCase();
const password = process.env.DESK_PASSWORD;
if (!email || !password || password.length < 12) {
  console.error("set DESK_EMAIL and DESK_PASSWORD (12+ characters)");
  process.exit(2);
}
const passwordHash = await hashPassword(password);
await getDb()
  .insert(s.users)
  .values({ id: randomUUID(), email, passwordHash })
  .onConflictDoUpdate({ target: s.users.email, set: { passwordHash, sessionVersion: sql`${s.users.sessionVersion} + 1` } });
console.log(`desk user ready: ${email}`);
await closeDb();

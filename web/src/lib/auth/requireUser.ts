import { eq } from "drizzle-orm";
import { getDb, type Db } from "../../db";
import * as s from "../../db/schema";
import { auth } from "../auth";

export interface VerifiedUser {
  id: string;
  email: string;
}

/**
 * The authorization choke point for /desk (pattern from the fantasy_football_dashboard,
 * audit F-004): the JWT is a stateless claim, so the user must still exist and the
 * token's session version must match the database. Returns null instead of throwing.
 */
export async function requireUser(db: Db = getDb()): Promise<VerifiedUser | null> {
  const session = await auth().catch(() => null);
  const id = session?.user?.id;
  const sv = (session?.user as { sessionVersion?: number } | undefined)?.sessionVersion;
  if (!id) return null;
  const [user] = await db.select().from(s.users).where(eq(s.users.id, id));
  if (!user || user.sessionVersion !== sv) return null;
  return { id: user.id, email: user.email };
}

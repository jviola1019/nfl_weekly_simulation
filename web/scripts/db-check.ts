/**
 * Run the SQL data checks (src/lib/dbcheck/checks.ts) against DATABASE_URL.
 *   npm run db-check
 * Prints every violated check with sample rows. Exit 0 when no error check is violated (warnings
 * are printed), 1 when one is, 2 when DATABASE_URL is not set. The URL is never printed.
 */
import { closeDb, getDb } from "../src/db";
import { reportDbChecks } from "../src/lib/dbcheck/run";

if (!process.env.DATABASE_URL) {
  console.error("db-check: DATABASE_URL is not set");
  process.exit(2);
}
try {
  const { errors } = await reportDbChecks(getDb());
  if (errors > 0) process.exitCode = 1;
} finally {
  await closeDb();
}

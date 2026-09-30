/**
 * Postgres test harness. TEST_DATABASE_URL points at a throwaway database whose name
 * ends in "_test" (the harness drops and re-creates its schemas, so it refuses any
 * other name). CI sets REQUIRE_DB_TESTS=1, which turns a missing URL into a failure:
 * the pg integration suites must never be skipped there (spec §6, P6 gate).
 */
import { join } from "node:path";
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";
import type { Db } from "../db";
import * as schema from "../db/schema";

export const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL ?? "";
if (process.env.REQUIRE_DB_TESTS === "1" && !TEST_DATABASE_URL) {
  throw new Error("REQUIRE_DB_TESTS=1 but TEST_DATABASE_URL is not set: the pg integration tests must run");
}
export const hasDb = TEST_DATABASE_URL !== "";

export const FIXTURE_BUNDLES = join(import.meta.dirname, "..", "..", "..", "contracts", "fixtures", "bundles");

export async function freshDb(): Promise<{ db: Db; client: postgres.Sql }> {
  const name = new URL(TEST_DATABASE_URL).pathname.slice(1);
  if (!name.endsWith("_test")) throw new Error(`refusing to reset database "${name}": its name must end in _test`);
  const client = postgres(TEST_DATABASE_URL, { max: 1, onnotice: () => {} });
  await client.unsafe("DROP SCHEMA IF EXISTS drizzle CASCADE; DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;");
  const db = drizzle(client, { schema });
  await migrate(db, { migrationsFolder: join(import.meta.dirname, "..", "..", "drizzle") });
  return { db, client };
}

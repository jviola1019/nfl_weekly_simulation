import { drizzle, type PostgresJsDatabase } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

export { schema };
export type Db = PostgresJsDatabase<typeof schema>;

let cached: { db: Db; client: postgres.Sql } | null = null;

/** DATABASE_URL is required; there is no silent fallback database. */
export function databaseUrl(env: NodeJS.ProcessEnv = process.env): string {
  const url = env.DATABASE_URL;
  if (!url) throw new Error("DATABASE_URL is not set");
  return url;
}

export function getDb(): Db {
  if (!cached) {
    const client = postgres(databaseUrl(), { max: 5, prepare: false });
    cached = { db: drizzle(client, { schema }), client };
  }
  return cached.db;
}

export async function closeDb(): Promise<void> {
  if (cached) {
    await cached.client.end({ timeout: 5 });
    cached = null;
  }
}

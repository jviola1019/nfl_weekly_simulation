/** Apply drizzle/ migrations to DATABASE_URL (a workflow step in production, never at page load). */
import { fileURLToPath } from "node:url";
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";
import { databaseUrl } from "../src/db";

const client = postgres(databaseUrl(), { max: 1, onnotice: () => {} });
await migrate(drizzle(client), { migrationsFolder: fileURLToPath(new URL("../drizzle", import.meta.url)) });
await client.end();
console.log("migrations applied");

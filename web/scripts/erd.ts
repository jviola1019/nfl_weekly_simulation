/**
 * Write the ERD (docs/ERD.md) from the Drizzle schema.
 *   npm run erd             # rewrite docs/ERD.md
 *   npm run erd -- --check  # exit 1 when docs/ERD.md is stale
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { renderErd } from "../src/lib/erd";

const target = join(import.meta.dirname, "..", "..", "docs", "ERD.md");
const erd = renderErd();

if (process.argv.includes("--check")) {
  let current = "";
  try {
    current = readFileSync(target, "utf8").replace(/\r\n/g, "\n");
  } catch {
    current = "";
  }
  if (current !== erd) {
    console.error("docs/ERD.md is stale: run npm run erd");
    process.exit(1);
  }
  console.log("docs/ERD.md matches the schema");
} else {
  writeFileSync(target, erd);
  console.log(`wrote ${target}`);
}

/**
 * Write the generated contract to ../contracts/schema/*.json. CI re-runs this and
 * fails on any diff (the Drizzle schema is the single owner of the contract).
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";
import { BUNDLE_KINDS, manifestSchema, ROW_SCHEMAS, SCHEMA_VERSION } from "../src/lib/contracts/bundle";

export function contractFiles(): Record<string, string> {
  const out: Record<string, string> = {};
  const dump = (v: unknown) => `${JSON.stringify(v, null, 2)}\n`;
  out["manifest.schema.json"] = dump({ $comment: `generated; schema_version ${SCHEMA_VERSION}`, ...z.toJSONSchema(manifestSchema) });
  for (const [name, schema] of Object.entries(ROW_SCHEMAS)) {
    out[`${name}.schema.json`] = dump(z.toJSONSchema(schema, { io: "input" }));
  }
  out["bundle_kinds.json"] = dump({ schema_version: SCHEMA_VERSION, kinds: BUNDLE_KINDS });
  return out;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  const dir = join(import.meta.dirname, "..", "..", "contracts", "schema");
  mkdirSync(dir, { recursive: true });
  for (const [name, text] of Object.entries(contractFiles())) writeFileSync(join(dir, name), text);
  console.log(`wrote ${Object.keys(contractFiles()).length} files to ${dir}`);
}

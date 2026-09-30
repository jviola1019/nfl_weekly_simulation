import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { contractFiles } from "../../../scripts/export-contracts";
import { loadBundle } from "../ingest/ingest";
import { BUNDLE_KINDS, BUNDLE_TABLES, manifestSchema, ROW_SCHEMAS, schemaMajor, type BundleTableName } from "./bundle";

const REPO = join(import.meta.dirname, "..", "..", "..", "..");
const CONTRACTS = join(REPO, "contracts");
type Case = { table: BundleTableName; row: Record<string, unknown>; why?: string };
const fixtures = JSON.parse(readFileSync(join(CONTRACTS, "fixtures", "rows.json"), "utf8")) as { valid: Case[]; invalid: Case[] };

describe("contract drift", () => {
  it("contracts/schema matches what the Drizzle schema generates (run npm run contracts:export)", () => {
    const generated = contractFiles();
    const onDisk = readdirSync(join(CONTRACTS, "schema")).sort();
    expect(onDisk).toEqual(Object.keys(generated).sort());
    for (const [name, text] of Object.entries(generated)) {
      expect(readFileSync(join(CONTRACTS, "schema", name), "utf8"), name).toBe(text);
    }
  });

  it("every bundle table has a row schema and every bundle kind names only known tables", () => {
    expect(Object.keys(ROW_SCHEMAS).sort()).toEqual(Object.keys(BUNDLE_TABLES).sort());
    for (const spec of Object.values(BUNDLE_KINDS)) {
      for (const t of [...spec.required, ...spec.optional]) expect(BUNDLE_TABLES).toHaveProperty(t);
    }
  });
});

describe("shared row fixtures (the R validator runs the same file)", () => {
  it.each(fixtures.valid.map((c) => [c.table, c] as const))("accepts a valid %s row", (_t, c) => {
    const r = ROW_SCHEMAS[c.table].safeParse(c.row);
    expect(r.success, JSON.stringify(r.error?.issues)).toBe(true);
  });

  it.each(fixtures.invalid.map((c) => [`${c.table}: ${c.why}`, c] as const))("rejects %s", (_t, c) => {
    expect(ROW_SCHEMAS[c.table].safeParse(c.row).success).toBe(false);
  });

  it("covers every rule family at least once", () => {
    const whys = fixtures.invalid.map((c) => c.why ?? "").join(" | ");
    for (const rule of ["UTC", "required", "not in the contract", "enum", "above 1", "below 0", "string", "run_id"]) {
      expect(whys).toContain(rule);
    }
  });
});

describe("manifest", () => {
  const weekly = join(CONTRACTS, "fixtures", "bundles", "weekly-2026-w04");
  const backtest = join(CONTRACTS, "fixtures", "bundles", "backtest-nfl-games-v1");

  it("the committed fixture bundles load and validate end to end", () => {
    for (const dir of [weekly, backtest]) {
      const b = loadBundle(dir);
      expect(b.manifest.qa.ok).toBe(true);
      expect(b.sha256).toMatch(/^[0-9a-f]{64}$/);
      for (const need of BUNDLE_KINDS[b.manifest.bundle_kind].required) expect(b.rows[need]?.length ?? 0).toBeGreaterThan(0);
    }
  });

  it("rejects unknown keys and malformed hashes", () => {
    const m = JSON.parse(readFileSync(join(weekly, "manifest.json"), "utf8"));
    expect(manifestSchema.safeParse(m).success).toBe(true);
    expect(manifestSchema.safeParse({ ...m, extra: 1 }).success).toBe(false);
    expect(manifestSchema.safeParse({ ...m, config_hash: "abc" }).success).toBe(false);
    expect(manifestSchema.safeParse({ ...m, bundle_kind: "props" }).success).toBe(false);
    expect(manifestSchema.safeParse({ ...m, generated_utc: "2026-09-29 20:51" }).success).toBe(false);
  });

  it("reads the schema major version", () => {
    expect(schemaMajor("1.0.0")).toBe(1);
    expect(schemaMajor("2.3.1")).toBe(2);
    expect(Number.isNaN(schemaMajor("x"))).toBe(true);
  });
});

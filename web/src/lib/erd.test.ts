import { readFileSync } from "node:fs";
import { join } from "node:path";
import { is } from "drizzle-orm";
import { getTableConfig, PgTable } from "drizzle-orm/pg-core";
import { describe, expect, it } from "vitest";
import * as schema from "../db/schema";
import { renderErd } from "./erd";

/**
 * The ERD (docs/ERD.md) is generated from the Drizzle schema by `npm run erd`. These tests pin
 * what it must show and fail when the committed file and the schema disagree (C2).
 */
const REPO = join(import.meta.dirname, "..", "..", "..");
const erd = renderErd();
const tables = Object.values(schema).filter((v: unknown): v is PgTable => is(v, PgTable)).map((t) => getTableConfig(t));

describe("the ERD rendered from the schema", () => {
  it("has one entity per table, sorted by name, with every column", () => {
    const names = [...erd.matchAll(/^ {2}(\w+) \{$/gm)].map((m) => m[1]!);
    expect(names).toEqual(tables.map((t) => t.name).sort());
    for (const t of tables) {
      const block = erd.match(new RegExp(`^ {2}${t.name} \\{\\n([\\s\\S]*?)\\n {2}\\}$`, "m"))?.[1] ?? "";
      expect(block.split("\n").length, t.name).toBe(t.columns.length);
    }
  });

  it("marks keys: composite primary keys, foreign keys and unique columns", () => {
    expect(erd).toMatch(/game_predictions \{[^}]*text run_id PK, FK/);
    expect(erd).toMatch(/users \{[^}]*text email UK/);
    expect(erd).toMatch(/model_runs \{[^}]*text bundle_sha256 UK/);
    expect(erd).toMatch(/games \{[^}]*timestamptz kickoff_utc\n/);
  });

  it("draws one relationship per foreign key, optional when a column is nullable", () => {
    expect(erd).toContain('teams ||--o{ games : "away_team_id"');
    expect(erd).toContain('teams ||--o{ games : "home_team_id"');
    expect(erd).toContain('players |o--o{ odds_snapshots : "player_id"');
    expect(erd).toContain('recommendations ||--o{ bet_grades : "run_id, rec_id"');
    const relationships = erd.split("\n").filter((l) => /^ {2}\w+ (\|\||\|o)--o\{ \w+ : "/.test(l));
    expect(relationships.length).toBe(tables.reduce((n, t) => n + t.foreignKeys.length, 0));
  });

  it("docs/ERD.md is what the schema renders (run npm run erd after a schema change)", () => {
    const committed = readFileSync(join(REPO, "docs", "ERD.md"), "utf8").replace(/\r\n/g, "\n");
    expect(committed).toBe(erd);
  });
});

/**
 * Every ingest is followed by the SQL data checks (C2): each workflow step that runs
 * `npm run ingest` also runs `npm run db-check` after its last ingest, the CLI exists, and the
 * local runner reports the checks after its own ingest. The workflows are read as text (no YAML
 * dependency): a step starts at a `- name:` or `- uses:` line.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const WEB = join(import.meta.dirname, "..", "..");
const REPO = join(WEB, "..");
const WORKFLOWS = [".github/workflows/ci-web.yml", ".github/workflows/weekly-sim.yml"];

function steps(yaml: string): string[][] {
  const out: string[][] = [];
  for (const line of yaml.split(/\r?\n/)) {
    if (/^\s+- (name|uses):/.test(line)) out.push([]);
    out.at(-1)?.push(line);
  }
  return out;
}

describe("every ingest is followed by npm run db-check", () => {
  for (const file of WORKFLOWS) {
    it(`${file}: each step that ingests runs db-check after its last ingest`, () => {
      const ingesting = steps(readFileSync(join(REPO, file), "utf8")).filter((s) => s.some((l) => l.includes("npm run ingest")));
      expect(ingesting.length, "steps that ingest").toBeGreaterThan(0);
      for (const step of ingesting) {
        const last = step.findLastIndex((l) => l.includes("npm run ingest"));
        const after = step.slice(last + 1).map((l) => l.trim());
        expect(after, `${file}: ${step[0]!.trim()}`).toContain("npm run db-check");
      }
    });
  }

  it("the CLI and the local runner exist", () => {
    const pkg = JSON.parse(readFileSync(join(WEB, "package.json"), "utf8")) as { scripts: Record<string, string> };
    expect(pkg.scripts["db-check"]).toBe("tsx scripts/db-check.ts");
    expect(readFileSync(join(WEB, "scripts", "local.ts"), "utf8")).toContain("reportDbChecks(");
  });
});

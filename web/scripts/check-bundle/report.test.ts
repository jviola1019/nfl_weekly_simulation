import { cpSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { BundleRejected, loadBundle } from "../../src/lib/ingest/ingest";
import { bundleReport } from "./report";

const SIM = join(import.meta.dirname, "..", "..", "..", "contracts", "fixtures", "bundles", "weekly-sim-2024-w15");

describe("check-bundle (the weekly-sim workflow's check before upload and ingest)", () => {
  it("summarises a bundle the ingest accepts", () => {
    const b = loadBundle(SIM);
    expect(bundleReport(b)).toEqual([
      `ok weekly weekly-sim-2024-w15 (bundle ${b.sha256.slice(0, 12)}): 51 rows in teams, games, game_predictions, score_distributions, source_status; QA passed`
    ]);
  });

  it("turns each QA failure into a GitHub warning, because a QA-failed bundle is still stored (as qa_failed)", () => {
    const b = loadBundle(SIM);
    const failed = { ...b, manifest: { ...b.manifest, qa: { ok: false, failures: ["games: not in the schedule: X", "two\nlines"] } } };
    expect(bundleReport(failed)).toEqual([
      `ok weekly weekly-sim-2024-w15 (bundle ${b.sha256.slice(0, 12)}): 51 rows in teams, games, game_predictions, score_distributions, source_status; QA FAILED (2)`,
      "::warning title=Bundle QA::games: not in the schedule: X",
      "::warning title=Bundle QA::two lines"
    ]);
  });

  it("a tampered bundle is rejected before anything is reported", () => {
    const dir = mkdtempSync(join(tmpdir(), "check-bundle-"));
    cpSync(SIM, dir, { recursive: true });
    const games = join(dir, "games.json");
    writeFileSync(games, readFileSync(games, "utf8").replace('"home_score":6', '"home_score":7'));
    expect(() => loadBundle(dir)).toThrow(BundleRejected);
    expect(() => loadBundle(dir)).toThrow("games.json: sha256 does not match the manifest");
  });
});

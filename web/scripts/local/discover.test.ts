import { cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { loadBundle } from "../../src/lib/ingest/ingest";
import { selectBundleDirs } from "./config";
import { discoverBundles } from "./discover";

const FIXTURE = join(__dirname, "..", "..", "..", "contracts", "fixtures", "bundles", "weekly-sim-2024-w15");
let tmp = "";
afterEach(() => tmp && rmSync(tmp, { recursive: true, force: true }));
const bundles = () => (tmp = mkdtempSync(join(tmpdir(), "nfl-discover-")));

describe("bundle discovery (npm run local)", () => {
  it("finds a bundle laid out the way actions/download-artifact writes it: manifest.json at the directory root", () => {
    // gh run download <run-id> -n sim-bundle -D bundles/<cycle_id>
    const root = bundles();
    const dir = join(root, "2024-w15-sim-20261013T052558Z");
    cpSync(FIXTURE, dir, { recursive: true });
    const found = discoverBundles(root);
    expect(found.strayManifest).toBe(false);
    expect(selectBundleDirs(found.entries)).toEqual({ ingest: ["2024-w15-sim-20261013T052558Z"], skipped: [] });
    expect(loadBundle(dir).manifest.cycle_id).toBe("weekly-sim-2024-w15");   // and it loads and verifies as downloaded
  });

  it("skips a directory without a readable manifest and ignores plain files", () => {
    const root = bundles();
    mkdirSync(join(root, "empty"));
    mkdirSync(join(root, "broken"));
    writeFileSync(join(root, "broken", "manifest.json"), "{ not json");
    writeFileSync(join(root, "notes.txt"), "x");
    const found = discoverBundles(root);
    expect(selectBundleDirs(found.entries)).toEqual({ ingest: [], skipped: ["broken", "empty"] });
  });

  it("flags a manifest.json sitting directly in bundles/ (downloaded without a cycle directory)", () => {
    const root = bundles();
    cpSync(FIXTURE, root, { recursive: true });
    expect(discoverBundles(root).strayManifest).toBe(true);
  });

  it("a missing bundles directory is an empty result, not an error", () => {
    const root = bundles();
    expect(discoverBundles(join(root, "nope"))).toEqual({ entries: [], strayManifest: false });
  });
});

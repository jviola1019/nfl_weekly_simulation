/**
 * Which directories under bundles/ the offline runner ingests (npm run local). A bundle is
 * a directory with manifest.json at its root, which is exactly how actions/download-artifact
 * lays out the weekly-sim workflow's `sim-bundle` artifact:
 *   gh run download <run-id> -n sim-bundle -D bundles/<cycle_id>
 * so the online run's bundle is viewed offline by the same code path as a local run_week.R one.
 */
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { BundleEntry } from "./config";

function readManifest(dir: string): unknown {
  try {
    return JSON.parse(readFileSync(join(dir, "manifest.json"), "utf8"));
  } catch {
    return null;
  }
}

export function discoverBundles(bundlesDir: string): { entries: BundleEntry[]; strayManifest: boolean } {
  if (!existsSync(bundlesDir)) return { entries: [], strayManifest: false };
  const dirs = readdirSync(bundlesDir, { withFileTypes: true }).filter((d) => d.isDirectory());
  return {
    entries: dirs.map((d) => ({ name: d.name, manifest: readManifest(join(bundlesDir, d.name)) })),
    strayManifest: existsSync(join(bundlesDir, "manifest.json"))
  };
}

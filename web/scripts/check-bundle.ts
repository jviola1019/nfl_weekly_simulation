/**
 * Check a bundle directory the way the ingest does, without a database (A8: the
 * weekly-sim workflow checks the simulator bundle before it uploads and ingests it).
 *   npm run check-bundle -- ../bundles/<cycle_id>
 * Exit 0 when the ingest would accept it (hashes, schema major, every row valid); QA
 * failures print as GitHub warnings (scripts/check-bundle/report.ts). Exit 1 when the
 * ingest would reject it, 2 on bad usage.
 */
import { BundleRejected, loadBundle } from "../src/lib/ingest/ingest";
import { bundleReport } from "./check-bundle/report";

const dir = process.argv[2];
if (!dir) {
  console.error("usage: npm run check-bundle -- <bundle_dir>");
  process.exit(2);
}
try {
  for (const line of bundleReport(loadBundle(dir))) console.log(line);
} catch (e) {
  if (!(e instanceof BundleRejected)) throw e;
  console.error(`::error title=Bundle rejected::${e.message}`);
  process.exit(1);
}

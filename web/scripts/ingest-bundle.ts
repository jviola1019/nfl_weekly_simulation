/**
 * Ingest one bundle directory into DATABASE_URL.
 *   npx tsx scripts/ingest-bundle.ts ../bundles/<cycle_id>
 * Exit 0 on published, duplicate (no-op) or qa_failed (stored, pointer unchanged);
 * exit 1 when the bundle is rejected (hash, schema or row validation).
 */
import { closeDb, getDb } from "../src/db";
import { BundleRejected, ingestBundle, loadBundle } from "../src/lib/ingest/ingest";

const dir = process.argv[2];
if (!dir) {
  console.error("usage: tsx scripts/ingest-bundle.ts <bundle_dir>");
  process.exit(2);
}
try {
  const bundle = loadBundle(dir);
  const res = await ingestBundle(getDb(), bundle);
  console.log(`${res.status}: run ${res.runId} (bundle ${res.bundleSha256.slice(0, 12)}), ${res.rowsWritten} rows written`);
  if (res.status === "qa_failed") console.log(`QA failures:\n  ${bundle.manifest.qa.failures.join("\n  ")}`);
} catch (e) {
  if (e instanceof BundleRejected) {
    console.error(`rejected: ${e.message}`);
    process.exitCode = 1;
  } else throw e;
} finally {
  await closeDb();
}

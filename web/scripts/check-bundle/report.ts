/**
 * What `npm run check-bundle` prints for a bundle the ingest accepts (A8): one summary line,
 * then each QA failure as a GitHub warning annotation. A QA-failed bundle is still
 * ingestible (it is stored as qa_failed and the publish pointer stays on the last good run),
 * so QA failures warn; only a bundle the ingest would reject fails the check.
 */
import type { LoadedBundle } from "../../src/lib/ingest/ingest";

export function bundleReport(bundle: LoadedBundle): string[] {
  const m = bundle.manifest;
  const rows = m.files.reduce((n, f) => n + f.rows, 0);
  const tables = m.files.map((f) => f.name.replace(/\.json$/, "")).join(", ");
  const qa = m.qa.ok ? "QA passed" : `QA FAILED (${m.qa.failures.length})`;
  return [
    `ok ${m.bundle_kind} ${m.cycle_id} (bundle ${bundle.sha256.slice(0, 12)}): ${rows} rows in ${tables}; ${qa}`,
    ...m.qa.failures.map((f) => `::warning title=Bundle QA::${f.replace(/\r?\n/g, " ")}`)
  ];
}

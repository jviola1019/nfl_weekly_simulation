import { DataUnavailable } from "@/components/DataUnavailable";
import { StatusBadge } from "@/components/StatusBadge";
import { dataHealth } from "@/lib/data/queries";
import { age, shortSha, utcStamp } from "@/lib/format";

export const dynamic = "force-dynamic";
export const metadata = { title: "Data health" };

export default async function DataHealthPage() {
  const { run, sources, ingests, runs } = await dataHealth();
  return (
    <>
      <h1 className="text-2xl font-semibold">Data health</h1>
      {run ? (
        <p className="mt-3 text-ink-2">
          Published weekly run generated {utcStamp(run.generatedUtc)} from code {shortSha(run.codeGitSha)}
          {run.codeDirty ? " (uncommitted changes)" : ""}. QA: <StatusBadge status={run.qaOk ? "ok" : "qa_failed"} label={run.qaOk ? "Passed" : "Failed"} />
        </p>
      ) : (
        <div className="mt-6"><DataUnavailable title="No published weekly run">Nothing ingested yet.</DataUnavailable></div>
      )}

      <section className="mt-8" aria-labelledby="sources">
        <h2 id="sources" className="text-lg font-semibold">Sources for this run</h2>
        <div tabIndex={0} role="region" aria-label="Scrollable table" className="mt-3 overflow-x-auto">
          <table className="w-full min-w-[640px] text-left text-sm">
            <thead className="text-ink-2"><tr><th className="py-1 pr-4 font-normal">Source</th><th className="pr-4 font-normal">Status</th><th className="pr-4 font-normal">Last success</th><th className="font-normal">Detail</th></tr></thead>
            <tbody>
              {sources.map((s) => (
                <tr key={s.source} className="border-t border-rule align-top">
                  <td className="py-2 pr-4">{s.source.replace(/_/g, " ")}</td>
                  <td className="py-2 pr-4"><StatusBadge status={s.status} /></td>
                  <td className="num py-2 pr-4">{s.lastSuccessUtc ? `${utcStamp(s.lastSuccessUtc)} (${age(s.lastSuccessUtc)})` : "–"}</td>
                  <td className="py-2 text-ink-2">{s.detail}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="mt-10" aria-labelledby="runs">
        <h2 id="runs" className="text-lg font-semibold">Recent runs</h2>
        <ul className="mt-3 max-w-3xl divide-y divide-rule text-sm">
          {runs.map((r) => {
            const failures = r.qaFailures as string[];
            return (
              <li key={r.runId} className="py-2">
                <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1">
                  <span className="font-medium">{r.modelLabel}</span>
                  <StatusBadge status={r.status} />
                </div>
                <p className="num mt-1 text-ink-2">
                  {r.kind} · data as of {utcStamp(r.dataAsofUtc)} · QA failures: {failures.length ? failures.join("; ") : "none"}
                </p>
              </li>
            );
          })}
        </ul>
      </section>

      <section className="mt-10" aria-labelledby="ingests">
        <h2 id="ingests" className="text-lg font-semibold">Ingest log</h2>
        <ul className="num mt-3 max-w-3xl divide-y divide-rule text-sm">
          {ingests.map((i) => (
            <li key={i.bundleSha256} className="flex flex-wrap items-center justify-between gap-2 py-2">
              <span>{i.cycleId}</span>
              <span className="text-ink-2">bundle {shortSha(i.bundleSha256, 12)}</span>
              <StatusBadge status={i.status} />
            </li>
          ))}
        </ul>
      </section>

      <section className="mt-10" aria-labelledby="unmatched">
        <h2 id="unmatched" className="text-lg font-semibold">Unmatched entities</h2>
        <div className="mt-3">
          <DataUnavailable title="Not tracked yet">
            The unmatched-entity queue (players and teams a provider names that the ID tables cannot resolve) arrives with
            the odds layer in Phase 2. Until then joins use nflverse IDs only.
          </DataUnavailable>
        </div>
      </section>
    </>
  );
}

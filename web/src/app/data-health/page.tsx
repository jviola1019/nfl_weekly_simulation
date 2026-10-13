import { Age } from "@/components/Age";
import { DataUnavailable } from "@/components/DataUnavailable";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, PageTitle, SectionTitle } from "@/components/ui";
import { dataHealth } from "@/lib/data/queries";
import { shortSha, utcStamp } from "@/lib/format";

export const dynamic = "force-dynamic";
export const metadata = { title: "Data health" };

export default async function DataHealthPage() {
  const { run, sources, ingests, runs } = await dataHealth();
  return (
    <>
      <PageTitle
        lead={
          run ? (
            <p>
              Published weekly run generated {utcStamp(run.generatedUtc)} from code {shortSha(run.codeGitSha)}
              {run.codeDirty ? " (uncommitted changes)" : ""}. QA:{" "}
              <StatusBadge status={run.qaOk ? "ok" : "qa_failed"} label={run.qaOk ? "Passed" : "Failed"} />
            </p>
          ) : null
        }
      >
        Data health
      </PageTitle>
      {run ? null : (
        <div className="mt-6">
          <DataUnavailable title="No published weekly run">Nothing ingested yet.</DataUnavailable>
        </div>
      )}

      <section className="mt-10" aria-labelledby="sources">
        <SectionTitle id="sources">Sources for this run</SectionTitle>
        <Card className="mt-3">
          <div tabIndex={0} role="region" aria-label="Scrollable table" className="overflow-x-auto">
            <table className="w-full min-w-[640px] text-left text-sm">
              <thead className="text-ink-2">
                <tr>
                  <th className="py-1 pr-4 font-normal">Source</th>
                  <th className="pr-4 font-normal">Status</th>
                  <th className="pr-4 font-normal">Last success</th>
                  <th className="font-normal">Detail</th>
                </tr>
              </thead>
              <tbody>
                {sources.map((s) => (
                  <tr key={s.source} className="border-t border-rule align-top">
                    <td className="py-2 pr-4">{s.source.replace(/_/g, " ")}</td>
                    <td className="py-2 pr-4"><StatusBadge status={s.status} /></td>
                    <td className="num py-2 pr-4">{s.lastSuccessUtc ? <>{utcStamp(s.lastSuccessUtc)} (<Age iso={s.lastSuccessUtc} />)</> : "–"}</td>
                    <td className="py-2 text-ink-2">{s.detail}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      </section>

      <div className="mt-10 grid gap-8 lg:grid-cols-2">
        <section aria-labelledby="runs">
          <SectionTitle id="runs">Recent runs</SectionTitle>
          <Card className="mt-3">
            <ul className="divide-y divide-rule text-sm">
              {runs.map((r) => {
                const failures = r.qaFailures as string[];
                return (
                  <li key={r.runId} className="py-2 first:pt-0 last:pb-0">
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
          </Card>
        </section>

        <section aria-labelledby="ingests">
          <SectionTitle id="ingests">Ingest log</SectionTitle>
          <Card className="mt-3">
            <ul className="num divide-y divide-rule text-sm">
              {ingests.map((i) => (
                <li key={i.bundleSha256} className="flex flex-wrap items-center justify-between gap-2 py-2 first:pt-0 last:pb-0">
                  <span>{i.cycleId}</span>
                  <span className="text-ink-2">bundle {shortSha(i.bundleSha256, 12)}</span>
                  <StatusBadge status={i.status} />
                </li>
              ))}
            </ul>
          </Card>
        </section>
      </div>

      <section className="mt-10" aria-labelledby="unmatched">
        <SectionTitle id="unmatched">Unmatched entities</SectionTitle>
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

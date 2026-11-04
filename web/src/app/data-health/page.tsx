import { Age } from "@/components/Age";
import { DataUnavailable } from "@/components/DataUnavailable";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, DataTable, Grid, Page, PageHeader, Section, Stamp } from "@/components/ui";
import { noRunContext, runContext } from "@/lib/context";
import { dataHealth } from "@/lib/data/queries";
import { shortSha } from "@/lib/format";

export const dynamic = "force-dynamic";
export const metadata = {
  title: "Data health",
  description: "When each data source last succeeded, whether the published run passed its checks, and the log of recent runs and ingests."
};

export default async function DataHealthPage() {
  const { run, sources, ingests, runs } = await dataHealth();
  return (
    <Page>
      <PageHeader
        title="Data health"
        lead={
          run ? (
            <p>
              Published weekly run generated <Stamp iso={run.generatedUtc} /> from code {shortSha(run.codeGitSha)}
              {run.codeDirty ? " (uncommitted changes)" : ""}. QA:{" "}
              <StatusBadge status={run.qaOk ? "ok" : "qa_failed"} label={run.qaOk ? "Passed" : "Failed"} />
            </p>
          ) : undefined
        }
        context={run ? runContext(run) : noRunContext("nothing has been ingested")}
      />
      {run ? null : <DataUnavailable title="No published weekly run">Nothing ingested yet.</DataUnavailable>}

      <Section id="sources" title="Sources for this run">
        <Card>
          <DataTable
            caption="Sources for this run"
            topAligned
            minWidth="table"
            columns={[
              { key: "source", header: "Source", rowHeader: true },
              { key: "status", header: "Status" },
              { key: "last", header: "Last success" },
              { key: "detail", header: "Detail" }
            ]}
            rows={sources.map((s) => ({
              key: s.source,
              cells: {
                source: s.source.replace(/_/g, " "),
                status: <StatusBadge status={s.status} />,
                last: s.lastSuccessUtc ? (
                  <span className="num">
                    <Stamp iso={s.lastSuccessUtc} /> (<Age iso={s.lastSuccessUtc} />)
                  </span>
                ) : (
                  "–"
                ),
                detail: <span className="text-ink-2">{s.detail}</span>
              }
            }))}
          />
        </Card>
      </Section>

      <Grid kind="sections">
        <Section id="runs" title="Recent runs">
          <Card>
            <ul className="divide-y divide-rule text-sm">
              {runs.map((r) => {
                const failures = r.qaFailures as string[];
                return (
                  <li key={r.runId} className="flex flex-col gap-tight py-row first:pt-0 last:pb-0">
                    <div className="flex flex-wrap items-center justify-between gap-x-stack gap-y-tight">
                      <span className="font-medium">{r.modelLabel}</span>
                      <StatusBadge status={r.status} />
                    </div>
                    <p className="num text-ink-2">
                      {r.kind} · data as of <Stamp iso={r.dataAsofUtc} /> · QA failures: {failures.length ? failures.join("; ") : "none"}
                    </p>
                  </li>
                );
              })}
            </ul>
          </Card>
        </Section>

        <Section id="ingests" title="Ingest log">
          <Card>
            <ul className="num divide-y divide-rule text-sm">
              {ingests.map((i) => (
                <li key={i.bundleSha256} className="flex flex-wrap items-center justify-between gap-snug py-row first:pt-0 last:pb-0">
                  <span>{i.cycleId}</span>
                  <span className="text-ink-2">bundle {shortSha(i.bundleSha256, 12)}</span>
                  <StatusBadge status={i.status} />
                </li>
              ))}
            </ul>
          </Card>
        </Section>
      </Grid>

      <Section id="unmatched" title="Unmatched entities">
        <DataUnavailable title="Not tracked yet">
          The unmatched-entity queue (players and teams a provider names that the ID tables cannot resolve) arrives with
          the odds layer in Phase 2. Until then joins use nflverse IDs only.
        </DataUnavailable>
      </Section>
    </Page>
  );
}

import Link from "next/link";
import { ClvHistogram } from "@/components/charts/ClvHistogram";
import { ReliabilityGrid } from "@/components/charts/ReliabilityGrid";
import { SkillIntervals } from "@/components/charts/SkillIntervals";
import { DataUnavailable } from "@/components/DataUnavailable";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, chipClass, DataTable, Grid, Page, PageHeader, Section, Stamp, StatTile, Term } from "@/components/ui";
import { backtestContext, noRunContext } from "@/lib/context";
import { evidence, ledger } from "@/lib/data/queries";
import { bps, shortSha, signedPct } from "@/lib/format";
import { candidateLabel } from "@/lib/policy";

export const dynamic = "force-dynamic";
export const metadata = {
  title: "Evidence",
  description: "The pre-registered test of every model against the no-vig closing market: Brier skill, calibration, promotion gates and closing-line value."
};

type Split = "confirm" | "tune";
const SPLIT_LABEL: Record<Split, string> = { confirm: "Confirm 2023–24", tune: "Tune 2018–22 (in-sample for selection)" };

interface ClvAgg {
  n: number;
  mean_clv_bps: number;
  clv_ci: [number, number];
  roi: number;
  roi_ci: [number, number];
}

export default async function EvidencePage({ searchParams }: { searchParams: Promise<{ split?: string; clv?: string }> }) {
  const sp = await searchParams;
  const split: Split = sp.split === "tune" ? "tune" : "confirm";
  const [ev, claims] = await Promise.all([evidence(), ledger()]);

  if (!ev) {
    return (
      <Page>
        <PageHeader title="Evidence" context={noRunContext("no backtest has been ingested")} />
        <DataUnavailable title="No backtest ingested">A backtest bundle appears here after ingest.</DataUnavailable>
      </Page>
    );
  }

  const pooled = ev.metrics.filter((m) => m.split === split && m.phase === "pooled");
  const market = pooled.find((m) => m.candidate === "C0");
  const confirm = ev.metrics.filter((m) => m.split === "confirm" && m.phase === "pooled" && m.candidate !== "C0");
  const confirmMarket = ev.metrics.find((m) => m.split === "confirm" && m.phase === "pooled" && m.candidate === "C0");
  const best = [...confirm].sort((a, b) => b.skill - a.skill)[0];
  const passing = ev.gates.filter((g) => g.brierStatus.startsWith("passes"));
  const clvSummary = (ev.bt.clvSummary ?? {}) as Record<string, ClvAgg | { venue: string; tau: number }>;
  const clvCands = [...new Set(ev.clv.map((c) => c.candidate))];
  const clvCand = sp.clv && clvCands.includes(sp.clv) ? sp.clv : clvCands.includes("C2") ? "C2" : clvCands[0];
  const clvAgg = clvCand ? (clvSummary[clvCand] as ClvAgg | undefined) : undefined;
  const controls = ev.bt.controls as Record<string, { passed?: boolean } & Record<string, unknown>>;
  const folds = (ev.window?.folds ?? {}) as Record<string, { seasons: number[] | string; use: string; sealed?: boolean }>;
  const q = (s: Split, c?: string) => `/evidence?split=${s}${c ? `&clv=${encodeURIComponent(c)}` : ""}`;
  const protocol = ev.window?.windowId ?? "the registered protocol";

  return (
    <Page>
      <PageHeader
        title="Evidence"
        lead={
          <div className="flex flex-col gap-snug">
            <p className="text-ink">
              {passing.length
                ? `${passing.map((g) => candidateLabel(g.candidate)).join(", ")} passed the Confirm-stage gates; the sealed 2025 holdout is still pending.`
                : "No model or blend beat the no-vig closing market in the pre-registered test."}
            </p>
            <p>
              Protocol <code className="text-sm">{ev.window?.windowId}</code> was frozen and pushed before any Confirm-window
              scoring, and every candidate was refit <Term id="walk-forward">walk-forward</Term>, week by week, on data available
              before kickoff. <Link href="/methodology">How it works</Link>
            </p>
          </div>
        }
        context={backtestContext({ windowId: ev.window?.windowId ?? null, cycleId: ev.run.cycleId, dataAsofUtc: ev.run.dataAsofUtc })}
      />

      <Section label="The test in numbers">
        <Grid kind="tiles">
          <StatTile value={confirm[0]?.n ?? "–"} label="Confirm games scored" source={`Protocol ${protocol}, Confirm 2023–24`} />
          <StatTile
            value={confirmMarket?.brier.toFixed(4) ?? "–"}
            label={
              <>
                Market <Term id="brier">Brier score</Term> (lower is better)
              </>
            }
            source="The no-vig closing market, Confirm 2023–24"
          />
          <StatTile
            value={best ? signedPct(best.skill) : "–"}
            label={
              <>
                Closest candidate, <Term id="skill">skill vs market</Term>
                {best ? `: ${candidateLabel(best.candidate)}; 95% interval ${signedPct(best.skillLo)} to ${signedPct(best.skillHi)}` : ""}
              </>
            }
            source="Confirm 2023–24, paired week-block bootstrap of 10,000 resamples"
          />
        </Grid>
      </Section>

      <nav className="flex flex-wrap items-center gap-snug border-y border-rule py-card-sm" aria-label="Window">
        <span className="text-sm text-muted">Window</span>
        {(["confirm", "tune"] as Split[]).map((s) => (
          <Link key={s} href={q(s, clvCand)} aria-current={s === split ? "true" : undefined} className={chipClass(s === split)}>
            {SPLIT_LABEL[s]}
          </Link>
        ))}
      </nav>

      <Section id="skill" title="Brier skill" srTitle>
        <Card className="flex flex-col gap-control">
          <SkillIntervals splitLabel={SPLIT_LABEL[split]} rows={pooled} />
          {market ? (
            <p className="text-sm text-muted">
              Market <Term id="brier">Brier</Term> {market.brier.toFixed(4)} on {market.n} games. <Term id="skill">Skill</Term> = 1 − Brier(candidate) / Brier(market);
              intervals from a paired week-block bootstrap (10,000 resamples).
            </p>
          ) : null}
        </Card>
      </Section>

      <Section id="rel" title="Reliability" srTitle>
        <Card>
          <ReliabilityGrid
            splitLabel={SPLIT_LABEL[split]}
            bins={ev.bins.filter((b) => b.split === split)}
            ece={Object.fromEntries(pooled.map((m) => [m.candidate, m.ece]))}
          />
        </Card>
      </Section>

      <Section id="gates" title="Promotion gates, Confirm stage">
        <p className="max-w-measure text-sm text-ink-2">
          G1: skill interval above zero. G2: Diebold–Mariano beats the market after Benjamini–Hochberg. G3: calibration
          slope interval contains 1 and <Term id="ece">ECE</Term> within 0.005 of the market. G4: every control passed. G1 and G2 must also hold
          on the sealed 2025 holdout.
        </p>
        <Card>
          <DataTable
            caption="Promotion gates, Confirm stage"
            minWidth="table"
            columns={[
              { key: "candidate", header: "Candidate", rowHeader: true },
              { key: "g1", header: "G1" },
              { key: "g2", header: "G2" },
              { key: "g3", header: "G3" },
              { key: "g4", header: "G4" },
              { key: "brier", header: "Brier status" },
              { key: "value", header: "Betting value" }
            ]}
            rows={ev.gates.map((g) => {
              const pass = (v: boolean) => <StatusBadge status={v ? "passes" : "failed"} label={v ? "Pass" : "Fail"} />;
              return {
                key: g.candidate,
                cells: {
                  candidate: candidateLabel(g.candidate),
                  g1: pass(g.g1),
                  g2: pass(g.g2),
                  g3: pass(g.g3),
                  g4: pass(g.g4),
                  brier: <StatusBadge status={g.brierStatus} />,
                  value: <span className="text-ink-2">{g.bettingValueStatus}</span>
                }
              };
            })}
          />
        </Card>
      </Section>

      <Section id="clv" title="Closing-line value at the opener">
        <nav className="flex flex-wrap items-center gap-snug" aria-label="CLV candidate">
          <span className="text-sm text-muted">Candidate</span>
          {clvCands.map((c) => (
            <Link key={c} href={q(split, c)} aria-current={c === clvCand ? "true" : undefined} className={chipClass(c === clvCand)}>
              {candidateLabel(c)}
            </Link>
          ))}
        </nav>
        <Card className="flex flex-col gap-control">
          {clvCand ? (
            <ClvHistogram
              candidate={clvCand}
              values={ev.clv.filter((c) => c.candidate === clvCand).map((c) => c.clvBps)}
              meanCi={clvAgg ? { mean: clvAgg.mean_clv_bps, lo: clvAgg.clv_ci[0], hi: clvAgg.clv_ci[1] } : null}
              roi={clvAgg?.roi ?? null}
            />
          ) : null}
          <p className="max-w-measure text-sm text-muted">
            Pick rule: the side where the model beats the ESPN BET no-vig opener by 3 points or more. <Term id="clv">CLV</Term> = 10,000 × (close −
            open), both no-vig at the same venue. Four candidates were examined and the intervals are not corrected for that.
            {clvAgg ? ` ${candidateLabel(clvCand!)}: ${clvAgg.n} picks, mean ${bps(clvAgg.mean_clv_bps)}.` : ""}
          </p>
        </Card>
      </Section>

      <Grid kind="sections">
        <Section id="controls" title="Controls">
          <Card className="flex flex-col gap-control">
            <p className="text-sm text-ink-2">Any failed control voids the run. Run status: <StatusBadge status={ev.bt.status} /></p>
            <ul className="divide-y divide-rule text-sm">
              {Object.entries(controls)
                .filter(([, v]) => v && typeof v === "object" && "passed" in v)
                .map(([k, v]) => (
                  <li key={k} className="flex items-center justify-between py-row first:pt-0 last:pb-0">
                    <span>{k.replace(/_/g, " ")}</span>
                    <StatusBadge status={v.passed ? "passes" : "failed"} label={v.passed ? "Passed" : "Failed"} />
                  </li>
                ))}
            </ul>
          </Card>
        </Section>

        <Section id="repro" title="Protocol and reproducibility">
          <Card className="flex flex-col gap-control">
            <dl className="num grid grid-cols-1 gap-x-stack gap-y-snug text-sm sm:grid-cols-[max-content_1fr]">
              <dt className="text-ink-2">Protocol sha256</dt><dd className="break-all">{ev.window?.protocolSha256}</dd>
              <dt className="text-ink-2">Frozen</dt><dd><Stamp iso={ev.window?.frozenAtUtc} /></dd>
              <dt className="text-ink-2">Result sha256</dt><dd className="break-all">{ev.bt.resultSha256}</dd>
              <dt className="text-ink-2">Code</dt><dd>{shortSha(ev.bt.codeGitSha)}</dd>
              <dt className="text-ink-2">Scored</dt><dd><Stamp iso={ev.bt.generatedUtc} /></dd>
            </dl>
            <ul className="divide-y divide-rule border-t border-rule text-sm">
              {Object.entries(folds).map(([name, f]) => (
                <li key={name} className="flex flex-wrap items-center justify-between gap-snug py-row last:pb-0">
                  <span>
                    <span className="capitalize">{name.replace("_", "-")}</span>{" "}
                    <span className="num text-ink-2">{Array.isArray(f.seasons) ? `${f.seasons[0]}–${f.seasons[f.seasons.length - 1]}` : f.seasons}</span>
                  </span>
                  <span className="text-ink-2">{f.sealed ? <StatusBadge status="pending" label="Sealed" /> : f.use}</span>
                </li>
              ))}
            </ul>
          </Card>
        </Section>
      </Grid>

      <Section id="ledger" title="Evidence ledger">
        <p className="max-w-measure text-sm text-ink-2">Every quantitative claim about the model, including withdrawn ones and negative results.</p>
        <Card>
          <DataTable
            caption="Evidence ledger"
            topAligned
            minWidth="table-wide"
            columns={[
              { key: "claim", header: "Claim" },
              { key: "status", header: "Status" },
              { key: "reason", header: "Reason" }
            ]}
            rows={claims.map((c) => ({
              key: c.claimId,
              cells: { claim: c.claim, status: <StatusBadge status={c.status} />, reason: <span className="text-ink-2">{c.reason}</span> }
            }))}
          />
        </Card>
      </Section>
    </Page>
  );
}

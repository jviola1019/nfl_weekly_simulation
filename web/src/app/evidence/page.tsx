import Link from "next/link";
import { ClvHistogram } from "@/components/charts/ClvHistogram";
import { ReliabilityGrid } from "@/components/charts/ReliabilityGrid";
import { SkillIntervals } from "@/components/charts/SkillIntervals";
import { DataUnavailable } from "@/components/DataUnavailable";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, chipClass, PageTitle, SectionTitle, StatTile } from "@/components/ui";
import { evidence, ledger } from "@/lib/data/queries";
import { bps, shortSha, signedPct, utcStamp } from "@/lib/format";
import { candidateLabel } from "@/lib/policy";

export const dynamic = "force-dynamic";
export const metadata = { title: "Evidence" };

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
      <>
        <PageTitle>Evidence</PageTitle>
        <div className="mt-6">
          <DataUnavailable title="No backtest ingested">A backtest bundle appears here after ingest.</DataUnavailable>
        </div>
      </>
    );
  }

  const pooled = ev.metrics.filter((m) => m.split === split && m.phase === "pooled");
  const market = pooled.find((m) => m.candidate === "C0");
  const confirm = ev.metrics.filter((m) => m.split === "confirm" && m.phase === "pooled" && m.candidate !== "C0");
  const best = [...confirm].sort((a, b) => b.skill - a.skill)[0];
  const passing = ev.gates.filter((g) => g.brierStatus.startsWith("passes"));
  const clvSummary = (ev.bt.clvSummary ?? {}) as Record<string, ClvAgg | { venue: string; tau: number }>;
  const clvCands = [...new Set(ev.clv.map((c) => c.candidate))];
  const clvCand = sp.clv && clvCands.includes(sp.clv) ? sp.clv : clvCands.includes("C2") ? "C2" : clvCands[0];
  const clvAgg = clvCand ? (clvSummary[clvCand] as ClvAgg | undefined) : undefined;
  const controls = ev.bt.controls as Record<string, { passed?: boolean } & Record<string, unknown>>;
  const folds = (ev.window?.folds ?? {}) as Record<string, { seasons: number[] | string; use: string; sealed?: boolean }>;
  const q = (s: Split, c?: string) => `/evidence?split=${s}${c ? `&clv=${encodeURIComponent(c)}` : ""}`;

  return (
    <>
      <PageTitle
        lead={
          <>
            <p className="text-ink">
              {passing.length
                ? `${passing.map((g) => candidateLabel(g.candidate)).join(", ")} passed the Confirm-stage gates; the sealed 2025 holdout is still pending.`
                : "No model or blend beat the no-vig closing market in the pre-registered test."}
            </p>
            <p className="mt-2">
              Protocol <code className="text-sm">{ev.window?.windowId}</code> was frozen and pushed before any Confirm-window
              scoring, and every candidate was refit walk-forward, week by week, on data available before kickoff.{" "}
              <Link href="/methodology">How it works</Link>
            </p>
          </>
        }
      >
        Evidence
      </PageTitle>

      <section aria-label="The test in numbers" className="mt-7 grid gap-4 sm:grid-cols-3">
        <StatTile value={confirm[0]?.n ?? "–"} label="Confirm games scored" />
        <StatTile
          value={ev.metrics.find((m) => m.split === "confirm" && m.phase === "pooled" && m.candidate === "C0")?.brier.toFixed(4) ?? "–"}
          label="Market Brier score (lower is better)"
        />
        <StatTile
          value={best ? signedPct(best.skill) : "–"}
          label={best ? `Closest candidate, skill vs market: ${candidateLabel(best.candidate)}; 95% interval ${signedPct(best.skillLo)} to ${signedPct(best.skillHi)}` : "Closest candidate, skill vs market"}
        />
      </section>

      <nav className="mt-7 flex flex-wrap items-center gap-1.5 border-y border-rule py-4" aria-label="Window">
        <span className="mr-1 text-[13px] text-muted">Window</span>
        {(["confirm", "tune"] as Split[]).map((s) => (
          <Link key={s} href={q(s, clvCand)} aria-current={s === split ? "true" : undefined} className={chipClass(s === split)}>
            {SPLIT_LABEL[s]}
          </Link>
        ))}
      </nav>

      <section className="mt-7" aria-labelledby="skill">
        <h2 id="skill" className="sr-only">Brier skill</h2>
        <Card>
          <SkillIntervals splitLabel={SPLIT_LABEL[split]} rows={pooled} />
          {market ? (
            <p className="mt-2 text-sm text-muted">
              Market Brier {market.brier.toFixed(4)} on {market.n} games. Skill = 1 − Brier(candidate) / Brier(market);
              intervals from a paired week-block bootstrap (10,000 resamples).
            </p>
          ) : null}
        </Card>
      </section>

      <section className="mt-8" aria-labelledby="rel">
        <h2 id="rel" className="sr-only">Reliability</h2>
        <Card>
          <ReliabilityGrid
            splitLabel={SPLIT_LABEL[split]}
            bins={ev.bins.filter((b) => b.split === split)}
            ece={Object.fromEntries(pooled.map((m) => [m.candidate, m.ece]))}
          />
        </Card>
      </section>

      <section className="mt-10" aria-labelledby="gates">
        <SectionTitle id="gates">Promotion gates, Confirm stage</SectionTitle>
        <p className="mt-2 max-w-3xl text-sm text-ink-2">
          G1: skill interval above zero. G2: Diebold–Mariano beats the market after Benjamini–Hochberg. G3: calibration
          slope interval contains 1 and ECE within 0.005 of the market. G4: every control passed. G1 and G2 must also hold
          on the sealed 2025 holdout.
        </p>
        <Card className="mt-3">
          <div tabIndex={0} role="region" aria-label="Scrollable table" className="overflow-x-auto">
            <table className="w-full min-w-[640px] text-left text-sm">
              <thead className="text-ink-2">
                <tr>
                  <th className="py-1 pr-4 font-normal">Candidate</th>
                  {["G1", "G2", "G3", "G4"].map((g) => <th key={g} className="pr-4 font-normal">{g}</th>)}
                  <th className="pr-4 font-normal">Brier status</th>
                  <th className="font-normal">Betting value</th>
                </tr>
              </thead>
              <tbody>
                {ev.gates.map((g) => (
                  <tr key={g.candidate} className="border-t border-rule">
                    <td className="py-1.5 pr-4">{candidateLabel(g.candidate)}</td>
                    {[g.g1, g.g2, g.g3, g.g4].map((v, i) => (
                      <td key={i} className="pr-4"><StatusBadge status={v ? "passes" : "failed"} label={v ? "Pass" : "Fail"} /></td>
                    ))}
                    <td className="pr-4"><StatusBadge status={g.brierStatus} /></td>
                    <td className="text-ink-2">{g.bettingValueStatus}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      </section>

      <section className="mt-10" aria-labelledby="clv">
        <SectionTitle id="clv">Closing-line value at the opener</SectionTitle>
        <nav className="mt-3 flex flex-wrap items-center gap-1.5" aria-label="CLV candidate">
          <span className="mr-1 text-[13px] text-muted">Candidate</span>
          {clvCands.map((c) => (
            <Link key={c} href={q(split, c)} aria-current={c === clvCand ? "true" : undefined} className={chipClass(c === clvCand)}>
              {candidateLabel(c)}
            </Link>
          ))}
        </nav>
        <Card className="mt-3">
          {clvCand ? (
            <ClvHistogram
              candidate={clvCand}
              values={ev.clv.filter((c) => c.candidate === clvCand).map((c) => c.clvBps)}
              meanCi={clvAgg ? { mean: clvAgg.mean_clv_bps, lo: clvAgg.clv_ci[0], hi: clvAgg.clv_ci[1] } : null}
              roi={clvAgg?.roi ?? null}
            />
          ) : null}
          <p className="mt-2 max-w-3xl text-sm text-muted">
            Pick rule: the side where the model beats the ESPN BET no-vig opener by 3 points or more. CLV = 10,000 × (close −
            open), both no-vig at the same venue. Four candidates were examined and the intervals are not corrected for that.
            {clvAgg ? ` ${candidateLabel(clvCand!)}: ${clvAgg.n} picks, mean ${bps(clvAgg.mean_clv_bps)}.` : ""}
          </p>
        </Card>
      </section>

      <div className="mt-10 grid gap-8 lg:grid-cols-2">
        <section aria-labelledby="controls">
          <SectionTitle id="controls">Controls</SectionTitle>
          <Card className="mt-3">
            <p className="text-sm text-ink-2">Any failed control voids the run. Run status: <StatusBadge status={ev.bt.status} /></p>
            <ul className="mt-3 divide-y divide-rule text-sm">
              {Object.entries(controls)
                .filter(([, v]) => v && typeof v === "object" && "passed" in v)
                .map(([k, v]) => (
                  <li key={k} className="flex items-center justify-between py-2">
                    <span>{k.replace(/_/g, " ")}</span>
                    <StatusBadge status={v.passed ? "passes" : "failed"} label={v.passed ? "Passed" : "Failed"} />
                  </li>
                ))}
            </ul>
          </Card>
        </section>

        <section aria-labelledby="repro">
          <SectionTitle id="repro">Protocol and reproducibility</SectionTitle>
          <Card className="mt-3">
            <dl className="num grid grid-cols-1 gap-x-8 gap-y-2 text-sm sm:grid-cols-[max-content_1fr]">
              <dt className="text-ink-2">Protocol sha256</dt><dd className="break-all">{ev.window?.protocolSha256}</dd>
              <dt className="text-ink-2">Frozen</dt><dd>{utcStamp(ev.window?.frozenAtUtc)}</dd>
              <dt className="text-ink-2">Result sha256</dt><dd className="break-all">{ev.bt.resultSha256}</dd>
              <dt className="text-ink-2">Code</dt><dd>{shortSha(ev.bt.codeGitSha)}</dd>
              <dt className="text-ink-2">Scored</dt><dd>{utcStamp(ev.bt.generatedUtc)}</dd>
            </dl>
            <ul className="mt-4 divide-y divide-rule border-t border-rule text-sm">
              {Object.entries(folds).map(([name, f]) => (
                <li key={name} className="flex flex-wrap items-center justify-between gap-2 py-2">
                  <span>
                    <span className="capitalize">{name.replace("_", "-")}</span>{" "}
                    <span className="num text-ink-2">{Array.isArray(f.seasons) ? `${f.seasons[0]}–${f.seasons[f.seasons.length - 1]}` : f.seasons}</span>
                  </span>
                  <span className="text-ink-2">{f.sealed ? <StatusBadge status="pending" label="Sealed" /> : f.use}</span>
                </li>
              ))}
            </ul>
          </Card>
        </section>
      </div>

      <section className="mt-10" aria-labelledby="ledger">
        <SectionTitle id="ledger">Evidence ledger</SectionTitle>
        <p className="mt-2 text-sm text-ink-2">Every quantitative claim about the model, including withdrawn ones and negative results.</p>
        <Card className="mt-3">
          <div tabIndex={0} role="region" aria-label="Scrollable table" className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-left text-sm">
              <thead className="text-ink-2">
                <tr><th className="py-1 pr-4 font-normal">Claim</th><th className="pr-4 font-normal">Status</th><th className="font-normal">Reason</th></tr>
              </thead>
              <tbody>
                {claims.map((c) => (
                  <tr key={c.claimId} className="border-t border-rule align-top">
                    <td className="py-2 pr-4">{c.claim}</td>
                    <td className="py-2 pr-4"><StatusBadge status={c.status} /></td>
                    <td className="py-2 text-ink-2">{c.reason}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      </section>
    </>
  );
}

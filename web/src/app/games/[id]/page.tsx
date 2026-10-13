import Link from "next/link";
import { notFound } from "next/navigation";
import { DataUnavailable } from "@/components/DataUnavailable";
import { Field, FieldKey, gapText } from "@/components/Field";
import { StatusBadge } from "@/components/StatusBadge";
import { ScoreDistributionChart } from "@/components/charts/ScoreDistributionChart";
import { candidateLines, evidence, gameDistributions, publicGame, runCandidates } from "@/lib/data/queries";
import { parseBins } from "@/lib/parseBins";
import { kickoff, pct } from "@/lib/format";
import { candidateLabel, fieldLineShortNote, publicFieldLine } from "@/lib/policy";
import { teamColors } from "@/lib/teams";

export const dynamic = "force-dynamic";

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return { title: id.replace(/_/g, " ") };
}

function TeamBlock({ id, name, big, side, winner }: { id: string; name: string; big: string; side: "away" | "home"; winner: boolean }) {
  const c = teamColors(id);
  const code = (
    <div className={`flex flex-col gap-1 ${side === "home" ? "items-end text-right" : ""}`}>
      <span className="wdth-expanded text-[40px] font-black leading-none sm:text-[52px]">{id}</span>
      <span className="text-[15px] font-medium">{name}</span>
    </div>
  );
  const value = (
    <span className="flex items-center gap-3">
      {winner ? <span className="rounded-[3px] px-2 py-0.5 text-[13px] font-bold" style={{ background: c.ink, color: c.primary }}>Won</span> : null}
      <span className="num wdth-expanded text-[56px] font-black leading-[0.9] sm:text-[88px]">{big}</span>
    </span>
  );
  return (
    <div
      className="flex items-center justify-between gap-6 px-6 py-6 sm:px-8"
      style={{ background: c.primary, color: c.ink, boxShadow: `inset ${side === "away" ? 8 : -8}px 0 0 ${c.accent}` }}
    >
      {side === "away" ? (
        <>
          {code}
          {value}
        </>
      ) : (
        <>
          {value}
          {code}
        </>
      )}
    </div>
  );
}

export default async function GamePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9]{4}_[0-9]{2}_[A-Z]{2,3}_[A-Z]{2,3}$/.test(id)) notFound();
  const [{ run, game }, ev] = await Promise.all([publicGame(id), evidence()]);
  if (!run || !game) notFound();
  const line = publicFieldLine(ev?.gates ?? [], await runCandidates(run.runId));
  const label = line ? candidateLabel(line.candidate) : "Model";
  const lines = line ? await candidateLines(run.runId, [line.candidate], [id]) : [];
  const pm = game.pMarket;
  const pmod = lines[0]?.p ?? null;
  const dist = await gameDistributions(run.runId, id);
  const hasDist = dist.margin !== null || dist.total !== null;
  const final = game.homeScore !== null && game.awayScore !== null ? { home: game.homeScore, away: game.awayScore } : null;
  const flagX = (p: number) => `${(1 - p) * 100}%`;

  return (
    <>
      <nav aria-label="Breadcrumb" className="flex flex-wrap items-center justify-between gap-2 text-sm text-muted">
        <span className="flex items-center gap-2">
          <Link href="/" className="text-ink-2">
            This week
          </Link>
          <span aria-hidden>/</span>
          <span>
            Week {game.week}, {game.season}
          </span>
          <span aria-hidden>/</span>
          <span className="text-ink">
            {game.awayTeamId} {game.neutral ? "vs" : "at"} {game.homeTeamId}
          </span>
        </span>
      </nav>

      <h1 className="sr-only">
        {game.awayName} {game.neutral ? "vs" : "at"} {game.homeName}
      </h1>
      <section aria-label={final ? "Final score" : "Market win chance"} className="mt-5 grid overflow-hidden rounded-[6px] border border-rule lg:grid-cols-[minmax(0,1fr)_260px_minmax(0,1fr)]">
        <TeamBlock id={game.awayTeamId} name={game.awayName} side="away" big={final ? String(final.away) : pm === null ? "–" : pct(1 - pm)} winner={!!final && final.away > final.home} />
        <div className="flex flex-col items-center justify-center gap-1.5 bg-surface px-5 py-5 text-center">
          <span className="wdth-expanded text-[22px] font-extrabold">{final ? "Final" : "Kickoff"}</span>
          <span className="text-sm text-ink-2">{kickoff(game.kickoffUtc)}</span>
          <span className="text-sm text-muted">{final ? "Result" : "Win chance, no-vig market"}</span>
        </div>
        <TeamBlock id={game.homeTeamId} name={game.homeName} side="home" big={final ? String(final.home) : pm === null ? "–" : pct(pm)} winner={!!final && final.home > final.away} />
      </section>

      <section aria-labelledby="prob" className="mt-9">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <h2 id="prob" className="wdth-expanded text-[22px] font-bold">
            Win probability
          </h2>
          <FieldKey showModel={pmod !== null} modelLabel={label} validated={line?.validated ?? false} />
        </div>
        {/* one flag per row, each opening toward the middle of the field, so neither can overflow */}
        <div className="relative mx-[26px] mt-4 sm:mx-[58px]" aria-hidden>
          {[
            pm !== null ? { p: pm, name: "Market", bg: "var(--field-market)" } : null,
            pmod !== null ? { p: pmod, name: "Model", bg: "var(--field-model)" } : null
          ]
            .filter((f): f is { p: number; name: string; bg: string } => f !== null)
            .map((f) => {
              const left = 1 - f.p < 0.5;
              return (
                <div key={f.name} className="relative h-9">
                  <span
                    className={`absolute bottom-0 whitespace-nowrap px-3 py-1.5 text-sm font-bold ${left ? "rounded-t-[4px] rounded-br-[4px]" : "-translate-x-full rounded-t-[4px] rounded-bl-[4px]"}`}
                    style={{ left: flagX(f.p), background: f.bg, color: "var(--field-ink)" }}
                  >
                    {f.name} · {1 - f.p >= 0.5 ? game.awayTeamId : game.homeTeamId} {pct(Math.max(f.p, 1 - f.p))}
                  </span>
                </div>
              );
            })}
        </div>
        <Field
          size="hero"
          gameId={game.gameId}
          awayId={game.awayTeamId}
          homeId={game.homeTeamId}
          awayName={game.awayName}
          homeName={game.homeName}
          kickoffUtc={game.kickoffUtc}
          neutral={game.neutral}
          pMarket={pm}
          model={pmod !== null && line ? { p: pmod, label, validated: line.validated } : null}
        />
        <p className="mt-2.5 text-sm text-muted">
          Each team&apos;s side of the field is its chance to win.
          {pm !== null && pmod !== null ? ` ${gapText(pm, pmod, game.awayTeamId, game.homeTeamId)}.` : ""}
        </p>
      </section>

      <section aria-label="Market against model" className="mt-8 grid gap-4 md:grid-cols-2">
        <article className="flex flex-col gap-3.5 rounded-[6px] border border-rule bg-surface px-5 py-5">
          <div className="flex items-baseline justify-between gap-3">
            <h3 className="font-bold">Moneyline · {game.homeTeamId} to win</h3>
            <span className="text-sm text-muted">nflverse consensus close</span>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-0.5">
              <span className="text-[13px] text-muted">Market</span>
              <span className="num flex items-center gap-2 text-[30px] font-extrabold" data-line="market">
                <span className="inline-block h-[22px] w-1" style={{ background: "var(--field-market)" }} aria-hidden />
                {pm === null ? <span className="text-[18px] font-bold text-ink-2">No market line</span> : pct(pm, 1)}
              </span>
            </div>
            <div className="flex flex-col gap-0.5">
              <span className="text-[13px] text-muted">{label}</span>
              <span className="num flex items-center gap-2 text-[30px] font-extrabold" data-line="model">
                <span className="inline-block h-[22px] w-1" style={{ background: "var(--field-model)" }} aria-hidden />
                {pct(pmod, 1)}
              </span>
            </div>
          </div>
          {line ? (
            <div className="flex flex-wrap items-center gap-2 border-t border-rule pt-3 text-sm text-ink-2">
              <StatusBadge status={line.validated ? "validated" : "unvalidated"} label={line.validated ? "Validated" : "Unvalidated research model"} />
              <span>
                {fieldLineShortNote(line)} <Link href="/evidence">Evidence</Link>
              </span>
            </div>
          ) : null}
        </article>
        <article className="flex flex-col gap-3 rounded-[6px] border border-rule bg-surface px-5 py-5">
          <h3 className="font-bold">Spread and total</h3>
          <p className="text-sm leading-relaxed text-ink-2">
            In the validation sprint (Tune 2018–22) no model beat the devigged closing spread or total price, so no spread or
            total is offered here.{hasDist ? " The simulator's margin and total distributions below are research output." : ""}
          </p>
        </article>
      </section>

      <section className="mt-10" aria-labelledby="dist">
        <h2 id="dist" className="wdth-expanded text-[22px] font-bold">
          Simulated margin and total
        </h2>
        {hasDist ? (
          (["margin", "total"] as const).map((kind) => {
            const bins = parseBins(dist[kind]);
            return bins ? (
              <div key={kind}>
                <ScoreDistributionChart kind={kind} bins={bins} homeId={game.homeTeamId} awayId={game.awayTeamId} nSims={run.nSims}
                  result={final ? (kind === "margin" ? final.home - final.away : final.home + final.away) : null} />
                {kind === "margin" ? <p className="mt-2 text-sm text-muted">Regulation ties go to overtime, so an exact tie is rare.</p> : null}
              </div>
            ) : (
              <div key={kind} className="mt-3">
                <DataUnavailable title={dist[kind] === null ? `No ${kind} distribution in this run` : `The ${kind} distribution is unreadable`}>
                  {dist[kind] === null
                    ? `The published run has no simulated ${kind} for this game.`
                    : `Its bins failed validation (one share per integer outcome, no gaps, shares between 0 and 1), so it is not drawn.`}
                </DataUnavailable>
              </div>
            );
          })
        ) : (
          <div className="mt-3">
            <DataUnavailable title="No simulator output in this run">
              The published run predicts win probabilities only. Margin and total distributions appear when the published run
              comes from the game simulator (run_week.R).
            </DataUnavailable>
          </div>
        )}
      </section>

      <section className="mt-10" aria-labelledby="moves">
        <h2 id="moves" className="wdth-expanded text-[22px] font-bold">
          Line movement
        </h2>
        <div className="mt-3">
          <DataUnavailable title="One market snapshot">
            The nflverse consensus line has no timestamp or book, so there is nothing to plot over time. Per-venue movement,
            with kickoff and close markers, appears once forward-captured ESPN and Kalshi snapshots are ingested (Phase 2).
          </DataUnavailable>
        </div>
      </section>
    </>
  );
}

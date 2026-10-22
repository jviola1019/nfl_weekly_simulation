import Link from "next/link";
import { notFound } from "next/navigation";
import { DataUnavailable } from "@/components/DataUnavailable";
import { Field, FieldKey, gapText } from "@/components/Field";
import { StatusBadge } from "@/components/StatusBadge";
import { ScoreDistributionChart } from "@/components/charts/ScoreDistributionChart";
import { Breadcrumb, Card, ContextList, Grid, Page, Section, Term } from "@/components/ui";
import { runContext } from "@/lib/context";
import { candidateLines, gameDistributions, publicGame, publicGates, runCandidates } from "@/lib/data/queries";
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
    <div className={`flex flex-col gap-tight ${side === "home" ? "items-end text-right" : ""}`}>
      <span className="wdth-expanded text-title font-black">{id}</span>
      <span className="text-base font-medium">{name}</span>
    </div>
  );
  const value = (
    <span className="flex items-center gap-control">
      {winner ? <span className="rounded-control px-2 py-0.5 text-sm font-bold" style={{ background: c.ink, color: c.primary }}>Won</span> : null}
      <span className="num wdth-expanded text-score font-black">{big}</span>
    </span>
  );
  return (
    <div
      className="flex items-center justify-between gap-stack p-6 sm:px-8"
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
  // the game and the promotion gates are independent: one round trip for both
  const [{ run, game }, gates] = await Promise.all([publicGame(id), publicGates()]);
  if (!run || !game) notFound();
  const line = publicFieldLine(gates, await runCandidates(run.runId));
  const label = line ? candidateLabel(line.candidate) : "Model";
  const [lines, dist] = await Promise.all([line ? candidateLines(run.runId, [line.candidate], [id]) : Promise.resolve([]), gameDistributions(run.runId, id)]);
  const pm = game.pMarket;
  const pmod = lines[0]?.p ?? null;
  const hasDist = dist.margin !== null || dist.total !== null;
  const final = game.homeScore !== null && game.awayScore !== null ? { home: game.homeScore, away: game.awayScore } : null;

  return (
    <Page>
      <div className="flex flex-col gap-control">
        <Breadcrumb
          items={[
            { label: "This week", href: "/" },
            { label: `Week ${game.week}, ${game.season}` },
            { label: `${game.awayTeamId} ${game.neutral ? "vs" : "at"} ${game.homeTeamId}` }
          ]}
        />
        <ContextList items={runContext(run, { omitWeek: true })} />
      </div>

      <h1 className="sr-only">
        {game.awayName} {game.neutral ? "vs" : "at"} {game.homeName}
      </h1>
      <section aria-label={final ? "Final score" : "Market win chance"} data-section className="grid overflow-hidden rounded-card border border-rule lg:grid-cols-[minmax(0,1fr)_16.25rem_minmax(0,1fr)]">
        <TeamBlock id={game.awayTeamId} name={game.awayName} side="away" big={final ? String(final.away) : pm === null ? "–" : pct(1 - pm)} winner={!!final && final.away > final.home} />
        <div className="flex flex-col items-center justify-center gap-snug bg-surface p-card text-center">
          <span className="wdth-expanded text-heading font-extrabold">{final ? "Final" : "Kickoff"}</span>
          <time dateTime={new Date(game.kickoffUtc).toISOString()} className="text-sm text-ink-2">
            {kickoff(game.kickoffUtc)}
          </time>
          <span className="text-sm text-muted">{final ? "Result" : <>Win chance, <Term id="no-vig">no-vig</Term> market</>}</span>
        </div>
        <TeamBlock id={game.homeTeamId} name={game.homeName} side="home" big={final ? String(final.home) : pm === null ? "–" : pct(pm)} winner={!!final && final.home > final.away} />
      </section>

      <Section id="prob" title="Win probability" aside={<FieldKey showModel={pmod !== null} modelLabel={label} validated={line?.validated ?? false} />}>
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
        <p className="text-sm text-muted">
          Each team&apos;s side of the field is its chance to win.
          {pm !== null && pmod !== null ? ` ${gapText(pm, pmod, game.awayTeamId, game.homeTeamId)}.` : ""} <Term id="field">How to read the field</Term>.
        </p>
      </Section>

      <Section label="Market against model">
        <Grid kind="pair">
          <Card as="article" className="flex flex-col gap-control">
            <div className="flex items-baseline justify-between gap-control">
              <h3 className="font-bold">Moneyline · {game.homeTeamId} to win</h3>
              <span className="text-sm text-muted">nflverse consensus close</span>
            </div>
            <div className="grid grid-cols-2 gap-control">
              <div className="flex flex-col gap-tight">
                <span className="text-sm text-muted">
                  <Term id="no-vig">Market</Term>
                </span>
                <span className="num flex items-center gap-snug text-figure font-extrabold" data-line="market">
                  <span className="inline-block h-5.5 w-1" style={{ background: "var(--field-market)" }} aria-hidden />
                  {pm === null ? <span className="text-lg font-bold text-ink-2">No market line</span> : pct(pm, 1)}
                </span>
              </div>
              <div className="flex flex-col gap-tight">
                <span className="text-sm text-muted">{label}</span>
                <span className="num flex items-center gap-snug text-figure font-extrabold" data-line="model">
                  <span className="inline-block h-5.5 w-1" style={{ background: "var(--field-model)" }} aria-hidden />
                  {pct(pmod, 1)}
                </span>
              </div>
            </div>
            {line ? (
              <div className="flex flex-wrap items-center gap-snug border-t border-rule pt-control text-sm text-ink-2">
                <StatusBadge status={line.validated ? "validated" : "unvalidated"} label={line.validated ? "Validated" : "Unvalidated research model"} />
                <span>
                  {fieldLineShortNote(line)} <Link href="/evidence">Evidence</Link>
                </span>
              </div>
            ) : null}
          </Card>
          <Card as="article" className="flex flex-col gap-control">
            <h3 className="font-bold">Spread and total</h3>
            <p className="text-sm text-ink-2">
              In the validation sprint (Tune 2018–22) no model beat the devigged closing spread or total price, so no spread or
              total is offered here.{hasDist ? " The simulator's margin and total distributions below are research output." : ""}
            </p>
          </Card>
        </Grid>
      </Section>

      <Section id="dist" title="Simulated margin and total">
        {hasDist ? (
          <div className="flex flex-col gap-stack">
            {(["margin", "total"] as const).map((kind) => {
              const bins = parseBins(dist[kind]);
              return bins ? (
                <div key={kind} className="flex flex-col gap-snug">
                  <ScoreDistributionChart kind={kind} bins={bins} homeId={game.homeTeamId} awayId={game.awayTeamId} nSims={run.nSims}
                    result={final ? (kind === "margin" ? final.home - final.away : final.home + final.away) : null} />
                  {kind === "margin" ? <p className="text-sm text-muted">Regulation ties go to overtime, so an exact tie is rare.</p> : null}
                </div>
              ) : (
                <DataUnavailable key={kind} title={dist[kind] === null ? `No ${kind} distribution in this run` : `The ${kind} distribution is unreadable`}>
                  {dist[kind] === null
                    ? `The published run has no simulated ${kind} for this game.`
                    : `Its bins failed validation (one share per integer outcome, no gaps, shares between 0 and 1), so it is not drawn.`}
                </DataUnavailable>
              );
            })}
          </div>
        ) : (
          <DataUnavailable title="No simulator output in this run">
            The published run predicts win probabilities only. Margin and total distributions appear when the published run
            comes from the game simulator (run_week.R).
          </DataUnavailable>
        )}
      </Section>

      <Section id="moves" title="Line movement">
        <DataUnavailable title="One market snapshot">
          The nflverse consensus line has no timestamp or book, so there is nothing to plot over time. Per-venue movement,
          with kickoff and close markers, appears once forward-captured ESPN and Kalshi snapshots are ingested (Phase 2).
        </DataUnavailable>
      </Section>
    </Page>
  );
}

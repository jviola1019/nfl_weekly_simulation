import Link from "next/link";
import { notFound } from "next/navigation";
import { DataUnavailable } from "@/components/DataUnavailable";
import { Field, FieldKey } from "@/components/Field";
import { StatusBadge } from "@/components/StatusBadge";
import { candidateLines, evidence, publicGame } from "@/lib/data/queries";
import { kickoff, pct } from "@/lib/format";
import { candidateLabel, publicModelCandidates } from "@/lib/policy";

export const dynamic = "force-dynamic";

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return { title: id.replace(/_/g, " ") };
}

export default async function GamePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9]{4}_[0-9]{2}_[A-Z]{2,3}_[A-Z]{2,3}$/.test(id)) notFound();
  const [{ run, game }, ev] = await Promise.all([publicGame(id), evidence()]);
  if (!run || !game) notFound();
  const shown = publicModelCandidates(ev?.gates ?? []);
  const lines = shown.length ? await candidateLines(run.runId, shown, [id]) : [];
  const pm = game.pMarket;

  return (
    <>
      <p className="text-sm">
        <Link href="/">This week</Link>
      </p>
      <h1 className="mt-2 text-2xl font-semibold">
        {game.awayName} {game.neutral ? "vs" : "at"} {game.homeName}
      </h1>
      <p className="mt-1 text-ink-2">
        Week {game.week}, {game.season}. {kickoff(game.kickoffUtc)}.
      </p>

      <section className="mt-6" aria-labelledby="prob">
        <h2 id="prob" className="text-lg font-semibold">Win probability</h2>
        <div className="mt-2">
          <FieldKey showModel={lines.length > 0} />
        </div>
        <Field
          gameId={game.gameId}
          awayId={game.awayTeamId}
          homeId={game.homeTeamId}
          awayName={game.awayName}
          homeName={game.homeName}
          kickoffUtc={game.kickoffUtc}
          neutral={game.neutral}
          pMarket={pm}
          model={lines[0]?.p != null ? { p: lines[0].p, label: candidateLabel(lines[0].candidate) } : null}
        />
        <table className="num mt-2 w-full max-w-xl text-left text-sm">
          <thead className="text-ink-2">
            <tr><th className="py-1 pr-4 font-normal">Source</th><th className="pr-4 font-normal">{game.homeTeamId} wins</th><th className="font-normal">{game.awayTeamId} wins</th></tr>
          </thead>
          <tbody>
            <tr className="border-t border-rule"><td className="py-1 pr-4">Market, no-vig consensus</td><td className="pr-4">{pct(pm, 1)}</td><td>{pm === null ? "–" : pct(1 - pm, 1)}</td></tr>
            {lines.map((l) => (
              <tr key={l.candidate} className="border-t border-rule"><td className="py-1 pr-4">{candidateLabel(l.candidate)}</td><td className="pr-4">{pct(l.p, 1)}</td><td>{l.p === null ? "–" : pct(1 - l.p, 1)}</td></tr>
            ))}
          </tbody>
        </table>
        {!lines.length ? (
          <p className="mt-3 flex flex-wrap items-center gap-2 text-sm text-ink-2">
            <StatusBadge status="not better than market" label="Model hidden" />
            No registered candidate beat the closing market in the pre-registered test. <Link href="/evidence">Evidence</Link>
          </p>
        ) : null}
      </section>

      <section className="mt-10" aria-labelledby="dist">
        <h2 id="dist" className="text-lg font-semibold">Simulated margin and total</h2>
        <div className="mt-3">
          <DataUnavailable title="No simulator output in this cycle">
            This week&apos;s bundle comes from the backtest candidates, which predict a win probability only. The score
            simulator&apos;s margin and total distributions appear here once a simulator bundle is ingested (Phase 1b makes it
            point-in-time).
          </DataUnavailable>
        </div>
      </section>

      <section className="mt-10" aria-labelledby="moves">
        <h2 id="moves" className="text-lg font-semibold">Line movement</h2>
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

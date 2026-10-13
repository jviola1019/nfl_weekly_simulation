import { StatusBadge } from "@/components/StatusBadge";
import { type Bin, coveredMass, type DistKind, distributionSummary, outcomeLabel } from "@/lib/distribution";
import { ChartFigure } from "./ChartFigure";
import { LazyScoreDistributionPlot } from "./LazyScoreDistributionPlot";

/**
 * The simulator's final margin or total points for one game (A8), laid out like the
 * approved game-page mockup: a card per chart. One series, so no legend box: the title and
 * the marker labels name everything. The summary and the table view carry every value
 * (tooltips enhance, never gate), and both are rendered by the server. The plot itself
 * (ScoreDistributionPlot: columns, ticks, median and result markers, a crosshair on pointer
 * or arrow keys) is a client component that loads as its slot nears the viewport, so its
 * script is not part of the game page's first load (final review I6: it cost mobile LCP).
 */
export function ScoreDistributionChart({
  kind,
  bins,
  homeId,
  awayId,
  nSims,
  result
}: {
  kind: DistKind;
  bins: Bin[];
  homeId: string;
  awayId: string;
  nSims: number | null;
  result: number | null;
}) {
  const label = (v: number) => outcomeLabel(kind, v, homeId, awayId);
  const share = (p: number) => `${(p * 100).toFixed(2)}%`;
  const summary = distributionSummary(kind, bins, nSims, homeId, awayId, result);

  return (
    <section className="mt-4 rounded-[6px] border border-rule bg-surface px-5 pb-4 pt-1">
      <ChartFigure
        title={kind === "margin" ? "Simulated final margin" : "Simulated total points"}
        summary={summary}
        legend={<StatusBadge status="unvalidated" label="Simulator (unvalidated)" />}
        table={
          <table className="num w-full text-left">
            <thead className="text-ink-2">
              <tr>
                <th className="py-1 pr-4 font-normal">{kind === "margin" ? `Margin (${homeId} minus ${awayId})` : "Total points"}</th>
                <th className="font-normal">Share of simulated games</th>
              </tr>
            </thead>
            <tbody>
              {bins.map((b) => (
                <tr key={b.x} className="border-t border-rule">
                  <td className="py-1 pr-4">{label(b.x)}</td>
                  <td>{share(b.p)}</td>
                </tr>
              ))}
              <tr className="border-t border-rule text-ink-2">
                <td className="py-1 pr-4">Outside the range shown</td>
                <td>{share(Math.max(0, 1 - coveredMass(bins)))}</td>
              </tr>
            </tbody>
          </table>
        }
      >
        <LazyScoreDistributionPlot kind={kind} bins={bins} homeId={homeId} awayId={awayId} nSims={nSims} result={result} />
      </ChartFigure>
    </section>
  );
}

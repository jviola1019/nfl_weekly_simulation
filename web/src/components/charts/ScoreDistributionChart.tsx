import { StatusBadge } from "@/components/StatusBadge";
import { Card, DataTable } from "@/components/ui";
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
  const title = kind === "margin" ? "Simulated final margin" : "Simulated total points";

  return (
    <Card>
      <ChartFigure
        title={title}
        summary={summary}
        legend={<StatusBadge status="unvalidated" label="Simulator (unvalidated)" />}
        table={
          <DataTable
            caption={`${title}, every outcome`}
            numeric
            dense
            columns={[
              { key: "outcome", header: kind === "margin" ? `Margin (${homeId} minus ${awayId})` : "Total points", rowHeader: true },
              { key: "share", header: "Share of simulated games" }
            ]}
            rows={[
              ...bins.map((b) => ({ key: String(b.x), cells: { outcome: label(b.x), share: share(b.p) } })),
              { key: "outside", cells: { outcome: "Outside the range shown", share: share(Math.max(0, 1 - coveredMass(bins))) }, muted: true }
            ]}
          />
        }
      >
        <LazyScoreDistributionPlot kind={kind} bins={bins} homeId={homeId} awayId={awayId} nSims={nSims} result={result} />
      </ChartFigure>
    </Card>
  );
}

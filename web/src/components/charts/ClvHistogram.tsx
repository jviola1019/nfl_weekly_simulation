"use client";

import { scaleLinear } from "@visx/scale";
import { bps, signedPct } from "@/lib/format";
import { candidateLabel } from "@/lib/policy";
import { ChartFigure, LineKey } from "./ChartFigure";
import { ChartTooltip } from "./ChartTooltip";
import { useChartWidth } from "./useChartWidth";

/**
 * Distribution of per-pick closing-line value (bps) for one candidate: columns of
 * pick counts per 50-bps bin, a zero line, and the mean with its bootstrap interval.
 * Descriptive only: the betting-value gate needs 400 decision-time picks (A2).
 */
export function ClvHistogram({
  candidate,
  values,
  meanCi,
  roi
}: {
  candidate: string;
  values: number[];
  meanCi: { mean: number; lo: number; hi: number } | null;
  roi: number | null;
}) {
  const [ref, W] = useChartWidth(720);
  const H = W < 560 ? 220 : 260;
  const left = 44;
  const right = 16;
  const top = 16;
  const bottom = 40;
  const width = 50;
  const lo = Math.max(-800, Math.floor(Math.min(...values, -200) / width) * width);
  const hi = Math.min(800, Math.ceil(Math.max(...values, 200) / width) * width);
  const edges: number[] = [];
  for (let e = lo; e < hi; e += width) edges.push(e);
  const counts = edges.map((e) => values.filter((v) => (v >= e && v < e + width) || (e === lo && v < lo) || (e === hi - width && v >= hi)).length);
  const x = scaleLinear({ domain: [lo, hi], range: [left, W - right] });
  const y = scaleLinear({ domain: [0, Math.max(1, ...counts)], range: [H - bottom, top], nice: true });
  // columns fill the bin less a 2px surface gap; the rounded data-end shrinks with thin columns
  const barW = Math.max(1, Math.min(24, x(lo + width) - x(lo) - 2));
  const rr = Math.min(4, barW / 2);
  const n = values.length;
  const mean = n ? values.reduce((a, b) => a + b, 0) / n : 0;
  const summary =
    `${candidateLabel(candidate)}: ${n} decision-time picks at the 2024 ESPN BET opener. Mean CLV ${bps(mean)}` +
    (meanCi ? ` (95% interval ${bps(meanCi.lo)} to ${bps(meanCi.hi)})` : "") +
    (roi !== null ? `; flat-stake ROI ${signedPct(roi, 1)}.` : ".") +
    ` Descriptive only: fewer than the 400 picks the betting-value gate requires.`;

  return (
    <ChartFigure
      title={`Closing-line value per pick, ${candidateLabel(candidate)}`}
      summary={summary}
      legend={
        <div className="flex flex-wrap gap-x-5">
          <LineKey color="var(--model)" label="Picks per 50-bps bin" />
          <LineKey color="var(--ink)" label="Mean and 95% interval" />
        </div>
      }
      table={
        <table className="num w-full text-left">
          <thead className="text-ink-2">
            <tr><th className="py-1 pr-4 font-normal">CLV bin (bps)</th><th className="font-normal">Picks</th></tr>
          </thead>
          <tbody>
            {edges.map((e, i) => (
              <tr key={e} className="border-t border-rule"><td className="py-1 pr-4">{e} to {e + width}</td><td>{counts[i]}</td></tr>
            ))}
          </tbody>
        </table>
      }
    >
      <ChartTooltip>
        <div ref={ref}>
        <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} className="block h-auto max-w-full" role="img" aria-label={summary}>
          {y.ticks(4).map((t) => (
            <g key={t}>
              <line x1={left} x2={W - right} y1={y(t)} y2={y(t)} stroke="var(--grid)" strokeWidth={1} />
              <text x={left - 8} y={y(t) + 4} textAnchor="end" fontSize={12} fill="var(--ink-muted)" className="num">{t}</text>
            </g>
          ))}
          {edges.map((e, i) => {
            const h = y(0) - y(counts[i] ?? 0);
            const cx = x(e + width / 2);
            return (
              <g key={e}>
                {h > 0 ? (
                  <path
                    d={`M${cx - barW / 2},${y(0)} v${-(h - rr)} q0,${-rr} ${rr},${-rr} h${barW - 2 * rr} q${rr},0 ${rr},${rr} v${h - rr} z`}
                    fill="var(--model)"
                  />
                ) : null}
                <rect
                  x={cx - (x(lo + width) - x(lo)) / 2}
                  y={top}
                  width={x(lo + width) - x(lo)}
                  height={H - bottom - top}
                  fill="transparent"
                  tabIndex={counts[i] ? 0 : -1}
                  role="graphics-symbol"
                  aria-label={`${e} to ${e + width} bps: ${counts[i]} picks`}
                  data-tip-value={`${counts[i]} picks`}
                  data-tip-label={`${e} to ${e + width} bps`}
                />
              </g>
            );
          })}
          <line x1={x(0)} x2={x(0)} y1={top} y2={H - bottom} stroke="var(--ink-muted)" strokeWidth={1} />
          {meanCi ? (
            <g>
              <line x1={x(meanCi.lo)} x2={x(meanCi.hi)} y1={top + 6} y2={top + 6} stroke="var(--ink)" strokeWidth={2} strokeLinecap="round" />
              <circle cx={x(meanCi.mean)} cy={top + 6} r={5} fill="var(--ink)" stroke="var(--surface)" strokeWidth={2} />
            </g>
          ) : null}
          {x.ticks(W < 560 ? 4 : 8).map((t) => (
            <text key={t} x={x(t)} y={H - 16} textAnchor="middle" fontSize={12} fill="var(--ink-muted)" className="num">{t}</text>
          ))}
          <text x={(left + W - right) / 2} y={H - 2} textAnchor="middle" fontSize={12} fill="var(--ink-2)">CLV (bps), side taken</text>
        </svg>
        </div>
      </ChartTooltip>
    </ChartFigure>
  );
}

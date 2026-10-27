"use client";

import { useState } from "react";
import {
  type Bin,
  binQuantile,
  columnPath,
  type DistKind,
  distributionSummary,
  outcomeLabel,
  stepPaths,
  ticksEvery
} from "@/lib/distribution";
import { linearScale } from "@/lib/linearScale";
import { useChartWidth } from "./useChartWidth";

/**
 * The plot of one simulated margin or total: one-point columns, ticks on football steps (7
 * points for margins, 10 for totals) and labelled markers for the simulator's median (model
 * gold) and, once the game is final, the result (actual rose). Where a one-point column would
 * be under 5px wide (phones) a step outline with a 10% wash keeps every outcome visible. A
 * crosshair snaps to the nearest outcome on pointer or arrow keys. This is the client half of
 * ScoreDistributionChart; LazyScoreDistributionPlot loads it as the slot nears the viewport,
 * so its script is off the page's first load.
 */
export function ScoreDistributionPlot({
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
  const [ref, W] = useChartWidth(720);
  const [focus, setFocus] = useState<number | null>(null);
  const H = W < 560 ? 240 : 280;
  const left = 44;
  const right = 16;
  const top = 44;
  const bottom = 30;
  const first = bins[0]!.x;
  const lo = first - 0.5;
  const hi = bins[bins.length - 1]!.x + 0.5;
  const x = linearScale({ domain: [lo, hi], range: [left, W - right] });
  const y = linearScale({ domain: [0, Math.max(...bins.map((b) => b.p))], range: [H - bottom, top], nice: true });
  const binPx = x(first + 0.5) - x(lo);
  const columns = binPx >= 5;
  const barW = Math.min(24, binPx - 2);
  const label = (v: number) => outcomeLabel(kind, v, homeId, awayId);
  const share = (p: number) => `${(p * 100).toFixed(2)}%`;
  const summary = distributionSummary(kind, bins, nSims, homeId, awayId, result);
  const median = binQuantile(bins, 0.5);
  const focused = focus === null ? null : (bins[focus] ?? null);
  // ticks on multiples of 7 (margins) or 10 (totals), widened until labels are 72px / 40px apart
  const base = kind === "margin" ? 7 : 10;
  const step = base * Math.max(1, Math.ceil((kind === "margin" ? 72 : 40) / (binPx * base)));
  const markers = [
    { v: median, text: `Median ${label(median)}`, color: "var(--model)", row: 0 },
    ...(result !== null && result >= lo && result <= hi ? [{ v: result, text: `Final ${label(result)}`, color: "var(--actual)", row: 1 }] : [])
  ];
  const anchor = (px: number) => (px > W - 130 ? "end" : px < left + 130 ? "start" : "middle");
  const nearest = (clientX: number, svg: SVGSVGElement) => {
    const v = Math.round(x.invert(clientX - svg.getBoundingClientRect().left));
    return Math.min(Math.max(v - first, 0), bins.length - 1);
  };
  const { line, area } = stepPaths(bins, x, y);

  return (
    <div ref={ref} className="relative">
      <svg
        width={W}
        height={H}
        viewBox={`0 0 ${W} ${H}`}
        className="block h-auto max-w-full"
        role="img"
        aria-label={summary}
        tabIndex={0}
        onPointerMove={(e) => setFocus(nearest(e.clientX, e.currentTarget))}
        onPointerLeave={() => setFocus(null)}
        onBlur={() => setFocus(null)}
        onKeyDown={(e) => {
          const i = focus ?? bins.findIndex((b) => b.x === median);
          if (e.key === "ArrowRight") setFocus(Math.min(i + 1, bins.length - 1));
          else if (e.key === "ArrowLeft") setFocus(Math.max(i - 1, 0));
          else if (e.key === "Home") setFocus(0);
          else if (e.key === "End") setFocus(bins.length - 1);
          else return;
          e.preventDefault();
        }}
      >
        {y.ticks(4).map((t) => (
          <g key={t}>
            <line x1={left} x2={W - right} y1={y(t)} y2={y(t)} stroke="var(--grid)" strokeWidth={1} />
            <text x={left - 8} y={y(t) + 4} textAnchor="end" fontSize={12} fill="var(--ink-muted)" className="num">
              {t === 0 ? "0%" : `${(t * 100).toFixed(t < 0.01 ? 1 : 0)}%`}
            </text>
          </g>
        ))}
        {columns ? (
          bins.map((b) => (b.p > 0 ? <path key={b.x} d={columnPath(x(b.x), y(0), y(0) - y(b.p), barW, 2)} fill="var(--ink-muted)" /> : null))
        ) : (
          <>
            <path d={area} fill="var(--ink-muted)" fillOpacity={0.1} />
            <path d={line} fill="none" stroke="var(--ink-muted)" strokeWidth={2} strokeLinejoin="round" />
          </>
        )}
        <line x1={left} x2={W - right} y1={y(0)} y2={y(0)} stroke="var(--rule)" strokeWidth={1} />
        {kind === "margin" && lo < 0 && hi > 0 ? <line x1={x(0)} x2={x(0)} y1={top} y2={y(0)} stroke="var(--ink-muted)" strokeWidth={1} /> : null}
        {markers.map((m) => (
          <g key={m.text}>
            {/* lines start below both label rows, so no marker crosses another marker's label */}
            <line x1={x(m.v)} x2={x(m.v)} y1={top - 6} y2={y(0)} stroke={m.color} strokeWidth={2} />
            <text x={x(m.v) + (anchor(x(m.v)) === "start" ? 6 : anchor(x(m.v)) === "end" ? -6 : 0)} y={10 + m.row * 16}
              textAnchor={anchor(x(m.v))} fontSize={12} fontWeight={600} fill="var(--ink-2)">{m.text}</text>
          </g>
        ))}
        {focused ? <line x1={x(focused.x)} x2={x(focused.x)} y1={top} y2={y(0)} stroke="var(--ink)" strokeWidth={1} /> : null}
        {ticksEvery(lo, hi, step).map((t) => (
          <text key={t} x={x(t)} y={H - 10} textAnchor="middle" fontSize={12} fill="var(--ink-muted)" className="num">
            {kind === "margin" ? label(t) : t}
          </text>
        ))}
      </svg>
      {focused ? (
        <div
          role="status"
          className="pointer-events-none absolute z-10 rounded-control border border-rule bg-surface px-2 py-1 text-sm"
          style={{ left: Math.min(Math.max(0, x(focused.x) + 12), Math.max(0, W - 170)), top: 40 }}
        >
          <div className="num font-semibold text-ink">{share(focused.p)} of simulated games</div>
          <div className="text-ink-2">{label(focused.x)}</div>
        </div>
      ) : null}
    </div>
  );
}

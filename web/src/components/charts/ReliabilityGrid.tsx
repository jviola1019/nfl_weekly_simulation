"use client";

import { scaleLinear } from "@visx/scale";
import { candidateLabel } from "@/lib/policy";
import { pct } from "@/lib/format";
import { ChartFigure, LineKey } from "./ChartFigure";
import { ChartTooltip } from "./ChartTooltip";
import { useChartWidth } from "./useChartWidth";

export interface BinRow {
  candidate: string;
  bin: number;
  pMean: number;
  yMean: number;
  n: number;
}

/**
 * Reliability diagrams as small multiples (one per candidate, same axes), ten
 * equal-mass bins each. The diagonal is perfect calibration. The market panel is
 * drawn in market blue, model candidates in model gold; each panel has one series.
 */
export function ReliabilityGrid({ bins, ece, splitLabel }: { bins: BinRow[]; ece: Record<string, number>; splitLabel: string }) {
  const order = ["C0", "C1", "C2", "E1", "K[E1]", "B1[C1]", "B1[C2]", "B1[E1]", "B2[E1]"];
  const byCand = new Map<string, BinRow[]>();
  for (const b of bins) byCand.set(b.candidate, [...(byCand.get(b.candidate) ?? []), b]);
  const cands = order.filter((c) => byCand.has(c));
  const [ref, W] = useChartWidth(720);
  const cols = W < 560 ? 2 : 3;
  const gap = 16;
  const S = Math.max(120, Math.min(320, Math.floor((W - gap * (cols - 1)) / cols)));
  const pad = 42;
  const x = scaleLinear({ domain: [0, 1], range: [pad, S - 18] });
  const y = scaleLinear({ domain: [0, 1], range: [S - pad, 12] });
  const worst = [...cands].sort((a, b) => (ece[b] ?? 0) - (ece[a] ?? 0))[0];
  const summary =
    `${splitLabel}: observed home-win rate against predicted probability in ten equal-mass bins. ` +
    `Market ECE ${pct(ece.C0 ?? NaN, 1)}; the largest ECE is ${candidateLabel(worst ?? "")} at ${pct(ece[worst ?? ""] ?? NaN, 1)}. ` +
    `Points above the diagonal mean the home team won more often than predicted.`;

  return (
    <ChartFigure
      title={`Reliability, ${splitLabel}`}
      summary={summary}
      legend={
        <div className="flex flex-wrap gap-x-5">
          <LineKey color="var(--market)" label="Market" />
          <LineKey color="var(--model)" label="Model candidates" />
          <LineKey color="var(--neutral-mid)" label="Perfect calibration" />
        </div>
      }
      table={
        <table className="num w-full text-left">
          <thead className="text-ink-2">
            <tr><th className="py-1 pr-4 font-normal">Candidate</th><th className="pr-4 font-normal">Bin</th><th className="pr-4 font-normal">Mean predicted</th><th className="pr-4 font-normal">Observed</th><th className="font-normal">Games</th></tr>
          </thead>
          <tbody>
            {cands.flatMap((c) =>
              (byCand.get(c) ?? []).map((b) => (
                <tr key={`${c}-${b.bin}`} className="border-t border-rule">
                  <td className="py-1 pr-4">{candidateLabel(c)}</td>
                  <td className="pr-4">{b.bin}</td>
                  <td className="pr-4">{pct(b.pMean, 1)}</td>
                  <td className="pr-4">{pct(b.yMean, 1)}</td>
                  <td>{b.n}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      }
    >
      <ChartTooltip>
        <div ref={ref} className="grid gap-4" style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}>
          {cands.map((c) => {
            const pts = byCand.get(c) ?? [];
            const color = c === "C0" ? "var(--market)" : "var(--model)";
            const path = pts.map((b, i) => `${i ? "L" : "M"}${x(b.pMean).toFixed(1)},${y(b.yMean).toFixed(1)}`).join(" ");
            return (
              <div key={c}>
                <p className="text-sm">
                  {candidateLabel(c)} <span className="num text-muted">ECE {pct(ece[c] ?? NaN, 1)}</span>
                </p>
                <svg width={S} height={S} viewBox={`0 0 ${S} ${S}`} className="block h-auto max-w-full" role="img" aria-label={`${candidateLabel(c)} reliability`}>
                  {[0, 0.5, 1].map((t) => (
                    <g key={t}>
                      <line x1={x(t)} x2={x(t)} y1={y(0)} y2={y(1)} stroke="var(--grid)" strokeWidth={1} />
                      <line x1={x(0)} x2={x(1)} y1={y(t)} y2={y(t)} stroke="var(--grid)" strokeWidth={1} />
                      <text x={x(t)} y={S - 12} textAnchor="middle" fontSize={12} fill="var(--ink-muted)" className="num">{pct(t)}</text>
                      <text x={pad - 6} y={y(t) + 4} textAnchor="end" fontSize={12} fill="var(--ink-muted)" className="num">{pct(t)}</text>
                    </g>
                  ))}
                  <line x1={x(0)} y1={y(0)} x2={x(1)} y2={y(1)} stroke="var(--neutral-mid)" strokeWidth={1.5} />
                  <path d={path} fill="none" stroke={color} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
                  {pts.map((b) => (
                    <g key={b.bin}>
                      <circle cx={x(b.pMean)} cy={y(b.yMean)} r={4} fill={color} stroke="var(--surface)" strokeWidth={2} />
                      <circle
                        cx={x(b.pMean)}
                        cy={y(b.yMean)}
                        r={12}
                        fill="transparent"
                        tabIndex={0}
                        role="graphics-symbol"
                        aria-label={`${candidateLabel(c)} bin ${b.bin}: predicted ${pct(b.pMean, 1)}, observed ${pct(b.yMean, 1)}, ${b.n} games`}
                        data-tip-value={`${pct(b.yMean, 1)} observed`}
                        data-tip-label={`${candidateLabel(c)}: predicted ${pct(b.pMean, 1)}, ${b.n} games`}
                      />
                    </g>
                  ))}
                </svg>
              </div>
            );
          })}
        </div>
      </ChartTooltip>
    </ChartFigure>
  );
}

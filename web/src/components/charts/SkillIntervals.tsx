"use client";

import { scaleLinear } from "@visx/scale";
import { candidateLabel } from "@/lib/policy";
import { signedPct } from "@/lib/format";
import { ChartFigure, LineKey } from "./ChartFigure";
import { ChartTooltip } from "./ChartTooltip";
import { useChartWidth } from "./useChartWidth";

export interface SkillRow {
  candidate: string;
  skill: number;
  skillLo: number;
  skillHi: number;
  brier: number;
  n: number;
}

/**
 * Brier skill vs the no-vig market with 95% week-block bootstrap intervals. The
 * market is the zero line (blue); candidates are dots with interval whiskers in ink.
 * Positive is better than the market. One axis, one series. Below 560px the
 * candidate labels sit above their whiskers so the plot keeps the full width.
 */
export function SkillIntervals({ rows, splitLabel }: { rows: SkillRow[]; splitLabel: string }) {
  const data = rows.filter((r) => r.candidate !== "C0").sort((a, b) => b.skill - a.skill);
  const [ref, W] = useChartWidth(720);
  const stacked = W < 560;
  const rowH = stacked ? 48 : 34;
  const left = stacked ? 24 : 220;
  const right = 24;
  const top = 12;
  const H = top + data.length * rowH + 36;
  const lo = Math.min(-0.1, ...data.map((d) => d.skillLo)) * 1.05;
  const hi = Math.max(0.02, ...data.map((d) => d.skillHi)) * 1.05;
  const x = scaleLinear({ domain: [lo, hi], range: [left, W - right] });
  const ticks = x.ticks(6);
  const best = data[0];
  const beats = data.filter((d) => d.skillLo > 0);
  const summary =
    `${splitLabel}: ${data.length} candidates against the no-vig closing market (${data[0]?.n ?? 0} games). ` +
    (beats.length
      ? `${beats.map((b) => candidateLabel(b.candidate)).join(", ")} beat the market with the interval above zero.`
      : `None beats the market: no interval lies above zero. The closest is ${candidateLabel(best?.candidate ?? "")} at ${signedPct(best?.skill ?? 0)} (${signedPct(best?.skillLo ?? 0)} to ${signedPct(best?.skillHi ?? 0)}).`);

  return (
    <ChartFigure
      title={`Brier skill vs the market, ${splitLabel}`}
      summary={summary}
      legend={
        <div className="flex flex-wrap gap-x-5">
          <LineKey color="var(--market)" label="Market (zero skill)" />
          <LineKey color="var(--ink)" label="Candidate skill, 95% interval" marker />
        </div>
      }
      table={
        <table className="num w-full text-left">
          <thead className="text-ink-2">
            <tr><th className="py-1 pr-4 font-normal">Candidate</th><th className="pr-4 font-normal">Brier</th><th className="pr-4 font-normal">Skill</th><th className="font-normal">95% interval</th></tr>
          </thead>
          <tbody>
            {data.map((d) => (
              <tr key={d.candidate} className="border-t border-rule">
                <td className="py-1 pr-4">{candidateLabel(d.candidate)}</td>
                <td className="pr-4">{d.brier.toFixed(4)}</td>
                <td className="pr-4">{signedPct(d.skill)}</td>
                <td>{signedPct(d.skillLo)} to {signedPct(d.skillHi)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      }
    >
      <ChartTooltip>
        <div ref={ref}>
        <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} className="block h-auto max-w-full" role="img" aria-label={summary}>
          {ticks.map((t) => (
            <g key={t}>
              <line x1={x(t)} x2={x(t)} y1={top} y2={H - 28} stroke="var(--grid)" strokeWidth={1} />
              <text x={x(t)} y={H - 10} textAnchor="middle" fontSize={12} fill="var(--ink-muted)" className="num">
                {signedPct(t, 0)}
              </text>
            </g>
          ))}
          <line x1={x(0)} x2={x(0)} y1={top - 4} y2={H - 28} stroke="var(--market)" strokeWidth={2} />
          {data.map((d, i) => {
            const cy = top + i * rowH + (stacked ? 32 : rowH / 2);
            return (
              <g key={d.candidate}>
                <text x={stacked ? 0 : left - 12} y={stacked ? cy - 14 : cy + 5} textAnchor={stacked ? "start" : "end"} fontSize={14} fill="var(--ink)">
                  {candidateLabel(d.candidate)}
                </text>
                <line x1={x(d.skillLo)} x2={x(d.skillHi)} y1={cy} y2={cy} stroke="var(--ink-2)" strokeWidth={2} strokeLinecap="round" />
                <circle cx={x(d.skill)} cy={cy} r={5} fill="var(--ink)" stroke="var(--surface)" strokeWidth={2} />
                <rect
                  x={left}
                  y={cy - 12}
                  width={W - left - right}
                  height={24}
                  fill="transparent"
                  tabIndex={0}
                  role="graphics-symbol"
                  aria-label={`${candidateLabel(d.candidate)}: ${signedPct(d.skill)}, interval ${signedPct(d.skillLo)} to ${signedPct(d.skillHi)}`}
                  data-tip-value={`${signedPct(d.skill)} (${signedPct(d.skillLo)} to ${signedPct(d.skillHi)})`}
                  data-tip-label={`${candidateLabel(d.candidate)}, Brier ${d.brier.toFixed(4)}`}
                />
              </g>
            );
          })}
        </svg>
        </div>
      </ChartTooltip>
    </ChartFigure>
  );
}

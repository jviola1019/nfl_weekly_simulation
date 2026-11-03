import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { pctTicks } from "@/lib/format";
import { ScoreDistributionChart } from "./ScoreDistributionChart";
import { ScoreDistributionPlot } from "./ScoreDistributionPlot";

const P = [0.1, 0.2, 0.25, 0.2, 0.15, 0.1];
const bins = [-2, -1, 0, 1, 2, 3].map((x, i) => ({ x, p: P[i]! }));

describe("ScoreDistributionChart (server render)", () => {
  it("is a card with a figure, a computed summary and one table row per outcome; the plot loads later (final review I6)", () => {
    const html = renderToStaticMarkup(<ScoreDistributionChart kind="margin" bins={bins} homeId="SF" awayId="LA" nSims={100000} result={-2} />);
    expect(html).toContain("<figure");
    expect(html).toContain("Simulated final margin");
    expect(html).toContain("Simulator (unvalidated)");
    expect(html).toContain(
      "Simulator (unvalidated): median margin Tie. In at least 90% of the 100,000 simulated games the margin falls between LA by 2 and SF by 3. Final: LA by 2."
    );
    expect((html.match(/<tr class="border-t border-rule">/g) ?? []).length).toBe(bins.length);
    expect(html).toContain("<td>25.00%</td>");
    expect(html).toContain("Outside the range shown");
    expect(html).toContain("data-plot-slot");   // the slot the client plot fills when it nears the viewport
    expect(html).not.toContain('role="img"');   // the plot (and its script) is not in the page's first load
  });
});

describe("ScoreDistributionPlot (server render of the client plot)", () => {
  it("labels the median and the result, with colours from the tokens", () => {
    const html = renderToStaticMarkup(<ScoreDistributionPlot kind="margin" bins={bins} homeId="SF" awayId="LA" nSims={100000} result={-2} />);
    expect(html).toContain('role="img"');
    expect(html).toContain("Median Tie");
    expect(html).toContain("Final LA by 2");
    expect(html).toContain('stroke="var(--model)"');
    expect(html).toContain('stroke="var(--actual)"');
    expect(html).not.toMatch(/#[0-9a-f]{3,6}/i);   // colours come from the tokens
  });

  it("labels a total in points and leaves the result out until the game is final", () => {
    const totals = [40, 41, 42].map((x, i) => ({ x, p: [0.3, 0.4, 0.3][i]! }));
    const html = renderToStaticMarkup(<ScoreDistributionPlot kind="total" bins={totals} homeId="SF" awayId="LA" nSims={null} result={null} />);
    expect(html).toContain("Median 41 points");
    expect(html).toContain("median total 41 points");
    expect(html).not.toContain("Final ");
    expect(html).not.toContain('stroke="var(--actual)"');
  });

  // 2026 week 9, JAX at BAL: a total distribution peaking at 2.544% gets ticks every 0.5%, which the axis labelled
  // 0%, 0.5%, 1%, 2%, 2%, 3% (1.5% and 2.5% rounded to whole percents), so its top gridline read 3% at 2.5%
  it("labels every y gridline with its own value when the ticks are half a percent apart", () => {
    const totals = Array.from({ length: 91 }, (_, i) => 20 + i).map((x) => ({ x, p: 0.02544 * Math.exp(-((x - 52) ** 2) / (2 * 15.7 ** 2)) }));
    const html = renderToStaticMarkup(<ScoreDistributionPlot kind="total" bins={totals} homeId="BAL" awayId="JAX" nSims={100000} result={null} />);
    const yLabels = [...html.matchAll(/text-anchor="end"[^>]*>([0-9.]+%)<\/text>/g)].map((m) => m[1]);
    expect(yLabels).toEqual(["0%", "0.5%", "1.0%", "1.5%", "2.0%", "2.5%"]);
  });
});

describe("pctTicks", () => {
  it("gives each tick the decimals of the tick step, so no two labels are the same", () => {
    expect(pctTicks([0, 0.005, 0.01, 0.015, 0.02, 0.025])).toEqual(["0%", "0.5%", "1.0%", "1.5%", "2.0%", "2.5%"]);
    expect(pctTicks([0, 0.01, 0.02, 0.03])).toEqual(["0%", "1%", "2%", "3%"]);
    expect(pctTicks([0, 0.002, 0.004, 0.006])).toEqual(["0%", "0.2%", "0.4%", "0.6%"]);
    expect(pctTicks([0, 0.0005, 0.001])).toEqual(["0%", "0.05%", "0.10%"]);
    expect(pctTicks([0.01])).toEqual(["1%"]);
  });
});

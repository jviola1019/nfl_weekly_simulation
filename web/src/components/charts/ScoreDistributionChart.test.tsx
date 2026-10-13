import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
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
});

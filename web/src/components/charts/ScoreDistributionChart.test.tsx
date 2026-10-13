import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { ScoreDistributionChart } from "./ScoreDistributionChart";

const P = [0.1, 0.2, 0.25, 0.2, 0.15, 0.1];
const bins = [-2, -1, 0, 1, 2, 3].map((x, i) => ({ x, p: P[i]! }));

describe("ScoreDistributionChart (server render)", () => {
  it("is a card with a figure, a computed summary, labelled median and result, and one table row per outcome", () => {
    const html = renderToStaticMarkup(<ScoreDistributionChart kind="margin" bins={bins} homeId="SF" awayId="LA" nSims={100000} result={-2} />);
    expect(html).toContain("<figure");
    expect(html).toContain("Simulated final margin");
    expect(html).toContain("Simulator (unvalidated)");
    expect(html).toContain(
      "Simulator (unvalidated): median margin Tie. In at least 90% of the 100,000 simulated games the margin falls between LA by 2 and SF by 3. Final: LA by 2."
    );
    expect(html).toContain("Median Tie");
    expect(html).toContain("Final LA by 2");
    expect((html.match(/<tr class="border-t border-rule">/g) ?? []).length).toBe(bins.length);
    expect(html).toContain("<td>25.00%</td>");
    expect(html).toContain("Outside the range shown");
    expect(html).toContain('stroke="var(--model)"');
    expect(html).toContain('stroke="var(--actual)"');
    expect(html).not.toMatch(/#[0-9a-f]{3,6}\b/i);   // colours come from the tokens
  });

  it("labels a total in points and leaves the result out until the game is final", () => {
    const totals = [40, 41, 42].map((x, i) => ({ x, p: [0.3, 0.4, 0.3][i]! }));
    const html = renderToStaticMarkup(<ScoreDistributionChart kind="total" bins={totals} homeId="SF" awayId="LA" nSims={null} result={null} />);
    expect(html).toContain("Simulated total points");
    expect(html).toContain("Median 41 points");
    expect(html).toContain("median total 41 points");
    expect(html).not.toContain("Final ");
    expect(html).not.toContain('stroke="var(--actual)"');
  });
});

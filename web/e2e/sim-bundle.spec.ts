import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";
import { pct } from "../src/lib/format";
import { drawLazyCharts, SCHEMES, WIDTHS } from "./helpers";

/**
 * A published simulator run (A8). CI ingests the committed fixture after the main e2e
 * run and then runs `--grep @sim`; locally, point E2E_SIM_BUNDLE at the bundle that
 * `npm run local` published (the newest one under bundles/). The probabilities on the
 * pages must equal the bundle's numbers at the precision each place displays them.
 */
const BUNDLE = process.env.E2E_SIM_BUNDLE ?? fileURLToPath(new URL("../../contracts/fixtures/bundles/weekly-sim-2024-w15", import.meta.url));
const read = <T,>(name: string) => JSON.parse(readFileSync(join(BUNDLE, `${name}.json`), "utf8")) as T;
type Pred = { game_id: string; candidate: string; p_home_final?: number; p_home_mkt_novig?: number };
type Game = { game_id: string; home_team_id: string; away_team_id: string };
type Team = { team_id: string; full_name: string };
type Dist = { game_id: string; kind: "margin" | "total"; bins: { x: number; p: number }[] };

const preds = read<Pred[]>("game_predictions");
const games = read<Game[]>("games");
const teams = read<Team[]>("teams");
const name = (id: string) => teams.find((t) => t.team_id === id)!.full_name;
const market = (id: string) => preds.find((p) => p.game_id === id && p.candidate === "C0")?.p_home_mkt_novig ?? null;
const sim = (id: string) => preds.find((p) => p.game_id === id && p.candidate === "C3")!.p_home_final!;

/** The Field's accessible summary, built from the bundle with the display rounding (pct). */
function fieldSummary(g: Game): string {
  const away = name(g.away_team_id);
  const home = name(g.home_team_id);
  const m = market(g.game_id);
  const s = sim(g.game_id);
  const marketPart = m === null ? `${away} at ${home}: no market line.` : `${away} at ${home}. Market: ${away} ${pct(1 - m)}, ${home} ${pct(m)}.`;
  return `${marketPart} Simulator (unvalidated): ${away} ${pct(1 - s)}, ${home} ${pct(s)}.`;
}

test.describe("@sim simulator run", () => {
  test("the home page shows the simulator line, labelled unvalidated, with the bundle's numbers", async ({ page }) => {
    await page.goto("/");
    const status = page.getByRole("complementary", { name: "Model status" });
    await expect(status).toContainText("Unvalidated");
    await expect(status).toContainText("Simulator");
    for (const g of games) {
      await expect(page.locator(`article[data-game="${g.game_id}"]`), g.game_id).toHaveAttribute("aria-label", fieldSummary(g));
    }
  });

  for (const g of games) {
    test(`game ${g.game_id}: market and simulator probabilities equal the bundle at the displayed precision`, async ({ page }) => {
      await page.goto(`/games/${g.game_id}`);
      // a game the market never priced says so in words where the number would be (audit M11)
      await expect(page.locator('[data-line="market"]')).toHaveText(market(g.game_id) === null ? "No market line" : pct(market(g.game_id), 1));
      await expect(page.locator('[data-line="model"]')).toHaveText(pct(sim(g.game_id), 1));
      await expect(page.locator(`article[data-game="${g.game_id}"]`)).toHaveAttribute("aria-label", fieldSummary(g));
    });
  }

  test("the game page draws margin and total distributions, each with a summary and a full table view", async ({ page }) => {
    const g = games[0]!;
    const dists = read<Dist[]>("score_distributions").filter((d) => d.game_id === g.game_id);
    await page.goto(`/games/${g.game_id}`);
    await drawLazyCharts(page);   // each figure's plot arrives as its slot nears the viewport
    await expect(page.getByText("Regulation ties go to overtime, so an exact tie is rare.")).toHaveCount(1);
    for (const [kind, title] of [["margin", "Simulated final margin"], ["total", "Simulated total points"]] as const) {
      const fig = page.locator("figure").filter({ hasText: title });
      await expect(fig).toHaveCount(1);
      await expect(fig.locator("figcaption")).toContainText("median");
      await expect(fig.locator("figcaption")).toContainText("In at least 90% of");
      await fig.getByText("Table view").click();
      const bins = dists.find((d) => d.kind === kind)!.bins;
      await expect(fig.locator("tbody tr")).toHaveCount(bins.length + 1);   // every outcome, plus the share outside the range
    }
  });

  for (const scheme of SCHEMES) {
    for (const width of WIDTHS) {
      test(`distributions at ${width}px ${scheme}: no overflow, no axe violation`, async ({ page }) => {
        await page.setViewportSize({ width, height: 900 });
        await page.emulateMedia({ colorScheme: scheme });
        await page.goto(`/games/${games[0]!.game_id}`, { waitUntil: "networkidle" });
        await expect(page.locator("figure")).toHaveCount(2);
        await drawLazyCharts(page);
        const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
        expect(overflow).toBeLessThanOrEqual(0);
        const axe = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa", "best-practice"]).analyze();
        expect(axe.violations.map((v) => `${v.id} (${v.impact})`)).toEqual([]);
      });
    }
  }
});

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "@playwright/test";
import { pct } from "../src/lib/format";

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
      await expect(page.locator('[data-line="market"]')).toHaveText(pct(market(g.game_id), 1));
      await expect(page.locator('[data-line="model"]')).toHaveText(pct(sim(g.game_id), 1));
      await expect(page.locator(`article[data-game="${g.game_id}"]`)).toHaveAttribute("aria-label", fieldSummary(g));
    });
  }
});

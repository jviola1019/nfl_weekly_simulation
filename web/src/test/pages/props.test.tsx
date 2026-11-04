import { readFileSync } from "node:fs";
import { join } from "node:path";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

// the props protocol as registered: the page names it, its weeks and the module commit it tests
const REPO = join(import.meta.dirname, "..", "..", "..", "..");
const registered = JSON.parse(readFileSync(join(REPO, "backtest", "eval_windows", "nfl_props_v1.json"), "utf8")) as {
  protocol_id: string;
  weeks: number[];
  module: { code_commit: string };
};

describe("the props page", () => {
  // the first import of a page compiles its whole module graph; on a cold cache and a busy machine that takes longer than the 5 s default
  it("states the props work as the repo records it, not as it stood before the props fixes", async () => {
    const { default: PropsPage } = await import("../../app/props/page");
    const html = renderToStaticMarkup(<PropsPage />);
    expect(html).toContain(registered.protocol_id);
    expect(html).toContain(`weeks ${registered.weeks[0]}–${registered.weeks.at(-1)}`);
    expect(html).toContain(registered.module.code_commit.slice(0, 7));
    // the stale claims: column-wide labels (P1), stake disagreeing with the recommendation (P2, P3), anytime-TD
    // prices missing (P5), and checkpoint A5 as undecided (decided 2026-09-30)
    expect(html).not.toMatch(/column-wide|stake disagree|never reach the output|still an owner decision/);
    expect(html.match(/<h1/g)).toHaveLength(1);
    expect(html).not.toMatch(/\bnull\b|undefined|NaN/);
  }, 30_000);
});

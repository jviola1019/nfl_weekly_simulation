import { describe, expect, it } from "vitest";
import { backtestContext, noRunContext, runContext } from "./context";

describe("runContext", () => {
  const run = { season: 2024, week: 15, cycleId: "weekly-sim-2024-w15", dataAsofUtc: "2026-10-03 12:00:00+00" };

  it("states the week, the run and the data date, the last one as an instant", () => {
    expect(runContext(run)).toEqual([
      { label: "Week", value: "2024 season, week 15" },
      { label: "Run", value: "weekly-sim-2024-w15" },
      { label: "Data as of", value: "2026-10-03 12:00 UTC", iso: "2026-10-03 12:00:00+00" }
    ]);
  });

  it("can leave the week out for a page whose title already names it", () => {
    expect(runContext(run, { omitWeek: true }).map((i) => i.label)).toEqual(["Run", "Data as of"]);
  });

  it("does not invent a week for a run that has none", () => {
    expect(runContext({ ...run, week: null })[0]).toEqual({ label: "Week", value: "2024 season" });
    expect(runContext({ ...run, season: null, week: null })[0]).toEqual({ label: "Week", value: "not stated" });
  });
});

describe("noRunContext", () => {
  it("says there is no run and why the page has none", () => {
    expect(noRunContext("props are not priced yet")).toEqual([{ label: "Run", value: "none published (props are not priced yet)" }]);
  });
});

describe("backtestContext", () => {
  it("states the protocol, the run and the data date", () => {
    expect(backtestContext({ windowId: "nfl_games_v1", cycleId: "backtest-nfl-games-v1-7244a0bc", dataAsofUtc: "2026-09-29T20:51:29Z" })).toEqual([
      { label: "Protocol", value: "nfl_games_v1" },
      { label: "Run", value: "backtest-nfl-games-v1-7244a0bc" },
      { label: "Data as of", value: "2026-09-29 20:51 UTC", iso: "2026-09-29T20:51:29Z" }
    ]);
  });

  it("says when no protocol is recorded instead of printing nothing", () => {
    expect(backtestContext({ windowId: null, cycleId: "c", dataAsofUtc: "2026-09-29T20:51:29Z" })[0]).toEqual({ label: "Protocol", value: "not recorded" });
  });
});

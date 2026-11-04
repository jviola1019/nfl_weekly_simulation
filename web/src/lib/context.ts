import { utcStamp } from "./format";

/** One labelled fact in the line under a page title: which run, which week, how fresh the data is. */
export interface ContextItem {
  label: string;
  value: string;
  /** An instant: the value is then drawn inside a <time> element carrying this datetime. */
  iso?: string | null;
}

/** The fields of a published run that the context line needs. */
export interface RunLike {
  season: number | null;
  week: number | null;
  cycleId: string;
  dataAsofUtc: string;
}

/**
 * What a weekly run is and how old its data is; every page that shows run data states it.
 * `omitWeek` is for a page whose own title already names the week (a game's breadcrumb).
 */
export function runContext(run: RunLike, options: { omitWeek?: boolean } = {}): ContextItem[] {
  const season = run.season === null ? "" : `${run.season} season`;
  const week = run.week === null ? season : `${season}${season ? ", " : ""}week ${run.week}`;
  return [
    ...(options.omitWeek ? [] : [{ label: "Week", value: week || "not stated" }]),
    { label: "Run", value: run.cycleId },
    { label: "Data as of", value: utcStamp(run.dataAsofUtc), iso: run.dataAsofUtc }
  ];
}

/** For a page that has no run to show: say so, never leave the line out. */
export function noRunContext(what: string): ContextItem[] {
  return [{ label: "Run", value: `none published (${what})` }];
}

/** What a backtest is and how old its data is: the protocol it was scored under, the run and the data date. */
export function backtestContext(ev: { windowId: string | null; cycleId: string; dataAsofUtc: string }): ContextItem[] {
  return [
    { label: "Protocol", value: ev.windowId ?? "not recorded" },
    { label: "Run", value: ev.cycleId },
    { label: "Data as of", value: utcStamp(ev.dataAsofUtc), iso: ev.dataAsofUtc }
  ];
}

import { describe, expect, it } from "vitest";
import { sortSlate } from "./slateSort";

const row = (id: string, pMarket: number | null, gap: number) => ({ id, g: { pMarket }, gap });
const rows = [row("none", null, 0), row("near", 0.52, 0.01), row("far", 0.9, 0.2), row("tie", 0.5, 0), row("mid", 0.7, 0.05)];
const ids = (xs: { id: string }[]) => xs.map((x) => x.id);

describe("sortSlate", () => {
  it("closest puts a game without a market last, not first", () => {
    expect(ids(sortSlate(rows, "closest"))).toEqual(["tie", "near", "mid", "far", "none"]);
  });
  it("gap puts a game without a market last even against a zero gap", () => {
    expect(ids(sortSlate(rows, "gap"))).toEqual(["far", "mid", "near", "tie", "none"]);
  });
  it("kickoff keeps the order and does not mutate the input", () => {
    const copy = [...rows];
    expect(ids(sortSlate(rows, "kickoff"))).toEqual(ids(copy));
    expect(rows).toEqual(copy);
  });
});

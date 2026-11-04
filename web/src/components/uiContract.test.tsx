import { describe, expect, it } from "vitest";
import * as ui from "./ui";
import { StatTile } from "./ui";

/** What Track B2 closed: no number without its source line, and one page-title component. */
describe("the ui contract", () => {
  it("a headline number cannot be drawn without its source line (a type error, so `npm run typecheck` fails)", () => {
    // @ts-expect-error source is required: every number says where it comes from
    const tile = <StatTile value="1" label="games" />;
    expect(tile.props.source).toBeUndefined();
  });

  it("the previous PageTitle is gone: a page's title is a PageHeader", () => {
    expect("PageTitle" in ui).toBe(false);
    expect("PageHeader" in ui).toBe(true);
  });
});

import type { ReactElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { Breadcrumb, Card, DataTable, Grid, Page, PageHeader, Section, Stamp, StatTile, Term } from "./ui";

const html = (el: ReactElement) => renderToStaticMarkup(el);

describe("Stamp", () => {
  it("draws an instant in a <time> with a machine-readable datetime", () => {
    expect(html(<Stamp iso="2026-10-03 12:00:00+00" />)).toBe('<time dateTime="2026-10-03T12:00:00.000Z">2026-10-03 12:00 UTC</time>');
  });
  it("says so when there is no instant", () => {
    expect(html(<Stamp iso={null} />)).toBe("–");
  });
  it("keeps an empty value as a dash", () => {
    expect(html(<Stamp iso="" />)).toBe("–");
  });
  it("throws a named error for a value that is not an instant", () => {
    expect(() => html(<Stamp iso="garbage" />)).toThrow('Stamp: "garbage" is not an instant');
    expect(() => html(<Stamp iso="   " />)).toThrow('Stamp: "   " is not an instant');
  });
});

describe("PageHeader", () => {
  const context = [
    { label: "Run", value: "weekly-sim-2024-w15" },
    { label: "Data as of", value: "ignored when iso is set", iso: "2026-10-03T12:00:00Z" }
  ];

  it("is one h1 in wide Archivo with the lead and the context line (run, week, data date)", () => {
    const out = html(<PageHeader title="Evidence" lead="What the test found." context={context} />);
    expect(out.match(/<h1/g)).toHaveLength(1);
    expect(out).toContain('<h1 class="wdth-expanded text-title font-black">Evidence</h1>');
    expect(out).toContain("max-w-measure");
    expect(out).toContain("data-context");
    expect(out).toContain("<dt>Run</dt>");
    expect(out).toContain('<time dateTime="2026-10-03T12:00:00.000Z">2026-10-03 12:00 UTC</time>');
    expect(out).not.toContain("ignored when iso is set");
  });

  it("has a hero and a compact size, and an aside beside it", () => {
    expect(html(<PageHeader title="Week 4" size="hero" />)).toContain("text-hero font-black");
    expect(html(<PageHeader title="Sign in" size="compact" />)).toContain("text-title-sm font-black");
    expect(html(<PageHeader title="Week 4" aside={<p>status</p>} />)).toContain("lg:w-aside");
    expect(html(<PageHeader title="Desk" actions={<button>Sign out</button>} />)).toContain("<button>Sign out</button>");
  });
});

describe("Section", () => {
  it("is a landmark named by its visible title", () => {
    const out = html(
      <Section id="gates" title="Promotion gates">
        <p>body</p>
      </Section>
    );
    expect(out).toContain('aria-labelledby="gates"');
    expect(out).toContain('<h2 id="gates" data-section-title="true" class="wdth-expanded text-heading font-bold">Promotion gates</h2>');
    expect(out).toContain("gap-control");
  });

  it("is named by a label when it has no title, and keeps a screen-reader-only title", () => {
    const labelled = html(
      <Section label="Sort and filter">
        <p>body</p>
      </Section>
    );
    expect(labelled).toContain('aria-label="Sort and filter"');
    expect(labelled).not.toContain("<h2");
    const hidden = html(
      <Section id="rel" title="Reliability" srTitle>
        <p>body</p>
      </Section>
    );
    expect(hidden).toContain('<h2 id="rel" data-section-title="true" class="sr-only">Reliability</h2>');
  });

  it("puts an aside on the title's row", () => {
    const out = html(
      <Section id="prob" title="Win probability" aside={<ul>legend</ul>}>
        <p>body</p>
      </Section>
    );
    expect(out).toMatch(/<div class="flex flex-wrap items-end justify-between gap-control"><h2[^>]*>Win probability<\/h2><ul>legend<\/ul><\/div>/);
  });

  it("carries a label-named section's id on the section, and a titled section's id only on its heading", () => {
    const labelled = html(
      <Section id="filters" label="Sort and filter">
        <p>body</p>
      </Section>
    );
    expect(labelled).toMatch(/<section [^>]*id="filters"[^>]*aria-label="Sort and filter"/);
    const titled = html(
      <Section id="gates" title="Promotion gates">
        <p>body</p>
      </Section>
    );
    expect(titled.match(/id="gates"/g)).toHaveLength(1);
    expect(titled).not.toMatch(/<section [^>]*\sid=/);
  });
});

describe("Card, Grid and Page", () => {
  it("has one surface in three paddings and a sunken tone", () => {
    expect(html(<Card>x</Card>)).toBe('<div class="rounded-card border border-rule bg-surface p-card">x</div>');
    expect(html(<Card pad="sm" tone="sunken">x</Card>)).toBe('<div class="rounded-card border border-rule bg-sunken p-card-sm">x</div>');
    expect(html(<Card as="aside" aria-label="Model status">x</Card>)).toContain('<aside aria-label="Model status"');
  });

  it("fixes the grids and the page rhythm", () => {
    expect(html(<Grid kind="tiles">x</Grid>)).toContain("sm:grid-cols-3");
    expect(html(<Grid kind="fields">x</Grid>)).toContain("lg:grid-cols-2");
    expect(html(<Page>x</Page>)).toBe('<div data-page="true" class="flex flex-col gap-section">x</div>');
  });
});

describe("StatTile and Term", () => {
  it("prints the value, the label, the source line and a link to the term's definition", () => {
    const out = html(<StatTile value="0.2098" label={<>Market <Term id="brier">Brier score</Term></>} source="Backtest nfl_games_v1" />);
    expect(out).toContain("data-stat");
    expect(out).toContain("0.2098");
    expect(out).toContain('<span data-source="true" class="text-sm text-muted">Backtest nfl_games_v1</span>');
    expect(out).toContain('href="/methodology#term-brier"');
  });

  it("links a term to its definition and defaults the text to the term's label", () => {
    expect(html(<Term id="no-vig" />)).toContain('href="/methodology#term-no-vig">No-vig probability</a>');
    expect(html(<Term id="clv">CLV</Term>)).toContain(">CLV</a>");
  });
});

describe("DataTable", () => {
  const columns = [{ key: "candidate", header: "Candidate", rowHeader: true }, { key: "g1", header: "G1" }];
  const rows = [
    { key: "a", cells: { candidate: "Elo", g1: "Pass" } },
    { key: "b", cells: { candidate: "EPA", g1: "Fail" }, muted: true }
  ];

  it("has a caption, column scopes, a row header, a labelled scroll region and pass-through attributes", () => {
    const out = html(<DataTable caption="Promotion gates" columns={columns} rows={rows} data-desk="x" />);
    expect(out).toContain('<div tabindex="0" role="region" aria-label="Promotion gates (table)" class="overflow-x-auto">');
    expect(out).toContain('<caption class="sr-only">Promotion gates</caption>');
    expect(out.match(/<th scope="col"/g)).toHaveLength(2);
    expect(out).toContain('<tr class="border-t border-rule"><th scope="row">Elo</th><td>Pass</td></tr>');
    expect(out).toContain('<tr class="border-t border-rule text-ink-2"><th scope="row">EPA</th><td>Fail</td></tr>');
    expect(out).toContain('data-desk="x"');
    expect(out).toContain('class="data-table"');
  });

  it("can show its caption, scroll below a minimum width, and say so when it has no rows", () => {
    const out = html(<DataTable caption="Leans" showCaption columns={columns} rows={[]} empty={<span>No paper leans</span>} minWidth="table-wide" numeric topAligned dense />);
    expect(out).toContain('<caption class="data-table-caption">Leans</caption>');
    expect(out).toContain("min-w-tabular-wide");
    expect(out).toContain("data-table num data-table-dense data-table-top");
    expect(out).toContain('<td colSpan="2" class="text-ink-2"><span>No paper leans</span></td>');
  });

  it("keeps plain cells classless, as the chart table views have always been", () => {
    const out = html(<DataTable caption="Margin" columns={[{ key: "m", header: "Margin", rowHeader: true }, { key: "s", header: "Share" }]} rows={[{ key: "0", cells: { m: "Tie", s: "25.00%" } }]} />);
    expect(out).toContain("<td>25.00%</td>");
  });

  it("throws on a row that lacks a column's cell instead of drawing a hole", () => {
    expect(() => html(<DataTable caption="Gates" columns={columns} rows={[{ key: "x", cells: { candidate: "Elo" } }]} />)).toThrow(/row "x" has no cell for column "g1"/);
  });

  it("throws the same named error for a cell that is undefined or null", () => {
    const row = (g1: null | undefined) => <DataTable caption="Gates" columns={columns} rows={[{ key: "x", cells: { candidate: "Elo", g1 } }]} />;
    expect(() => html(row(undefined))).toThrow(/row "x" has no cell for column "g1"/);
    expect(() => html(row(null))).toThrow(/row "x" has no cell for column "g1"/);
  });

  it("does not take an inherited key such as constructor for a cell", () => {
    const named = [{ key: "candidate", header: "Candidate", rowHeader: true }, { key: "constructor", header: "Constructor" }];
    expect(() => html(<DataTable caption="Gates" columns={named} rows={[{ key: "x", cells: { candidate: "Elo" } }]} />)).toThrow(/row "x" has no cell for column "constructor"/);
  });
});

describe("Breadcrumb", () => {
  it("links the earlier crumbs and marks the last as the current page", () => {
    const out = html(<Breadcrumb items={[{ label: "This week", href: "/" }, { label: "DEN at SF" }]} />);
    expect(out).toContain('<nav aria-label="Breadcrumb"');
    expect(out).toContain('<a class="text-ink-2" href="/">This week</a>');
    expect(out).toContain('aria-current="page"');
    expect(out.match(/aria-hidden="true">\//g)).toHaveLength(1);
  });
});

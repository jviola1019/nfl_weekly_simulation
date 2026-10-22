/**
 * Broadcast Line layout primitives. Every page is built from these, so type, spacing and radius
 * come from the tokens in globals.css (type roles, spacing roles, radius, measure) and a page
 * never picks a size of its own: a page is a <Page> of <Section>s under one <PageHeader>, cards
 * are <Card>, tables are <DataTable>, a headline number is a <StatTile>. Colour comes only from
 * the colour tokens, so the press-box (light) and night-game (dark) themes apply everywhere.
 */
import Link from "next/link";
import type { ComponentPropsWithoutRef, ReactNode } from "react";
import type { ContextItem } from "@/lib/context";
import { utcStamp } from "@/lib/format";
import { TERMS, type TermId, termHref } from "@/lib/glossary";

/**
 * An instant as text, inside a <time> so its machine-readable value travels with it. A value that is
 * not an instant throws, by name (an empty value is a dash, as before).
 */
export function Stamp({ iso }: { iso: string | null | undefined }) {
  if (!iso) return <>–</>;
  const at = new Date(iso);
  if (Number.isNaN(at.getTime())) throw new Error(`Stamp: "${iso}" is not an instant`);
  const canonical = at.toISOString();
  return <time dateTime={canonical}>{utcStamp(canonical)}</time>;
}

/** A term, linked to its definition on /methodology. */
export function Term({ id, children }: { id: TermId; children?: ReactNode }) {
  return (
    <Link href={termHref(id)} className="decoration-dotted">
      {children ?? TERMS[id].label}
    </Link>
  );
}

/** The line under a page title: which run, which week and how fresh its data is. */
export function ContextList({ items }: { items: ContextItem[] }) {
  return (
    <dl data-context className="flex flex-wrap gap-x-stack gap-y-tight text-sm text-muted">
      {items.map((item) => (
        <div key={item.label} className="flex gap-snug">
          <dt>{item.label}</dt>
          <dd className="num text-ink-2">{item.iso ? <Stamp iso={item.iso} /> : item.value}</dd>
        </div>
      ))}
    </dl>
  );
}

/** The sections of a page, one section gap apart. Every page returns one. */
export function Page({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div data-page className={`flex flex-col gap-section ${className}`.trim()}>
      {children}
    </div>
  );
}

const H1 = {
  hero: "text-hero font-black",
  page: "text-title font-black",
  compact: "text-title-sm font-black"
} as const;

/**
 * A page's title block: the h1 in wide Archivo, an optional lead, and the context line (run,
 * week and data date). `aside` is a card beside it on a wide screen (the home page's model
 * status); `actions` are small controls at its end (the desk's sign-out).
 */
export function PageHeader({
  title,
  lead,
  context,
  aside,
  actions,
  size = "page"
}: {
  title: ReactNode;
  lead?: ReactNode;
  context?: ContextItem[];
  aside?: ReactNode;
  actions?: ReactNode;
  size?: keyof typeof H1;
}) {
  return (
    <header data-page-header className="flex flex-col gap-section lg:flex-row lg:items-end lg:justify-between">
      <div className="flex min-w-0 flex-col gap-control">
        <h1 className={`wdth-expanded ${H1[size]}`}>{title}</h1>
        {lead ? <div className="max-w-measure text-lg text-ink-2 text-pretty">{lead}</div> : null}
        {context ? <ContextList items={context} /> : null}
      </div>
      {aside ? <div className="w-full lg:w-aside lg:shrink-0">{aside}</div> : null}
      {actions ? <div className="flex flex-wrap items-center gap-control lg:shrink-0">{actions}</div> : null}
    </header>
  );
}

/** A section's heading (h2) in wide Archivo; `srOnly` keeps it for assistive technology only. */
export function SectionTitle({ id, children, srOnly = false }: { id: string; children: ReactNode; srOnly?: boolean }) {
  return (
    <h2 id={id} data-section-title className={srOnly ? "sr-only" : "wdth-expanded text-heading font-bold"}>
      {children}
    </h2>
  );
}

type SectionProps = { children: ReactNode; className?: string; measure?: boolean } & (
  | { id: string; title: ReactNode; srTitle?: boolean; aside?: ReactNode; label?: never }
  | { label: string; id?: string; title?: never; srTitle?: never; aside?: never }
);

/**
 * One section of a page: a landmark named by its title (or by a label when it has none), the title
 * a control gap above its content. `aside` sits on the title's row (a legend, a count).
 */
export function Section(props: SectionProps) {
  const { children, className = "", measure = false } = props;
  const title =
    props.label === undefined ? (
      <SectionTitle id={props.id} srOnly={props.srTitle}>
        {props.title}
      </SectionTitle>
    ) : null;
  return (
    <section
      data-section
      id={title ? undefined : props.id}
      aria-labelledby={title ? props.id : undefined}
      aria-label={title ? undefined : props.label}
      className={`flex flex-col gap-control ${measure ? "max-w-measure" : ""} ${className}`.trim()}
    >
      {title && props.aside ? (
        <div className="flex flex-wrap items-end justify-between gap-control">
          {title}
          {props.aside}
        </div>
      ) : (
        title
      )}
      {children}
    </section>
  );
}

const GRID = {
  tiles: "grid gap-stack sm:grid-cols-3",
  pair: "grid gap-stack md:grid-cols-2",
  fields: "grid gap-stack lg:grid-cols-2",
  sections: "grid gap-section lg:grid-cols-2"
} as const;

/** A grid of cards or sections: the column counts and gap are fixed here, not chosen per page. */
export function Grid({ kind, children }: { kind: keyof typeof GRID; children: ReactNode }) {
  return <div className={GRID[kind]}>{children}</div>;
}

const PAD = { card: "p-card", sm: "p-card-sm", none: "" } as const;

/** The one bordered surface: a card (20px padding), a dense card (16px), or a sunken empty state. */
export function Card({
  as: Tag = "div",
  tone = "surface",
  pad = "card",
  className = "",
  ...rest
}: ComponentPropsWithoutRef<"div"> & { as?: "div" | "article" | "aside" | "section"; tone?: "surface" | "sunken"; pad?: keyof typeof PAD }) {
  return <Tag {...rest} className={`rounded-card border border-rule ${tone === "sunken" ? "bg-sunken" : "bg-surface"} ${PAD[pad]} ${className}`.trim()} />;
}

/**
 * A headline number with what it counts (the label, unit included) and where it comes from (the
 * source line). A term the label uses is linked to its definition on /methodology with <Term>.
 */
export function StatTile({ value, label, source }: { value: ReactNode; label: ReactNode; source?: ReactNode }) {
  return (
    <Card data-stat className="flex flex-col gap-tight">
      <span className="num wdth-expanded text-stat font-extrabold">{value}</span>
      <span className="text-sm text-ink-2">{label}</span>
      {source ? (
        <span data-source className="text-sm text-muted">
          {source}
        </span>
      ) : null}
    </Card>
  );
}

export interface DataColumn {
  /** Names the column: a row gives its cell under this key (an object, so no array of elements needs keys). */
  key: string;
  header: ReactNode;
  /** The first column only: its cells become row headers (<th scope="row">). */
  rowHeader?: boolean;
  nowrap?: boolean;
}

export interface DataRow {
  key: string;
  /** One cell per column, under the column's key. A missing or null cell is a mistake and throws, never an empty cell. */
  cells: Record<string, ReactNode>;
  /** A summary or remainder row drawn in secondary ink. */
  muted?: boolean;
}

/**
 * Every table. It carries a caption (hidden unless `showCaption`), column headers with scope, an
 * optional row-header column, and sits in a keyboard-scrollable region named "<caption> (table)", so
 * it never shares a landmark name with the section around it. Padding comes
 * from the row and cell tokens (`.data-table` in globals.css); dense is for long chart tables.
 */
export function DataTable({
  caption,
  showCaption = false,
  columns,
  rows,
  empty,
  minWidth,
  dense = false,
  numeric = false,
  topAligned = false,
  ...tableProps
}: {
  caption: string;
  showCaption?: boolean;
  columns: DataColumn[];
  rows: DataRow[];
  empty?: ReactNode;
  minWidth?: "table" | "table-wide";
  dense?: boolean;
  numeric?: boolean;
  topAligned?: boolean;
} & Omit<ComponentPropsWithoutRef<"table">, "children" | "className">) {
  const cls = ["data-table", numeric ? "num" : "", dense ? "data-table-dense" : "", topAligned ? "data-table-top" : "", minWidth === "table" ? "min-w-tabular" : "", minWidth === "table-wide" ? "min-w-tabular-wide" : ""]
    .filter(Boolean)
    .join(" ");
  return (
    <div tabIndex={0} role="region" aria-label={`${caption} (table)`} className="overflow-x-auto">
      <table {...tableProps} className={cls}>
        <caption className={showCaption ? "data-table-caption" : "sr-only"}>{caption}</caption>
        <thead>
          <tr>
            {columns.map((c) => (
              <th key={c.key} scope="col" className={c.nowrap ? "whitespace-nowrap" : undefined}>
                {c.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.length === 0 && empty ? (
            <tr className="border-t border-rule">
              <td colSpan={columns.length} className="text-ink-2">
                {empty}
              </td>
            </tr>
          ) : null}
          {rows.map((r) => (
            <tr key={r.key} className={r.muted ? "border-t border-rule text-ink-2" : "border-t border-rule"}>
              {columns.map((c, i) => {
                const cell = Object.hasOwn(r.cells, c.key) ? r.cells[c.key] : undefined;
                if (cell === undefined || cell === null) throw new Error(`DataTable "${caption}": row "${r.key}" has no cell for column "${c.key}"`);
                return i === 0 && c.rowHeader ? (
                  <th key={c.key} scope="row" className={c.nowrap ? "whitespace-nowrap" : undefined}>
                    {cell}
                  </th>
                ) : (
                  <td key={c.key} className={c.nowrap ? "whitespace-nowrap" : undefined}>
                    {cell}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** Where this page sits: the last crumb is the current page. */
export function Breadcrumb({ items }: { items: { label: ReactNode; href?: string }[] }) {
  return (
    <nav aria-label="Breadcrumb" className="text-sm text-muted">
      <ol className="flex flex-wrap items-center gap-x-snug">
        {items.map((item, i) => {
          const last = i === items.length - 1;
          return (
            <li key={i} className="flex items-center gap-snug">
              {item.href && !last ? (
                <Link href={item.href} className="text-ink-2">
                  {item.label}
                </Link>
              ) : (
                <span aria-current={last ? "page" : undefined} className={last ? "text-ink" : undefined}>
                  {item.label}
                </span>
              )}
              {last ? null : <span aria-hidden>/</span>}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}

/** A 44px segment chip (sort, day, window and candidate pickers, the theme choice); `on` is the current choice. */
export function chipClass(on: boolean): string {
  return `inline-flex h-11 items-center rounded-control border px-control text-sm no-underline ${on ? "border-ink bg-ink font-semibold text-surface" : "border-rule text-ink-2 hover:border-ink-2"}`;
}

/** The ink button: the header's Desk link, the sign-in button. */
export const BUTTON_CLASS = "inline-flex h-11 items-center rounded-control border border-ink bg-ink px-4 text-sm font-semibold text-surface no-underline";

/** A quiet bordered button (secondary actions). */
export const QUIET_BUTTON_CLASS = "inline-flex h-11 items-center rounded-control border border-rule px-4 text-sm text-ink";

export const INPUT_CLASS = "mt-tight block h-11 w-full rounded-control border border-rule bg-surface px-4 text-ink";

/** @deprecated The previous page title; pages move to PageHeader and this goes in the last task of Track B2. */
export function PageTitle({ children, lead, compact = false }: { children: ReactNode; lead?: ReactNode; compact?: boolean }) {
  return <PageHeader title={children} lead={lead} size={compact ? "compact" : "page"} />;
}

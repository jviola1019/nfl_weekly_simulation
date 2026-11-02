/**
 * Every chart is a <figure> with a computed text summary, a table view (the WCAG
 * equivalent; tooltips enhance, never gate) and the plot. Dataviz rules: one axis,
 * thin marks, a legend when there are two or more series, text in ink tokens.
 * The table is a DataTable (components/ui.tsx), which brings its own labelled scroll region.
 */
export function ChartFigure({
  title,
  summary,
  legend,
  table,
  children
}: {
  title: string;
  summary: string;
  legend?: React.ReactNode;
  table: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <figure className="flex flex-col gap-control">
      <figcaption className="flex flex-col gap-tight">
        <p className="font-medium">{title}</p>
        <p className="max-w-measure text-sm text-ink-2">{summary}</p>
      </figcaption>
      {legend ? <div>{legend}</div> : null}
      <div>{children}</div>
      <details className="text-sm">
        <summary className="cursor-pointer text-ink-2">Table view</summary>
        <div className="mt-snug">{table}</div>
      </details>
    </figure>
  );
}

export function LineKey({ color, label, marker = false }: { color: string; label: string; marker?: boolean }) {
  return (
    <span className="inline-flex items-center gap-snug text-sm text-ink-2">
      {marker ? (
        <span className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: color }} aria-hidden />
      ) : (
        <span className="inline-block h-0.5 w-4" style={{ background: color }} aria-hidden />
      )}
      {label}
    </span>
  );
}

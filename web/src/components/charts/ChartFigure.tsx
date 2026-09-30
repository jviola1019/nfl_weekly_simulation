/**
 * Every chart is a <figure> with a computed text summary, a table view (the WCAG
 * equivalent; tooltips enhance, never gate) and the plot. Dataviz rules: one axis,
 * thin marks, a legend when there are two or more series, text in ink tokens.
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
    <figure className="mt-4">
      <figcaption>
        <p className="font-medium">{title}</p>
        <p className="mt-1 max-w-3xl text-sm text-ink-2">{summary}</p>
      </figcaption>
      {legend ? <div className="mt-3">{legend}</div> : null}
      <div className="mt-3">{children}</div>
      <details className="mt-2 text-sm">
        <summary className="cursor-pointer text-ink-2">Table view</summary>
        <div tabIndex={0} role="region" aria-label="Scrollable table" className="mt-2 overflow-x-auto">{table}</div>
      </details>
    </figure>
  );
}

export function LineKey({ color, label, marker = false }: { color: string; label: string; marker?: boolean }) {
  return (
    <span className="inline-flex items-center gap-2 text-sm text-ink-2">
      {marker ? (
        <span className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: color }} aria-hidden />
      ) : (
        <span className="inline-block h-[2px] w-4" style={{ background: color }} aria-hidden />
      )}
      {label}
    </span>
  );
}

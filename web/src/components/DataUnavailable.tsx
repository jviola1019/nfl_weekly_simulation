/** An honest empty state: what is missing, why, and what would fill it. */
export function DataUnavailable({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-[3px] border border-rule bg-sunken px-4 py-4">
      <p className="font-medium">{title}</p>
      <div className="mt-1 text-sm text-ink-2">{children}</div>
    </div>
  );
}

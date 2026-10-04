/**
 * Broadcast Line layout primitives (A8), taken from the redesigned home and game pages
 * (#207, from the approved mockup) so every page shares one design language: wide Archivo
 * titles, one-border cards on the surface token, 44px segment chips, stat tiles. Colour
 * comes only from the tokens in globals.css, so the press-box (light) and night-game
 * (dark) themes apply everywhere.
 */
export function PageTitle({ children, lead, compact = false }: { children: React.ReactNode; lead?: React.ReactNode; compact?: boolean }) {
  return (
    <header className="flex flex-col gap-3 pt-4">
      <h1 className={`wdth-expanded font-black leading-[0.95] tracking-[-0.01em] ${compact ? "text-[32px] sm:text-[40px]" : "text-[40px] sm:text-[56px]"}`}>
        {children}
      </h1>
      {lead ? <div className="max-w-[760px] text-[17px] leading-relaxed text-ink-2 [text-wrap:pretty]">{lead}</div> : null}
    </header>
  );
}

/** A page section's heading (the game page's "Win probability" style). */
export function SectionTitle({ id, children }: { id: string; children: React.ReactNode }) {
  return (
    <h2 id={id} className="wdth-expanded text-[22px] font-bold">
      {children}
    </h2>
  );
}

export function Card({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return <div className={`rounded-[6px] border border-rule bg-surface px-5 py-5 ${className}`}>{children}</div>;
}

/** A headline number with its caption (the home page's "This week in numbers"). */
export function StatTile({ value, label }: { value: React.ReactNode; label: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1.5 rounded-[6px] border border-rule bg-surface px-5 py-4">
      <span className="num wdth-expanded text-[40px] font-extrabold leading-none">{value}</span>
      <span className="text-sm text-muted">{label}</span>
    </div>
  );
}

/** A 44px segment chip (sort, day, window and candidate pickers); `on` is the current choice. */
export function chipClass(on: boolean): string {
  return `inline-flex h-11 items-center rounded-[3px] border px-3.5 text-[13px] no-underline ${on ? "border-ink bg-ink font-semibold text-surface" : "border-rule text-ink-2 hover:border-ink-2"}`;
}

/** The ink button of the header's Desk link. */
export const BUTTON_CLASS = "inline-flex h-11 items-center rounded-[3px] border border-ink bg-ink px-4 text-sm font-semibold text-surface no-underline";

/** A quiet bordered button (secondary actions). */
export const QUIET_BUTTON_CLASS = "inline-flex h-11 items-center rounded-[3px] border border-rule px-4 text-sm text-ink";

export const INPUT_CLASS = "mt-1 block h-11 w-full rounded-[3px] border border-rule bg-surface px-3 text-ink";

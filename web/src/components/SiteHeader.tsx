import Link from "next/link";
import { NavLinks } from "./NavLinks";
import { ThemeToggle } from "./ThemeToggle";

/** Broadcast Line wordmark: the scrimmage (market) and first-down (model) lines. */
function Wordmark() {
  return (
    <Link href="/" className="flex items-center gap-3 no-underline">
      <span className="flex h-[22px] gap-[3px]" aria-hidden>
        <span className="w-1 rounded-[1px]" style={{ background: "var(--field-market)" }} />
        <span className="w-1 rounded-[1px]" style={{ background: "var(--field-model)" }} />
      </span>
      <span className="wdth-expanded text-lg font-bold tracking-[0.01em]">Broadcast Line</span>
    </Link>
  );
}

export function SiteHeader() {
  return (
    <header className="border-b border-rule bg-surface">
      <div className="mx-auto flex max-w-[1440px] flex-wrap items-center gap-x-10 gap-y-1 px-4 sm:px-8 xl:px-16">
        <div className="flex h-16 items-center">
          <Wordmark />
        </div>
        <NavLinks />
        <div className="ml-auto flex h-16 items-center gap-3">
          <ThemeToggle />
          <Link
            href="/desk"
            className="inline-flex h-11 items-center rounded-[3px] border border-ink bg-ink px-4 text-sm font-semibold text-surface no-underline"
          >
            Desk
          </Link>
        </div>
      </div>
    </header>
  );
}

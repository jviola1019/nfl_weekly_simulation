import Link from "next/link";
import { BUTTON_CLASS } from "@/components/ui";
import { NavLinks } from "./NavLinks";

/** Broadcast Line wordmark: the scrimmage (market) and first-down (model) lines. */
function Wordmark() {
  return (
    <Link href="/" className="flex items-center gap-control no-underline">
      <span className="flex h-5.5 gap-0.75" aria-hidden>
        <span className="w-1 rounded-tick" style={{ background: "var(--field-market)" }} />
        <span className="w-1 rounded-tick" style={{ background: "var(--field-model)" }} />
      </span>
      <span className="wdth-expanded text-lg font-bold">Broadcast Line</span>
    </Link>
  );
}

/**
 * Two rows below lg (the wordmark and the Desk button, then the navigation), one row from lg up.
 * The theme choice lives in the footer, so nothing here is wider than a phone.
 */
export function SiteHeader() {
  return (
    <header className="border-b border-rule bg-surface print:hidden">
      <div className="mx-auto flex max-w-page flex-wrap items-center justify-between gap-x-section px-gutter lg:flex-nowrap lg:justify-start">
        <div className="flex h-16 items-center">
          <Wordmark />
        </div>
        <NavLinks />
        <div className="flex h-16 items-center lg:ml-auto">
          <Link href="/desk" className={BUTTON_CLASS}>
            Desk
          </Link>
        </div>
      </div>
    </header>
  );
}

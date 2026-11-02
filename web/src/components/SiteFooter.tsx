import { ThemeToggle } from "@/components/ThemeToggle";
import type { Theme } from "@/lib/theme";

/** The responsible-gambling notice on every page, and the theme choice. */
export function SiteFooter({ theme }: { theme: Theme }) {
  return (
    <footer className="border-t border-rule bg-surface">
      <div className="mx-auto flex max-w-page flex-col gap-stack px-gutter py-stack text-sm text-ink-2">
        <div className="flex max-w-measure flex-col gap-snug">
          <p>
            Research output from an unvalidated model. Nothing here is betting advice. If gambling stops being fun, call or
            text 1-800-GAMBLER (US) for free, confidential help.
          </p>
          <p className="text-muted">
            Probabilities are for adults in jurisdictions where sports betting is legal. Stakes are never shown on public
            pages.
          </p>
        </div>
        <ThemeToggle theme={theme} />
      </div>
    </footer>
  );
}

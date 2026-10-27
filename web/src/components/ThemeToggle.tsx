import { chipClass } from "@/components/ui";
import { THEME_ANCHOR, THEMES, type Theme } from "@/lib/theme";

/**
 * System, light or night game. Three 44px chips in a plain form that posts to /theme: the server
 * stores the choice in a cookie and renders it, so nothing flashes and no script is involved, and a
 * tap while the page is still loading is not lost (a form post does not wait for hydration).
 */
export function ThemeToggle({ theme }: { theme: Theme }) {
  return (
    <form id={THEME_ANCHOR} method="post" action="/theme" className="flex flex-wrap items-center gap-snug print:hidden">
      <span id="theme-label" className="text-sm text-ink-2">
        Theme
      </span>
      <div role="group" aria-labelledby="theme-label" className="flex flex-wrap gap-snug">
        {THEMES.map((t) => (
          <button key={t.value} type="submit" name="theme" value={t.value} aria-pressed={t.value === theme} className={chipClass(t.value === theme)}>
            {t.label}
          </button>
        ))}
      </div>
    </form>
  );
}

import Link from "next/link";
import { ThemeToggle } from "./ThemeToggle";

const NAV = [
  { href: "/", label: "This week" },
  { href: "/props", label: "Props" },
  { href: "/evidence", label: "Evidence" },
  { href: "/methodology", label: "Methodology" },
  { href: "/data-health", label: "Data health" },
  { href: "/desk", label: "Desk" }
];

export function SiteHeader() {
  return (
    <header className="border-b border-rule">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-x-6 gap-y-2 px-4 py-3">
        <Link href="/" className="wdth-expanded text-lg font-semibold tracking-tight no-underline">
          Broadcast Line
        </Link>
        <nav aria-label="Main" className="order-3 w-full sm:order-none sm:w-auto">
          <ul className="flex flex-wrap gap-x-4 text-sm text-ink-2">
            {NAV.map((n) => (
              <li key={n.href}>
                <Link href={n.href} className="inline-block whitespace-nowrap py-2 no-underline hover:underline">
                  {n.label}
                </Link>
              </li>
            ))}
          </ul>
        </nav>
        <div className="ml-auto">
          <ThemeToggle />
        </div>
      </div>
    </header>
  );
}

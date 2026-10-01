"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const NAV = [
  { href: "/", label: "This week" },
  { href: "/props", label: "Props" },
  { href: "/evidence", label: "Evidence" },
  { href: "/methodology", label: "Methodology" },
  { href: "/data-health", label: "Data health" }
];

/** Main navigation; the current section is underlined in ink and marked aria-current. */
export function NavLinks() {
  const path = usePathname() ?? "/";
  const isCurrent = (href: string) => (href === "/" ? path === "/" || path.startsWith("/games") : path.startsWith(href));
  return (
    <nav aria-label="Main" className="order-3 w-full lg:order-none lg:w-auto">
      <ul className="flex flex-wrap gap-x-6 text-sm">
        {NAV.map((n) => {
          const on = isCurrent(n.href);
          return (
            <li key={n.href}>
              <Link
                href={n.href}
                aria-current={on ? "page" : undefined}
                className={`inline-block whitespace-nowrap border-b-2 py-3 no-underline lg:py-[21px] ${on ? "border-ink font-semibold text-ink" : "border-transparent text-ink-2 hover:text-ink"}`}
              >
                {n.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

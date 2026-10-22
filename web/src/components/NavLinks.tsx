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

/**
 * Main navigation; the current section is underlined in ink and marked aria-current. It is
 * one line at every width: on a phone the five labels are spread across the row with a
 * 10px minimum gap (all five fit at 390px), and a narrower phone scrolls the row.
 */
export function NavLinks() {
  const path = usePathname() ?? "/";
  const isCurrent = (href: string) => (href === "/" ? path === "/" || path.startsWith("/games") : path.startsWith(href));
  return (
    <nav aria-label="Main" className="order-last w-full lg:order-none lg:w-auto">
      <ul className="-m-1 flex flex-nowrap justify-between gap-x-2.5 overflow-x-auto p-1 text-sm sm:justify-start sm:gap-x-stack lg:overflow-visible">
        {NAV.map((n) => {
          const on = isCurrent(n.href);
          return (
            <li key={n.href}>
              <Link
                href={n.href}
                aria-current={on ? "page" : undefined}
                className={`inline-flex h-11 items-center whitespace-nowrap border-b-2 no-underline lg:h-16 ${on ? "border-ink font-semibold text-ink" : "border-transparent text-ink-2 hover:text-ink"}`}
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

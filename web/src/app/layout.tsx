import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
import "./globals.css";

// Archivo variable (weight 100–900, width 62–125%): condensed for dense tables, expanded
// for team codes and scores (spec §4). The latin file is committed with its OFL licence
// (./fonts), so a build needs no network (A8: the app runs offline from the terminal).
const archivo = localFont({
  src: "./fonts/archivo-latin.woff2",
  weight: "100 900",
  style: "normal",
  display: "swap",
  variable: "--font-archivo",
  declarations: [{ prop: "font-stretch", value: "62% 125%" }]
});

export const metadata: Metadata = {
  title: { default: "Broadcast Line", template: "%s · Broadcast Line" },
  description: "NFL game probabilities: the no-vig market, model candidates and the pre-registered evidence behind them."
};

export const viewport: Viewport = { width: "device-width", initialScale: 1 };

// Every page carries a per-request CSP nonce (src/proxy.ts), and a statically
// prerendered page cannot: its scripts would be blocked. So nothing is static.
export const dynamic = "force-dynamic";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={archivo.variable}>
      <body>
        <a href="#main" className="skip-link">
          Skip to content
        </a>
        <SiteHeader />
        <main id="main" className="mx-auto max-w-[1440px] px-4 pb-10 pt-8 sm:px-8 xl:px-16">
          {children}
        </main>
        <SiteFooter />
      </body>
    </html>
  );
}

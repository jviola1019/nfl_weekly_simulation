import type { Metadata, Viewport } from "next";
import { Archivo } from "next/font/google";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
import "./globals.css";

// Archivo variable with the width axis: condensed for dense tables, expanded for
// team codes and scores (spec §4). Self-hosted by next/font at build time.
const archivo = Archivo({ subsets: ["latin"], axes: ["wdth"], variable: "--font-archivo", display: "swap" });

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
        <main id="main" className="mx-auto max-w-6xl px-4 pt-8">
          {children}
        </main>
        <SiteFooter />
      </body>
    </html>
  );
}

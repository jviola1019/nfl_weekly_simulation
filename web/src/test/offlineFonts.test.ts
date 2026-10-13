/**
 * Offline build (A8): the app must build and render with no network. The only build-time
 * download was next/font/google; Archivo is now committed and loaded with next/font/local.
 */
import { createHash } from "node:crypto";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { extname, join } from "node:path";
import { describe, expect, it } from "vitest";
import { buildCsp } from "../lib/security/csp";

const SRC = join(import.meta.dirname, "..");
const FONTS = join(SRC, "app", "fonts");
// fonts.gstatic.com/s/archivo/v25/k3kQo8UDI-1M0wlSfdnoLg.woff2 (latin; wght 100-900, wdth 62-125), fetched 2026-10-01
const ARCHIVO_SHA256 = "e3a28eade21a900c7155a247757f4b2834c07bb7ef07ad7efa55cebaac1e8f5e";

function files(dir: string): string[] {
  return readdirSync(dir).flatMap((n) => (statSync(join(dir, n)).isDirectory() ? files(join(dir, n)) : [join(dir, n)]));
}

describe("offline fonts", () => {
  it("the layout loads Archivo with next/font/local and nothing imports next/font/google", () => {
    const layout = readFileSync(join(SRC, "app", "layout.tsx"), "utf8");
    expect(layout).toContain('import localFont from "next/font/local"');
    expect(layout).toContain('src: "./fonts/archivo-latin.woff2"');
    const sources = files(SRC).filter((f) => [".ts", ".tsx"].includes(extname(f)) && !/\.test\.tsx?$/.test(f));
    expect(sources.filter((f) => readFileSync(f, "utf8").includes("next/font/google"))).toEqual([]);
  });

  it("the committed font is the pinned Archivo variable woff2", () => {
    const font = readFileSync(join(FONTS, "archivo-latin.woff2"));
    expect(font.subarray(0, 4).toString("latin1")).toBe("wOF2");
    expect(createHash("sha256").update(font).digest("hex")).toBe(ARCHIVO_SHA256);
  });

  it("the font ships with its SIL Open Font License", () => {
    const ofl = readFileSync(join(FONTS, "OFL.txt"), "utf8");
    expect(ofl).toContain("The Archivo Project Authors");
    expect(ofl).toContain("SIL Open Font License, Version 1.1");
  });

  it("the CSP still allows fonts from this origin only", () => {
    const fontSrc = buildCsp({ nonce: "n" }).split("; ").find((d) => d.startsWith("font-src "));
    expect(fontSrc).toBe("font-src 'self'");
  });
});

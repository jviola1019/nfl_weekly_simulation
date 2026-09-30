/**
 * Slop scan for the Broadcast Line design system (spec §4, audit U10). The rules
 * are written for this system rather than copied: the look the audit rejected was
 * gradients, glow, all-caps eyebrow labels, mono micro-labels, a coral-on-black
 * palette with Inter, stacked shadows, big radii and hype copy. Colour lives only in
 * the tokens of globals.css; components use the token utilities or var(--token).
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { extname, join, relative } from "node:path";
import { describe, expect, it } from "vitest";

const SRC = join(import.meta.dirname, "..");
const TOKENS_FILE = join(SRC, "app", "globals.css");

function files(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) return files(p);
    return [".ts", ".tsx", ".css", ".mjs"].includes(extname(p)) && !/\.test\.tsx?$/.test(p) ? [p] : [];
  });
}
const SOURCES = files(SRC).filter((p) => !p.includes(`${join("src", "test")}`));

interface Rule { id: string; pattern: RegExp; why: string; allow?: (file: string) => boolean }
const RULES: Rule[] = [
  { id: "gradient", pattern: /gradient/i, why: "no gradients (spec §4)" },
  { id: "glow-blur", pattern: /\b(blur|backdrop-blur|drop-shadow|glow)\b|shadow-\[0_0/i, why: "no glow or blur (spec §4)" },
  { id: "elevation", pattern: /\bshadow-(sm|md|lg|xl|2xl)\b/, why: "one border level, no elevation stacks" },
  { id: "all-caps", pattern: /\buppercase\b|text-transform:\s*uppercase/, why: "no all-caps labels; sentence case" },
  { id: "eyebrow", pattern: /\btracking-(wider|widest)\b|\bfont-mono\b/, why: "no eyebrow or mono micro-labels" },
  { id: "radius", pattern: /\brounded-(lg|xl|2xl|3xl)\b/, why: "3px radius; no pill cards" },
  { id: "inter", pattern: /\b(Inter|Roboto|Poppins)\b/, why: "Archivo only (the Inter look is audit U10)" },
  { id: "coral", pattern: /#(d97757|cc785c|da7756|e07a5f)\b/i, why: "no Claude-coral accent (audit U10)" },
  { id: "tailwind-palette", pattern: /\b(text|bg|border|fill|stroke|ring|from|to)-(slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-\d{2,3}\b/, why: "colour comes from the design tokens" },
  { id: "raw-hex", pattern: /#[0-9a-f]{6}\b|#[0-9a-f]{3}\b(?![0-9a-z-])/i, why: "hex colours live only in globals.css tokens", allow: (f) => f === TOKENS_FILE },
  { id: "particles", pattern: /from\s+["'](three|tsparticles|@tsparticles\/[\w-]+|canvas-confetti)["']|particles\.js/, why: "no particles or WebGL (audit U5)" },
  { id: "hype", pattern: /\b(lock of the (week|day)|guaranteed|can'?t lose|sure thing|unlock|supercharge|revolutionary|cutting-edge|game-?changer|AI-powered|seamless)\b/i, why: "no hype copy; this is an unvalidated research model" },
  { id: "emoji", pattern: /\p{Extended_Pictographic}/u, why: "no emoji in UI copy; status uses an icon and a label" }
];

const BAD_SAMPLES: Record<string, string> = {
  gradient: 'className="bg-gradient-to-r"',
  "glow-blur": 'className="backdrop-blur"',
  elevation: 'className="shadow-lg"',
  "all-caps": 'className="uppercase text-xs"',
  eyebrow: 'className="tracking-widest"',
  radius: 'className="rounded-2xl"',
  inter: 'import { Inter } from "next/font/google"',
  coral: "color: #d97757;",
  "tailwind-palette": 'className="text-gray-500"',
  "raw-hex": 'fill="#ff0000"',
  particles: 'import * as THREE from "three"',
  hype: "Our lock of the week",
  emoji: "Hot pick 🔥"
};

describe("slop scan", () => {
  it("every rule catches its own bad sample (the scan is not vacuous)", () => {
    for (const r of RULES) expect(r.pattern.test(BAD_SAMPLES[r.id] ?? ""), r.id).toBe(true);
    for (const ok of ['className="rounded-[3px] border border-rule text-ink-2"', 'style={{ background: "var(--market)" }}', "Market favours Buffalo Bills", "the side where the model beats the opener by three points"]) {
      for (const r of RULES) expect(r.pattern.test(ok), `${r.id} on ${ok}`).toBe(false);
    }
  });

  it("scans the app sources", () => {
    expect(SOURCES.length).toBeGreaterThan(20);
    expect(SOURCES).toContain(TOKENS_FILE);
  });

  it.each(RULES.map((r) => [r.id, r] as const))("%s", (_id, rule) => {
    const hits: string[] = [];
    for (const file of SOURCES) {
      if (rule.allow?.(file)) continue;
      readFileSync(file, "utf8").split("\n").forEach((line, i) => {
        // the rules document themselves in comments; scan code and copy only
        const code = line.replace(/\/\/.*$/, "").replace(/\/\*.*?\*\//g, "");
        if (/^\s*\*/.test(line)) return;
        if (rule.pattern.test(code)) hits.push(`${relative(SRC, file)}:${i + 1}  ${line.trim().slice(0, 100)}`);
      });
    }
    expect(hits, rule.why).toEqual([]);
  });

  it("the series tokens match the validated palette in both themes", () => {
    const css = readFileSync(TOKENS_FILE, "utf8");
    const light = css.slice(css.indexOf(":root {"), css.indexOf("@media"));
    const dark = css.slice(css.indexOf(':root[data-theme="dark"]'), css.indexOf("@theme"));
    const tok = (block: string, name: string) => new RegExp(`--${name}:\\s*(#[0-9a-f]{6})`, "i").exec(block)?.[1]?.toLowerCase();
    expect([tok(light, "surface"), tok(light, "market"), tok(light, "model"), tok(light, "actual")]).toEqual(["#fbfcfa", "#2563d1", "#b98600", "#d4456f"]);
    expect([tok(dark, "surface"), tok(dark, "market"), tok(dark, "model"), tok(dark, "actual")]).toEqual(["#13201b", "#4a86ea", "#b08a0e", "#d9577f"]);
  });
});

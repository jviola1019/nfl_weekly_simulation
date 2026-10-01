/**
 * Docs truth: what the docs say about the web app must match the code. Each check
 * parses a doc and compares it with the source it describes, so a doc edit or a
 * code change that breaks the claim fails here instead of misleading a reader.
 */
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { extname, join, sep } from "node:path";
import { describe, expect, it } from "vitest";
import { BUNDLE_TABLES } from "../lib/contracts/bundle";

const WEB = join(import.meta.dirname, "..", "..");
const REPO = join(WEB, "..");
const readme = readFileSync(join(WEB, "README.md"), "utf8");
const spec = readFileSync(join(REPO, "docs", "superpowers", "specs", "2026-09-28-nfl-overhaul-design.md"), "utf8");
const pkg = JSON.parse(readFileSync(join(WEB, "package.json"), "utf8")) as { scripts: Record<string, string> };

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((n) => (statSync(join(dir, n)).isDirectory() ? walk(join(dir, n)) : [join(dir, n)]));
}

describe("docs truth: web/README.md", () => {
  it("every npm script it names exists", () => {
    const named = [...readme.matchAll(/npm (?:run )?([a-z][\w:-]*)/g)].map((m) => m[1]!).filter((n) => !["ci", "install"].includes(n));
    expect(named.length).toBeGreaterThan(5);
    for (const n of new Set(named)) expect(pkg.scripts, `npm run ${n}`).toHaveProperty(n === "test" ? "test" : n);
  });

  it("every file path it names exists", () => {
    const paths = [...readme.matchAll(/`((?:\.\.\/)?[\w.-]+(?:\/[\w.*<>-]+)+)`/g)]
      .map((m) => m[1]!)
      .filter((p) => !p.includes("<") && !p.includes("*") && !p.startsWith("bundles/"));
    expect(paths.length).toBeGreaterThan(8);
    for (const p of paths) {
      const clean = p.replace(/§.*$/, "").trim();
      expect(existsSync(join(WEB, clean)) || existsSync(join(REPO, clean)), clean).toBe(true);
    }
  });

  it("its bundle table list is exactly the contract's", () => {
    const line = readme.split("\n").find((l) => l.startsWith("Bundle tables:")) ?? "";
    const listed = [...line.matchAll(/`([a-z_]+)`/g)].map((m) => m[1]);
    expect(listed).toEqual(Object.keys(BUNDLE_TABLES));
  });
});

describe("docs truth: spec §4 against the app", () => {
  it("the palette table matches the CSS tokens in both themes", () => {
    const css = readFileSync(join(WEB, "src", "app", "globals.css"), "utf8");
    const light = css.slice(css.indexOf(":root {"), css.indexOf("@media"));
    const dark = css.slice(css.indexOf(':root[data-theme="dark"]'), css.indexOf("@theme"));
    const tok = (block: string, name: string) => new RegExp(`--${name}:\\s*(#[0-9a-f]{6})`, "i").exec(block)?.[1]?.toLowerCase();
    const surfaces = /Light \(surface `(#[0-9a-f]{6})`\) \| Dark "night game" \(surface `(#[0-9a-f]{6})`\)/i.exec(spec);
    expect(surfaces, "palette header").not.toBeNull();
    expect([tok(light, "surface"), tok(dark, "surface")]).toEqual([surfaces![1], surfaces![2]]);
    for (const [role, token] of [["Market", "market"], ["Model", "model"], ["Actual / close", "actual"]] as const) {
      const row = new RegExp(`\\| ${role.replace("/", "\\/")} \\| \`(#[0-9a-f]{6})\` \\| \`(#[0-9a-f]{6})\` \\|`, "i").exec(spec);
      expect(row, role).not.toBeNull();
      expect([tok(light, token), tok(dark, token)], role).toEqual([row![1]!.toLowerCase(), row![2]!.toLowerCase()]);
    }
  });

  it("every page in the route table exists", () => {
    const table = spec.slice(spec.indexOf("**Pages:**"), spec.indexOf("A responsible-gambling footer"));
    const routes = [...table.matchAll(/^\| `([^`]+)`/gm)].map((m) => m[1]!.split(" ")[0]!);
    expect(routes).toEqual(["/", "/games/[id]", "/props", "/evidence", "/methodology", "/data-health", "/desk/*", "/login"]);
    for (const r of routes) {
      const dir = r === "/" ? "" : r.replace("/*", "");
      expect(existsSync(join(WEB, "src", "app", dir, "page.tsx")), r).toBe(true);
    }
  });
});

describe("docs truth: source comments", () => {
  it("every test file a comment points to exists", () => {
    const refs = walk(join(WEB, "src"))
      .filter((f) => [".ts", ".tsx"].includes(extname(f)))
      .flatMap((f) => [...readFileSync(f, "utf8").matchAll(/\b([\w/-]+\.(?:test|spec)\.tsx?)\b/g)].map((m) => [f, m[1]!] as const));
    expect(refs.length).toBeGreaterThan(0);
    const all = [...walk(join(WEB, "src")), ...(existsSync(join(WEB, "e2e")) ? walk(join(WEB, "e2e")) : [])].map((f) => f.split(sep).join("/"));
    for (const [from, ref] of refs) expect(all.some((f) => f.endsWith(ref.replace(/^.*\//, "/")) || f.endsWith(ref)), `${ref} (named in ${from})`).toBe(true);
  });
});

describe("portable paths", () => {
  it("no file path comes from a file: URL's .pathname or a file:// string compare (both break on Windows)", () => {
    const files = [...walk(join(WEB, "scripts")), ...walk(join(WEB, "src")), join(WEB, "next.config.mjs")].filter(
      (f) => [".ts", ".tsx", ".mjs"].includes(extname(f)) && !f.endsWith("docsTruth.test.ts"),
    );
    const patterns = [/import\.meta\.url\)\.pathname/, /`file:\/\/\$\{process\.argv/];
    const bad = files.flatMap((f) => patterns.filter((re) => re.test(readFileSync(f, "utf8"))).map((re) => `${f}: ${re}`));
    expect(bad).toEqual([]);
  });
});

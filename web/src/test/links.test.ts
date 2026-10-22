import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const CSS = readFileSync(join(import.meta.dirname, "..", "app", "globals.css"), "utf8");

/** The declarations of the first `a` rule inside the base layer, or undefined when there is none. */
function baseLinkDeclarations(css: string): string | undefined {
  const layer = /@layer base\s*\{/.exec(css);
  if (!layer) return undefined;
  const start = layer.index + layer[0].length;
  let depth = 1;
  let i = start;
  for (; depth > 0 && i < css.length; i++) {
    if (css[i] === "{") depth++;
    else if (css[i] === "}") depth--;
  }
  const base = css.slice(start, i - 1);
  return /(?:^|[\s}])a\s*\{([^}]*)\}/.exec(base)?.[1];
}

describe("links", () => {
  // Tailwind's preflight resets every link to `text-decoration: inherit`, so a link is underlined only
  // when the base layer's `a` rule sets the line. Without it links and terms read as plain text (WCAG 1.4.1).
  it("are underlined: the base-layer `a` rule declares text-decoration-line: underline", () => {
    const declarations = baseLinkDeclarations(CSS);
    expect(declarations, "globals.css has a base-layer `a` rule").toBeDefined();
    expect(declarations).toMatch(/(?:^|[\s;])text-decoration-line:\s*underline\s*;/);
  });
});

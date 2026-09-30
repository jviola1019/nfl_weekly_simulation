import { expect, test } from "@playwright/test";

test.use({ reducedMotion: "reduce" });

for (const path of ["/", "/evidence"]) {
  test(`nothing animates under reduced motion on ${path}`, async ({ page }) => {
    await page.goto(path, { waitUntil: "networkidle" });
    const moving = await page.evaluate(() => {
      const running = document.getAnimations().filter((a) => a.playState === "running").length;
      const transitions = [...document.querySelectorAll<HTMLElement>("body *")].filter((el) => {
        const d = getComputedStyle(el).transitionDuration.split(",").map((x) => Number.parseFloat(x));
        return d.some((x) => x > 0);
      }).length;
      return { running, transitions };
    });
    expect(moving).toEqual({ running: 0, transitions: 0 });
  });
}

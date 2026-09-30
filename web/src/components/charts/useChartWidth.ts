"use client";

import { useCallback, useState } from "react";

/**
 * Width of a chart's container in CSS pixels, so a chart lays itself out at its real
 * size and its text stays at the type scale (a scaled viewBox would shrink 12px ticks
 * to 6px on a phone and blow them up to 20px on a desktop). The server render uses
 * `initial`; the first measurement replaces it.
 */
export function useChartWidth(initial: number) {
  const [width, setWidth] = useState(initial);
  const ref = useCallback((el: HTMLElement | null) => {
    if (!el) return;
    const ro = new ResizeObserver(([entry]) => {
      const w = Math.floor(entry?.contentRect.width ?? 0);
      if (w > 0) setWidth(w);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  return [ref, width] as const;
}

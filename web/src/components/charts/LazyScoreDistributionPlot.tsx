"use client";

import dynamic from "next/dynamic";
import { type ComponentProps, useEffect, useRef, useState } from "react";
import type { ScoreDistributionPlot } from "./ScoreDistributionPlot";

// ssr: false keeps the plot (and its script) out of the server HTML and the first load; the
// figure's summary and table view are already there without it
const Plot = dynamic(() => import("./ScoreDistributionPlot").then((m) => m.ScoreDistributionPlot), { ssr: false });

/**
 * The slot a score-distribution plot draws into. It reserves the plot's height (240px on a
 * phone-wide container, 280px otherwise, as the plot picks) so nothing shifts when the plot
 * arrives, and loads the plot once the slot is within 400px of the viewport (at once where
 * IntersectionObserver is missing).
 */
export function LazyScoreDistributionPlot(props: ComponentProps<typeof ScoreDistributionPlot>) {
  const slot = useRef<HTMLDivElement>(null);
  const [near, setNear] = useState(false);
  useEffect(() => {
    const el = slot.current;
    if (!el) return;
    if (typeof IntersectionObserver === "undefined") {
      const frame = requestAnimationFrame(() => setNear(true));
      return () => cancelAnimationFrame(frame);
    }
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry?.isIntersecting) {
          setNear(true);
          io.disconnect();
        }
      },
      { rootMargin: "400px 0px" }
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);
  return (
    <div ref={slot} data-plot-slot className="min-h-[240px] sm:min-h-[280px]">
      {near ? <Plot {...props} /> : null}
    </div>
  );
}

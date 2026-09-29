"use client";

import { useRef, useState } from "react";

/**
 * One tooltip for a chart. Marks (or their larger transparent hit areas) carry
 * data-tip-value and data-tip-label; the tooltip follows pointer and keyboard focus.
 * Values lead, labels follow; text is inserted as text, never HTML.
 */
export function ChartTooltip({ children }: { children: React.ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const [tip, setTip] = useState<{ x: number; y: number; value: string; label: string } | null>(null);

  function show(target: EventTarget | null, clientX?: number, clientY?: number) {
    const el = (target as Element | null)?.closest?.("[data-tip-value]") as HTMLElement | SVGElement | null;
    const box = ref.current?.getBoundingClientRect();
    if (!el || !box) return setTip(null);
    const r = el.getBoundingClientRect();
    const x = (clientX ?? r.left + r.width / 2) - box.left;
    const y = (clientY ?? r.top) - box.top;
    setTip({ x, y, value: el.getAttribute("data-tip-value") ?? "", label: el.getAttribute("data-tip-label") ?? "" });
  }

  return (
    <div
      ref={ref}
      className="relative"
      onPointerMove={(e) => show(e.target, e.clientX, e.clientY)}
      onPointerLeave={() => setTip(null)}
      onFocus={(e) => show(e.target)}
      onBlur={() => setTip(null)}
    >
      {children}
      {tip ? (
        <div
          role="status"
          className="pointer-events-none absolute z-10 rounded-[3px] border border-rule bg-surface px-2 py-1 text-sm"
          style={{ left: Math.max(0, tip.x + 12), top: Math.max(0, tip.y - 44) }}
        >
          <div className="num font-semibold text-ink">{tip.value}</div>
          <div className="text-ink-2">{tip.label}</div>
        </div>
      ) : null}
    </div>
  );
}

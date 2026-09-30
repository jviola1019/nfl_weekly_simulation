/**
 * Governance and freshness states. Status colours are reserved for state and always
 * carry an icon and a label (never colour alone); they are distinct from the
 * market/model/actual series colours.
 */
type Tone = "good" | "warn" | "crit" | "neutral";

const TONE_BY_STATUS: Record<string, Tone> = {
  validated: "good",
  reproducible: "good",
  complete: "good",
  ok: "good",
  published: "good",
  passes: "good",
  unvalidated: "warn",
  stale: "warn",
  "not evaluable": "warn",
  pending: "warn",
  withdrawn: "crit",
  void: "crit",
  failed: "crit",
  qa_failed: "crit",
  "not better than market": "neutral",
  unavailable: "neutral",
  superseded: "neutral"
};

function toneFor(status: string): Tone {
  const key = Object.keys(TONE_BY_STATUS).find((k) => status.toLowerCase().startsWith(k));
  return key ? TONE_BY_STATUS[key]! : "neutral";
}

const TONE_CLASS: Record<Tone, string> = {
  good: "text-good",
  warn: "text-warn",
  crit: "text-crit",
  neutral: "text-ink-2"
};

function Icon({ tone }: { tone: Tone }) {
  // circle-check / circle-alert / circle-x / circle-minus, 14px, stroke only
  const common = { width: 14, height: 14, viewBox: "0 0 16 16", fill: "none", stroke: "currentColor", strokeWidth: 1.6, "aria-hidden": true } as const;
  if (tone === "good") return <svg {...common}><circle cx="8" cy="8" r="6.5" /><path d="M5 8.2l2 2 4-4.2" /></svg>;
  if (tone === "warn") return <svg {...common}><circle cx="8" cy="8" r="6.5" /><path d="M8 4.5v4.2M8 11.2v.3" /></svg>;
  if (tone === "crit") return <svg {...common}><circle cx="8" cy="8" r="6.5" /><path d="M5.5 5.5l5 5M10.5 5.5l-5 5" /></svg>;
  return <svg {...common}><circle cx="8" cy="8" r="6.5" /><path d="M5 8h6" /></svg>;
}

export function StatusBadge({ status, label }: { status: string; label?: string }) {
  const tone = toneFor(status);
  return (
    <span className={`inline-flex items-center gap-1.5 whitespace-nowrap text-sm ${TONE_CLASS[tone]}`}>
      <Icon tone={tone} />
      <span>{label ?? status}</span>
    </span>
  );
}

/** Formatting helpers. Probabilities are shown as whole percents unless precision matters. */
const ET = "America/New_York";

export function pct(p: number | null | undefined, digits = 0): string {
  if (p === null || p === undefined || !Number.isFinite(p)) return "–";
  return `${(p * 100).toFixed(digits)}%`;
}

/** Signed percentage points, e.g. +2.4 pts */
export function pts(d: number, digits = 1): string {
  const v = d * 100;
  return `${v > 0 ? "+" : v < 0 ? "−" : ""}${Math.abs(v).toFixed(digits)} pts`;
}

/** Signed percent with a real minus sign, e.g. −5.64% */
export function signedPct(x: number, digits = 2): string {
  const v = x * 100;
  return `${v > 0 ? "+" : v < 0 ? "−" : ""}${Math.abs(v).toFixed(digits)}%`;
}

export function bps(x: number): string {
  return `${x > 0 ? "+" : x < 0 ? "−" : ""}${Math.abs(Math.round(x))} bps`;
}

export function fixed(x: number, digits = 4): string {
  return x.toFixed(digits);
}

export function kickoff(iso: string): string {
  const d = new Date(iso);
  const day = new Intl.DateTimeFormat("en-US", { timeZone: ET, weekday: "short", month: "short", day: "numeric" }).format(d);
  const time = new Intl.DateTimeFormat("en-US", { timeZone: ET, hour: "numeric", minute: "2-digit" }).format(d);
  return `${day}, ${time} ET`;
}

export function weekday(iso: string): string {
  return new Intl.DateTimeFormat("en-US", { timeZone: ET, weekday: "long" }).format(new Date(iso));
}

export function utcStamp(iso: string | null | undefined): string {
  if (!iso) return "–";
  const d = new Date(iso);
  return `${d.toISOString().slice(0, 16).replace("T", " ")} UTC`;
}

export function age(iso: string | null | undefined, now: Date = new Date()): string {
  if (!iso) return "never";
  const mins = Math.round((now.getTime() - new Date(iso).getTime()) / 60000);
  if (mins < 60) return `${mins} min ago`;
  const hours = Math.round(mins / 60);
  if (hours < 48) return `${hours} h ago`;
  return `${Math.round(hours / 24)} days ago`;
}

export function shortSha(sha: string, n = 8): string {
  return sha.slice(0, n);
}

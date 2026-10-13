/**
 * A linear scale with just what the score-distribution charts use: call, invert, ticks and
 * nice. It replaces @visx/scale there because that pulls d3-scale with its colour, time and
 * format modules (about 90 KiB gzipped) into the game page's script, which cost mobile LCP
 * (final review I6). The arithmetic is d3-array's tick algorithm, and linearScale.test.ts
 * checks it against @visx/scale. Other charts keep @visx/scale.
 */
const E10 = Math.sqrt(50);
const E5 = Math.sqrt(10);
const E2 = Math.sqrt(2);

function tickIncrement(start: number, stop: number, count: number): number {
  const step = (stop - start) / Math.max(0, count);
  const power = Math.floor(Math.log10(step));
  const error = step / 10 ** power;
  const factor = error >= E10 ? 10 : error >= E5 ? 5 : error >= E2 ? 2 : 1;
  return power >= 0 ? factor * 10 ** power : -(10 ** -power) / factor;
}

function niceDomain([a, b]: [number, number], count: number): [number, number] {
  let start = a;
  let stop = b;
  let previous: number | undefined;
  for (let i = 0; i < 10; i += 1) {
    const step = tickIncrement(start, stop, count);
    if (step === previous) return [start, stop];
    if (step > 0) {
      start = Math.floor(start / step) * step;
      stop = Math.ceil(stop / step) * step;
    } else if (step < 0) {
      start = Math.ceil(start * step) / step;
      stop = Math.floor(stop * step) / step;
    } else break;
    previous = step;
  }
  return [start, stop];
}

function tickValues(start: number, stop: number, count: number): number[] {
  if (start === stop && count > 0) return [start];
  const step = tickIncrement(start, stop, count);
  if (!Number.isFinite(step) || step === 0) return [];
  const out: number[] = [];
  if (step > 0) {
    let r0 = Math.round(start / step);
    let r1 = Math.round(stop / step);
    if (r0 * step < start) r0 += 1;
    if (r1 * step > stop) r1 -= 1;
    for (let i = 0; i <= r1 - r0; i += 1) out.push((r0 + i) * step);
  } else {
    const inv = -step;
    let r0 = Math.round(start * inv);
    let r1 = Math.round(stop * inv);
    if (r0 / inv < start) r0 += 1;
    if (r1 / inv > stop) r1 -= 1;
    for (let i = 0; i <= r1 - r0; i += 1) out.push((r0 + i) / inv);
  }
  return out;
}

export interface LinearScale {
  (v: number): number;
  invert(px: number): number;
  ticks(count?: number): number[];
  domain(): [number, number];
}

export function linearScale({ domain, range, nice = false }: { domain: [number, number]; range: [number, number]; nice?: boolean }): LinearScale {
  const [d0, d1] = nice ? niceDomain(domain, 10) : domain;
  const [r0, r1] = range;
  const scale = ((v: number) => r0 + ((v - d0) / (d1 - d0)) * (r1 - r0)) as LinearScale;
  scale.invert = (px) => d0 + ((px - r0) / (r1 - r0)) * (d1 - d0);
  scale.ticks = (count = 10) => tickValues(d0, d1, count);
  scale.domain = () => [d0, d1];
  return scale;
}

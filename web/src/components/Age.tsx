import { age } from "@/lib/format";

/**
 * "x min ago", the one value in the app that reads the request-time clock. It is marked
 * data-age so the offline/online pixel-parity spec (e2e/parity.spec.ts) can mask it: two
 * servers asked at different moments legitimately differ here and nowhere else.
 */
export function Age({ iso }: { iso: string | null | undefined }) {
  return <span data-age>{age(iso)}</span>;
}

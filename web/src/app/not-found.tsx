import Link from "next/link";

export default function NotFound() {
  return (
    <div className="max-w-xl">
      <h1 className="text-2xl font-semibold">Not found</h1>
      <p className="mt-2 text-ink-2">That page or game is not in the published data. <Link href="/">Back to this week</Link></p>
    </div>
  );
}

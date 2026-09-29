import Link from "next/link";
import { StatusBadge } from "@/components/StatusBadge";
import { evidence, ledger, pointerRun } from "@/lib/data/queries";
import { shortSha } from "@/lib/format";
import { candidateLabel } from "@/lib/policy";

export const dynamic = "force-dynamic";
export const metadata = { title: "Methodology" };

/** Generated from the ingested runs (their config), the backtest and the evidence ledger. */
export default async function MethodologyPage() {
  const [ev, weekly, claims] = await Promise.all([evidence(), pointerRun("weekly"), ledger()]);
  const cfg = (weekly?.config ?? {}) as { selections?: Record<string, Record<string, number | string>>; paper_edge?: number; market_source?: string };
  const sel = cfg.selections ?? {};
  const counts = claims.reduce<Record<string, number>>((acc, c) => ({ ...acc, [c.status]: (acc[c.status] ?? 0) + 1 }), {});

  return (
    <article className="max-w-3xl">
      <h1 className="text-2xl font-semibold">Methodology</h1>
      <p className="mt-3 text-ink-2">
        This page is generated from the published runs and the evidence ledger, so it cannot drift from what the numbers
        were computed with.
      </p>

      <h2 className="mt-8 text-lg font-semibold">The benchmark</h2>
      <p className="mt-2">
        The market probability is the closing moneyline with the bookmaker margin removed proportionally:
        p = q<sub>home</sub> / (q<sub>home</sub> + q<sub>away</sub>). {cfg.market_source ? `Source: ${cfg.market_source}.` : null}
      </p>

      <h2 className="mt-8 text-lg font-semibold">Registered candidates</h2>
      <ul className="mt-2 space-y-3">
        <li>
          <span className="font-medium">{candidateLabel("C1")}</span>: FiveThirtyEight-style Elo on final scores, ratings
          since 1999{sel.c1 ? `; tuned K ${sel.c1.K}, home field ${sel.c1.hfa} Elo points, ${Number(sel.c1.regress) * 100}% regression each season` : ""}.
        </li>
        <li>
          <span className="font-medium">{candidateLabel("C2")}</span>: ridge logistic model on home-minus-away
          exponentially weighted EPA per play, success rate, pass/rush splits, the starting quarterback&apos;s EPA per
          dropback and rest{sel.c2 ? `; half-life ${sel.c2.halflife} team-games, penalty ${sel.c2.lambda}` : ""}.
        </li>
        <li><span className="font-medium">{candidateLabel("E1")}</span>: equal-weight average of the two on the log-odds scale.</li>
        <li><span className="font-medium">Market stacks (B1)</span>: logistic regression on the market&apos;s and a model&apos;s log-odds, refit every week; the market weight is learned.</li>
        <li><span className="font-medium">{candidateLabel("B2[E1]")}</span>: a fixed blend; the weight on the market was chosen on the tuning window{sel.b2_e1 ? ` (${Number(sel.b2_e1.w) * 100}%, the top of the grid)` : ""}.</li>
        <li><span className="font-medium">{candidateLabel("K[E1]")}</span>: the ensemble recalibrated on earlier out-of-fold predictions{sel.k_e1 ? ` (${sel.k_e1.method})` : ""}.</li>
      </ul>
      <p className="mt-3 text-sm text-ink-2">
        The Monte Carlo score simulator joins as its own candidate in the next protocol version, once its features are
        point-in-time.
      </p>

      <h2 className="mt-8 text-lg font-semibold">How candidates are judged</h2>
      <ul className="mt-2 list-disc space-y-2 pl-5">
        <li>Walk-forward by NFL week: every fit uses only games that kicked off before that week, and a guard rejects any input that finished after kickoff.</li>
        <li>Tune on 2018–22, confirm on 2023–24, then score the sealed 2025 holdout once. The protocol file is hashed and committed before scoring.</li>
        <li>Brier skill against the market with paired week-block bootstrap intervals, Diebold–Mariano tests with Benjamini–Hochberg correction, calibration slope and ECE.</li>
        <li>Controls void a run: a leak canary, shuffled labels, a market copy that must score exactly zero, and a second process that must reproduce the result hash.</li>
        <li>Betting value is judged on closing-line value at decision-time prices, with at least 400 picks in a single look.</li>
      </ul>
      {ev?.window ? (
        <p className="mt-3 text-sm text-ink-2">
          Current protocol <code>{ev.window.windowId}</code>, sha256 {shortSha(ev.window.protocolSha256, 12)}; result{" "}
          {shortSha(ev.bt.resultSha256, 12)}. <Link href="/evidence">Results</Link>
        </p>
      ) : null}

      <h2 className="mt-8 text-lg font-semibold">What is shown publicly</h2>
      <p className="mt-2">
        A model line appears on public pages only for a candidate that passed its gates. Until then the site shows the
        market alone and no picks. Stakes are never public; the private desk tracks paper leans only
        {cfg.paper_edge ? ` (edge of ${cfg.paper_edge * 100} points or more)` : ""}.
      </p>

      <h2 className="mt-8 text-lg font-semibold">Claims ledger</h2>
      <ul className="mt-2 flex flex-wrap gap-x-6 gap-y-1">
        {Object.entries(counts).map(([status, n]) => (
          <li key={status}><StatusBadge status={status} label={`${n} ${status}`} /></li>
        ))}
      </ul>
    </article>
  );
}

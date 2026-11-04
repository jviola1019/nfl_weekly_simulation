import Link from "next/link";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, Page, PageHeader, Section, Term } from "@/components/ui";
import { noRunContext, runContext } from "@/lib/context";
import { evidence, ledger, pointerRun } from "@/lib/data/queries";
import { shortSha } from "@/lib/format";
import { TERM_IDS, TERMS, termAnchor } from "@/lib/glossary";
import { candidateLabel } from "@/lib/policy";

export const dynamic = "force-dynamic";
export const metadata = {
  title: "Methodology",
  description: "How the market probability is built, which models are registered, how they are judged, what is shown publicly, and what each term means."
};

/** Generated from the ingested runs (their config), the backtest and the evidence ledger. */
export default async function MethodologyPage() {
  const [ev, weekly, claims] = await Promise.all([evidence(), pointerRun("weekly"), ledger()]);
  const cfg = (weekly?.config ?? {}) as { selections?: Record<string, Record<string, number | string>>; paper_edge?: number; market_source?: string };
  const sel = cfg.selections ?? {};
  const counts = claims.reduce<Record<string, number>>((acc, c) => ({ ...acc, [c.status]: (acc[c.status] ?? 0) + 1 }), {});

  return (
    <Page>
      <PageHeader
        title="Methodology"
        lead="This page is generated from the published runs and the evidence ledger, so it cannot drift from what the numbers were computed with."
        context={weekly ? runContext(weekly) : noRunContext("nothing has been ingested")}
      />

      <Section id="benchmark" title="The benchmark" measure>
        <Card>
          <p>
            The market probability is the closing moneyline with the bookmaker margin removed proportionally (<Term id="no-vig">no-vig</Term>):
            p = q<sub>home</sub> / (q<sub>home</sub> + q<sub>away</sub>). {cfg.market_source ? `Source: ${cfg.market_source}.` : null}
          </p>
        </Card>
      </Section>

      <Section id="candidates" title="Registered candidates" measure>
        <Card className="flex flex-col gap-control">
          <ul className="space-y-control">
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
          <p className="border-t border-rule pt-control text-sm text-ink-2">
            The Monte Carlo score simulator ({candidateLabel("C3")}) joins as its own candidate in the next protocol version, once
            its features are point-in-time. Until then a simulator run is research output: its line is the simulation&apos;s win
            probability after the production pipeline&apos;s 70% weight on the no-vig market (<code>SHRINKAGE</code>, <Term id="shrinkage">shrinkage toward the market</Term>); games
            without a market show the unshrunk value.
          </p>
        </Card>
      </Section>

      <Section id="judged" title="How candidates are judged" measure>
        <Card className="flex flex-col gap-control">
          <ul className="list-disc space-y-snug pl-5">
            <li><Term id="walk-forward">Walk-forward</Term> by NFL week: every fit uses only games that kicked off before that week, and a guard rejects any input that finished after kickoff.</li>
            <li>Tune on 2018–22, confirm on 2023–24, then score the <Term id="holdout">sealed 2025 holdout</Term> once. The protocol file is hashed and committed before scoring.</li>
            <li><Term id="brier">Brier</Term> <Term id="skill">skill</Term> against the market with paired week-block bootstrap intervals (<Term id="interval" />), Diebold–Mariano tests with Benjamini–Hochberg correction, calibration slope and <Term id="ece">ECE</Term>.</li>
            <li>Controls void a run: a leak canary, shuffled labels, a market copy that must score exactly zero, and a second process that must reproduce the result hash.</li>
            <li>Betting value is judged on <Term id="clv">closing-line value</Term> at decision-time prices, with at least 400 picks in a single look.</li>
          </ul>
          {ev?.window ? (
            <p className="border-t border-rule pt-control text-sm text-ink-2">
              Current protocol <code>{ev.window.windowId}</code>, sha256 {shortSha(ev.window.protocolSha256, 12)}; result{" "}
              {shortSha(ev.bt.resultSha256, 12)}. <Link href="/evidence">Results</Link>
            </p>
          ) : null}
        </Card>
      </Section>

      <Section id="public" title="What is shown publicly" measure>
        <Card>
          <p>
            A candidate that passed its gates is shown as validated. Until one does, the fields carry one research line,
            labelled <Term id="unvalidated">unvalidated</Term> wherever it appears: the {candidateLabel("E1")} when the published run has it, otherwise the
            game simulator. There are no public picks. Stakes are never public; the private desk tracks paper leans only
            {cfg.paper_edge ? ` (edge of ${cfg.paper_edge * 100} points or more)` : ""}.
          </p>
        </Card>
      </Section>

      <Section id="claims" title="Claims ledger" measure>
        <Card>
          <ul className="flex flex-wrap gap-x-stack gap-y-tight">
            {Object.entries(counts).map(([status, n]) => (
              <li key={status}><StatusBadge status={status} label={`${n} ${status}`} /></li>
            ))}
          </ul>
        </Card>
      </Section>

      <Section id="definitions" title="Definitions" measure>
        <Card>
          <dl className="flex flex-col gap-stack">
            {TERM_IDS.map((id) => (
              <div key={id} id={termAnchor(id)} className="flex flex-col gap-tight">
                <dt className="font-medium">{TERMS[id].label}</dt>
                <dd className="text-sm text-ink-2">{TERMS[id].definition}</dd>
              </div>
            ))}
          </dl>
        </Card>
      </Section>
    </Page>
  );
}

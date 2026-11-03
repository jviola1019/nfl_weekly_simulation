import Link from "next/link";
import { DataUnavailable } from "@/components/DataUnavailable";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, Grid, Page, PageHeader, Section } from "@/components/ui";
import { noRunContext } from "@/lib/context";

export const metadata = {
  title: "Props",
  description: "Player props by market. None is priced here until its market passes a pre-registered backtest, and the page says why."
};

const MARKETS = [
  { group: "Touchdowns", items: ["Anytime", "First", "Two or more"] },
  { group: "Yardage", items: ["Passing yards", "Rushing yards", "Receiving yards"] },
  { group: "Counts", items: ["Receptions", "Completions", "Pass attempts", "Passing TDs", "Interceptions"] }
];

export default function PropsPage() {
  return (
    <Page>
      <PageHeader
        title="Player props"
        lead={
          <span className="flex flex-wrap items-center gap-snug">
            <StatusBadge status="unvalidated" label="Props model unvalidated" />
            <span>No prop is priced here until its market passes a pre-registered backtest.</span>
          </span>
        }
        context={noRunContext("no prop is priced yet; game probabilities are on This week")}
      />

      <Grid kind="tiles">
        {MARKETS.map((m) => (
          <Section key={m.group} id={`m-${m.group}`} title={m.group}>
            <Card pad="sm">
              <ul className="text-sm">
                {m.items.map((i) => (
                  <li key={i} className="flex items-center justify-between gap-control border-t border-rule py-row first:border-t-0 first:pt-0 last:pb-0">
                    <span>{i}</span>
                    <StatusBadge status="unvalidated" label="Not priced" />
                  </li>
                ))}
              </ul>
            </Card>
          </Section>
        ))}
      </Grid>

      <DataUnavailable title="Why this page is empty">
        <p>
          Most props defects from the audit are fixed: each row has one decision (its side, tier and stake agree), a price
          comes only from a quote captured before kickoff, players are matched by id rather than by name, and
          opponent-defense adjustments apply (audit P1–P5, P9, P10, P12–P14). Four are open: projections weight three
          seasons equally, ignore injuries and depth charts, and can fall back to placeholder players (P6); props correlate
          only with the game total (P7); yards are a normal clipped at zero and receptions a Poisson (P8); and several
          markets listed above have no model yet (P11). Phase 4 rebuilds the model (usage shares, a touchdown engine),
          and Phase 5 backtests each market separately.
        </p>
        <p className="mt-snug">
          A prospective test is running: nfl_props_v1, signed on 2026-11-02, scores Kalshi&apos;s prop prices and our
          props model on 2026 weeks 9–18. The model it tests is the code of commit 4c1c377, from before these fixes, so
          the fixed model needs a protocol of its own.
        </p>
        <p className="mt-snug">
          A market is backtested only with at least 300 settled player-games that had a pre-kickoff price: a two-sided
          quote with a spread of at most 0.10, updated in the 60 minutes before kickoff (checkpoint A5). Below that it is
          tracked prospectively and labelled that way. See <Link href="/methodology">Methodology</Link>.
        </p>
      </DataUnavailable>
    </Page>
  );
}

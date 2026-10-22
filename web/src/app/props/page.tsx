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
          The props engine has known defects that change every row (audit P1–P13): labels are column-wide, recommendation
          and stake disagree, and anytime-TD prices never reach the output. Phase 4 fixes them and rebuilds the model
          (usage shares, a touchdown engine), and Phase 5 backtests each market separately.
        </p>
        <p className="mt-snug">
          A market is backtested only with at least 300 settled player-games that had a pre-kickoff price; below that it
          is tracked prospectively and labelled that way. What counts as a pre-kickoff price (checkpoint A5) is still an
          owner decision. See <Link href="/methodology">Methodology</Link>.
        </p>
      </DataUnavailable>
    </Page>
  );
}

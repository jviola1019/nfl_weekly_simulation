import Link from "next/link";
import { DataUnavailable } from "@/components/DataUnavailable";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, PageTitle } from "@/components/ui";

export const metadata = { title: "Props" };

const MARKETS = [
  { group: "Touchdowns", items: ["Anytime", "First", "Two or more"] },
  { group: "Yardage", items: ["Passing yards", "Rushing yards", "Receiving yards"] },
  { group: "Counts", items: ["Receptions", "Completions", "Pass attempts", "Passing TDs", "Interceptions"] }
];

export default function PropsPage() {
  return (
    <>
      <PageTitle
        lead={
          <span className="flex flex-wrap items-center gap-2">
            <StatusBadge status="unvalidated" label="Props model unvalidated" />
            <span>No prop is priced here until its market passes a pre-registered backtest.</span>
          </span>
        }
      >
        Player props
      </PageTitle>

      <div className="mt-8 grid gap-5 sm:grid-cols-3">
        {MARKETS.map((m) => (
          <Card key={m.group}>
            <section aria-labelledby={`m-${m.group}`}>
              <h2 id={`m-${m.group}`} className="font-bold">{m.group}</h2>
              <ul className="mt-3 text-sm">
                {m.items.map((i) => (
                  <li key={i} className="flex items-center justify-between gap-3 border-t border-rule py-2">
                    <span>{i}</span>
                    <StatusBadge status="unvalidated" label="Not priced" />
                  </li>
                ))}
              </ul>
            </section>
          </Card>
        ))}
      </div>

      <div className="mt-8">
        <DataUnavailable title="Why this page is empty">
          <p>
            The props engine has known defects that change every row (audit P1–P13): labels are column-wide, recommendation
            and stake disagree, and anytime-TD prices never reach the output. Phase 4 fixes them and rebuilds the model
            (usage shares, a touchdown engine), and Phase 5 backtests each market separately.
          </p>
          <p className="mt-2">
            A market is backtested only with at least 300 settled player-games that had a pre-kickoff price; below that it
            is tracked prospectively and labelled that way. What counts as a pre-kickoff price (checkpoint A5) is still an
            owner decision. See <Link href="/methodology">Methodology</Link>.
          </p>
        </DataUnavailable>
      </div>
    </>
  );
}

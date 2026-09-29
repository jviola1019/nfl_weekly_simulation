import Link from "next/link";
import { DataUnavailable } from "@/components/DataUnavailable";
import { Field, FieldKey } from "@/components/Field";
import { StatusBadge } from "@/components/StatusBadge";
import { candidateLines, evidence, publicSlate } from "@/lib/data/queries";
import { age, utcStamp, weekday } from "@/lib/format";
import { candidateLabel, publicModelCandidates } from "@/lib/policy";

export const dynamic = "force-dynamic";

const SORTS = { kickoff: "Kickoff", closest: "Closest", favourite: "Biggest favourite" } as const;
type Sort = keyof typeof SORTS;

export default async function ThisWeek({ searchParams }: { searchParams: Promise<{ sort?: string; day?: string }> }) {
  const sp = await searchParams;
  const sort: Sort = sp.sort && sp.sort in SORTS ? (sp.sort as Sort) : "kickoff";
  const [{ run, games }, ev] = await Promise.all([publicSlate(), evidence()]);

  if (!run) {
    return (
      <>
        <h1 className="text-2xl font-semibold">This week</h1>
        <div className="mt-6">
          <DataUnavailable title="No published weekly run">
            Nothing has been ingested yet. A weekly bundle from the R engine appears here after <code>ingest-bundle</code>.
          </DataUnavailable>
        </div>
      </>
    );
  }

  const shown = publicModelCandidates(ev?.gates ?? []);
  const lines = shown.length ? await candidateLines(run.runId, shown.slice(0, 1)) : [];
  const days = [...new Set(games.map((g) => weekday(g.kickoffUtc)))];
  const day = sp.day && days.includes(sp.day) ? sp.day : null;
  let list = day ? games.filter((g) => weekday(g.kickoffUtc) === day) : games;
  if (sort === "closest") list = [...list].sort((a, b) => Math.abs((a.pMarket ?? 0.5) - 0.5) - Math.abs((b.pMarket ?? 0.5) - 0.5));
  if (sort === "favourite") list = [...list].sort((a, b) => Math.abs((b.pMarket ?? 0.5) - 0.5) - Math.abs((a.pMarket ?? 0.5) - 0.5));
  const href = (s: Sort, d: string | null) => `/?sort=${s}${d ? `&day=${encodeURIComponent(d)}` : ""}`;

  return (
    <>
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h1 className="text-2xl font-semibold">
          Week {run.week}, {run.season} season
        </h1>
        <p className="text-sm text-muted">
          Market data as of {utcStamp(run.dataAsofUtc)} ({age(run.dataAsofUtc)})
        </p>
      </div>

      <div className="mt-4 max-w-3xl space-y-2 text-ink-2">
        <p>
          Each strip runs from the away end zone to the home end zone. The blue marker is where the betting market places
          the game: its no-vig probability that the home team wins.
        </p>
        {shown.length ? (
          <p>The gold line is {candidateLabel(shown[0]!)}, which passed its pre-registered gates.</p>
        ) : (
          <p className="flex flex-wrap items-center gap-2">
            <StatusBadge status="not better than market" label="Model lines hidden" />
            <span>
              In the pre-registered test on 2023–24, no model or blend beat the closing market, so only the market is
              shown. <Link href="/evidence">See the evidence</Link>.
            </span>
          </p>
        )}
      </div>

      <form className="mt-6 flex flex-wrap items-center gap-x-6 gap-y-2 text-sm" aria-label="Sort and filter">
        <div className="flex items-center gap-2">
          <span className="text-ink-2">Sort</span>
          {(Object.keys(SORTS) as Sort[]).map((s) => (
            <Link
              key={s}
              href={href(s, day)}
              aria-current={s === sort ? "true" : undefined}
              className={`rounded-[3px] border px-2 py-1 no-underline ${s === sort ? "border-ink text-ink" : "border-rule text-ink-2"}`}
            >
              {SORTS[s]}
            </Link>
          ))}
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-ink-2">Day</span>
          <Link href={href(sort, null)} aria-current={!day ? "true" : undefined} className={`rounded-[3px] border px-2 py-1 no-underline ${!day ? "border-ink text-ink" : "border-rule text-ink-2"}`}>
            All
          </Link>
          {days.map((d) => (
            <Link key={d} href={href(sort, d)} aria-current={d === day ? "true" : undefined} className={`rounded-[3px] border px-2 py-1 no-underline ${d === day ? "border-ink text-ink" : "border-rule text-ink-2"}`}>
              {d}
            </Link>
          ))}
        </div>
      </form>

      <div className="mt-4">
        <FieldKey showModel={shown.length > 0} modelLabel={shown[0] ? candidateLabel(shown[0]) : undefined} />
      </div>

      <div className="mt-2 divide-y divide-rule">
        {list.map((g) => {
          const line = lines.find((l) => l.gameId === g.gameId && l.p !== null);
          return (
            <Field
              key={g.gameId}
              gameId={g.gameId}
              awayId={g.awayTeamId}
              homeId={g.homeTeamId}
              awayName={g.awayName}
              homeName={g.homeName}
              kickoffUtc={g.kickoffUtc}
              neutral={g.neutral}
              pMarket={g.pMarket}
              model={line ? { p: line.p as number, label: candidateLabel(line.candidate) } : null}
              href={`/games/${g.gameId}`}
              final={g.homeScore !== null && g.awayScore !== null ? { home: g.homeScore, away: g.awayScore } : null}
            />
          );
        })}
      </div>
      <p className="mt-4 text-sm text-muted">
        Market: nflverse consensus moneyline, proportionally devigged. It carries no timestamp or book, so line movement is
        not shown here.
      </p>
    </>
  );
}

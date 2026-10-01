import Link from "next/link";
import { DataUnavailable } from "@/components/DataUnavailable";
import { Field, FieldKey } from "@/components/Field";
import { StatusBadge } from "@/components/StatusBadge";
import { candidateLines, evidence, publicSlate } from "@/lib/data/queries";
import { age, utcStamp, weekday } from "@/lib/format";
import { candidateLabel, publicFieldLine } from "@/lib/policy";

export const dynamic = "force-dynamic";

const SORTS = { kickoff: "Kickoff", gap: "Biggest gap", closest: "Closest game" } as const;
type Sort = keyof typeof SORTS;

const ET = "America/New_York";
const shortDay = (iso: string) => new Intl.DateTimeFormat("en-US", { timeZone: ET, weekday: "short", month: "short", day: "numeric" }).format(new Date(iso));
const longDay = (iso: string) => new Intl.DateTimeFormat("en-US", { timeZone: ET, weekday: "long", month: "short", day: "numeric" }).format(new Date(iso));

export default async function ThisWeek({ searchParams }: { searchParams: Promise<{ sort?: string; day?: string; model?: string }> }) {
  const sp = await searchParams;
  const sort: Sort = sp.sort && sp.sort in SORTS ? (sp.sort as Sort) : "kickoff";
  const showModel = sp.model !== "off";
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

  const line = publicFieldLine(ev?.gates ?? []);
  const label = candidateLabel(line.candidate);
  const lines = await candidateLines(run.runId, [line.candidate]);
  const pModel = (gameId: string) => {
    const l = lines.find((x) => x.gameId === gameId && x.p !== null);
    return l ? (l.p as number) : null;
  };

  const rows = games.map((g) => {
    const p = pModel(g.gameId);
    const gap = p !== null && g.pMarket !== null ? Math.abs(p - g.pMarket) : 0;
    const flips = p !== null && g.pMarket !== null ? g.pMarket >= 0.5 !== p >= 0.5 : false;
    return { g, m: showModel && p !== null ? { p, label, validated: line.validated } : null, gap, flips, hasModel: p !== null && g.pMarket !== null };
  });
  const statRows = rows.filter((r) => r.hasModel);
  const biggest = statRows.length ? statRows.reduce((a, b) => (b.gap > a.gap ? b : a)) : null;
  const flipCount = statRows.filter((r) => r.flips).length;

  const days = [...new Set(games.map((g) => weekday(g.kickoffUtc)))];
  const day = sp.day && days.includes(sp.day) ? sp.day : null;
  let list = day ? rows.filter((r) => weekday(r.g.kickoffUtc) === day) : rows;
  if (sort === "gap") list = [...list].sort((a, b) => b.gap - a.gap);
  if (sort === "closest") list = [...list].sort((a, b) => Math.abs((a.g.pMarket ?? 0.5) - 0.5) - Math.abs((b.g.pMarket ?? 0.5) - 0.5));
  const groups =
    sort === "kickoff"
      ? days
          .map((d) => ({ label: longDay(list.find((r) => weekday(r.g.kickoffUtc) === d)?.g.kickoffUtc ?? games[0]!.kickoffUtc), items: list.filter((r) => weekday(r.g.kickoffUtc) === d) }))
          .filter((x) => x.items.length)
      : [{ label: sort === "gap" ? "Sorted by the model–market gap" : "Sorted by the closest market line", items: list }];

  const href = (s: Sort, d: string | null, m: boolean) => {
    const q = new URLSearchParams({ sort: s });
    if (d) q.set("day", d);
    if (!m) q.set("model", "off");
    return `/?${q.toString()}`;
  };
  const chip = (on: boolean) =>
    `inline-flex h-11 items-center rounded-[3px] border px-3.5 text-[13px] no-underline ${on ? "border-ink bg-ink font-semibold text-surface" : "border-rule text-ink-2 hover:border-ink-2"}`;
  const first = games[0]?.kickoffUtc;
  const last = games[games.length - 1]?.kickoffUtc;

  return (
    <>
      <section className="grid gap-8 pt-4 lg:grid-cols-[minmax(0,1fr)_420px] lg:items-end">
        <div className="flex flex-col gap-3">
          <p className="text-[15px] text-muted">
            {run.season} season{first && last ? ` · ${shortDay(first)} – ${shortDay(last)}` : ""}
          </p>
          <h1 className="wdth-expanded text-[64px] font-black leading-[0.9] tracking-[-0.02em] sm:text-[104px]">Week {run.week}</h1>
          <p className="mt-2 max-w-[660px] text-[17px] leading-relaxed text-ink-2 [text-wrap:pretty]">
            Every game is a field. The line splits it by win chance, so each team&apos;s side of the field is its probability of winning.
            Blue is the betting market&apos;s no-vig price; gold is {line.validated ? "a validated model" : "our research model"}.
          </p>
        </div>
        <aside aria-label="Model status" className="flex flex-col gap-3 rounded-[6px] border border-rule bg-surface p-5">
          <div className="flex items-center gap-3">
            <StatusBadge status={line.validated ? "validated" : "unvalidated"} label={line.validated ? "Validated" : "Unvalidated"} />
            <span className="font-semibold">{label}</span>
          </div>
          <p className="text-sm leading-relaxed text-ink-2 [text-wrap:pretty]">
            {line.validated
              ? "This model passed its pre-registered gates. It is still not betting advice."
              : "In the pre-registered test on 2023–24 (570 games), no model or blend beat the closing market's Brier score. Read the gold line as research output, never as advice."}
          </p>
          <Link href="/evidence" className="text-sm font-semibold">
            See the evidence
          </Link>
        </aside>
      </section>

      <section aria-label="This week in numbers" className="mt-7 grid gap-4 sm:grid-cols-3">
        <div className="flex flex-col gap-1.5 rounded-[6px] border border-rule bg-surface px-5 py-4">
          <span className="num wdth-expanded text-[40px] font-extrabold leading-none">{games.length}</span>
          <span className="text-sm text-muted">games on the slate</span>
        </div>
        <div className="flex flex-col gap-1.5 rounded-[6px] border border-rule bg-surface px-5 py-4">
          <span className="num wdth-expanded text-[40px] font-extrabold leading-none">
            {statRows.length ? `${flipCount} of ${statRows.length}` : "–"}
          </span>
          <span className="text-sm text-muted">games where the model picks a different favourite</span>
        </div>
        <div className="flex flex-col gap-1.5 rounded-[6px] border border-rule bg-surface px-5 py-4">
          <span className="num wdth-expanded text-[40px] font-extrabold leading-none">{biggest ? `${(biggest.gap * 100).toFixed(1)} pts` : "–"}</span>
          <span className="text-sm text-muted">largest model–market gap{biggest ? `: ${biggest.g.awayTeamId} at ${biggest.g.homeTeamId}` : ""}</span>
        </div>
      </section>

      <section aria-label="Sort and filter" className="mt-7 flex flex-col gap-4 border-y border-rule py-4 lg:flex-row lg:items-center lg:justify-between">
        <FieldKey showModel={showModel} modelLabel={label} validated={line.validated} />
        <div className="flex flex-wrap items-center gap-x-5 gap-y-2">
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="mr-1 text-[13px] text-muted">Sort</span>
            {(Object.keys(SORTS) as Sort[]).map((s) => (
              <Link key={s} href={href(s, day, showModel)} aria-current={s === sort ? "true" : undefined} className={chip(s === sort)}>
                {SORTS[s]}
              </Link>
            ))}
          </div>
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="mr-1 text-[13px] text-muted">Day</span>
            <Link href={href(sort, null, showModel)} aria-current={!day ? "true" : undefined} className={chip(!day)}>
              All
            </Link>
            {days.map((d) => (
              <Link key={d} href={href(sort, d, showModel)} aria-current={d === day ? "true" : undefined} className={chip(d === day)}>
                {d.slice(0, 3)}
              </Link>
            ))}
          </div>
          <Link
            href={href(sort, day, !showModel)}
            aria-label={showModel ? "Model line is on. Turn it off" : "Model line is off. Turn it on"}
            className={chip(showModel)}
          >
            Model line {showModel ? "on" : "off"}
          </Link>
        </div>
      </section>

      {groups.map((grp) => (
        <section key={grp.label} className="mt-7 flex flex-col gap-3.5" aria-label={grp.label}>
          <h2 className="text-base font-semibold text-ink-2">{grp.label}</h2>
          <div className="grid gap-5 lg:grid-cols-2">
            {grp.items.map(({ g, m }) => (
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
                model={m}
                href={`/games/${g.gameId}`}
                final={g.homeScore !== null && g.awayScore !== null ? { home: g.homeScore, away: g.awayScore } : null}
              />
            ))}
          </div>
        </section>
      ))}

      <p className="mt-6 text-sm text-muted">
        Market: nflverse consensus moneyline, proportionally devigged, as of {utcStamp(run.dataAsofUtc)} ({age(run.dataAsofUtc)}). It
        carries no timestamp or book, so line movement is not shown here.
      </p>
    </>
  );
}

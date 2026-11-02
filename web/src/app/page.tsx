import Link from "next/link";
import { Age } from "@/components/Age";
import { DataUnavailable } from "@/components/DataUnavailable";
import { Field, FieldKey } from "@/components/Field";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, chipClass, Grid, Page, PageHeader, Section, Stamp, StatTile, Term } from "@/components/ui";
import { noRunContext, runContext } from "@/lib/context";
import { candidateLines, publicGates, publicSlate, runCandidates } from "@/lib/data/queries";
import { sortSlate } from "@/lib/slateSort";
import { weekday } from "@/lib/format";
import { candidateLabel, fieldLineNote, fieldLineNoun, publicFieldLine } from "@/lib/policy";

export const dynamic = "force-dynamic";
export const metadata = {
  // the root layout's title template does not apply to the page of its own segment
  title: { absolute: "This week · Broadcast Line" },
  description: "Every NFL game of the week drawn as a field: the no-vig market's win probability against the model's, with the run and the date of the data stated."
};

const SORTS = { kickoff: "Kickoff", gap: "Biggest gap", closest: "Closest game" } as const;
type Sort = keyof typeof SORTS;

const ET = "America/New_York";
const shortDay = (iso: string) => new Intl.DateTimeFormat("en-US", { timeZone: ET, weekday: "short", month: "short", day: "numeric" }).format(new Date(iso));
const longDay = (iso: string) => new Intl.DateTimeFormat("en-US", { timeZone: ET, weekday: "long", month: "short", day: "numeric" }).format(new Date(iso));

export default async function ThisWeek({ searchParams }: { searchParams: Promise<{ sort?: string; day?: string; model?: string }> }) {
  const sp = await searchParams;
  const sort: Sort = sp.sort && sp.sort in SORTS ? (sp.sort as Sort) : "kickoff";
  const showModel = sp.model !== "off";
  // the slate and the promotion gates are independent: one round trip for both
  const [{ run, games }, gates] = await Promise.all([publicSlate(), publicGates()]);

  if (!run) {
    return (
      <Page>
        <PageHeader title="This week" context={noRunContext("nothing has been ingested")} />
        <DataUnavailable title="No published weekly run">
          Nothing has been ingested yet. A weekly bundle from the R engine appears here after <code>ingest-bundle</code>.
        </DataUnavailable>
      </Page>
    );
  }

  const line = publicFieldLine(gates, await runCandidates(run.runId));
  const label = line ? candidateLabel(line.candidate) : "Model";
  const lines = line ? await candidateLines(run.runId, [line.candidate]) : [];
  const pModel = (gameId: string) => {
    const l = lines.find((x) => x.gameId === gameId && x.p !== null);
    return l ? (l.p as number) : null;
  };

  const rows = games.map((g) => {
    const p = pModel(g.gameId);
    const gap = p !== null && g.pMarket !== null ? Math.abs(p - g.pMarket) : 0;
    const flips = p !== null && g.pMarket !== null ? g.pMarket >= 0.5 !== p >= 0.5 : false;
    return { g, m: showModel && line && p !== null ? { p, label, validated: line.validated } : null, gap, flips, hasModel: p !== null && g.pMarket !== null };
  });
  const statRows = rows.filter((r) => r.hasModel);
  const biggest = statRows.length ? statRows.reduce((a, b) => (b.gap > a.gap ? b : a)) : null;
  const flipCount = statRows.filter((r) => r.flips).length;

  const days = [...new Set(games.map((g) => weekday(g.kickoffUtc)))];
  const day = sp.day && days.includes(sp.day) ? sp.day : null;
  let list = day ? rows.filter((r) => weekday(r.g.kickoffUtc) === day) : rows;
  list = sortSlate(list, sort);
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
  const first = games[0]?.kickoffUtc;
  const last = games[games.length - 1]?.kickoffUtc;
  const modelSource = line ? `${label} against the no-vig market, ${statRows.length} games with both lines` : "This run carries no model line";

  return (
    <Page>
      <PageHeader
        size="hero"
        title={run.week === null ? "This week" : `Week ${run.week}`}
        lead={
          <>
            Every game is a field. The line splits it by win chance, so each team&apos;s side of the field is its probability of winning.
            Blue is the betting market&apos;s no-vig price{line ? `; gold is ${fieldLineNoun(line)}` : ""}. <Term id="field">How to read a field</Term>.
          </>
        }
        context={[...runContext(run), { label: "Games", value: first && last ? `${shortDay(first)} – ${shortDay(last)}` : "none scheduled" }]}
        aside={
          <Card as="aside" aria-label="Model status" className="flex flex-col gap-control">
            <div className="flex items-center gap-control">
              {line ? (
                <StatusBadge status={line.validated ? "validated" : "unvalidated"} label={line.validated ? "Validated" : "Unvalidated"} />
              ) : (
                <StatusBadge status="unavailable" label="Market only" />
              )}
              {line ? <span className="font-semibold">{label}</span> : null}
            </div>
            <p className="text-sm text-ink-2 text-pretty">{fieldLineNote(line)}</p>
            <Link href="/evidence" className="text-sm font-semibold">
              See the evidence
            </Link>
          </Card>
        }
      />

      <Section label="This week in numbers">
        <Grid kind="tiles">
          <StatTile value={games.length} label="games on the slate" source={`Published run ${run.cycleId}`} />
          <StatTile
            value={statRows.length ? `${flipCount} of ${statRows.length}` : "–"}
            label="games where the model picks a different favourite"
            source={modelSource}
          />
          <StatTile
            value={biggest ? `${(biggest.gap * 100).toFixed(1)} pts` : "–"}
            label={
              <>
                largest <Term id="gap">model–market gap</Term>
                {biggest ? `: ${biggest.g.awayTeamId} at ${biggest.g.homeTeamId}` : ""}
              </>
            }
            source={modelSource}
          />
        </Grid>
      </Section>

      <Section label="Sort and filter" className="border-y border-rule py-card-sm lg:flex-row lg:items-center lg:justify-between">
        <FieldKey showModel={showModel && line !== null} modelLabel={label} validated={line?.validated ?? false} />
        <div className="flex flex-wrap items-center gap-x-stack gap-y-snug">
          <div className="flex flex-wrap items-center gap-snug">
            <span className="text-sm text-muted">Sort</span>
            {(Object.keys(SORTS) as Sort[]).map((s) => (
              <Link key={s} href={href(s, day, showModel)} aria-current={s === sort ? "true" : undefined} className={chipClass(s === sort)}>
                {SORTS[s]}
              </Link>
            ))}
          </div>
          <div className="flex flex-wrap items-center gap-snug">
            <span className="text-sm text-muted">Day</span>
            <Link href={href(sort, null, showModel)} aria-current={!day ? "true" : undefined} className={chipClass(!day)}>
              All
            </Link>
            {days.map((d) => (
              <Link key={d} href={href(sort, d, showModel)} aria-current={d === day ? "true" : undefined} className={chipClass(d === day)}>
                {d.slice(0, 3)}
              </Link>
            ))}
          </div>
          {line ? (
            <Link
              href={href(sort, day, !showModel)}
              aria-label={showModel ? "Model line is on. Turn it off" : "Model line is off. Turn it on"}
              className={chipClass(showModel)}
            >
              Model line {showModel ? "on" : "off"}
            </Link>
          ) : null}
        </div>
      </Section>

      {groups.map((grp, i) => (
        <Section key={grp.label} id={`group-${i}`} title={grp.label}>
          <Grid kind="fields">
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
          </Grid>
        </Section>
      ))}

      <p className="max-w-measure text-sm text-muted">
        Market: the nflverse consensus <Term id="close">closing line</Term>, <Term id="no-vig">devigged</Term> in proportion, as of{" "}
        <Stamp iso={run.dataAsofUtc} /> (<Age iso={run.dataAsofUtc} />). It carries no timestamp or book, so line movement is not shown here.
      </p>
    </Page>
  );
}

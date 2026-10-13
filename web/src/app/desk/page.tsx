import { redirect } from "next/navigation";
import { Field, FieldKey } from "@/components/Field";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, PageTitle, QUIET_BUTTON_CLASS, SectionTitle } from "@/components/ui";
import { signOut } from "@/lib/auth";
import { requireUser } from "@/lib/auth/requireUser";
import { deskSlate } from "@/lib/data/queries";
import { pct, pts } from "@/lib/format";
import { candidateLabel, deskLead, NO_LEANS_SIMULATOR, SIMULATOR_CANDIDATE } from "@/lib/policy";

export const dynamic = "force-dynamic";
export const metadata = { title: "Desk", robots: { index: false } };

export default async function DeskPage() {
  const user = await requireUser();
  if (!user) redirect("/login");
  const { run, games, candidate, lines, recs } = await deskSlate();
  const model = candidate ?? "";
  // in kickoff order, like the board below
  const order = new Map(games.map((g, i) => [g.gameId, i]));
  const leans = recs
    .filter((r) => r.tier !== "pass")
    .sort((a, b) => (order.get(a.gameId) ?? 0) - (order.get(b.gameId) ?? 0));

  return (
    <>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <PageTitle
          lead={
            <span className="flex flex-wrap items-center gap-2">
              <StatusBadge status="unvalidated" label="Paper only" />
              {deskLead(candidate)}
            </span>
          }
        >
          Desk
        </PageTitle>
        <form action={async () => { "use server"; await signOut({ redirectTo: "/" }); }} className="flex items-center gap-3">
          <span className="text-sm text-ink-2">{user.email}</span>
          <button type="submit" className={QUIET_BUTTON_CLASS}>Sign out</button>
        </form>
      </div>

      {run ? (
        <>
          <section className="mt-10" aria-labelledby="leans">
            <SectionTitle id="leans">Paper leans, {candidateLabel(model)} vs market</SectionTitle>
            <Card className="mt-3">
              <div tabIndex={0} role="region" aria-label="Scrollable table" className="overflow-x-auto">
                <table className="num w-full min-w-[720px] text-left text-sm" data-desk="recommendations">
                  <thead className="text-ink-2">
                    <tr><th className="py-1 pr-4 font-normal">Game</th><th className="pr-4 font-normal">Side</th><th className="pr-4 font-normal">Model</th><th className="pr-4 font-normal">Market</th><th className="pr-4 font-normal">Edge</th><th className="pr-4 font-normal">Price</th><th className="pr-4 font-normal">Stake</th><th className="font-normal">Note</th></tr>
                  </thead>
                  <tbody>
                    {leans.length === 0 ? (
                      <tr className="border-t border-rule">
                        <td colSpan={8} className="py-2 text-ink-2" data-desk="no-leans">
                          {candidate === SIMULATOR_CANDIDATE ? NO_LEANS_SIMULATOR : "No paper leans in this run."}
                        </td>
                      </tr>
                    ) : null}
                    {leans.map((r) => {
                      const g = games.find((x) => x.gameId === r.gameId);
                      const team = r.side === "home" ? g?.homeTeamId : g?.awayTeamId;
                      return (
                        <tr key={r.recId} className="border-t border-rule align-top">
                          <td className="whitespace-nowrap py-2 pr-4">{g ? `${g.awayTeamId} at ${g.homeTeamId}` : r.gameId}</td>
                          <td className="whitespace-nowrap py-2 pr-4">{team}</td>
                          <td className="whitespace-nowrap py-2 pr-4">{pct(r.pModel, 1)}</td>
                          <td className="whitespace-nowrap py-2 pr-4">{pct(r.pMktNovig, 1)}</td>
                          <td className="whitespace-nowrap py-2 pr-4">{r.pMktNovig !== null ? pts(r.pModel - r.pMktNovig) : "–"}</td>
                          <td className="whitespace-nowrap py-2 pr-4">{r.priceAmerican !== null ? (r.priceAmerican > 0 ? `+${r.priceAmerican}` : r.priceAmerican) : "–"}</td>
                          <td className="whitespace-nowrap py-2 pr-4" data-stake>{pct(r.stakePct, 1)}</td>
                          <td className="py-2 text-ink-2">{r.passReason}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </Card>
          </section>

          <section className="mt-10" aria-labelledby="board">
            <SectionTitle id="board">Board</SectionTitle>
            <div className="mt-3"><FieldKey showModel={candidate !== null} modelLabel={candidateLabel(model)} validated={false} /></div>
            <div className="mt-3 grid gap-5 lg:grid-cols-2">
              {games.map((g) => {
                const l = lines.find((x) => x.gameId === g.gameId && x.candidate === model && x.p !== null);
                return (
                  <Field key={g.gameId} gameId={g.gameId} awayId={g.awayTeamId} homeId={g.homeTeamId} awayName={g.awayName}
                    homeName={g.homeName} kickoffUtc={g.kickoffUtc} neutral={g.neutral} pMarket={g.pMarket}
                    model={l ? { p: l.p as number, label: candidateLabel(model), validated: false } : null} />
                );
              })}
            </div>
          </section>
        </>
      ) : null}
    </>
  );
}

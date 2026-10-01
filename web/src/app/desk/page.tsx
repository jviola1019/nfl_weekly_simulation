import { redirect } from "next/navigation";
import { Field, FieldKey } from "@/components/Field";
import { StatusBadge } from "@/components/StatusBadge";
import { signOut } from "@/lib/auth";
import { requireUser } from "@/lib/auth/requireUser";
import { deskSlate } from "@/lib/data/queries";
import { pct, pts } from "@/lib/format";
import { candidateLabel } from "@/lib/policy";

export const dynamic = "force-dynamic";
export const metadata = { title: "Desk", robots: { index: false } };

const DESK_MODEL = "C2";

export default async function DeskPage() {
  const user = await requireUser();
  if (!user) redirect("/login");
  const { run, games, lines, recs } = await deskSlate();
  // in kickoff order, like the board below
  const order = new Map(games.map((g, i) => [g.gameId, i]));
  const leans = recs
    .filter((r) => r.tier !== "pass")
    .sort((a, b) => (order.get(a.gameId) ?? 0) - (order.get(b.gameId) ?? 0));

  return (
    <>
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h1 className="text-2xl font-semibold">Desk</h1>
        <form action={async () => { "use server"; await signOut({ redirectTo: "/" }); }}>
          <span className="mr-3 text-sm text-ink-2">{user.email}</span>
          <button type="submit" className="rounded-[3px] border border-rule px-2 py-1 text-sm">Sign out</button>
        </form>
      </div>
      <p className="mt-3 flex max-w-3xl flex-wrap items-center gap-2 text-ink-2">
        <StatusBadge status="unvalidated" label="Paper only" />
        Every candidate here failed to beat the closing market (nfl_games_v1). Leans are tracked on paper to test the
        prospective closing-line-value hypothesis; stakes are zero.
      </p>

      {run ? (
        <>
          <section className="mt-8" aria-labelledby="leans">
            <h2 id="leans" className="text-lg font-semibold">Paper leans, {candidateLabel(DESK_MODEL)} vs market</h2>
            <div tabIndex={0} role="region" aria-label="Scrollable table" className="mt-3 overflow-x-auto">
              <table className="num w-full min-w-[720px] text-left text-sm" data-desk="recommendations">
                <thead className="text-ink-2">
                  <tr><th className="py-1 pr-4 font-normal">Game</th><th className="pr-4 font-normal">Side</th><th className="pr-4 font-normal">Model</th><th className="pr-4 font-normal">Market</th><th className="pr-4 font-normal">Edge</th><th className="pr-4 font-normal">Price</th><th className="pr-4 font-normal">Stake</th><th className="font-normal">Note</th></tr>
                </thead>
                <tbody>
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
          </section>

          <section className="mt-10" aria-labelledby="board">
            <h2 id="board" className="text-lg font-semibold">Board</h2>
            <div className="mt-2"><FieldKey showModel modelLabel={candidateLabel(DESK_MODEL)} validated={false} /></div>
            <div className="mt-3 grid gap-5 lg:grid-cols-2">
              {games.map((g) => {
                const l = lines.find((x) => x.gameId === g.gameId && x.candidate === DESK_MODEL && x.p !== null);
                return (
                  <Field key={g.gameId} gameId={g.gameId} awayId={g.awayTeamId} homeId={g.homeTeamId} awayName={g.awayName}
                    homeName={g.homeName} kickoffUtc={g.kickoffUtc} neutral={g.neutral} pMarket={g.pMarket}
                    model={l ? { p: l.p as number, label: candidateLabel(DESK_MODEL), validated: false } : null} />
                );
              })}
            </div>
          </section>
        </>
      ) : null}
    </>
  );
}

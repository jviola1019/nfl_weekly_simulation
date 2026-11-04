import { redirect } from "next/navigation";
import { Field, FieldKey } from "@/components/Field";
import { StatusBadge } from "@/components/StatusBadge";
import { Card, DataTable, Grid, Page, PageHeader, QUIET_BUTTON_CLASS, Section } from "@/components/ui";
import { signOut } from "@/lib/auth";
import { requireUser } from "@/lib/auth/requireUser";
import { noRunContext, runContext } from "@/lib/context";
import { deskSlate } from "@/lib/data/queries";
import { pct, pts } from "@/lib/format";
import { candidateLabel, deskLead, NO_LEANS_SIMULATOR, SIMULATOR_CANDIDATE } from "@/lib/policy";

export const dynamic = "force-dynamic";
export const metadata = { title: "Desk", description: "The private desk: paper leans and the board for the published run.", robots: { index: false } };

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
    <Page>
      <PageHeader
        title="Desk"
        lead={
          <span className="flex flex-wrap items-center gap-snug">
            <StatusBadge status="unvalidated" label="Paper only" />
            {deskLead(candidate)}
          </span>
        }
        context={run ? runContext(run) : noRunContext("nothing has been ingested")}
        actions={
          <form action={async () => { "use server"; await signOut({ redirectTo: "/" }); }} className="flex items-center gap-control">
            <span className="text-sm text-ink-2">{user.email}</span>
            <button type="submit" className={QUIET_BUTTON_CLASS}>Sign out</button>
          </form>
        }
      />

      {run ? (
        <>
          <Section id="leans" title={`Paper leans, ${candidateLabel(model)} vs market`}>
            <Card>
              <DataTable
                data-desk="recommendations"
                caption={`Paper leans, ${candidateLabel(model)} against the market`}
                numeric
                minWidth="table-wide"
                columns={[
                  { key: "game", header: "Game", rowHeader: true, nowrap: true },
                  { key: "side", header: "Side", nowrap: true },
                  { key: "model", header: "Model", nowrap: true },
                  { key: "market", header: "Market", nowrap: true },
                  { key: "edge", header: "Edge", nowrap: true },
                  { key: "price", header: "Price", nowrap: true },
                  { key: "stake", header: "Stake", nowrap: true },
                  { key: "note", header: "Note" }
                ]}
                empty={<span data-desk="no-leans">{candidate === SIMULATOR_CANDIDATE ? NO_LEANS_SIMULATOR : "No paper leans in this run."}</span>}
                rows={leans.map((r) => {
                  const g = games.find((x) => x.gameId === r.gameId);
                  const team = r.side === "home" ? g?.homeTeamId : g?.awayTeamId;
                  return {
                    key: r.recId,
                    cells: {
                      game: g ? `${g.awayTeamId} at ${g.homeTeamId}` : r.gameId,
                      // a lean whose game is not on the slate keeps its stored side (Ruling R2)
                      side: team ?? r.side,
                      model: pct(r.pModel, 1),
                      market: pct(r.pMktNovig, 1),
                      edge: r.pMktNovig !== null ? pts(r.pModel - r.pMktNovig) : "–",
                      price: r.priceAmerican !== null ? (r.priceAmerican > 0 ? `+${r.priceAmerican}` : r.priceAmerican) : "–",
                      stake: <span data-stake>{pct(r.stakePct, 1)}</span>,
                      note: <span className="text-ink-2">{r.passReason}</span>
                    }
                  };
                })}
              />
            </Card>
            <p className="max-w-measure text-sm text-muted">
              Model and market are win probabilities for the side shown, in percent; the market is the no-vig nflverse close. Edge is the model minus the
              market, in percentage points. Stake is a share of the paper bankroll.
            </p>
          </Section>

          <Section id="board" title="Board">
            <FieldKey showModel={candidate !== null} modelLabel={candidateLabel(model)} validated={false} />
            <Grid kind="fields">
              {games.map((g) => {
                const l = lines.find((x) => x.gameId === g.gameId && x.candidate === model && x.p !== null);
                return (
                  <Field key={g.gameId} gameId={g.gameId} awayId={g.awayTeamId} homeId={g.homeTeamId} awayName={g.awayName}
                    homeName={g.homeName} kickoffUtc={g.kickoffUtc} neutral={g.neutral} pMarket={g.pMarket}
                    model={l ? { p: l.p as number, label: candidateLabel(model), validated: false } : null} />
                );
              })}
            </Grid>
          </Section>
        </>
      ) : null}
    </Page>
  );
}

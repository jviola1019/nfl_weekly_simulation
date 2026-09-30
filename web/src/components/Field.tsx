import Link from "next/link";
import { kickoff, pct, pts } from "@/lib/format";

/**
 * The Field (spec §4 hero): one game as a 0-100% strip, away end zone on the left,
 * home end zone on the right. The blue scrimmage marker is the no-vig market's home
 * win probability; the gold first-down line is a model's, drawn only where policy
 * allows (desk, or a candidate that passed its gates). The shaded gap is the edge.
 * Every value is also printed as text, so nothing depends on colour or hover.
 */
export interface FieldProps {
  gameId: string;
  awayId: string;
  homeId: string;
  awayName: string;
  homeName: string;
  kickoffUtc: string;
  neutral: boolean;
  pMarket: number | null;
  model?: { p: number; label: string } | null;
  href?: string;
  final?: { home: number; away: number } | null;
}

const YARD_LINES = [10, 20, 30, 40, 50, 60, 70, 80, 90];

export function Field(props: FieldProps) {
  const { awayId, homeId, awayName, homeName, pMarket, model } = props;
  const pm = pMarket === null ? null : Math.min(Math.max(pMarket, 0), 1);
  const edge = model && pm !== null ? model.p - pm : null;
  const favourite = pm === null ? null : pm >= 0.5 ? homeName : awayName;
  const summary =
    pm === null
      ? `${awayName} at ${homeName}: no market line`
      : `${awayName} at ${homeName}. Market: ${homeName} ${pct(pm)}, ${awayName} ${pct(1 - pm)}.` +
        (model ? ` ${model.label}: ${homeName} ${pct(model.p)} (${pts(edge ?? 0)} vs market).` : "");

  const title = (
    <span className="wdth-expanded font-semibold">
      {awayId} <span className="font-normal text-muted">{props.neutral ? "vs" : "at"}</span> {homeId}
    </span>
  );

  return (
    <article className="py-4" aria-label={summary} data-game={props.gameId}>
      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
        <h3 className="text-base">
          {props.href ? (
            <Link href={props.href} className="no-underline hover:underline">
              {title}
            </Link>
          ) : (
            title
          )}
          <span className="sr-only">
            {" "}
            ({awayName} at {homeName})
          </span>
        </h3>
        <p className="text-sm text-muted">
          {props.final ? `Final ${props.final.away}–${props.final.home}` : kickoff(props.kickoffUtc)}
        </p>
      </div>

      <div className="relative mt-2 h-10" role="img" aria-label={summary}>
        {/* the field: hairline yard lines, one border level */}
        <div className="absolute inset-0 rounded-[3px] border border-rule">
          {YARD_LINES.map((y) => (
            <span
              key={y}
              className="absolute top-0 bottom-0 w-px"
              style={{ left: `${y}%`, background: y === 50 ? "var(--rule)" : "var(--grid)" }}
            />
          ))}
        </div>
        {edge !== null && pm !== null && model ? (
          <span
            className="field-model absolute top-1 bottom-1"
            style={{
              left: `${Math.min(pm, model.p) * 100}%`,
              width: `${Math.abs(edge) * 100}%`,
              background: "color-mix(in srgb, var(--model) 18%, transparent)"
            }}
          />
        ) : null}
        {model ? (
          <span
            className="field-model absolute top-0 bottom-0 w-[2px] -translate-x-1/2"
            style={{ left: `${model.p * 100}%`, background: "var(--model)" }}
          />
        ) : null}
        {pm !== null ? (
          <span
            className="field-marker absolute top-0 bottom-0 w-[3px] -translate-x-1/2 rounded-[2px]"
            style={{ left: `${pm * 100}%`, background: "var(--market)", boxShadow: "0 0 0 2px var(--surface)" }}
          />
        ) : null}
      </div>

      <div className="num mt-1.5 flex justify-between text-sm">
        <span>
          <span className="text-ink-2">{awayId}</span> {pm === null ? "–" : pct(1 - pm)}
        </span>
        <span className="text-muted">
          {pm === null ? "No market line" : favourite ? `Market favours ${favourite}` : null}
          {model && edge !== null ? (
            <>
              {" · "}
              {model.label} {pts(edge)}
            </>
          ) : null}
        </span>
        <span>
          {pm === null ? "–" : pct(pm)} <span className="text-ink-2">{homeId}</span>
        </span>
      </div>
    </article>
  );
}

/** Series key shown above a list of strips. */
export function FieldKey({ showModel, modelLabel }: { showModel: boolean; modelLabel?: string }) {
  return (
    <ul className="flex flex-wrap gap-x-5 gap-y-1 text-sm text-ink-2" aria-label="Legend">
      <li className="flex items-center gap-2">
        <span className="inline-block h-4 w-[3px] rounded-[2px]" style={{ background: "var(--market)" }} aria-hidden />
        Market, no-vig home win probability
      </li>
      {showModel ? (
        <li className="flex items-center gap-2">
          <span className="inline-block h-4 w-[2px]" style={{ background: "var(--model)" }} aria-hidden />
          {modelLabel ?? "Model"}; shaded gap is the edge
        </li>
      ) : null}
    </ul>
  );
}

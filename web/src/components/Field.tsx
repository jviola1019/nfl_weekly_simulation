import Link from "next/link";
import { kickoff, pct } from "@/lib/format";
import { teamColors } from "@/lib/teams";

/**
 * The Field (Broadcast Line redesign, owner-approved 2026-10-01): each game is a
 * night-turf field between the two end zones. The line splits the field by win
 * chance, so each team's side is its probability of winning: the away team owns the
 * left share, the home team the right. Blue is the no-vig market; gold is the model
 * (validated, or the labelled research line). The hatched band is the gap. Every
 * value is printed as text beside a colour swatch, so nothing depends on colour.
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
  model?: { p: number; label: string; validated: boolean } | null;
  href?: string;
  final?: { home: number; away: number } | null;
  size?: "strip" | "hero";
}

const YARD_LINES = [10, 20, 30, 40, 50, 60, 70, 80, 90];
const clamp = (p: number) => Math.min(Math.max(p, 0), 1);

/** Plain-language gap between the model and the market (home probabilities). */
export function gapText(pm: number, pModel: number, awayId: string, homeId: string): string {
  const gap = (pModel - pm) * 100;
  if (Math.abs(gap) < 3) return "Model within 3 points of the market";
  const lean = gap > 0 ? homeId : awayId;
  const flips = pm >= 0.5 !== pModel >= 0.5;
  return `Model is ${Math.abs(gap).toFixed(1)} points more on ${lean}${flips ? " and makes it the favourite" : ""}`;
}

export function Field(props: FieldProps) {
  const { awayId, homeId, awayName, homeName, model } = props;
  const hero = props.size === "hero";
  const pm = props.pMarket === null ? null : clamp(props.pMarket);
  const pmod = model ? clamp(model.p) : null;
  const away = teamColors(awayId);
  const home = teamColors(homeId);
  const xMarket = pm === null ? null : (1 - pm) * 100;
  const xModel = pmod === null ? null : (1 - pmod) * 100;
  const summary =
    pm === null
      ? `${awayName} at ${homeName}: no market line`
      : `${awayName} at ${homeName}. Market: ${awayName} ${pct(1 - pm)}, ${homeName} ${pct(pm)}.` +
        (model && pmod !== null ? ` ${model.label}${model.validated ? "" : " (unvalidated)"}: ${awayName} ${pct(1 - pmod)}, ${homeName} ${pct(pmod)}.` : "");

  const title = (
    <span className="flex items-center gap-2.5">
      <TeamChip id={awayId} />
      <span className="wdth-expanded text-[22px] font-extrabold leading-none">{awayId}</span>
      <span className="text-sm text-muted">{props.neutral ? "vs" : "at"}</span>
      <TeamChip id={homeId} />
      <span className="wdth-expanded text-[22px] font-extrabold leading-none">{homeId}</span>
    </span>
  );

  return (
    <article
      className={hero ? "" : "rounded-[6px] border border-rule bg-surface px-4 pb-3.5 pt-4"}
      aria-label={summary}
      data-game={props.gameId}
    >
      {hero ? null : (
        <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1">
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
          <p className="num text-sm text-muted">{props.final ? `Final ${props.final.away}–${props.final.home}` : kickoff(props.kickoffUtc)}</p>
        </div>
      )}

      <div
        className={`${hero ? "h-[150px]" : "mt-3 h-[64px] sm:h-[86px]"} flex overflow-hidden rounded-[4px] border border-[color:var(--turf-edge)]`}
        role="img"
        aria-label={summary}
      >
        <EndZone id={awayId} colors={away} side="away" hero={hero} />
        <div className="relative flex-1" style={{ backgroundImage: "var(--turf-stripes)", backgroundSize: "100% 100%" }}>
          {YARD_LINES.map((y) => (
            <span key={y}>
              <span
                className="absolute top-0 bottom-0 w-[2px] -translate-x-1/2"
                style={{ left: `${y}%`, background: y === 50 ? "var(--turf-line-mid)" : "var(--turf-line)" }}
              />
              <span
                className={`num wdth-condensed absolute -translate-x-1/2 font-bold ${hero ? "bottom-1.5 text-[11px] sm:bottom-2.5 sm:text-xl" : "bottom-1 hidden text-xs sm:block"}`}
                style={{ left: `${y}%`, color: "var(--turf-number)" }}
                aria-hidden
              >
                {y <= 50 ? y : 100 - y}
              </span>
            </span>
          ))}
          {xModel !== null && xMarket !== null ? (
            <svg className="field-model absolute top-0 h-full" style={{ left: `${Math.min(xMarket, xModel)}%`, width: `${Math.abs(xModel - xMarket)}%` }} aria-hidden>
              <defs>
                <pattern id={`hatch-${props.gameId}`} width="7" height="7" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
                  <rect width="7" height="7" fill="var(--field-model)" fillOpacity="0.16" />
                  <line x1="0" y1="0" x2="0" y2="7" stroke="var(--field-model)" strokeOpacity="0.62" strokeWidth="2" />
                </pattern>
              </defs>
              <rect width="100%" height="100%" fill={`url(#hatch-${props.gameId})`} />
            </svg>
          ) : null}
          {xModel !== null ? (
            <span
              className="field-model absolute -top-px -bottom-px w-[5px] -translate-x-1/2"
              style={{ left: `${xModel}%`, background: "var(--field-model)", boxShadow: "0 0 0 1px var(--field-outline)" }}
            />
          ) : null}
          {xMarket !== null ? (
            <span
              className="field-marker absolute -top-px -bottom-px w-[5px] -translate-x-1/2"
              style={{ left: `${xMarket}%`, background: "var(--field-market)", boxShadow: "0 0 0 1px var(--field-outline)" }}
            />
          ) : null}
        </div>
        <EndZone id={homeId} colors={home} side="home" hero={hero} />
      </div>

      {hero ? null : <Readout pm={pm} pmod={pmod} awayId={awayId} homeId={homeId} model={model ?? null} />}
    </article>
  );
}

function TeamChip({ id }: { id: string }) {
  const c = teamColors(id);
  return <span aria-hidden className="inline-block h-[26px] w-2.5 rounded-[2px]" style={{ background: c.primary, boxShadow: `inset -3px 0 0 ${c.accent}` }} />;
}

function EndZone({ id, colors, side, hero }: { id: string; colors: ReturnType<typeof teamColors>; side: "away" | "home"; hero: boolean }) {
  return (
    <div
      className={`${hero ? "w-[58px]" : "w-[26px] sm:w-[46px]"} flex shrink-0 items-center justify-center`}
      style={{
        background: colors.primary,
        [side === "away" ? "borderRight" : "borderLeft"]: `${hero ? 3 : 2}px solid var(--turf-edge)`
      }}
    >
      <span
        className={`wdth-expanded ${hero ? "text-[22px]" : "hidden text-[15px] sm:inline"} font-extrabold tracking-[0.14em]`}
        style={{ writingMode: "vertical-rl", transform: side === "away" ? "rotate(180deg)" : undefined, color: colors.ink }}
        aria-hidden
      >
        {id}
      </span>
    </div>
  );
}

function Readout({
  pm,
  pmod,
  awayId,
  homeId,
  model
}: {
  pm: number | null;
  pmod: number | null;
  awayId: string;
  homeId: string;
  model: FieldProps["model"] | null;
}) {
  const swatch = (v: string, h: string) => <span aria-hidden className={`inline-block w-1 ${h}`} style={{ background: v }} />;
  return (
    <div className="num mt-2.5 grid grid-cols-2 items-end gap-x-3 gap-y-2 sm:grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)]">
      <div className="flex flex-col gap-0.5">
        <span className="flex items-baseline gap-2">
          <span className="self-center">{swatch("var(--field-market)", "h-5")}</span>
          <span className="wdth-expanded text-[26px] font-extrabold leading-none sm:text-[28px]">{pm === null ? "–" : pct(1 - pm)}</span>
          <span className="text-[13px] text-muted">{awayId}</span>
        </span>
        {pmod !== null ? (
          <span className="flex items-center gap-2 whitespace-nowrap text-sm font-semibold text-ink-2">
            {swatch("var(--field-model)", "h-3.5")}
            {pct(1 - pmod)} model
          </span>
        ) : null}
      </div>
      <p className="order-last col-span-2 pb-1 text-[13px] leading-snug text-ink-2 sm:order-none sm:col-span-1 sm:max-w-[250px] sm:text-center">
        {pm === null ? "No market line" : pmod !== null ? gapText(pm, pmod, awayId, homeId) : `${pm >= 0.5 ? homeId : awayId} favoured by the market`}
        {model && !model.validated ? <span className="sr-only"> (unvalidated research model)</span> : null}
      </p>
      <div className="flex flex-col items-end gap-0.5">
        <span className="flex items-baseline gap-2">
          <span className="text-[13px] text-muted">{homeId}</span>
          <span className="wdth-expanded text-[26px] font-extrabold leading-none sm:text-[28px]">{pm === null ? "–" : pct(pm)}</span>
          <span className="self-center">{swatch("var(--field-market)", "h-5")}</span>
        </span>
        {pmod !== null ? (
          <span className="flex items-center gap-2 whitespace-nowrap text-sm font-semibold text-ink-2">
            model {pct(pmod)}
            {swatch("var(--field-model)", "h-3.5")}
          </span>
        ) : null}
      </div>
    </div>
  );
}

/** Series key shown above a list of fields. */
export function FieldKey({ showModel, modelLabel, validated }: { showModel: boolean; modelLabel?: string; validated?: boolean }) {
  return (
    <ul className="flex flex-wrap gap-x-5 gap-y-1.5 text-sm text-ink-2" aria-label="Legend">
      <li className="flex items-center gap-2">
        <span className="inline-block h-5 w-[5px]" style={{ background: "var(--field-market)" }} aria-hidden />
        Market, no-vig
      </li>
      {showModel ? (
        <>
          <li className="flex items-center gap-2">
            <span className="inline-block h-5 w-[5px]" style={{ background: "var(--field-model)" }} aria-hidden />
            {modelLabel ?? "Model"}
            {validated ? "" : ", unvalidated"}
          </li>
          <li className="flex items-center gap-2">
            <svg width="22" height="20" aria-hidden>
              <defs>
                <pattern id="hatch-key" width="7" height="7" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
                  <rect width="7" height="7" fill="var(--field-model)" fillOpacity="0.2" />
                  <line x1="0" y1="0" x2="0" y2="7" stroke="var(--field-model)" strokeOpacity="0.7" strokeWidth="2" />
                </pattern>
              </defs>
              <rect width="22" height="20" fill="url(#hatch-key)" stroke="var(--field-model)" strokeOpacity="0.8" />
            </svg>
            Gap between them
          </li>
        </>
      ) : null}
    </ul>
  );
}

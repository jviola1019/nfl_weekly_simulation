#!/usr/bin/env bash
# The testing program's weekly steps (HYPOTHESES.md §14-15), for one NFL week of 2026:
#   run:   the production model (run_week.R) at a decision point, then a snapshot; the run's outputs are copied to
#          <store>/run_<UTC stamp>/ because the next run overwrites artifacts/ and adds a new bundle
#   snap:  venue_snapshot.R and props_snapshot.R (raw responses and per-venue prices to <store>/raw, which must stay
#          private; aggregates to <store>/out)
#   fetch: after the week, Kalshi's settlements and hourly candles for the week's games (keyless)
#   score: score_week.R on everything above
# Usage, from anywhere:
#   weekly_prospective.sh <mode> <production_checkout> <research_checkout> <store> <week> [<decision stamps for score>]
# The production checkout runs run_week.R at its own commit; the research checkout holds these scripts. Rscript must be
# on PATH. A failed step is logged and the next step still runs.
set -u
mode=$1; prod=$2; res=$3; store=$4; week=$5; decision=${6:-}
H=reports/2026-10-29/hypotheses; F=reports/2026-10-28/feasibility
stamp=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$store/raw" "$store/out" "$store/logs"
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$store/logs/steps.log"; }
snap() {
  (cd "$res" && Rscript "$H/venue_snapshot.R" "$store/out/venues" "$store/raw" > "$store/logs/venues_$stamp.log" 2>&1); log "venue snapshot exit=$?"
  (cd "$res" && Rscript "$H/props_snapshot.R" "$store/out/props" "$store/raw" > "$store/logs/props_$stamp.log" 2>&1); log "props snapshot exit=$?"
}
case "$mode" in
  run)
    (cd "$prod" && Rscript run_week.R "$week" 2026 > "$store/logs/run_week_$stamp.log" 2>&1); rc=$?; log "run_week.R $week exit=$rc"
    if [ $rc -eq 0 ]; then
      b=$(ls -d "$prod"/bundles/2026-w$(printf %02d "$week")-sim-* 2>/dev/null | sort | tail -1)
      d="$store/run_$stamp"; mkdir -p "$d"
      cp "$b"/game_predictions.json "$b"/score_distributions.json "$b"/manifest.json "$b"/source_status.json "$d"/ 2>/dev/null
      cp "$prod"/artifacts/baseline_games.csv "$prod"/artifacts/baseline_props.csv "$d"/ 2>/dev/null
      log "saved $(basename "$b") to $d"
    fi
    snap ;;
  snap) snap ;;
  fetch)
    series="$store/series"; mkdir -p "$series"
    for s in KXNFLGAME KXNFLSPREAD KXNFLTOTAL KXNFLTEAMTOTAL KXNFLTD KXNFLREC KXNFLRECYDS KXNFLRSHYDS KXNFLPASSYDS KXNFLPASSTDS KXNFLPASSATT KXNFLPASSCOMP KXNFLRSHATT KXNFLPASSINT KXNFLRRYDS; do
      : > "$series/${s}_p1__20260101T000000Z.json.gz"   # kalshi_settled.R takes its series from such names
    done
    from=${FROM:?set FROM=YYYY-MM-DD}; to=${TO:?set TO=YYYY-MM-DD}
    (cd "$res" && Rscript "$F/kalshi_settled.R" "$store/kalshi" "$series" --from="$from" --to="$to" > "$store/logs/settled_$stamp.log" 2>&1); log "kalshi_settled exit=$?"
    (cd "$res" && Rscript "$F/kalshi_candles.R" "$store/kalshi" "$store/kalshi/kalshi_settled.csv.gz" > "$store/logs/candles_$stamp.log" 2>&1); log "kalshi_candles exit=$?" ;;
  score)
    # the earliest saved run is the decision run; earlier weeks' settlements feed props_frame.R's dispersion fit: weeks
    # 1-7 from the feasibility study, and every week this store's parent holds (wWW/kalshi; props_frame.R keeps only the
    # weeks before the scored one)
    run=$(ls -d "$store"/run_* 2>/dev/null | sort | head -1)
    early="$res/$F/props/kalshi_settled_w1-5.csv.gz,$res/$F/props/kalshi_settled.csv.gz"
    for f in "$(dirname "$store")"/w[0-9][0-9]/kalshi/kalshi_settled.csv.gz; do
      [ -f "$f" ] && [ "$f" != "$store/kalshi/kalshi_settled.csv.gz" ] && early="$early,$f"
    done
    dflag=""; [ -n "$decision" ] && dflag="--decision=$decision"
    (cd "$res" && Rscript "$H/score_week.R" "$store/score" --week="$week" --run="$run" --snaps="$store/raw" $dflag \
      --settled="$early,$store/kalshi/kalshi_settled.csv.gz" --candles="$store/kalshi/kalshi_candles.csv.gz" > "$store/logs/score_$stamp.log" 2>&1); log "score_week exit=$?" ;;
  *) echo "mode must be run, snap, fetch or score" >&2; exit 2 ;;
esac

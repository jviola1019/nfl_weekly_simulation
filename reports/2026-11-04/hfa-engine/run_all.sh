#!/usr/bin/env bash
# The three engine runs of 2024 week 15, one per home-field estimator, one after another, each with a fresh HOME
# (so each builds its own calibration cache). Run from the repository root of the commit under test:
#   bash reports/2026-11-04/hfa-engine/run_all.sh <log dir> <scratch dir for the three HOMEs>
# Each run takes about 20 minutes. The runs rewrite the tracked audit tables, which are restored after each.
set -u
T=${1:?log dir}; S=${2:?scratch dir}
D=$(cd "$(dirname "$0")" && pwd)
for est in league strength_free team_margin; do
  H="$S/home-hfa-$est"; rm -rf "$H"; mkdir -p "$H"
  echo "$(date -u +%FT%TZ) start $est" >> "$T/runs.time"
  HFA_EST=$est HOME="$H" R_USER="$H" Rscript "$D/run.R" 15 2024 > "$T/run_$est.log" 2>&1
  echo "$(date -u +%FT%TZ) end $est exit $?" >> "$T/runs.time"
  git checkout -q -- artifacts/baseline_games.csv artifacts/baseline_props.csv 2>/dev/null
done

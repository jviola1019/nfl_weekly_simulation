#!/usr/bin/env bash
# Reproduce the A3 research (reports/2026-10-28/a3-research) from scratch and compare every output with the
# committed file. Run from the repository root with the D1 branch fetched (late-movement reads its archive):
#   bash reports/2026-10-28/feasibility/rerun_research.sh <scratch_dir> <git ref of D1>
# Writes <scratch_dir>/rerun_compare.csv (file, identical, max_abs_diff, note) and prints it. The Wikipedia fetch
# (flex-fetch.mjs) is not re-run: it reads the live pages, and data/wikipedia_revisions.json pins the revisions.
set -euo pipefail
OUT="$1"; D1REF="$2"
R=reports/2026-10-28/a3-research
mkdir -p "$OUT"
git show "${D1REF}:backtest/data/odds_archive/espn_game_odds.csv" > "$OUT/espn_game_odds.csv"
Rscript "$R/scripts/flex-games.R" "$R/data/flex-bullets.json" backtest/data/games.csv "$OUT/flex-games.csv" > "$OUT/log-flex-games.txt" 2>&1
Rscript "$R/scripts/research-table.R" "$OUT/research-table.rds" > "$OUT/log-table.txt" 2>&1
Rscript "$R/scripts/a3-research.R" cluster "$OUT/research-table.rds" "$OUT" > "$OUT/log-cluster.txt" 2>&1
Rscript "$R/scripts/a3-research.R" late "$OUT/research-table.rds" "$OUT" "$R/data/flex-games.csv" > "$OUT/log-late.txt" 2>&1
Rscript "$R/scripts/late-movement.R" "$OUT/espn_game_odds.csv" "$R/data/flex-games.csv" "$OUT/late_movement.csv" > "$OUT/log-movement.txt" 2>&1
Rscript "$R/scripts/a3-research.R" joint "$OUT/research-table.rds" "$OUT" 1000 > "$OUT/log-joint.txt" 2>&1
Rscript "$R/scripts/a3-research.R" joint_linear "$OUT/research-table.rds" "$OUT" 1000 > "$OUT/log-joint-linear.txt" 2>&1
Rscript "$R/scripts/a3-research.R" power "$OUT/research-table.rds" "$OUT" 20 > "$OUT/log-power.txt" 2>&1
Rscript "$R/scripts/s4-null-diagnostic.R" "$OUT/s4-null-diagnostic.csv" 2000 > "$OUT/log-diagnostic.txt" 2>&1
Rscript "$R/scripts/a3-research.R" s4 "$OUT/research-table.rds" "$OUT" 5 > "$OUT/log-s4.txt" 2>&1
# a script file, not Rscript -e: the inline form crashed (exit 139) on Windows in the first rerun
Rscript reports/2026-10-28/feasibility/compare_research.R "$OUT" "$OUT/rerun_compare.csv"

#!/usr/bin/env bash
# Starts prospective_dispatch.R every 15 minutes, just after each quarter hour, for as long as this shell lives. The
# Windows scheduled task in register_prospective_task.ps1 does the same without a shell. Both can run at once: the
# dispatcher's lock lets one start through at a time, and a finished step is never run again.
# Usage: prospective_loop.sh <store> <checkout for run_week.R> <research checkout> [first week] [last week]
store=$1; prod=$2; res=$3; first=${4:-9}; last=${5:-18}
mkdir -p "$store/logs"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) loop started (weeks $first-$last, run_week.R from $prod, scripts from $res)" >> "$store/logs/dispatch.log"
while true; do
  Rscript "$res/reports/2026-10-29/hypotheses/prospective_dispatch.R" --store="$store" --prod="$prod" --res="$res" \
    --first-week="$first" --last-week="$last" >> "$store/logs/loop.log" 2>&1
  sleep $(( 900 - $(date -u +%s) % 900 + 5 ))
done

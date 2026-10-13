# Plan 1b-1 evidence (2026-10-01)

These are the measurements behind the "Measured baseline" table in `docs/superpowers/plans/2026-10-01-phase1b-1-explicit-model.md`. Each script's output is saved next to it as `<script>.out.txt`; they were run on 2026-10-01 from the repo root on Windows with the renv library.

| Script | Reads | Finding |
|---|---|---|
| `m22_terms.R` | a `run_logs/games_ready_*.rds` (here `games_ready_20260929_224207.rds`, a local run of 2024 week 15) | **M22, M22b.** The simulated means equal drives × points per drive (+ home field) bit for bit, and the turnover term is non-finite in every game. The 13 named terms (every term except turnover and weather, which enter after `total_mu`) decompose the legacy chain's total exactly. The term sizes, and the gap between the legacy total and the simulated total. |
| `m22b_predict.R` | the same file | **M22b.** Predicted change in score SDs when the SD blend uses the simulated total. |
| `m23_rest.R` | nflverse schedules 2023, 2024 and 2026 | **M23.** Short-rest counts for 2024 week 15 when rest is measured from the week's first kickoff vs each team's own game; nflverse `home_rest`/`away_rest` vs own-date rest; the rest columns for unplayed 2026 games. |
| `m24_neutral.R` | nflverse schedules 2015–2024 and 2026 | **M24.** The engine's neutral-site column names are absent while `location` marks 53 neutral games; the predicted change in league and team home-field advantage. |

**`dry-run/`.** Checks that the plan's code works as written:
- `apply_plan.R <plan.md> <worktree> <tasks>` applies the plan's code blocks verbatim to a worktree of `main`, and stops if any replacement anchor does not match exactly once.
- `analyze.R <pre-fix games_ready.rds> <worktree after Tasks 1-3> <worktree after Tasks 1-7>` compares the engine runs with the plan's predictions. It needs `scripts/golden_master.R compare 15 2024 reports/2026-09-29/golden-master/2024-w15` to have been run in each worktree.
- `compare_tasks1-3.out.txt` and `compare_tasks1-7.out.txt` are those golden-master compares on Windows; `analyze.out.txt` is the comparison.

**Data limits:**
- No script reads the 2025 season, which is the sealed holdout.
- The `games_ready` file is gitignored. Every `NFLsimulation.R` run writes one, including `scripts/golden_master.R record 15 2024 <dir>`, so `m22_terms.R` and `m22b_predict.R` can be re-run on a fresh record.

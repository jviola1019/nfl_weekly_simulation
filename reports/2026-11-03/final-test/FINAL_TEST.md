# Final end-to-end test of the integration (PR #231), 2026-11-03

**What was tested.** The integration branch as one system:
- the weekly run, `Rscript run_week.R` with no arguments, so the week comes from the schedule;
- its web bundle and both audit tables;
- the local app on that bundle (`npm run local`);
- the project's Playwright suite against the app.

Each run used a clean detached checkout, a fresh HOME and the renv package set (dplyr 1.1.4).

**Result.** The test found six defects, five in the first run and one in the app's charts. All six are fixed, each with a test that failed before its fix.
- **The rerun on the fixed head:** 23 of 23 checks pass.
- **The app:** every page serves with no console error.
- **The Playwright suite on the real run:** 135 of 135 pass.
- **One new modelling finding** (home field measures team strength) is recorded for the term-admission backtest, not patched.

## 1. First run: `a639552`, 2026-11-03 04:46–05:06Z

- **Week:** `Auto-resolved 2026 week 9 (15 games, first kickoff Thu 2026-11-05 20:15 ET)`. That is right for a Tuesday after Monday Night Football (#215).
- **Badge:** Injuries FULL, Weather FULL, Market Data PARTIAL ("2 game(s) without market odds"), Calibration spline (diagnostic only).
  - Weather is FULL because #219 gives real coordinates to week 7's three fallback venues.
  - The two games without a line, ARI at SEA and TB at CHI, had no nflverse line at run time. Both were posted by 05:30Z.
- **Defense rankings:** applied (#216). No "unavailable" or "NEUTRAL" line.
- **Props:** 606 rows over all 15 games.
- **Bundle:** `2026-w09-sim-20261103T050629Z`, QA passed.
- **`final_check.R`:** 20 PASS and 2 FAIL (`out/check_first_run_a639552.csv`). Both FAILs are the no-market defect below:
  - **A3:** the bundle's C3 is not the audit table's shrunk blend for the two games without a line.
  - **A5:** the audit table has a market and a bet for both games.

## 2. Defects found, and their fixes (commits on `integration/2026-11-02`)

| # | Defect | Fix | Test (failures before the fix) |
|---|---|---|---|
| 1 | **A game without a market line was priced and bet in `artifacts/baseline_games.csv`.** `attach_market_probs()` fills it with the model's probability, as the blend's input only. The comparison took that fill for a market: ARI at SEA at the model's own −337/+337 ("Bet ARI moneyline"), and TB at CHI at −111/+111 ("Bet CHI moneyline", raw Kelly 0.053), where nflverse later listed CHI −285. The bundle and the app were never affected. | `de42950`: the snapshot passes no market where `market_available` is FALSE. The table gives such a game no price, `prob_source` "none", the unshrunk blend and "No Play". | `test-comparison-no-market.R` (10) |
| 2 | **An injury season that failed to download dropped out unflagged.** One empty season beside loaded ones read "full"; all empty read "unavailable" with no cause. This is the silent failure behind the golden-master misdiagnosis of 2026-11-03. | `6006ac8`: an empty season is downloaded again past nflreadr's memoised failure (2 retries, 3 s apart). One that stays empty is "partial", with nflreadr's warning as the cause. | `test-injury-load.R` (8) |
| 3 | **The Rams had no time zone in the game model** (`LAR` where schedules use `LA`, the game model's half of audit P9). Travel was 0 for LA at WAS this week. Travel is not an admitted term, so no simulated output moved. | `08149e7` | `test-team-tz.R` (2) |
| 4 | **The Props page called fixed defects open.** It listed P1–P13 as open and checkpoint A5 as undecided. | `16ac64e`: it lists what is fixed and what is open (P6–P8, P11), the running `nfl_props_v1` test of the `4c1c377` module, and A5's rule. | `web/src/test/pages/props.test.tsx` |
| 5 | **The weekly program marked a step missed after three failed starts, however far off its deadline.** Week 9's `preclose_predict` failed three times in 30 minutes on a DNS outage, with the PC moving in and out of standby. It was marked missed 54 hours before its deadline. | `2991757` (merged as `63807cb`): three tries at successive starts, then hourly until the deadline, at most 12. The step was rerun at 20:30Z: "15 predictions written, before the week's first kickoff". | `test-prospective-dispatch.R` (2) |
| 6 | **Two gridlines of the total chart carried the same label** (found in the app, section 4). | `e45f4be`: `pctTicks()` | `ScoreDistributionChart.test.tsx` (2) |

**Fix 1 on the run's own data.** A replay put the first run's saved slate (`run_logs/final_*.rds`) through the fixed code, with each game's lines as the run saw them (rebuilt from the first run's `baseline_games.csv`). The replay script is not committed, because it reads that run's private outputs.
- **The 13 games with a line:** every compared column is unchanged (market probability and prices, source, blend, shrunk blend, EV, pick, pick type, recommendation, Kelly, market pick).
- **The two games without a line:** no market, "none", "No Play". Their shrunk probability equals the bundle's C3 (0.7681 and 0.5513).

**Recorded, not fixed:**
- **A package mismatch.** `renv.lock` pins TMB 1.9.17 with glmmTMB 1.1.13, whose Windows binary was built with TMB 1.9.19 and warns at load. The GLMM feeds only the unadmitted `glmm` term. A lock change is an owner decision, and the `nfl_props_v1` package set is frozen.
- **A harmless warning.** `build_res_blend()` warns that the calibration backtest's per-game table has no `game_type` key. The collapse uses `game_id`, which is unique, and the warning predates the integration.

## 3. Rerun on the fixed head: `63807cb`, 2026-11-03 20:31–20:52Z

- **Week:** the same resolution, 2026 week 9.
- **Badge:** Injuries FULL, Weather FULL, Market Data FULL. nflverse had posted every line by then.
- **Defense rankings:** applied.
- **Props:** 606 rows over 15 games, none priced or staked. The module requires a market quote, and none is captured.
- **Bundle:** `2026-w09-sim-20261103T205214Z`, `code_git_sha 63807cb`, `code_dirty FALSE`, QA passed.
- **`final_check.R`:** 23 PASS, 0 FAIL, 3 NOTE (`out/check_rerun_63807cb.csv`). The notes are the badge, the prop types and A4 (gaps to the market over 10 points): JAX at BAL's simulated total, 52, against the market's 40.5.

**On real data:**
- **The Madrid game:** CIN at ATL (`MAD01`, "Neutral") is `neutral: true` in the bundle, with a home-field term of exactly 0. The app shows "Cincinnati Bengals vs Atlanta Falcons".
- **The Rams:** LA at WAS now logs the Rams' −0.4 travel term (not admitted).
- **Roofs:** the two roofs nflverse leaves blank are omitted, not guessed. They are the Bernabéu, and Lucas Oil Stadium's retractable roof.
- **The golden master** (CI, every first-parent commit against the one before): "no differences" for each of the five fixes. The 2024 week-15 reference stands.

**The simulator against the market this week** (`out/games_week9_rerun.csv`):
- Its win probabilities differ from the market's by 1.3 points on average, 2.6 at most (JAX at BAL), after the 70% shrinkage.
- Its median margins are more extreme than the market's spread in 13 of 15 games, by 1.75 points on average.
- Its totals average 2.0 points above the market's, and are higher in 9 of 15 games.

**New finding, not fixed: home field measures team strength.**
- **The cause:** `team_hfa_table()` (`R/schedule_context.R`) sets a team's home field to its mean home margin, shrunk toward the league value with weight n/(n+60). A home margin is mostly team strength, which the `base` term already carries.
- **The effect this week:** Washington's home field is −1.27 points (a home *dis*advantage) and New England's is +3.67.
- **Why it matters:** `hfa` is one of the two admitted mean terms. It fits the over-extreme margins above.
- **Its age:** the estimator dates from the original model (`f581004`). #223 moved it but did not change it.
- **The fix to test:** half the difference between a team's home and away margins, which cancels strength, still shrunk toward the league value. It changes every simulated output, so it is a term-admission question for the walk-forward backtest (M22), not a patch.

## 4. The final window: the local app

`npm run local` on the rerun's bundle plus the backtest bundle (`scripts/write_backtest_bundle.R`, QA ok):
- a new PostgreSQL cluster, migrations applied, both bundles published;
- **SQL data checks: 18 checks, 0 errors, 0 warnings;**
- `next build`, then served at http://127.0.0.1:3000.

**Every public page** (`app_shots.mjs`, `out/app_pages.json`): 24 page views, all HTTP 200, with 0 console errors.
- **Pages:** home, all 15 game pages, props, evidence, methodology, data health and the desk.
- **Variants:** home at 390 px and in the dark theme, and a game page at 390 px dark.
- **Charts:** every game page drew both of its distribution charts.
- **The desk:** without a session it redirects to sign-in.

**What it shows:**
- **This week:** "Week 9", run `2026-w09-sim-20261103T205214Z`, data as of 20:52 UTC, games Thu Nov 5 – Mon Nov 9.
  - **Tiles:** 15 games; 0 of 15 where the model picks a different favourite; the largest model–market gap is 2.6 pts (JAX at BAL).
  - **Cards:** one field per game with kickoff in ET, each "within 3 points of the market".
- **A game page** (JAX at BAL): JAX 80% / BAL 20% at the no-vig market, Thu Nov 5, 8:15 PM ET.
  - **Moneyline:** BAL 19.6% market against 22.2% simulator.
  - **Margin distribution:** median JAX by 6, with 90% between JAX by 29 and BAL by 17.
  - **Total distribution:** median 52 points, with 90% between 29 and 82.
- **Props:** nothing priced, with the corrected explanation (fix 4).
- **Evidence:** "No model or blend beat the no-vig closing market in the pre-registered test". 570 Confirm games; market Brier 0.2098; the closest candidate is +0.02% (−0.38% to +0.45%). Every control passed, and the 2025 holdout is sealed.
- **Data health:** the run from code `63807cbd`, QA passed, all four sources ok, both bundles in the ingest log.

**Defect 6, found on the game pages and fixed** (`e45f4be`):
- **What it was:** the total chart's y-axis read 0%, 0.5%, 1%, 2%, 2%, 3%. With ticks every 0.5% (this total peaks at 2.544%), 1.5% and 2.5% rounded to whole percents, so the top gridline said 3% at 2.5%.
- **The fix:** `pctTicks()` gives each tick the step's decimals. The live axis now reads 0%, 0.5%, 1.0%, 1.5%, 2.0%, 2.5%.
- **Test:** `ScoreDistributionChart.test.tsx`, which failed before the fix.
- **The other charts are clean:** a scan of every chart on the evidence page found repeated labels only where an x and a y axis share values.

## 5. The Playwright suite against the real run

`E2E_BASE_URL=http://127.0.0.1:3000 E2E_SIM_BUNDLE=<the rerun's bundle> npx playwright test --grep-invert @parity`, with a throwaway desk user seeded into the local database. `@parity` compares offline against online, so it stays in CI.

- **First pass: 128 passed and 7 failed.** All 7 came from fixture data, not from the app:
  - the accessibility and layout spec visits `PUBLIC_PAGES`'s fixed `/games/2026_04_DEN_SF`, which is a 404 outside the weekly fixture (6 failures, at 3 widths × 2 themes);
  - the desk spec expects paper leans, which a simulator run never has. The desk shows its "No paper leans in a simulator run" message by design.
- **Fixed in `08c8410`:** with `E2E_SIM_BUNDLE` set, `PUBLIC_PAGES` uses the run's own first game and the desk spec checks the simulator's message with zero stake cells. Unset (CI's main pass), both are unchanged.
- **Second pass: 135 passed, 0 failed.** That includes `@sim`, which holds each page's probabilities to the bundle's at display precision, plus axe and overflow at three widths in both themes, security headers, desk sign-in, no public stakes, ID leaks, reduced motion and offline.

## Files

- `final_check.R`: the log, bundle, schedule and audit-table checks. `Rscript final_check.R <checkout> <run log> <git sha> [<out dir>]`; it exits 1 on a FAIL.
- `app_shots.mjs`: a screenshot and the text of every public page, including each game page. `node app_shots.mjs <web dir> <base url> <bundle dir> <out dir>`.
- `out/`:
  - both check results (`check_first_run_a639552.csv`, `check_rerun_63807cb.csv`);
  - the rerun's per-game table (`games_week9_rerun.csv`, nflverse consensus lines and the simulator);
  - the page summary (`app_pages.json`).
- The screenshots are not committed: they are reproducible from the bundle with `app_shots.mjs`.

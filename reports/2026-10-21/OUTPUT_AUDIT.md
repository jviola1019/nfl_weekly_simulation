# Output audit: 2026 week 7 (main 4c1c377)

Track V2 of the plan revised on 2026-10-20.

**The run.** `HOME=<empty dir> Rscript run_week.R 7 2026` in a clean, detached worktree at main `4c1c377`.
- It started at 2026-10-21T04:27:19Z and finished at 04:56:20Z: 29 minutes, exit 0.
- Bundle: `bundles/2026-w07-sim-20261021T045617Z`, `QA: passed`, 14 games, 570 player props.

Every figure below comes from that run's console log, its bundle files, the nflverse 2026 schedule (`nflreadr::load_schedules(2026)`, read on 2026-10-21), or the manifest of odds-capture run 39499941009.

## Checks that pass

- **Games.** All 14 week-7 games are present, matching the nflverse schedule's 14.
- **Kickoffs (ET).** They run from Thu 10-22 20:15 to Mon 10-26 20:15. PIT at NO is in Paris (Stade de France, `PAR00`, Sun 09:30 ET). The schedule's `location` is `Neutral`, and the bundle's `neutral` is `true`.
- **Probabilities.** No value lies outside (0, 1). Both the market (C0) and the simulator (C3) are present for every game.
- **Data quality.** Overall HIGH, with injuries FULL and market FULL.
- **Provenance.** `code_git_sha` is 4c1c377 and `code_dirty` is false.
- **C3 against C0.** After the production blend and the 0.70 shrinkage, the mean absolute gap is 0.60 points and the largest is 1.65 points (DAL at PHI).

## Findings

| # | Finding | Evidence | Kind | Fix (track) |
|---|---|---|---|---|
| F1 | Every opponent-defense multiplier is 1.0. The log prints "Defense rankings unavailable: In argument: `pass_def_multiplier = dplyr::if_else(...)`" for all 14 games. | run log | correctness | P13, PR #216 |
| F2 | The Tuesday odds capture fetched no ESPN game odds. ESPN's default scoreboard still listed week 6, with all 14 games final, so the 216 h horizon selected nothing. | run 39499941009: 193 manifest rows (191 Kalshi market pages, 1 Kalshi series, 1 ESPN scoreboard), 0 `espn_game_odds` | correctness | A0 follow-up: the capture also reads the next week by number. ESPN rejects a `dates=` range with HTTP 400. A live ESPN-only capture at 2026-10-21 05:09Z fetched 15 of 15 game odds. PR to follow. |
| F3 | The production calibration window includes 2025, and the run prints 2025 model-against-market metrics. These are in-sample: calibration Brier, model 0.214 against market 0.212. | "Calibrating: season 2025" (22 weeks); the by-season table | 2025 seal | Disclose in `nfl_preclose_v1` and `nfl_games_v2`. Every 2026 production run (and the 2026-10-13 C3 retest) prints this. Owner decision: should 2026 production calibrate without 2025 until the holdout opens, and should the per-season print hide sealed seasons? |
| F4 | Over the calibration window (1,355 games, 2021–2025), the engine is worse than the market: ΔLog-loss +0.0131 [0.0025, 0.0260] and ΔBrier +0.0034 [0.0012, 0.0058], week-block bootstrap. Yet the console prints "HIGH CONFIDENCE BETTING OPPORTUNITIES" for 5 games with a mean edge of 8.0 points. | run log | misleading output | Relabel these as unvalidated model–market gaps. This needs an engine edit (owner STOP). The app's banner is B1. |
| F5 | The raw simulator is far from the market: a mean absolute gap of 8.05 points against C0, reaching 22.5 points (NYG at HOU, 0.583 against 0.808). The raw model's Brier is 0.247 against the market's 0.212 in calibration. | bundle `p_home_raw`; run log | model quality | G1 (point-in-time features) and G2 (term admission) |
| F6 | Three games used league-average weather.<br>• PIT at NO: Stade de France, `PAR00`, is missing from `stadium_coords`, and nflverse calls it a dome although its roof covers only the stands.<br>• NYG at HOU: nflverse still names the venue "Reliant Stadium" (`HOU00`).<br>• SF at ATL: Mercedes-Benz Stadium, `ATL97`.<br>The lookup joins on the stadium name, and nflverse's `roof` is NA before kickoff for the retractable roofs (ATL, HOU, ARI). | run log; nflverse schedule | data | C2 weather: key on `stadium_id`, add foreign venues, and give retractable roofs an explicit unknown state |
| F7 | All 28 score distributions sum to between 0.99908 and 0.99932. About 0.08% of the mass is lost to dropped bins, and QA passes. | bundle `score_distributions.json` | data | Add tail bins (or renormalize) and document the QA tolerance (C2) |
| F8 | The bundle calls the market lines "consensus closing lines" for games one to five days from kickoff. | `source_status.json`; manifest `market_source` | labelling | `R/sim_bundle.R`: say "consensus line as of <time>" until kickoff |
| F9 | No prop has a market price. The keyed Odds API path is skipped ("ODDS_API_KEY not set"), so all 570 props carry model-derived lines and odds, and none has positive EV. The run notes "PROP_REQUIRE_MARKET_ODDS=TRUE but no market odds found; retaining model rows". | run log | M11 rule | P1 Tasks 3–7, then the K venues |
| F10 | The 2024–2026 player stats are reloaded once for each of the 14 games. | the run log repeats "Loading player stats" 14 times | efficiency | Load once per run (P1/C2) |
| F11 | "There were 50 or more warnings", and none were shown. | run log | hygiene | V4: re-run with `options(warn = 1)` and triage |
| F12 | The calibrator marked invalid (audit M4) is still loaded ("Ensemble calibrator loaded (invalid …)", "Using SPLINE calibration"). The data-quality summary says "spline (DIAGNOSTIC ONLY)", and `home_win_prob_cal` equals `home_win_prob` in every printed row. | run log | dead path | Track X: prove the path is diagnostic only, then remove `ensemble_calibration_*` with that evidence |

## Not yet checked

- The app's pages for this run: ingest it, then take screenshots. This comes after B2.
- The warnings in F11.

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

## App check (2026-10-21)

**Method.** Main `4c1c377` was built from the audit worktree. Its own database (`nfl_audit`) holds this run's bundle plus the backtest bundle. It was served on 127.0.0.1:3200 and captured with the Playwright CLI at 390 and 1440 px.

- **Home.**
  - "Week 7", "2026 season · Thu, Oct 22 – Mon, Oct 26", with all 14 games, their ET kickoffs, and the market and simulator probabilities.
  - Stat tiles: 14 games, "0 of 14" model favourites that differ from the market, and a largest gap of 1.7 pts (DAL at PHI).
  - The market note reads "nflverse consensus moneyline, proportionally devigged, as of 2026-10-21 04:56 UTC (13 h ago)".
- **Game (NE at CHI).**
  - The breadcrumb reads Week 7, 2026. Kickoff is Thu, Oct 22, 8:15 PM ET. Market 58.3%, simulator 57.5%.
  - The margin and total distributions render once scrolled into view: 100 and 104 bar paths, with no browser console error. A full-page capture without scrolling shows only their lazy placeholders.
- **Data health.** All four sources show a last success (13 h ago). Weather is stale, and the three fallback games are named.
- **Props.** Nothing is priced, and the page says why.

**New and confirmed findings:**
- **F8 reaches the UI.** The game page's moneyline card says "nflverse consensus close", and data health says "closing moneylines", for a line taken one to five days before kickoff.
- **F13.** The props page says "the props engine has known defects … (audit P1–P13) … Phase 4 fixes them". That text becomes stale once P1 merges (#216 and the P1 PR). Update the copy with P1's close-out.

## F11 resolved: the "50 or more warnings" (2026-10-22)

**Method.** The same run was repeated with `options(warn = 1)` and a fresh HOME, so the calibration was recomputed rather than read from cache. There were 642 warning lines with 10 distinct messages:
- 7 are package-build notices.
- 1 is a join-hygiene message: "Backtest per-game table: missing key columns game_type".
- The other **634** are the finding below.

**F11, the finding.** `simulate_game_nb: invalid mu_home=NA, using fallback 21.5`, and the same for `mu_away`. **317 games** in the calibration backtest (2021–2025) were simulated with 21.5 points for each team, which is a coin flip.
- They come to 63–65 per season, spread across every regular-season week at about 4 a week (17–20 per week number over five seasons).
- That is about 23% of the 1,355 calibration games.
- A warm-cache run shows none of this, which is why it went unnoticed.

The calibration means (`NFLsimulation.R`, around lines 4560–4660) multiply expected drives by points per drive and add rest points and a margin shift, through about ten team joins. The even spread points to a join or term missing for particular teams, not to early-season sparsity.

**Why it matters:** these fallback games feed the calibration fit, the blend and the model-against-market diagnostics. They are a likely part of the raw simulator's poor Brier, 0.247 against the market's 0.212.

**Owner:** G1, the A3a defect "21.5/10.0, `safe_mu`/`safe_sd`: silent substitution → remove". The first step is to diagnose which join or term yields NA for these games, as an owner-gated engine change.

### F11 root cause (2026-10-26)

**The cause.** `hfa_tbl` is built only for `teams_on_slate`, the teams playing in the week being simulated (`NFLsimulation.R:2798`). The calibration backtest joins it for every team of every past week (`recent_form_at_sim`, `:4387`).
- A team on a bye in the target week therefore has `hfa = NA` in all of its calibration games.
- That makes `margin_shift` NA, so both means are NA, and `simulate_game_nb` replaces them with 21.5 each.
- A neutral-site game escapes, because `if_else(neutral_site, 0, …)` gives 0 there.

**Evidence.** From the cold-cache calibration file of the warn = 1 run, read by `f11-teams.R` in the session scratchpad:
- The games with a simulated margin of about 0 involve LAC, WAS, BUF or JAX: 99%, 99%, 98% and 92% of each team's 2021–2025 calibration games.
- Exactly **317** calibration games involve one of these four teams, F11's count.
- `nflreadr::load_schedules(2026)` gives week 7's bye teams as **BUF, JAX, LAC, WAS**.
- JAX is lower (92%) because of its London games, which are neutral-site.

**Why nothing caught it.**
- The golden master pins week 15 of 2024, where all 32 teams play.
- `calib_cache_key` has no week. The first run of a season caches a calibration broken for that week's bye teams, and every later week of the season reuses it.

**Fix (owner-gated engine edit):** `fix/calib-hfa-all-teams`, PR #223.
- `team_hfa_table()` builds home field for every team in the schedule.
- `assert_finite_means()` stops a calibration week whose means are not finite, and names the missing inputs.
- The cache version goes to 4L.

**Measured effect** (a cold-cache `run_week.R 7 2026` with `warn = 1`, before and after; #223's CHANGELOG):
- Fallback warnings: 634 before, 0 after.
- Raw simulator over the 1,355 calibration games:
  - Brier 0.247 → 0.243;
  - log-loss 0.690 → 0.682;
  - the market's are 0.212 and 0.611.
- The production blend is unchanged: Brier 0.215, log-loss 0.624.
- Blend minus market (week-block bootstrap): ΔLog-loss +0.0131 [0.0025, 0.0260] before and +0.0134 [0.0022, 0.0265] after.
- **The fix makes the simulator's inputs honest. It does not close the gap to the market, so F4 stands.**

### F11b: the 2019 Raiders in the calibration (2026-10-27, owner decision)

CI's golden master on #223 stops at calibration 2019 week 1 (2024 week 15's calibration starts there). The new stop names the missing inputs: `2019_01_DEN_OAK` has none of the home team's drive inputs (`home_off_drives_pg`, `home_def_drives_pg`, `home_off_ppd`, `home_def_ppd`). It is reproduced locally with `golden_master.R record 15 2024`.

**Cause.** Pre-existing on main; #223's stop exposed it.
- nflverse play-by-play uses franchise codes. In `nflreadr::load_pbp(2019)` the posteams of this game are `DEN` and `LV`, and `OAK` never appears.
- `load_schedules()` keeps the codes of the time: `OAK` through 2019, and `SD` and `STL` in 2015–2019.
- The drive and points-per-drive tables are keyed by the play-by-play's code and joined on the schedule's, so those teams have no drive data for their pre-move games.
- On main every 2019 Raiders calibration game was a silent 21.5–21.5 coin flip.

**Options.** Both are engine edits, and both change the golden master:
- **A. Franchise codes in the schedule (recommended).** Map OAK→LV, SD→LAC and STL→LA, the map `R/sim_bundle.R` already uses. Form, pace and points per drive carry across a relocation; home field pools both stadiums.
- **B. Schedule codes in the play-by-play.** OAK and LV stay separate, so LV starts 2020 with no form.

Production runs are unaffected: 2026's calibration spans 2021–2025. The finding is posted on #223.

## F14, an engine kickoff bug (from P1's final review)
`games_ready$kickoff_utc` (`NFLsimulation.R:2025`) holds the Eastern wall-clock time labelled UTC. For example, 2026_07_NE_CHI shows "20:15 UTC" for a 20:15 ET kickoff, because `as.POSIXct(<Date>)` gives midnight UTC. The web bundle computes its own correct kickoff (`2026-10-23T00:15:00Z`), and P1 now reads `game_date` and `kickoff_time_raw`, so neither uses this column. It is owner-gated engine work for G1.

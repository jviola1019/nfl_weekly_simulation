# =============================================================================
# VVF variable registry (master plan A3a; design 2026-10-20 §2 and §5): one row
# per variable with its definition, source, known_at class, unit test, parameter
# count, defects (audit IDs, fix, owning phase) and evidence. The stages refuse
# any feature without a row or known after the decision (provenance.R), and
# scripts/write_variable_ledger.R renders docs/VARIABLE_LEDGER.md from it.
# =============================================================================

suppressPackageStartupMessages(library(data.table))

# known_at classes (design §2), in the order they become known within week w.
# `anchor` is the decision's own price, known at every decision by construction.
VVF_KNOWN_AT <- data.table::data.table(
  class = c("anchor", "schedule", "results_w-2", "qb_prev_start", "results_w-1", "weather_fcst_tue18z",
            "injury_wed", "injury_thu", "injury_fri", "weather_fcst_fri21z", "gameday"),
  becomes_known = c(
    "At the decision: the anchor price itself",
    "When the schedule entry is published (for a playoff game, after the previous round)",
    "After week w-2's last game",
    "After the team's previous game (week w-1)",
    "After week w-1's last game, Monday night or Tuesday",
    "When the forecast issued by Tuesday 18:00Z is published",
    "When Wednesday's injury report is published",
    "When Thursday's injury report is published",
    "When Friday's (final) injury report is published",
    "When the forecast issued by Friday 21:00Z is published",
    "Kickoff: actual starters, the roof state, anything else fixed only on game day"))

# Decision points and their information sets (design §2). The close is the last
# price before kickoff: inactives and starters are known by then, which is how
# v2's close-anchored screen used the actual starting QB. Post-hoc variables are
# refused at every decision.
VVF_DECISIONS <- list(
  open_isa = c("anchor", "schedule", "results_w-2", "qb_prev_start"),
  open_isb = c("anchor", "schedule", "results_w-2", "qb_prev_start", "results_w-1"),
  tue_18z = c("anchor", "schedule", "results_w-2", "qb_prev_start", "results_w-1", "weather_fcst_tue18z"),
  fri_21z = c("anchor", "schedule", "results_w-2", "qb_prev_start", "results_w-1", "weather_fcst_tue18z",
              "injury_wed", "injury_thu", "injury_fri", "weather_fcst_fri21z"),
  close = VVF_KNOWN_AT$class
)

VVF_DECISION_INFO <- data.table::data.table(
  decision = names(VVF_DECISIONS),
  price = c("ESPN BET opener, no-vig", "ESPN BET opener, no-vig", "Kalshi mid at the first hourly candle at or after 18:00Z; ESPN Tuesday capture",
            "Kalshi mid at or after 21:00Z; ESPN capture", "No-vig close (nflverse consensus)"),
  use = c("Confirmatory (IS-A, primary)", "Secondary (IS-B): 'may not be executable' until the A0 opener-timing study",
          "Prospective 2026", "Prospective 2026, exploratory", "Close-anchored screens (v2 reproduction, G2 market labels)"))

vvf_defect <- function(id, text, fix, phase, audit = "", status = "open") {
  list(id = id, text = text, fix = fix, phase = phase, audit = audit, status = status)
}

vvf_entry <- function(name, kind, group, definition, source, known_at, unit_test, n_params = NA_integer_,
                      posthoc = FALSE, defects = list(), evidence = "") {
  data.table::data.table(name = name, kind = kind, group = group, definition = definition, source = source,
                         known_at = known_at, posthoc = posthoc, unit_test = unit_test,
                         n_params = as.integer(n_params), defects = list(defects), evidence = evidence)
}

VVF_SRC_FEAT <- "backtest/vvf/features.R: vvf_build_features"
VVF_SRC_ANCHOR <- "backtest/vvf/features.R: vvf_anchor_features"
VVF_TEST_FEAT <- "tests/testthat/test-vvf-features.R"
VVF_TEST_REPRO <- "tests/testthat/test-vvf-v2-reproduction.R"
VVF_AUDIT <- "reports/2026-09-28/AUDIT.md"
VVF_ADDENDUM <- "reports/2026-09-29/AUDIT-ADDENDUM.md"
VVF_OUTPUT_AUDIT <- "reports/2026-10-21/OUTPUT_AUDIT.md (docs/modeling-roadmap)"

vvf_inj_defect <- function() {
  vvf_defect("A3-INJ-CUTOFF",
             "Built with the kickoff - 6 h rule (date_modified + 6 h < kickoff), so a Saturday update counts; no report-day cutoff",
             "Rebuild injuries_team/injuries_qb with a report-day cutoff (date_modified <= Friday 21:00Z) to earn class injury_fri",
             "A4", "design 2026-10-20, section 2")
}

vvf_feature_rows <- function() {
  f <- function(name, group, definition, source, known_at, unit_test = VVF_TEST_REPRO, defects = list(), posthoc = FALSE) {
    vvf_entry(name, "feature", group, definition, source, known_at, unit_test, 1L, posthoc, defects)
  }
  starter <- vvf_defect("A3-STARTER", "Uses the game's actual starting QB (C2's QB EPA features), unknown at the opener",
                        "PC-C2 rebuilds C2 on IS-A with the previous starter", "A4", "master plan 2026-10-19, Context")
  sched <- "backtest/data/games.csv (nflverse schedule) via vvf_build_features"
  rbindlist(list(
    f("d_c1", "model vs market", "logit(C1 Elo walk-forward) - lp_anchor; a team's rating moves only when it plays, so it uses results through the team's previous game",
      paste0(VVF_SRC_ANCHOR, "; vvf_base_predictions (bt_elo_run)"), "results_w-1", VVF_TEST_FEAT),
    f("d_c2", "model vs market", "logit(C2 EPA GLM walk-forward) - lp_anchor", paste0(VVF_SRC_ANCHOR, "; vvf_base_predictions (bt_epa_walk_forward)"),
      "gameday", VVF_TEST_FEAT, list(starter)),
    f("d_e1", "model vs market", "logit(E1 = logit mean of C1 and C2) - lp_anchor; aliased with d_c1 and d_c2 when entered jointly",
      paste0(VVF_SRC_ANCHOR, "; vvf_base_predictions (bt_e1)"), "gameday", VVF_TEST_FEAT, list(starter)),
    f("lp_anchor", "market shape", "logit of the no-vig anchor price (v2's lp_c0 when the anchor is the close)", VVF_SRC_ANCHOR, "anchor", VVF_TEST_FEAT),
    f("home_dog", "market shape", "1 if the anchor prices the home team below 0.5", VVF_SRC_ANCHOR, "anchor", VVF_TEST_FEAT),
    f("big_fav", "market shape", "1 if |p_anchor - 0.5| > 0.3", VVF_SRC_ANCHOR, "anchor", VVF_TEST_FEAT),
    f("rest_diff", "schedule", "home rest days - away rest days", sched, "schedule"),
    f("home_short", "schedule", "1 if the home team has 6 or fewer rest days", sched, "schedule"),
    f("away_short", "schedule", "1 if the away team has 6 or fewer rest days", sched, "schedule"),
    f("home_bye", "schedule", "1 if the home team has 13 or more rest days", sched, "schedule"),
    f("away_bye", "schedule", "1 if the away team has 13 or more rest days", sched, "schedule"),
    f("thursday", "schedule", "1 for a Thursday game", "backtest/vvf/data/game_context.csv (weekday) via vvf_build_features", "schedule"),
    f("div", "schedule", "1 for a division game", sched, "schedule"),
    f("neutral_site", "schedule", "1 when the schedule's location is Neutral", sched, "schedule"),
    f("late_reg", "schedule", "1 for regular-season weeks 15 and later", sched, "schedule"),
    f("playoff", "schedule", "1 for a postseason game", sched, "schedule"),
    f("away_travel_1000km", "travel and venue", "great-circle km / 1000 from the away team's usual home stadium to the game venue",
      "backtest/vvf/data/venues.csv via vvf_build_features (vvf_home_venues, vvf_haversine_km)", "schedule"),
    f("travel_diff_1000km", "travel and venue", "away travel - home travel, km / 1000", "venues.csv via vvf_build_features", "schedule"),
    f("tz_shift_away", "travel and venue", "UTC offset of the venue - UTC offset of the away team's home, hours, at kickoff",
      "venues.csv via vvf_build_features (vvf_utc_offset_h)", "schedule"),
    f("abs_tz_away", "travel and venue", "|tz_shift_away|: time zones crossed by the away team", "venues.csv via vvf_build_features", "schedule"),
    f("west_early", "travel and venue", "1 if the away team's body clock is before 11:00 and it travelled 2+ zones east",
      "venues.csv via vvf_build_features (vvf_local_hour)", "schedule"),
    f("primetime", "travel and venue", "1 if the local kickoff is 19:30 or later (the final, post-flex kickoff)", "venues.csv via vvf_build_features", "schedule"),
    f("altitude", "travel and venue", "1 if the venue is 1,000 m or higher", "venues.csv via vvf_build_features", "schedule"),
    f("roof_closed", "travel and venue", "1 if the roof is dome or closed", sched, "gameday", VVF_TEST_REPRO,
      list(vvf_defect("A3-ROOF", "For retractable roofs the state is decided on game day; nflverse's roof is NA before kickoff for them",
                      "Split into a fixed dome flag (schedule) and the retractable state (gameday)", "A4", "F6, OUTPUT_AUDIT"))),
    f("turf", "travel and venue", "1 if the surface is not grass", "game_context.csv (surface) via vvf_build_features", "schedule"),
    f("inj_diff_qb", "injuries and QB", "home - away status-weighted QB injury count (Out 1, Doubtful 0.75, Questionable 0.25)",
      "backtest/vvf/data/injuries_team.csv via vvf_injury_index", "gameday", VVF_TEST_FEAT, list(vvf_inj_defect())),
    f("inj_diff_ol", "injuries and QB", "home - away status-weighted offensive-line injury count", "injuries_team.csv via vvf_injury_index", "gameday",
      VVF_TEST_FEAT, list(vvf_inj_defect())),
    f("inj_diff_skill", "injuries and QB", "home - away status-weighted WR/TE/RB injury count", "injuries_team.csv via vvf_injury_index", "gameday",
      VVF_TEST_FEAT, list(vvf_inj_defect())),
    f("inj_diff_dl", "injuries and QB", "home - away status-weighted defensive-line injury count", "injuries_team.csv via vvf_injury_index", "gameday",
      VVF_TEST_FEAT, list(vvf_inj_defect())),
    f("inj_diff_lb", "injuries and QB", "home - away status-weighted linebacker injury count", "injuries_team.csv via vvf_injury_index", "gameday",
      VVF_TEST_FEAT, list(vvf_inj_defect())),
    f("inj_diff_db", "injuries and QB", "home - away status-weighted defensive-back injury count", "injuries_team.csv via vvf_injury_index", "gameday",
      VVF_TEST_FEAT, list(vvf_inj_defect())),
    f("inj_diff_all", "injuries and QB", "sum of the six group differences; aliased with them when entered jointly",
      "injuries_team.csv via vvf_injury_index", "gameday", VVF_TEST_FEAT, list(vvf_inj_defect())),
    f("qb_out_diff", "injuries and QB", "home - away: the previous game's starter is listed Out or Doubtful", "injuries_qb.csv via vvf_qb_out",
      "gameday", VVF_TEST_FEAT, list(vvf_inj_defect())),
    f("qb_change_diff", "injuries and QB", "home - away: this game's actual starter differs from the previous starter", "games.csv via vvf_qb_out",
      "gameday", VVF_TEST_FEAT, list(starter)),
    f("ref_ml_resid", "officials", "the assigned referee's prior-season mean of (y - p_close), shrunk with 50 pseudo-games",
      "game_context.csv (referee) via vvf_referee_tendencies", "gameday", VVF_TEST_FEAT,
      list(vvf_defect("A3-REF", "The referee assignment's publication time is not recorded", "Date the assignment (it is reported mid-week) before any pre-close use", "A4"))),
    f("ref_tot_resid", "officials", "the assigned referee's prior-season mean of (total - total_line), shrunk with 50 pseudo-games",
      "game_context.csv (referee) via vvf_referee_tendencies", "gameday", VVF_TEST_FEAT,
      list(vvf_defect("A3-REF", "The referee assignment's publication time is not recorded", "Date the assignment (it is reported mid-week) before any pre-close use", "A4"))),
    f("cold_obs", "weather (observed, post-hoc)", "1 for an outdoor game observed at 32 F or colder", "game_context.csv (temp_obs) via vvf_build_features",
      "gameday", VVF_TEST_REPRO, posthoc = TRUE),
    f("windy_obs", "weather (observed, post-hoc)", "1 for an outdoor game observed at 15 mph or more", "game_context.csv (wind_obs) via vvf_build_features",
      "gameday", VVF_TEST_REPRO, posthoc = TRUE)
  ))
}

vvf_engine_rows <- function() {
  m5 <- vvf_defect("M5", "Windows include later games; team n() counts unplayed games",
                   "features_asof; count played games only; append canary", "G1", VVF_AUDIT)
  e <- function(name, group, definition, source, known_at, unit_test, defects, posthoc = FALSE, kind = "engine",
                n_params = NA_integer_, evidence = "") {
    vvf_entry(name, kind, group, definition, source, known_at, unit_test, n_params, posthoc, defects, evidence)
  }
  setting <- function(name, value, definition) {
    e(name, "setting", sprintf("%s (config.R default %s)", definition, value), sprintf("config.R: %s", name), "schedule",
      "none yet (A3b S5 validation curve)",
      list(vvf_defect("A3-S5", "Never tuned by a validation curve; the S5 curve needs a point-in-time C3 walk-forward",
                      "Run the A3b S5 validation curve with the one-SE rule on Tune 2018-22 once G1's predict_week exists", "G2")),
      kind = "setting", n_params = 1L)
  }
  rbindlist(list(
    e("hfa", "engine means", "Home-field advantage points per team", "NFLsimulation.R: team_hfa_tbl, hfa_tbl", "gameday",
      "none", list(m5, vvf_defect("F11",
        paste("Built only for the simulated week's teams, so a team on a bye had no home field in any of its calibration games:",
              "both means went NA and simulate_game_nb used 21.5 for each (317 of 1,355 games in the 2026 week-7 run)"),
        paste("team_hfa_table() for every schedule team, assert_finite_means() and calibration cache version 4L",
              "(fix/calib-hfa-all-teams 922dae6, owner-gated, unmerged); then the A3a bye-week regression check"),
        "F11 fix", paste(VVF_OUTPUT_AUDIT, "'F11 root cause' (e99476d)"))), posthoc = TRUE),
    e("rho_score", "engine means", "Score correlation of the Gaussian copula (RHO_SCORE from rho_hat)", "NFLsimulation.R: RHO_SCORE, rho_hat",
      "gameday", "none", list(m5), posthoc = TRUE),
    e("pts_cap", "engine means", "Points cap PTS_CAP_HI (max team points + 2, at least 60)", "NFLsimulation.R: PTS_CAP_HI", "gameday",
      "none", list(m5), posthoc = TRUE),
    e("ppd_tables", "engine means", "Production points-per-drive tables off_ppd_tbl / def_ppd_tbl (recency-weighted)",
      "NFLsimulation.R: off_ppd_tbl, def_ppd_tbl", "results_w-1", "none",
      list(vvf_defect("A3-PPD", "Code read 2026-10-22: the summaries have no week cut, so re-running a past week would use later games' drives (to confirm)",
                      "features_asof cut, with an append canary", "G1", "A3 planner"))),
    e("glmm_prior", "engine means", "NB-GLMM team ratings used as a mean prior, weight GLMM_BLEND_W", "NFLsimulation.R: glmm_preds (glmmTMB)",
      "results_w-1", "none",
      list(vvf_defect("M9", "No season term, a silent try, an unversioned NB cache key", "Add a season term, log failures, version the key", "G1", VVF_AUDIT))),
    e("qb_starter", "engine means", "QB adjustment and QB change", "NFLsimulation.R QB adjustment; injury_scalp.R: default_quality",
      "gameday", "tests/testthat/test-backup-qb.R",
      list(vvf_defect("A3-QB", "Uses the actual starter; backup quality is silently 0.35 under the 2026 depth-chart schema",
                      "Use the previous starter at the opener; flag the schema change (injury_scalp.R edit is an owner STOP)", "G1",
                      "master plan 2026-10-19, A3a"))),
    e("team_tz", "engine means", "Team time-zone table team_tz", "NFLsimulation.R: team_tz", "schedule", "none",
      list(vvf_defect("A3-TZ", "Keyed LAR while nflverse uses LA, so the join misses", "Fix the key (engine edit, owner STOP)", "G1",
                      "master plan 2026-10-19, A3a"))),
    e("injury_adj", "engine means", "Injury adjustment of the scoring means", "NFLsimulation.R / injury_scalp.R injury impacts", "injury_fri",
      "tests/testthat/test-injury-model.R",
      list(vvf_defect("M18", "Computed but never in the means", "Admit only through the test, at the close and the Friday decision point", "G2", VVF_ADDENDUM))),
    e("weather", "engine means", "Venue weather and dome flags", "NFLsimulation.R: stadium_coords, get_hourly_weather", "weather_fcst_fri21z",
      "tests/testthat/test-weather.R",
      list(vvf_defect("M21", "Joined by stadium name; history fetched from the forecast endpoint", "Key by stadium_id; use historical forecasts; log misses", "G2", VVF_ADDENDUM),
           vvf_defect("S3", "No timeout or retry; failure returns NULL silently; neutral sites fall back to Kansas", "Timeout, loud failure, venue coordinates", "G2", VVF_AUDIT),
           vvf_defect("F6", "Three 2026 week-7 games used league-average weather (PAR00 missing, HOU00 renamed, ATL97 roof NA)", "Key on stadium_id, add foreign venues, explicit unknown roof state", "C2", VVF_OUTPUT_AUDIT)),
      posthoc = TRUE),
    e("neutral_travel", "engine means", "Travel for neutral-site games", "NFLsimulation.R travel terms", "schedule", "tests/testthat/test-schedule-context.R",
      list(vvf_defect("A3-NEUTRAL", "Measured from the home stadium", "Venue coordinates", "G2", "master plan 2026-10-19, A3a"))),
    e("turnover_term", "engine means", "Turnover adjustment to_adj_pts", "NFLsimulation.R: to_adj_pts", "results_w-1", "tests/testthat/test-mu-terms.R",
      list(vvf_defect("M22", "NaN source", "Explicit NA rule plus a test", "G2", VVF_ADDENDUM))),
    e("safe_mu_sd", "engine guards", "Substitutions for invalid means and SDs: simulate_game_nb's 21.5 mean and 10.0 SD; safe_mu (21) and safe_sd (7)",
      "NFLsimulation.R: simulate_game_nb; R/utils.R: safe_mu, safe_sd", "schedule", "tests/testthat/test-simulate-game-nb.R",
      list(vvf_defect("A3-SAFE",
        paste("Silent substitution. F11 showed its cost (317 calibration games at 21.5-21.5). The calibration path is covered by",
              "assert_finite_means() once 922dae6 merges; the slate path's safe_mu(21) / safe_sd(7) remain"),
        "Remove the substitutions; a missing mean or SD stops the run", "G1", "master plan 2026-10-19, A3a")), n_params = 4L),
    e("dup_loaders", "engine data", "load_defense_rankings and load_red_zone_efficiency, each defined twice",
      "R/correlated_props.R, R/red_zone_data.R, sports/nfl/props/data_sources.R", "results_w-1", "tests/testthat/test-module-duplicates.R",
      list(vvf_defect("A3-DUP", "Each defined twice", "Keep one; a source-order test (deletion needs approval)", "P1", "master plan 2026-10-19, A3a"),
           vvf_defect("P13", "load_defense_rankings() always errors, so defense adjustments are always neutral", "PR #216", "P1", VVF_AUDIT))),
    e("calibrator", "engine calibration", "Ensemble spline/isotonic calibrator (ensemble_calibration_*)", "NFLsimulation.R calibration path",
      "gameday", "tests/testthat/test-calibration.R",
      list(vvf_defect("M4", "Trained on the final score", "Remove after proof it is diagnostic only", "X", VVF_AUDIT),
           vvf_defect("F12", "Still loaded and printed as SPLINE; home_win_prob_cal equals home_win_prob", "Track X removal with that evidence", "X", VVF_OUTPUT_AUDIT)),
      posthoc = TRUE),
    e("devig", "market", "Proportional devig of a two-way moneyline (the C0 and anchor prices)", "backtest/common.R: bt_novig_home",
      "anchor", "tests/testthat/test-backtest-games.R", list(), kind = "market", n_params = 0L,
      evidence = paste("M3 (pre-registered): on 4,426 games 2006-2022 every alternative (additive, power, Shin, odds ratio) differs from",
                       "proportional by less than 0.0001 log-loss, Holm p = 1; proportional stays. Calibration slope 1.025 [0.940, 1.110],",
                       "intercept -0.047 [-0.111, +0.017] (reports/2026-10-21/devig-study/RESULTS.md, docs/modeling-roadmap 625ef27)")),
    setting("RECENCY_HALFLIFE", "3.0", "Recency half-life in games for recency_weights() and the calibration path's rec_wts"),
    setting("GLMM_BLEND_W", "0.38", "Weight of the NB-GLMM prior in the means"),
    setting("SOS_STRENGTH", "0.45", "Strength-of-schedule exponent"),
    setting("SHRINKAGE", "0.70", "Market shrinkage of the published probability"),
    setting("N_RECENT", "6", "Recent games per team in recent form")
  ))
}

vvf_registry <- function() {
  rbindlist(list(vvf_feature_rows(), vvf_engine_rows()))
}

# v2's screened features in v2's order (PR #205 BT2_SCREEN, post-hoc excluded;
# v2's lp_c0 is lp_anchor), and its "situational" joint set
VVF_V2_FEATURES <- c("d_c1", "d_c2", "d_e1", "lp_anchor", "home_dog", "big_fav",
                     "rest_diff", "home_short", "away_short", "home_bye", "away_bye", "thursday", "div",
                     "neutral_site", "late_reg", "playoff",
                     "away_travel_1000km", "travel_diff_1000km", "tz_shift_away", "abs_tz_away", "west_early",
                     "primetime", "altitude", "roof_closed", "turf",
                     "inj_diff_qb", "inj_diff_ol", "inj_diff_skill", "inj_diff_dl", "inj_diff_lb", "inj_diff_db",
                     "inj_diff_all", "qb_out_diff", "qb_change_diff", "ref_ml_resid", "ref_tot_resid")
VVF_V2_SITUATIONAL <- setdiff(VVF_V2_FEATURES, c("d_c1", "d_c2", "d_e1", "lp_anchor", "home_dog", "big_fav"))

#' Disclosures the ledger and the protocols carry
vvf_disclosures <- function() {
  data.table::data.table(
    id = c("F3", "F11-CALIB", "CLV-POWER", "V1-BUILDER", "V1-CLV-2024", "V2-TUNE"),
    text = c(
      paste("The production calibration window includes 2025. Every 2026 production run before PR #218, and the 2026-10-13 C3 retest,",
            "printed in-sample 2025 model-against-market figures (week 7: calibration Brier, model 0.214 against market 0.212;",
            "those figures predate the F11 fix and are contaminated by it)."),
      paste("Every calibration-based figure computed before the F11 fix (fix/calib-hfa-all-teams 922dae6) merges is contaminated in",
            "any week with byes: the bye teams' calibration games were simulated at 21.5-21.5. That includes the output audit's F3, F4",
            "and F5 figures. They are re-measured after the fix merges."),
      paste("2025 ESPN opener and close prices, with 2025 scores, were read once, on 2026-09-29, by the A2 power study.",
            "No model, threshold or feature was chosen on them; the 400-pick gate's sigma came from it."),
      paste("backtest/build_inputs.R (v1) also reads that 2024-2025 price file to build backtest/data/espn_open_close.csv,",
            "keeping 2024 rows only (found by the A3 planner on 2026-10-22). The owner decides whether it should refuse the file."),
      "v1 already looked at 2024 opener CLV for C1, C2, E1 and K[E1], so 2024 is secondary evidence for PC-C2.",
      paste("v2's close-anchored screen (PR #205) chose nothing on Confirm 2023-24 or the 2025 holdout; it used Tune 2018-22,",
            "and this framework reproduces its numbers on the same inputs.")),
    source = c(VVF_OUTPUT_AUDIT, paste(VVF_OUTPUT_AUDIT, "'F11 root cause'"), "design 2026-10-20, section 6",
               "backtest/build_inputs.R", "design 2026-10-20, section 6",
               "reports/2026-09-30/validation-sprint/REPORT.md (PR #205)"))
}

# =============================================================================
# Validation sprint v2: point-in-time game features for the Tune-window screen
# and the v2 candidates.
#
# Every feature is known before kickoff:
#   - schedule facts (rest days, division, roof, surface, neutral site, weekday,
#     kickoff time, venue) are published with the schedule;
#   - the starting QB is announced before kickoff (and priced by the market);
#   - injury counts use report_status rows timestamped > 6 h before kickoff
#     (backtest/v2/build_inputs.R);
#   - referee tendencies use prior seasons only;
#   - base model probabilities (C1 Elo, C2 EPA GLM, E1) are walk-forward: a
#     week's prediction uses only games that kicked off earlier.
# Observed game-day weather (temp_obs, wind_obs) is NOT point-in-time; it is
# screened only as a labelled post-hoc diagnostic and never enters a candidate.
# =============================================================================

BT2_V1_SELECTIONS <- list(c1 = list(K = 20, hfa = 30, regress = 0.45), c2 = list(halflife = 8, lambda = 100))
BT2_INJ_STATUS_W <- c(out = 1, doubtful = 0.75, questionable = 0.25)
BT2_INJ_GROUPS <- c("qb", "ol", "skill", "dl", "lb", "db")
BT2_REF_SHRINK_GAMES <- 50   # referee tendencies are shrunk toward 0 with this many pseudo-games

#' v1 base candidates, walk-forward, for seasons <= max_season (Confirm/Holdout never loaded)
bt2_base_predictions <- function(inp_v1, max_season = BT2_MAX_SPRINT_SEASON, sel = BT2_V1_SELECTIONS) {
  games <- inp_v1$games[season <= max_season]
  bt2_guard_seasons(games$season, max_season, "base prediction games")
  pred_seasons <- seq(BT2_FIRST_PRED_SEASON, max_season)
  weeks <- bt_week_schedule(games, pred_seasons)
  c1 <- bt_elo_run(games, sel$c1$K, sel$c1$hfa, sel$c1$regress)
  feats <- bt_epa_features(games, inp_v1$team_games[game_id %in% games$game_id],
                           inp_v1$qb_games[game_id %in% games$game_id], sel$c2$halflife,
                           seq(BT_EPA_FIRST_TRAIN_SEASON, max_season))
  c2 <- bt_epa_walk_forward(feats, games, weeks, sel$c2$lambda)
  d <- merge(merge(games[season %in% pred_seasons], c1, by = "game_id"), c2, by = "game_id", all.x = TRUE)
  d[, p_e1 := bt_e1(p_c1, p_c2)]
  setorder(d, kickoff, game_id)
  list(pred = d, weeks = weeks)
}

#' Each franchise's usual home venue per season (mode of its home games' stadium_id)
bt2_home_venues <- function(g) {
  h <- g[!neutral & !is.na(stadium_id), .N, by = .(season, team = home_franchise, stadium_id)]
  setorder(h, season, team, -N)
  h[, .SD[1], by = .(season, team)][, .(season, team, home_stadium = stadium_id)]
}

#' Status-weighted injury index per team-game and group, plus the listed-QB flag
bt2_injury_index <- function(inj_team) {
  x <- copy(inj_team)
  for (grp in BT2_INJ_GROUPS) {
    x[, (paste0("inj_", grp)) := BT2_INJ_STATUS_W[["out"]] * get(paste0(grp, "_out")) +
        BT2_INJ_STATUS_W[["doubtful"]] * get(paste0(grp, "_doubtful")) +
        BT2_INJ_STATUS_W[["questionable"]] * get(paste0(grp, "_questionable"))]
  }
  x[, inj_all := Reduce(`+`, mget(paste0("inj_", BT2_INJ_GROUPS)))]
  x[, .SD, .SDcols = c("game_id", "team", paste0("inj_", c(BT2_INJ_GROUPS, "all")))]
}

#' The team's previous-game starter is listed Out or Doubtful for this game
bt2_qb_out <- function(g, inj_qb) {
  starters <- rbind(g[, .(game_id, kickoff, season, team = home_franchise, qb = home_qb_id)],
                    g[, .(game_id, kickoff, season, team = away_franchise, qb = away_qb_id)])
  setorder(starters, team, kickoff)
  starters[, prev_qb := shift(qb), by = team]
  starters[, qb_change := !is.na(prev_qb) & !is.na(qb) & qb != prev_qb]
  listed <- unique(inj_qb[status %in% c("out", "doubtful"),
                          .(game_id, team = bt2_franchise(team), prev_qb = gsis_id, listed = TRUE)])
  starters <- merge(starters, listed, by = c("game_id", "team", "prev_qb"), all.x = TRUE)
  starters[, .(game_id, team, qb_out = !is.na(listed), qb_change)]
}

#' Referee tendencies from prior seasons only: mean (y - p_c0) and mean (total - total_line),
#' shrunk toward 0 with BT2_REF_SHRINK_GAMES pseudo-games
bt2_referee_tendencies <- function(d) {
  seasons <- sort(unique(d$season))
  out <- vector("list", length(seasons))
  for (i in seq_along(seasons)) {
    s <- seasons[i]
    prior <- d[season < s & !is.na(referee) & referee != ""]
    if (!nrow(prior)) next
    t <- prior[, .(n = .N, ml_sum = sum(y - p_c0, na.rm = TRUE), n_ml = sum(!is.na(y)),
                   tot_sum = sum(total - total_line, na.rm = TRUE), n_tot = sum(!is.na(total_line))), by = referee]
    t[, `:=`(ref_ml_resid = ml_sum / (n_ml + BT2_REF_SHRINK_GAMES),
             ref_tot_resid = tot_sum / (n_tot + BT2_REF_SHRINK_GAMES), season = s)]
    out[[i]] <- t[, .(season, referee, ref_ml_resid, ref_tot_resid)]
  }
  rbindlist(out)
}

#' Build the feature table for every predicted game (seasons <= max_season)
bt2_build_features <- function(base, inp_v2, max_season = BT2_MAX_SPRINT_SEASON) {
  d <- copy(base$pred)
  bt2_guard_seasons(d$season, max_season, "feature rows")
  ctx <- inp_v2$game_context[season <= max_season]
  d <- merge(d, ctx[, .(game_id, weekday, total_line, over_odds, under_odds, home_spread_odds, away_spread_odds,
                        surface, temp_obs, wind_obs, referee, stadium_id)], by = "game_id", all.x = TRUE)
  d[, `:=`(margin = home_score - away_score, total = home_score + away_score)]
  d[, lp_c0 := bt_logit(bt_clip(p_c0))]
  d[, `:=`(d_c1 = bt_logit(bt_clip(p_c1)) - lp_c0, d_c2 = bt_logit(bt_clip(p_c2)) - lp_c0,
           d_e1 = bt_logit(bt_clip(p_e1)) - lp_c0)]

  # schedule situations
  d[, `:=`(rest_diff = home_rest - away_rest,
           home_short = as.integer(home_rest <= 6), away_short = as.integer(away_rest <= 6),
           home_bye = as.integer(home_rest >= 13), away_bye = as.integer(away_rest >= 13),
           div = as.integer(div_game == 1), neutral_site = as.integer(neutral),
           roof_closed = as.integer(roof %in% c("dome", "closed")),
           turf = as.integer(!is.na(surface) & !grepl("grass", surface)),
           thursday = as.integer(weekday == "Thursday"),
           late_reg = as.integer(phase == "REG" & week >= 15), playoff = as.integer(phase == "POST"))]

  # venue geometry: travel, time zones, altitude, body clock, prime time
  v <- inp_v2$venues
  hv <- bt2_home_venues(merge(d, ctx[, .(game_id)], by = "game_id"))
  d <- merge(d, v[, .(stadium_id, g_lat = latitude, g_lon = longitude, g_elev = elevation_m, g_tz = timezone)],
             by = "stadium_id", all.x = TRUE)
  for (side in c("home", "away")) {
    hs <- merge(hv, v[, .(home_stadium = stadium_id, lat = latitude, lon = longitude, tz = timezone)], by = "home_stadium")
    setnames(hs, c("team", "lat", "lon", "tz"), c(paste0(side, "_franchise"), paste0(side, "_lat"), paste0(side, "_lon"),
                                                  paste0(side, "_tz")))
    d <- merge(d, hs[, -"home_stadium"], by = c("season", paste0(side, "_franchise")), all.x = TRUE)
  }
  d[, away_travel_1000km := bt2_haversine_km(away_lat, away_lon, g_lat, g_lon) / 1000]
  d[, home_travel_1000km := bt2_haversine_km(home_lat, home_lon, g_lat, g_lon) / 1000]
  d[, travel_diff_1000km := away_travel_1000km - home_travel_1000km]
  d[, tz_shift_away := bt2_utc_offset_h(kickoff, g_tz) - bt2_utc_offset_h(kickoff, away_tz)]
  d[, abs_tz_away := abs(tz_shift_away)]
  d[, away_body_hour := bt2_local_hour(kickoff, away_tz)]
  d[, west_early := as.integer(!is.na(away_body_hour) & away_body_hour < 11 & tz_shift_away >= 2)]
  d[, local_hour := bt2_local_hour(kickoff, g_tz)]
  d[, primetime := as.integer(!is.na(local_hour) & local_hour >= 19.5)]
  d[, altitude := as.integer(!is.na(g_elev) & g_elev >= 1000)]

  # injuries (report_status, > 6 h before kickoff); no report row = 0
  ii <- bt2_injury_index(inp_v2$injuries_team[season <= max_season])
  for (side in c("home", "away")) {
    x <- copy(ii); setnames(x, "team", paste0(side, "_franchise"))
    setnames(x, setdiff(names(x), c("game_id", paste0(side, "_franchise"))),
             paste0(side, "_", setdiff(names(x), c("game_id", paste0(side, "_franchise")))))
    d <- merge(d, x, by = c("game_id", paste0(side, "_franchise")), all.x = TRUE)
  }
  inj_cols <- grep("^(home|away)_inj_", names(d), value = TRUE)
  for (cc in inj_cols) set(d, which(is.na(d[[cc]])), cc, 0)
  for (grp in c(BT2_INJ_GROUPS, "all")) d[, (paste0("inj_diff_", grp)) := get(paste0("home_inj_", grp)) - get(paste0("away_inj_", grp))]
  d[, inj_reported := as.integer(game_id %in% inp_v2$injuries_team$game_id)]

  qb <- bt2_qb_out(d[, .(game_id, kickoff, season, home_franchise, away_franchise, home_qb_id, away_qb_id)],
                   inp_v2$injuries_qb[season <= max_season])
  for (side in c("home", "away")) {
    x <- copy(qb); setnames(x, c("team", "qb_out", "qb_change"), c(paste0(side, "_franchise"), paste0(side, "_qb_out"),
                                                                 paste0(side, "_qb_change")))
    d <- merge(d, x, by = c("game_id", paste0(side, "_franchise")), all.x = TRUE)
  }
  d[, `:=`(qb_out_diff = as.integer(home_qb_out %in% TRUE) - as.integer(away_qb_out %in% TRUE),
           qb_change_diff = as.integer(home_qb_change %in% TRUE) - as.integer(away_qb_change %in% TRUE))]

  # referee (prior seasons only)
  rt <- bt2_referee_tendencies(d)
  d <- merge(d, rt, by = c("season", "referee"), all.x = TRUE)
  d[is.na(ref_ml_resid), ref_ml_resid := 0]
  d[is.na(ref_tot_resid), ref_tot_resid := 0]

  # market shape (tests whether the close itself is miscalibrated)
  d[, `:=`(home_dog = as.integer(p_c0 < 0.5), big_fav = as.integer(abs(p_c0 - 0.5) > 0.3))]
  # spread / total market prices (devigged when both sides are quoted)
  d[, p_cover_mkt := bt_novig_home(home_spread_odds, away_spread_odds)]
  d[, p_over_mkt := bt_novig_home(over_odds, under_odds)]
  d[, `:=`(ats_resid = margin - spread_line, tot_resid = total - total_line)]
  d[, `:=`(cover = fifelse(is.na(ats_resid) | ats_resid == 0, NA_integer_, as.integer(ats_resid > 0)),
           over = fifelse(is.na(tot_resid) | tot_resid == 0, NA_integer_, as.integer(tot_resid > 0)))]

  # observed weather: post-hoc diagnostic only (outdoor/open games)
  d[, `:=`(cold_obs = as.integer(!roof_closed & !is.na(temp_obs) & temp_obs <= 32),
           windy_obs = as.integer(!roof_closed & !is.na(wind_obs) & wind_obs >= 15))]
  setorder(d, kickoff, game_id)
  d[]
}

#' Features screened, by family. `posthoc` ones are diagnostics, never candidate inputs.
BT2_SCREEN <- data.table::rbindlist(list(
  data.table::data.table(feature = c("d_c1", "d_c2", "d_e1"), group = "model vs market", posthoc = FALSE),
  data.table::data.table(feature = c("lp_c0", "home_dog", "big_fav"), group = "market shape", posthoc = FALSE),
  data.table::data.table(feature = c("rest_diff", "home_short", "away_short", "home_bye", "away_bye", "thursday",
                                     "div", "neutral_site", "late_reg", "playoff"), group = "schedule", posthoc = FALSE),
  data.table::data.table(feature = c("away_travel_1000km", "travel_diff_1000km", "tz_shift_away", "abs_tz_away",
                                     "west_early", "primetime", "altitude", "roof_closed", "turf"),
                         group = "travel and venue", posthoc = FALSE),
  data.table::data.table(feature = c(paste0("inj_diff_", c(BT2_INJ_GROUPS, "all")), "qb_out_diff", "qb_change_diff"),
                         group = "injuries and QB", posthoc = FALSE),
  data.table::data.table(feature = c("ref_ml_resid", "ref_tot_resid"), group = "officials", posthoc = FALSE),
  data.table::data.table(feature = c("cold_obs", "windy_obs"), group = "weather (observed, post-hoc)", posthoc = TRUE)
))

# =============================================================================
# VVF point-in-time game features (master plan A3), for the screens and their
# controls. Each feature's known_at class is declared in backtest/vvf/registry.R
# and asserted by vvf_assert_known_at() before any stage uses it.
#
# Ported with attribution from PR #205 (validation sprint v2,
# backtest/v2/features.R at 759dd1c; owner decision 2026-10-20). Changes:
#   - names use the vvf_ prefix; the season guard also refuses sealed seasons;
#   - the features that depend on the anchor price (lp_anchor, d_c1, d_c2, d_e1,
#     home_dog, big_fav and the movement target delta) are computed by
#     vvf_anchor_features() for a chosen anchor, the close or the opener. v2
#     computed them against the close only; with anchor = "close" they are
#     identical to v2's;
#   - the screen list moved to the registry (VVF_V2_FEATURES).
# Observed game-day weather (cold_obs, windy_obs) is a post-hoc diagnostic and
# never enters a decision.
# =============================================================================

VVF_V1_SELECTIONS <- list(c1 = list(K = 20, hfa = 30, regress = 0.45), c2 = list(halflife = 8, lambda = 100))
VVF_INJ_STATUS_W <- c(out = 1, doubtful = 0.75, questionable = 0.25)
VVF_INJ_GROUPS <- c("qb", "ol", "skill", "dl", "lb", "db")
VVF_REF_SHRINK_GAMES <- 50   # referee tendencies are shrunk toward 0 with this many pseudo-games
VVF_ANCHORS <- c(close = "p_c0", open = "p_open")

#' v1 base candidates (C1 Elo, C2 EPA GLM, E1), walk-forward, for seasons <= max_season
vvf_base_predictions <- function(inp_v1, max_season, sel = VVF_V1_SELECTIONS) {
  games <- inp_v1$games[season <= max_season]
  vvf_guard_seasons(games$season, max_season, "base prediction games")
  pred_seasons <- seq(VVF_FIRST_PRED_SEASON, max_season)
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
vvf_home_venues <- function(g) {
  h <- g[!neutral & !is.na(stadium_id), .N, by = .(season, team = home_franchise, stadium_id)]
  setorder(h, season, team, -N)
  h[, .SD[1], by = .(season, team)][, .(season, team, home_stadium = stadium_id)]
}

#' Status-weighted injury index per team-game and group
vvf_injury_index <- function(inj_team) {
  x <- copy(inj_team)
  for (grp in VVF_INJ_GROUPS) {
    x[, (paste0("inj_", grp)) := VVF_INJ_STATUS_W[["out"]] * get(paste0(grp, "_out")) +
        VVF_INJ_STATUS_W[["doubtful"]] * get(paste0(grp, "_doubtful")) +
        VVF_INJ_STATUS_W[["questionable"]] * get(paste0(grp, "_questionable"))]
  }
  x[, inj_all := Reduce(`+`, mget(paste0("inj_", VVF_INJ_GROUPS)))]
  x[, .SD, .SDcols = c("game_id", "team", paste0("inj_", c(VVF_INJ_GROUPS, "all")))]
}

#' The team's previous-game starter is listed Out or Doubtful for this game;
#' qb_change compares this game's actual starter with the previous one
vvf_qb_out <- function(g, inj_qb) {
  starters <- rbind(g[, .(game_id, kickoff, season, team = home_franchise, qb = home_qb_id)],
                    g[, .(game_id, kickoff, season, team = away_franchise, qb = away_qb_id)])
  setorder(starters, team, kickoff)
  starters[, prev_qb := shift(qb), by = team]
  starters[, qb_change := !is.na(prev_qb) & !is.na(qb) & qb != prev_qb]
  listed <- unique(inj_qb[status %in% c("out", "doubtful"),
                          .(game_id, team = vvf_franchise(team), prev_qb = gsis_id, listed = TRUE)])
  starters <- merge(starters, listed, by = c("game_id", "team", "prev_qb"), all.x = TRUE)
  starters[, .(game_id, team, qb_out = !is.na(listed), qb_change)]
}

#' Referee tendencies from prior seasons only: mean (y - p_c0) and mean
#' (total - total_line), shrunk toward 0 with VVF_REF_SHRINK_GAMES pseudo-games
vvf_referee_tendencies <- function(d) {
  seasons <- sort(unique(d$season))
  out <- vector("list", length(seasons))
  for (i in seq_along(seasons)) {
    s <- seasons[i]
    prior <- d[season < s & !is.na(referee) & referee != ""]
    if (!nrow(prior)) next
    t <- prior[, .(n = .N, ml_sum = sum(y - p_c0, na.rm = TRUE), n_ml = sum(!is.na(y)),
                   tot_sum = sum(total - total_line, na.rm = TRUE), n_tot = sum(!is.na(total_line))), by = referee]
    t[, `:=`(ref_ml_resid = ml_sum / (n_ml + VVF_REF_SHRINK_GAMES),
             ref_tot_resid = tot_sum / (n_tot + VVF_REF_SHRINK_GAMES), season = s)]
    out[[i]] <- t[, .(season, referee, ref_ml_resid, ref_tot_resid)]
  }
  rbindlist(out)
}

#' Build the anchor-free feature table for every predicted game (seasons <= max_season)
vvf_build_features <- function(base, inp, max_season) {
  d <- copy(base$pred)
  vvf_guard_seasons(d$season, max_season, "feature rows")
  ctx <- inp$game_context[season <= max_season]
  d <- merge(d, ctx[, .(game_id, weekday, total_line, over_odds, under_odds, home_spread_odds, away_spread_odds,
                        surface, temp_obs, wind_obs, referee, stadium_id)], by = "game_id", all.x = TRUE)
  d[, `:=`(margin = home_score - away_score, total = home_score + away_score)]
  d[, lp_c0 := bt_logit(bt_clip(p_c0))]

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
  v <- inp$venues
  hv <- vvf_home_venues(merge(d, ctx[, .(game_id)], by = "game_id"))
  d <- merge(d, v[, .(stadium_id, g_lat = latitude, g_lon = longitude, g_elev = elevation_m, g_tz = timezone)],
             by = "stadium_id", all.x = TRUE)
  for (side in c("home", "away")) {
    hs <- merge(hv, v[, .(home_stadium = stadium_id, lat = latitude, lon = longitude, tz = timezone)], by = "home_stadium")
    setnames(hs, c("team", "lat", "lon", "tz"), c(paste0(side, "_franchise"), paste0(side, "_lat"), paste0(side, "_lon"),
                                                  paste0(side, "_tz")))
    d <- merge(d, hs[, -"home_stadium"], by = c("season", paste0(side, "_franchise")), all.x = TRUE)
  }
  d[, away_travel_1000km := vvf_haversine_km(away_lat, away_lon, g_lat, g_lon) / 1000]
  d[, home_travel_1000km := vvf_haversine_km(home_lat, home_lon, g_lat, g_lon) / 1000]
  d[, travel_diff_1000km := away_travel_1000km - home_travel_1000km]
  d[, tz_shift_away := vvf_utc_offset_h(kickoff, g_tz) - vvf_utc_offset_h(kickoff, away_tz)]
  d[, abs_tz_away := abs(tz_shift_away)]
  d[, away_body_hour := vvf_local_hour(kickoff, away_tz)]
  d[, west_early := as.integer(!is.na(away_body_hour) & away_body_hour < 11 & tz_shift_away >= 2)]
  d[, local_hour := vvf_local_hour(kickoff, g_tz)]
  d[, primetime := as.integer(!is.na(local_hour) & local_hour >= 19.5)]
  d[, altitude := as.integer(!is.na(g_elev) & g_elev >= 1000)]

  # injuries (report_status, > 6 h before kickoff); no report row = 0
  ii <- vvf_injury_index(inp$injuries_team[season <= max_season])
  for (side in c("home", "away")) {
    x <- copy(ii); setnames(x, "team", paste0(side, "_franchise"))
    setnames(x, setdiff(names(x), c("game_id", paste0(side, "_franchise"))),
             paste0(side, "_", setdiff(names(x), c("game_id", paste0(side, "_franchise")))))
    d <- merge(d, x, by = c("game_id", paste0(side, "_franchise")), all.x = TRUE)
  }
  inj_cols <- grep("^(home|away)_inj_", names(d), value = TRUE)
  for (cc in inj_cols) set(d, which(is.na(d[[cc]])), cc, 0)
  for (grp in c(VVF_INJ_GROUPS, "all")) d[, (paste0("inj_diff_", grp)) := get(paste0("home_inj_", grp)) - get(paste0("away_inj_", grp))]
  d[, inj_reported := as.integer(game_id %in% inp$injuries_team$game_id)]

  qb <- vvf_qb_out(d[, .(game_id, kickoff, season, home_franchise, away_franchise, home_qb_id, away_qb_id)],
                   inp$injuries_qb[season <= max_season])
  for (side in c("home", "away")) {
    x <- copy(qb); setnames(x, c("team", "qb_out", "qb_change"), c(paste0(side, "_franchise"), paste0(side, "_qb_out"),
                                                                 paste0(side, "_qb_change")))
    d <- merge(d, x, by = c("game_id", paste0(side, "_franchise")), all.x = TRUE)
  }
  d[, `:=`(qb_out_diff = as.integer(home_qb_out %in% TRUE) - as.integer(away_qb_out %in% TRUE),
           qb_change_diff = as.integer(home_qb_change %in% TRUE) - as.integer(away_qb_change %in% TRUE))]

  # referee (prior seasons only)
  rt <- vvf_referee_tendencies(d)
  d <- merge(d, rt, by = c("season", "referee"), all.x = TRUE)
  d[is.na(ref_ml_resid), ref_ml_resid := 0]
  d[is.na(ref_tot_resid), ref_tot_resid := 0]

  # spread / total market prices (devigged when both sides are quoted) and residuals
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

#' Add the anchor-relative features for `anchor` ("close" = the no-vig close
#' p_c0; "open" = the no-vig opener p_open, which also needs the same venue's
#' close p_close_venue for the movement target). Returns a copy.
vvf_anchor_features <- function(d, anchor = c("close", "open")) {
  anchor <- match.arg(anchor)
  need <- c(VVF_ANCHORS[[anchor]], if (anchor == "open") "p_close_venue")
  miss <- setdiff(need, names(d))
  if (length(miss)) {
    stop(sprintf("vvf_anchor_features: anchor '%s' needs column %s", anchor, paste(miss, collapse = ", ")), call. = FALSE)
  }
  d <- copy(d)
  d[, p_anchor := get(VVF_ANCHORS[[anchor]])]
  d[, lp_anchor := bt_logit(bt_clip(p_anchor))]
  d[, `:=`(d_c1 = bt_logit(bt_clip(p_c1)) - lp_anchor, d_c2 = bt_logit(bt_clip(p_c2)) - lp_anchor,
           d_e1 = bt_logit(bt_clip(p_e1)) - lp_anchor,
           home_dog = as.integer(p_anchor < 0.5), big_fav = as.integer(abs(p_anchor - 0.5) > 0.3))]
  if (anchor == "open") d[, delta := bt_logit(bt_clip(p_close_venue)) - lp_anchor]
  setattr(d, "vvf_anchor", anchor)
  d[]
}

# =============================================================================
# nfl_preclose_v1 (reports/2026-11-02/preclose-v1/PROTOCOL.md): v1's C2 features on an
# information set. v1's estimator (backtest/candidates/epa_glm.R) is unchanged; what
# changes is which earlier games a feature may see and which QB it describes:
#   IS-B  v1's own: every game that kicked off before the target, and the target's
#         actual starter (bt_epa_features).
#   IS-A  every game that kicked off before the first kickoff of week w-1 of the
#         target's season (no game of that season for weeks 1-2), and the starter of
#         the team's previous game, his EPA state at the same cutoff.
#   IS-T  the Tuesday track's: every game before the first kickoff of week w (IS-B's
#         results), and the starter of the team's previous game, the only starter
#         known on Tuesday.
# Needs backtest/common.R and backtest/candidates/epa_glm.R.
# =============================================================================

#' Each (season, week)'s IS-A cutoff: the first kickoff of week w-1 of the same season,
#' or the season's first kickoff for its first week
pc_isa_week_cutoffs <- function(games) {
  w <- games[, .(first_kick = min(kickoff)), by = .(season, week)]
  setorder(w, season, week)
  w[, isa_cutoff := shift(first_kick), by = season]
  w[is.na(isa_cutoff), isa_cutoff := first_kick]
  w[]
}

#' The starter of each team's previous game (any earlier season included), per game:
#' home_prev_qb and away_prev_qb; NA for a franchise's first game in the data
pc_prev_starters <- function(games) {
  long <- rbind(games[, .(game_id, kickoff, team = home_franchise, qb = home_qb_id, side = "home")],
                games[, .(game_id, kickoff, team = away_franchise, qb = away_qb_id, side = "away")])
  setorder(long, team, kickoff, game_id)
  long[, prev_qb := shift(qb), by = team]
  dcast(long, game_id ~ side, value.var = "prev_qb")[, .(game_id, home_prev_qb = home, away_prev_qb = away)]
}

#' Point-in-time EPA features on IS-A or IS-B for every game of `target_seasons`
#' (one halflife). info = "B" is v1's bt_epa_features, value for value.
pc_epa_features <- function(games, team_games, qb_games, halflife, target_seasons, info = c("A", "B", "T")) {
  info <- match.arg(info)
  decay <- 0.5^(1 / halflife)
  disc <- BT_EPA_SEASON_DISCOUNT
  k <- BT_EPA_PRIOR_GAMES

  tr <- bt_epa_team_rows(games, team_games)
  qr <- merge(qb_games, games[, .(game_id, season, kickoff)], by = "game_id")
  setorder(qr, qb_id, kickoff)
  pri <- bt_epa_league_priors(tr, qr)

  stat_cols <- c("off_plays", "off_epa", "off_sr", "off_pp", "off_pass", "off_rp", "off_rush",
                 "def_plays", "def_epa", "def_sr", "def_pp", "def_pass", "def_rp", "def_rush")
  tr[, idx := seq_len(.N)]
  st <- tr[, {
    m <- bt_ew_states(as.matrix(.SD), season, decay, disc)
    as.data.table(m)[, `:=`(idx = idx, kickoff = kickoff, season = season)]
  }, by = team, .SDcols = stat_cols]
  qr[, idx := seq_len(.N)]
  qst <- qr[, {
    m <- bt_ew_states(cbind(db = dropbacks, epa = qb_epa_sum), season, decay, disc)
    data.table(db = m[, "db"], epa = m[, "epa"], kickoff = kickoff, season = season)
  }, by = qb_id]

  tg <- games[season %in% target_seasons]
  if (info %in% c("A", "T")) {
    tg <- merge(tg, pc_isa_week_cutoffs(games)[, .(season, week, isa_cutoff, first_kick)], by = c("season", "week"), sort = FALSE)
    tg <- merge(tg, pc_prev_starters(games), by = "game_id", sort = FALSE)
    setorder(tg, kickoff, game_id)
    see <- if (info == "A") tg$isa_cutoff else tg$first_kick; hqb <- tg$home_prev_qb; aqb <- tg$away_prev_qb
  } else {
    see <- tg$kickoff; hqb <- tg$home_qb_id; aqb <- tg$away_qb_id
  }

  # the state of `who` (team or QB) after its last game that kicked off strictly before
  # `see`, discounted for any season boundary (v1's lookup, with the cutoff as a parameter)
  lookup <- function(states, key_col, keys, see, seas) {
    by_key <- split(seq_len(nrow(states)), states[[key_col]])
    val_cols <- setdiff(names(states), c(key_col, "kickoff", "season", "idx"))
    vals <- as.matrix(states[, ..val_cols])
    s_kick <- as.numeric(states$kickoff); s_season <- states$season
    out <- matrix(0, length(keys), length(val_cols), dimnames = list(NULL, val_cols))
    src_kick <- rep(NA_real_, length(keys))
    for (i in seq_along(keys)) {
      if (is.na(keys[i])) next
      rows <- by_key[[keys[i]]]
      if (is.null(rows)) next
      j <- findInterval(as.numeric(see[i]) - 1, s_kick[rows])
      if (j == 0) next
      r <- rows[j]
      out[i, ] <- vals[r, ] * disc^(seas[i] - s_season[r])
      src_kick[i] <- s_kick[r]
    }
    list(values = out, src_kick = src_kick)
  }
  hs <- lookup(st, "team", tg$home_franchise, see, tg$season)
  as_ <- lookup(st, "team", tg$away_franchise, see, tg$season)
  hq <- lookup(qst, "qb_id", hqb, see, tg$season)
  aq <- lookup(qst, "qb_id", aqb, see, tg$season)

  p <- pri[match(tg$season, pri$season)]
  rate <- function(sum_stat, sum_n, mu, nbar) (sum_stat + k * mu * nbar) / (sum_n + k * nbar)
  team_rates <- function(v) {
    data.table(
      off_epa = rate(v[, "off_epa"], v[, "off_plays"], p$mu_epa, p$n_plays),
      off_sr = rate(v[, "off_sr"], v[, "off_plays"], p$mu_sr, p$n_plays),
      off_pass = rate(v[, "off_pass"], v[, "off_pp"], p$mu_pass, p$n_pp),
      off_rush = rate(v[, "off_rush"], v[, "off_rp"], p$mu_rush, p$n_rp),
      def_epa = rate(v[, "def_epa"], v[, "def_plays"], p$mu_epa, p$n_plays),
      def_sr = rate(v[, "def_sr"], v[, "def_plays"], p$mu_sr, p$n_plays),
      def_pass = rate(v[, "def_pass"], v[, "def_pp"], p$mu_pass, p$n_pp),
      def_rush = rate(v[, "def_rush"], v[, "def_rp"], p$mu_rush, p$n_rp)
    )
  }
  H <- team_rates(hs$values); A <- team_rates(as_$values)
  qb_h <- rate(hq$values[, "epa"], hq$values[, "db"], p$mu_qb, p$n_db)
  qb_a <- rate(aq$values[, "epa"], aq$values[, "db"], p$mu_qb, p$n_db)
  rest_h <- ifelse(is.na(tg$home_rest), 7, tg$home_rest)
  rest_a <- ifelse(is.na(tg$away_rest), 7, tg$away_rest)
  feats <- data.table(
    game_id = tg$game_id, season = tg$season, week = tg$week, wk = tg$wk, kickoff = tg$kickoff,
    d_off_epa = H$off_epa - A$off_epa, d_off_sr = H$off_sr - A$off_sr,
    d_off_pass = H$off_pass - A$off_pass, d_off_rush = H$off_rush - A$off_rush,
    d_def_epa = H$def_epa - A$def_epa, d_def_sr = H$def_sr - A$def_sr,
    d_def_pass = H$def_pass - A$def_pass, d_def_rush = H$def_rush - A$def_rush,
    d_qb_epa = qb_h - qb_a,
    d_rest = pmin(pmax(rest_h - rest_a, -7), 7),
    home = as.numeric(!tg$neutral)
  )
  src_kick <- pmax(hs$src_kick, as_$src_kick, hq$src_kick, aq$src_kick, na.rm = TRUE)
  feats[, src_end := as.POSIXct(src_kick + BT_GAME_DURATION_SEC, origin = "1970-01-01", tz = "UTC")]
  bt_assert_asof(feats$src_end, feats$kickoff, sprintf("EPA features (halflife %s, IS-%s)", halflife, info))
  if (info == "A") {
    bad <- which(is.finite(src_kick) & src_kick >= as.numeric(see))
    if (length(bad)) stop("pc_epa_features: IS-A features saw a game at or after the cutoff: ", paste(feats$game_id[bad][1:min(3, length(bad))], collapse = ", "),
                          call. = FALSE)
    feats[, isa_cutoff := see]
  }
  feats[]
}

#' Walk-forward C2 on an information set: refit each week on every game (seasons from
#' BT_EPA_FIRST_TRAIN_SEASON, no ties) that kicked off before the week's cutoff, the
#' first kickoff of the week (IS-B, as v1) or its IS-A cutoff
pc_epa_walk_forward <- function(feats, games, seasons, lambda, info = c("A", "B", "T"), features = BT_EPA_FEATURES) {
  info <- match.arg(info)
  weeks <- bt_week_schedule(games, seasons)
  if (info == "A") weeks <- merge(weeks, pc_isa_week_cutoffs(games)[, .(season, week, cutoff_a = isa_cutoff)], by = c("season", "week"))[, cutoff := cutoff_a][, cutoff_a := NULL]
  setorder(weeks, cutoff, wk)
  bt_epa_walk_forward(feats, games, weeks, lambda, features)
}

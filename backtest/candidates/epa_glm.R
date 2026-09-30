# =============================================================================
# C2 EPA GLM: ridge logistic model on home-minus-away differences of
# exponentially weighted (by team-game) efficiency, computed point-in-time.
#
# For team T before game g, with T's earlier games j (most recent first):
#   weight_j = decay^age_j * season_discount^(seasons between j and g),  decay = 0.5^(1/halflife)
#   rate     = (sum_j weight_j * stat_j + k * mu * nbar) / (sum_j weight_j * plays_j + k * nbar)
# mu and nbar are the previous season's league per-play mean and plays per team-game,
# so the prior pulls early-season teams toward the league. Defense uses the plays
# opponents ran against T. The starting-QB feature is the same estimator over the
# starter's own dropbacks (qb_epa), whatever team they played for.
# Every row records the end time of the latest source game; bt_assert_asof()
# rejects any row whose sources were not final before its kickoff.
# =============================================================================

BT_EPA_PRIOR_GAMES <- 3
BT_EPA_SEASON_DISCOUNT <- 0.5
BT_EPA_FIRST_TRAIN_SEASON <- 2008L
BT_EPA_FEATURES <- c("d_off_epa", "d_off_sr", "d_off_pass", "d_off_rush",
                     "d_def_epa", "d_def_sr", "d_def_pass", "d_def_rush",
                     "d_qb_epa", "d_rest")

BT_EPA_GRID <- CJ(halflife = c(4, 8, 16), lambda = c(1, 10, 100, 300, 1000))

# Offense and defense rows per (game, team), with kickoff and season
bt_epa_team_rows <- function(games, team_games) {
  g <- games[, .(game_id, season, kickoff)]
  off <- team_games[, .(game_id, team, off_plays = plays, off_epa = epa_sum, off_sr = success_sum,
                        off_pp = pass_plays, off_pass = pass_epa_sum, off_rp = rush_plays, off_rush = rush_epa_sum)]
  def <- team_games[, .(game_id, team = opp, def_plays = plays, def_epa = epa_sum, def_sr = success_sum,
                        def_pp = pass_plays, def_pass = pass_epa_sum, def_rp = rush_plays, def_rush = rush_epa_sum)]
  r <- merge(off, def, by = c("game_id", "team"))
  r <- merge(r, g, by = "game_id")
  setorder(r, team, kickoff)
  r[]
}

# League priors by season, from the previous season's rows
bt_epa_league_priors <- function(team_rows, qb_rows) {
  s <- team_rows[, .(
    mu_epa = sum(off_epa) / sum(off_plays), mu_sr = sum(off_sr) / sum(off_plays),
    mu_pass = sum(off_pass) / sum(off_pp), mu_rush = sum(off_rush) / sum(off_rp),
    n_plays = mean(off_plays), n_pp = mean(off_pp), n_rp = mean(off_rp)
  ), by = season]
  q <- qb_rows[, .(mu_qb = sum(qb_epa_sum) / sum(dropbacks)), by = season]
  qg <- qb_rows[, .(db = sum(dropbacks)), by = .(season, game_id, team)][, .(n_db = mean(db)), by = season]
  s <- merge(merge(s, q, by = "season"), qg, by = "season")
  setorder(s, season)
  # prior for season t comes from season t-1; the first season uses itself (warm-up only)
  lagged <- copy(s)
  lagged[, season := season + 1L]
  first <- s[1]
  out <- rbind(first, lagged)[season <= max(s$season) + 1L]
  out[]
}

# Post-game exponentially weighted sums for an ordered stream of rows.
# x: numeric matrix of per-game sums; seasons: integer; returns matrix of post-game states.
bt_ew_states <- function(x, seasons, decay, season_discount) {
  n <- nrow(x)
  out <- matrix(0, n, ncol(x), dimnames = list(NULL, colnames(x)))
  state <- rep(0, ncol(x))
  for (i in seq_len(n)) {
    if (i > 1) state <- state * decay * season_discount^(seasons[i] - seasons[i - 1])
    state <- state + x[i, ]
    out[i, ] <- state
  }
  out
}

#' Point-in-time EPA features for every game in `target_games` (one halflife)
bt_epa_features <- function(games, team_games, qb_games, halflife, target_seasons) {
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

  # Pre-game state of `who` (team or QB) before each target kickoff: the post-game
  # state of their last earlier game, discounted for any season boundary.
  lookup <- function(states, key_col, keys, kick, seas) {
    by_key <- split(seq_len(nrow(states)), states[[key_col]])
    val_cols <- setdiff(names(states), c(key_col, "kickoff", "season", "idx"))
    vals <- as.matrix(states[, ..val_cols])
    s_kick <- as.numeric(states$kickoff); s_season <- states$season
    out <- matrix(0, length(keys), length(val_cols), dimnames = list(NULL, val_cols))
    src_end <- rep(NA_real_, length(keys))
    for (i in seq_along(keys)) {
      if (is.na(keys[i])) next
      rows <- by_key[[keys[i]]]
      if (is.null(rows)) next
      j <- findInterval(as.numeric(kick[i]) - 1, s_kick[rows])   # last kickoff strictly before
      if (j == 0) next
      r <- rows[j]
      out[i, ] <- vals[r, ] * disc^(seas[i] - s_season[r])
      src_end[i] <- s_kick[r] + BT_GAME_DURATION_SEC
    }
    list(values = out, src_end = as.POSIXct(src_end, origin = "1970-01-01", tz = "UTC"))
  }

  hs <- lookup(st, "team", tg$home_franchise, tg$kickoff, tg$season)
  as_ <- lookup(st, "team", tg$away_franchise, tg$kickoff, tg$season)
  hq <- lookup(qst, "qb_id", tg$home_qb_id, tg$kickoff, tg$season)
  aq <- lookup(qst, "qb_id", tg$away_qb_id, tg$kickoff, tg$season)

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
  src <- pmax(hs$src_end, as_$src_end, hq$src_end, aq$src_end, na.rm = TRUE)
  feats[, src_end := src]
  bt_assert_asof(feats$src_end, feats$kickoff, sprintf("EPA features (halflife %s)", halflife))
  feats[]
}

#' Fit on training rows and predict target rows (no intercept; `home` unpenalized;
#' features scaled by training sd, not centered, so swapping home/away flips signs)
bt_epa_fit_predict <- function(train, target, lambda, features = BT_EPA_FEATURES) {
  sds <- vapply(features, function(f) sd(train[[f]]), numeric(1))
  sds[!is.finite(sds) | sds == 0] <- 1
  mk <- function(d) cbind(sweep(as.matrix(d[, ..features]), 2, sds, "/"), home = d$home)
  X <- mk(train)
  beta <- bt_ridge_logistic(X, train$y, lambda, unpenalized = ncol(X))
  drop(bt_expit(mk(target) %*% beta))
}

#' Walk-forward C2 predictions: weekly refit on all earlier games
#' (seasons >= BT_EPA_FIRST_TRAIN_SEASON, no ties).
bt_epa_walk_forward <- function(feats, games, weeks, lambda, features = BT_EPA_FEATURES) {
  d <- merge(feats, games[, .(game_id, y)], by = "game_id")
  setorder(d, kickoff, game_id)
  out <- vector("list", nrow(weeks))
  for (i in seq_len(nrow(weeks))) {
    cut <- weeks$cutoff[i]
    train <- d[kickoff < cut & season >= BT_EPA_FIRST_TRAIN_SEASON & !is.na(y)]
    target <- d[wk == weeks$wk[i]]
    if (nrow(target) == 0L) next
    stopifnot(max(train$kickoff) < cut)
    out[[i]] <- data.table(game_id = target$game_id, p_c2 = bt_epa_fit_predict(train, target, lambda, features))
  }
  rbindlist(out)
}

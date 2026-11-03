# The model gauntlet's families (PLAN.md). Each one fits on games that kicked off before a cutoff, or runs
# sequentially so that a game's prediction comes before its result, and gives P(home win); the margin families
# also give a median margin. Definitions only: sourced by gauntlet.R and tests/testthat/test-model-gauntlet.R,
# after backtest/common.R and backtest/candidates/elo.R.

MG_SIGMA_FLOOR <- 10      # points: a margin SD below this is not credible for the NFL
MG_TD_POINTS <- 7         # a touchdown with its try (the league mean is about 6.95)
MG_REPLACEMENT_QB <- -0.10  # EPA per dropback assumed for a starter with no history

#' Weight of a game `age_weeks` old with half-life `halflife` weeks (Inf: equal weights)
mg_decay <- function(age_weeks, halflife) if (is.infinite(halflife)) rep(1, length(age_weeks)) else 0.5^(age_weeks / halflife)

mg_played_before <- function(g, cutoff) g[kickoff < cutoff & !is.na(home_score) & !is.na(away_score)]

# ---- F4-F6: margin ratings ---------------------------------------------------------------------------------

#' Weighted least squares on margins: margin = s_home - s_away + hfa * home (+ a team home term).
#' team_hfa: "none" (league home field); "strength_free" (a team home term, ridge-shrunk toward the league value,
#' estimated jointly with strength); "engine" (team_hfa_table()'s estimator: the team's mean home margin shrunk
#' n / (n + 60) toward the league value, with strengths from the "none" fit).
mg_ratings_fit <- function(g, cutoff, halflife_weeks, team_hfa = c("none", "strength_free", "engine"), shrink = 4) {
  team_hfa <- match.arg(team_hfa)
  tr <- mg_played_before(g, cutoff)
  teams <- sort(unique(c(tr$home_franchise, tr$away_franchise)))
  n <- nrow(tr); k <- length(teams)
  w <- mg_decay(as.numeric(difftime(cutoff, tr$kickoff, units = "weeks")), halflife_weeks)
  margin <- tr$home_score - tr$away_score
  hi <- match(tr$home_franchise, teams); ai <- match(tr$away_franchise, teams)
  X <- matrix(0, n, k, dimnames = list(NULL, teams))
  X[cbind(seq_len(n), hi)] <- 1
  X[cbind(seq_len(n), ai)] <- -1
  home <- as.numeric(!tr$neutral)
  Z <- cbind(X, hfa = home)
  pen <- c(rep(1e-8, k), 0)                                  # strengths are defined up to a constant
  if (team_hfa == "strength_free") {
    H <- matrix(0, n, k, dimnames = list(NULL, paste0("h_", teams)))
    H[cbind(seq_len(n), hi)] <- home
    Z <- cbind(Z, H)
    pen <- c(pen, rep(shrink, k))
  }
  beta <- drop(solve(crossprod(Z * w, Z) + diag(pen, ncol(Z)), crossprod(Z * w, margin)))
  strength <- setNames(beta[seq_len(k)], teams)
  hfa <- beta[["hfa"]]
  t_hfa <- setNames(rep(hfa, k), teams)
  if (team_hfa == "strength_free") t_hfa <- hfa + setNames(beta[k + 1 + seq_len(k)], teams)
  if (team_hfa == "engine") {
    hm <- tr[neutral == FALSE, .(m = mean(home_score - away_score), n = .N), by = home_franchise]
    wt <- hm$n / (hm$n + 60)
    t_hfa[hm$home_franchise] <- wt * hm$m + (1 - wt) * hfa
  }
  resid <- margin - drop(Z %*% beta)
  sigma <- max(MG_SIGMA_FLOOR, sqrt(sum(w * resid^2) / sum(w)))
  list(strength = strength, hfa = hfa, team_hfa = t_hfa, sigma = sigma)
}

#' Margin and P(home win) for `newg` (home_franchise, away_franchise, neutral). A team with no history rates 0.
mg_ratings_predict <- function(fit, newg) {
  s <- function(t) { v <- fit$strength[t]; v[is.na(v)] <- 0; unname(v) }
  h <- fit$team_hfa[newg$home_franchise]; h[is.na(h)] <- fit$hfa
  margin <- s(newg$home_franchise) - s(newg$away_franchise) + ifelse(newg$neutral, 0, unname(h))
  data.table(margin = margin, p_home = stats::pnorm(margin / fit$sigma))
}

# ---- F7: Poisson scores (Maher) ----------------------------------------------------------------------------

#' log E[points] = intercept + attack(scorer) + defence(opponent) + home, as an exponentially weighted Poisson GLM
mg_poisson_fit <- function(g, cutoff, halflife_weeks) {
  tr <- mg_played_before(g, cutoff)
  teams <- sort(unique(c(tr$home_franchise, tr$away_franchise)))
  w <- mg_decay(as.numeric(difftime(cutoff, tr$kickoff, units = "weeks")), halflife_weeks)
  long <- data.table(pts = c(tr$home_score, tr$away_score),
                     att = factor(c(tr$home_franchise, tr$away_franchise), levels = teams),
                     def = factor(c(tr$away_franchise, tr$home_franchise), levels = teams),
                     home = c(as.numeric(!tr$neutral), rep(0, nrow(tr))), w = c(w, w))
  X <- stats::model.matrix(~ att + def + home, data = long)
  fit <- stats::glm.fit(X, long$pts, weights = long$w, family = stats::poisson())
  b <- fit$coefficients; b[is.na(b)] <- 0
  list(b = b, teams = teams)
}

mg_poisson_means <- function(fit, att, def, home) {
  b <- fit$b
  eff <- function(prefix, t) { v <- b[paste0(prefix, t)]; v[is.na(v)] <- 0; unname(v) }   # the base level and new teams are 0
  exp(b[["(Intercept)"]] + eff("att", att) + eff("def", def) + b[["home"]] * home)
}

#' P(home win), P(away win), P(tie) from two independent Poisson scores; p_home splits a tie
mg_poisson_predict <- function(fit, newg) {
  home <- as.numeric(!newg$neutral)
  mh <- mg_poisson_means(fit, newg$home_franchise, newg$away_franchise, home)
  ma <- mg_poisson_means(fit, newg$away_franchise, newg$home_franchise, 0)
  x <- 0:90
  out <- t(vapply(seq_along(mh), function(i) {
    j <- outer(stats::dpois(x, mh[i]), stats::dpois(x, ma[i]))
    c(win = sum(j[lower.tri(j)]), loss = sum(j[upper.tri(j)]), tie = sum(diag(j)))
  }, numeric(3)))
  s <- rowSums(out)
  data.table(p_win = out[, "win"] / s, p_loss = out[, "loss"] / s, p_tie = out[, "tie"] / s,
             p_home = (out[, "win"] + 0.5 * out[, "tie"]) / s, margin = mh - ma)
}

# ---- F8: dynamic ratings (Kalman filter) -------------------------------------------------------------------

#' Team strengths follow random walks (process_sd points per week of time); the home field is a state with no
#' process noise; between seasons strengths shrink by `carry`. Each game's prediction comes before its update.
mg_kalman_run <- function(g, process_sd, carry, obs_sd = 13.5, hfa0 = 2, prior_sd = 7) {
  teams <- sort(unique(c(g$home_franchise, g$away_franchise)))
  k <- length(teams)
  x <- c(rep(0, k), hfa0)
  P <- diag(c(rep(prior_sd^2, k), 4), k + 1)
  last <- rep(NA_real_, k)
  season_now <- g$season[1]
  n <- nrow(g)
  p_out <- numeric(n); m_out <- numeric(n)
  hi <- match(g$home_franchise, teams); ai <- match(g$away_franchise, teams)
  t_week <- as.numeric(g$kickoff) / (7 * 86400)
  for (i in seq_len(n)) {
    if (g$season[i] != season_now) {
      x[seq_len(k)] <- carry * x[seq_len(k)]
      P[seq_len(k), seq_len(k)] <- carry^2 * P[seq_len(k), seq_len(k)] + diag((1 - carry^2) * prior_sd^2, k)
      season_now <- g$season[i]
    }
    for (t in c(hi[i], ai[i])) {
      if (!is.na(last[t])) P[t, t] <- P[t, t] + process_sd^2 * max(0, t_week[i] - last[t])
      last[t] <- t_week[i]
    }
    h <- numeric(k + 1); h[hi[i]] <- 1; h[ai[i]] <- -1; h[k + 1] <- if (g$neutral[i]) 0 else 1
    mu <- sum(h * x)
    S <- drop(crossprod(h, P %*% h)) + obs_sd^2
    m_out[i] <- mu
    p_out[i] <- stats::pnorm(mu / sqrt(S))
    if (is.na(g$home_score[i]) || is.na(g$away_score[i])) next
    Kg <- drop(P %*% h) / S
    x <- x + Kg * ((g$home_score[i] - g$away_score[i]) - mu)
    P <- P - tcrossprod(Kg, drop(crossprod(h, P)))
  }
  data.table(game_id = g$game_id, p_home = p_out, margin = m_out)
}

# ---- F9: drive simulator ------------------------------------------------------------------------------------

MG_DRIVE_OUTCOMES <- c("td", "fg", "def", "safety")   # per drive; "def" is a touchdown scored by the defence

#' One offence against one defence: each outcome's rate = league * (offence / league) * (defence / league)
mg_drive_matchup <- function(off, def, league) {
  r <- league[MG_DRIVE_OUTCOMES] * (off[MG_DRIVE_OUTCOMES] / league[MG_DRIVE_OUTCOMES]) * (def[MG_DRIVE_OUTCOMES] / league[MG_DRIVE_OUTCOMES])
  if (sum(r) > 0.95) r <- r * 0.95 / sum(r)
  r
}

#' Simulate games drive by drive: each side's drive count is 1 + Poisson(drives - 1); every drive ends in a
#' touchdown, a field goal, a defensive touchdown, a safety or nothing. A tie is split.
mg_drive_sim <- function(home_rates, away_rates, home_drives, away_drives, n_sims = 20000L, seed = 1L) {
  old <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
  on.exit(if (is.null(old)) rm(".Random.seed", envir = globalenv()) else assign(".Random.seed", old, envir = globalenv()))
  set.seed(seed, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  side <- function(r, drives) {
    n <- 1L + stats::rpois(n_sims, max(drives - 1, 0.5))
    td <- stats::rbinom(n_sims, n, r[["td"]]); left <- n - td
    fg <- stats::rbinom(n_sims, left, r[["fg"]] / (1 - r[["td"]])); left <- left - fg
    dt <- stats::rbinom(n_sims, left, r[["def"]] / (1 - r[["td"]] - r[["fg"]])); left <- left - dt
    sf <- stats::rbinom(n_sims, left, r[["safety"]] / (1 - r[["td"]] - r[["fg"]] - r[["def"]]))
    list(own = MG_TD_POINTS * td + 3L * fg, conceded = MG_TD_POINTS * dt + 2L * sf)
  }
  h <- side(home_rates, home_drives); a <- side(away_rates, away_drives)
  margins <- (h$own + a$conceded) - (a$own + h$conceded)
  list(p_home = mean(margins > 0) + 0.5 * mean(margins == 0), margin = stats::median(margins), margins = margins)
}

#' Drive rates by offence and by defence, exponentially weighted, with `prior_drives` pseudo-drives at the league
#' rate; a home factor per outcome (league home rate over league rate); drives per game by team (pace).
#' `drives` has one row per team-game: game_id, kickoff, team, opp, home (0/1), drives and the outcome counts.
mg_drive_rates <- function(drives, cutoff, halflife_weeks, prior_drives = 60) {
  tr <- drives[kickoff < cutoff]
  w <- mg_decay(as.numeric(difftime(cutoff, tr$kickoff, units = "weeks")), halflife_weeks)
  tot <- sum(w * tr$drives)
  league <- vapply(MG_DRIVE_OUTCOMES, function(o) sum(w * tr[[o]]) / tot, numeric(1))
  home_f <- vapply(MG_DRIVE_OUTCOMES, function(o) (sum((w * tr[[o]])[tr$home == 1]) / sum((w * tr$drives)[tr$home == 1])) / league[[o]], numeric(1))
  rate_by <- function(key) {
    teams <- sort(unique(tr[[key]]))
    m <- t(vapply(teams, function(t) {
      i <- tr[[key]] == t
      d <- sum(w[i] * tr$drives[i])
      vapply(MG_DRIVE_OUTCOMES, function(o) (sum(w[i] * tr[[o]][i]) + prior_drives * league[[o]]) / (d + prior_drives), numeric(1))
    }, numeric(length(MG_DRIVE_OUTCOMES))))
    dimnames(m) <- list(teams, MG_DRIVE_OUTCOMES)
    m
  }
  games_w <- tr[, .(w = mg_decay(as.numeric(difftime(cutoff, kickoff, units = "weeks")), halflife_weeks), drives), by = .(team)]
  pace <- games_w[, .(pace = (sum(w * drives) + 4 * mean(tr$drives)) / (sum(w) + 4)), by = team]
  list(off = rate_by("team"), def = rate_by("opp"), league = league, home = home_f,
       pace = setNames(pace$pace, pace$team), league_pace = mean(tr$drives))
}

#' P(home win) and median margin for each game of `newg` from fitted drive rates
mg_drive_predict <- function(rates, newg, n_sims = 20000L, seed = 20261103L) {
  get_row <- function(m, t) if (t %in% rownames(m)) m[t, ] else rates$league
  out <- lapply(seq_len(nrow(newg)), function(i) {
    h <- newg$home_franchise[i]; a <- newg$away_franchise[i]; hf <- if (newg$neutral[i]) rep(1, 4) else rates$home
    rh <- mg_drive_matchup(get_row(rates$off, h), get_row(rates$def, a), rates$league) * hf
    ra <- mg_drive_matchup(get_row(rates$off, a), get_row(rates$def, h), rates$league) * (if (newg$neutral[i]) rep(1, 4) else 2 - rates$home)
    pace <- function(t) if (t %in% names(rates$pace)) rates$pace[[t]] else rates$league_pace
    d <- (pace(h) + pace(a)) / 2
    s <- mg_drive_sim(rh, ra, d, d, n_sims = n_sims, seed = seed + i)
    data.table(p_home = s$p_home, margin = s$margin)
  })
  rbindlist(out)
}

# ---- F2: QB-adjusted Elo -----------------------------------------------------------------------------------

#' C1's Elo (bt_elo_run) with a starting-QB adjustment to each prediction: qb_weight * 25 Elo points per point of
#' margin * expected dropbacks * (starter's EPA per dropback - the team's recent starters'). A QB's value is his
#' exponentially weighted EPA per dropback over his previous games (half-life qb_halflife games), starting at a
#' replacement level; ratings are updated exactly as in C1.
mg_qb_elo_run <- function(games, qb_games, K, hfa, regress, qb_weight, qb_halflife, dropbacks = 35) {
  base <- bt_elo_run(games, K, hfa, regress)
  if (qb_weight == 0) return(data.table(game_id = games$game_id, p_home = base$p_c1))
  qg <- merge(qb_games, games[, .(game_id, kickoff)], by = "game_id")
  setorder(qg, kickoff)
  val <- list(); team_val <- list()
  decay <- 0.5^(1 / qb_halflife)
  value_of <- function(q) if (is.null(val[[q]])) MG_REPLACEMENT_QB else val[[q]]$num / val[[q]]$den
  # the QB values in force before each game: process QB games in kickoff order, predicting before updating
  adj <- numeric(nrow(games))
  gi <- split(seq_len(nrow(qg)), qg$game_id)
  elo_diff <- 400 * log10(base$p_c1 / (1 - base$p_c1))
  for (i in seq_len(nrow(games))) {
    gid <- games$game_id[i]
    hq <- games$home_qb_id[i]; aq <- games$away_qb_id[i]
    ht <- games$home_franchise[i]; at <- games$away_franchise[i]
    tv <- function(t) if (is.null(team_val[[t]])) MG_REPLACEMENT_QB else team_val[[t]]
    d_home <- value_of(hq) - tv(ht); d_away <- value_of(aq) - tv(at)
    adj[i] <- qb_weight * 25 * dropbacks * (d_home - d_away)
    rows <- gi[[gid]]
    if (is.null(rows)) next
    for (r in rows) {
      q <- qg$qb_id[r]; db <- qg$dropbacks[r]; e <- qg$qb_epa_sum[r]
      if (is.na(db) || db <= 0) next
      cur <- if (is.null(val[[q]])) list(num = 0, den = 0) else val[[q]]
      val[[q]] <- list(num = decay * cur$num + e, den = decay * cur$den + db)
      t <- qg$team[r]
      team_val[[t]] <- if (is.null(team_val[[t]])) value_of(q) else decay * team_val[[t]] + (1 - decay) * value_of(q)
    }
  }
  data.table(game_id = games$game_id, p_home = 1 / (1 + 10^(-(elo_diff + adj) / 400)))
}

# ---- stacks ---------------------------------------------------------------------------------------------------

#' logit P = a + b * logit(p0) + c * (logit(pF) - logit(p0)), ridge on c only: c = 0 means F adds nothing to p0
mg_stack_fit <- function(p0, pF, y, lambda = 1) {
  l0 <- bt_logit(bt_clip(p0)); dF <- bt_logit(bt_clip(pF)) - l0
  X <- cbind(a = 1, b = l0, c = dF)
  bt_ridge_logistic(X, y, lambda, unpenalized = 1:2)
}

mg_stack_predict <- function(fit, p0, pF) {
  l0 <- bt_logit(bt_clip(p0)); dF <- bt_logit(bt_clip(pF)) - l0
  bt_expit(fit[["a"]] + fit[["b"]] * l0 + fit[["c"]] * dF)
}

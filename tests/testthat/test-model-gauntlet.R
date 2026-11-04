# The model gauntlet's families (reports/2026-11-03/model-gauntlet/families.R) on synthetic leagues whose
# truth is known: each recovers what it should, and none uses a game played after the one it predicts.
suppressPackageStartupMessages(library(data.table))
for (f in c("common.R", "candidates/elo.R")) sys.source(file.path(PROJECT_ROOT, "backtest", f), envir = environment())
sys.source(file.path(PROJECT_ROOT, "reports", "2026-11-03", "model-gauntlet", "families.R"), envir = environment())

# a round-robin league: `weeks` weeks, every team plays every week, margins = strength difference + hfa + noise
synthetic_league <- function(strength, hfa = 2, weeks = 40, noise_sd = 0, seed = 1) {
  set.seed(seed)
  teams <- names(strength)
  rows <- list()
  t0 <- as.POSIXct("2010-09-12 17:00:00", tz = "UTC")
  for (w in seq_len(weeks)) {
    perm <- sample(teams)
    for (i in seq(1, length(perm), by = 2)) {
      h <- perm[i]; a <- perm[i + 1]
      m <- strength[[h]] - strength[[a]] + hfa + stats::rnorm(1, 0, noise_sd)
      rows[[length(rows) + 1]] <- data.table(game_id = sprintf("g%03d_%s_%s", w, a, h), season = 2010L, week = w, wk = 201000L + w,
                                             kickoff = t0 + (w - 1) * 7 * 86400 + i, home_franchise = h, away_franchise = a,
                                             home_score = 30 + m / 2, away_score = 30 - m / 2, neutral = FALSE)
    }
  }
  g <- rbindlist(rows)
  g[, y := as.integer(home_score > away_score)]
  setorder(g, kickoff)
  g[]
}

test_that("margin ratings recover planted strengths and home field, and predict the noiseless margin", {
  s <- c(A = 6, B = 3, C = 0, D = -2, E = -3, F = -4)
  g <- synthetic_league(s, hfa = 2.5, weeks = 30)
  fit <- mg_ratings_fit(g, cutoff = max(g$kickoff) + 1, halflife_weeks = Inf, team_hfa = "none")
  expect_equal(unname(fit$strength[names(s)] - mean(fit$strength)), unname(s - mean(s)), tolerance = 1e-6)
  expect_equal(fit$hfa, 2.5, tolerance = 1e-6)
  pr <- mg_ratings_predict(fit, data.table(home_franchise = "A", away_franchise = "F", neutral = FALSE))
  expect_equal(pr$margin, 6 - (-4) + 2.5, tolerance = 1e-6)
  expect_gt(pr$p_home, 0.5)
})

test_that("the strength-free team home field finds a planted home edge; the engine's estimator mixes in strength", {
  s <- c(A = 7, B = 3, C = 0, D = -1, E = -4, F = -5)
  g <- synthetic_league(s, hfa = 2, weeks = 40, noise_sd = 0)
  g[home_franchise == "C", `:=`(home_score = home_score + 2, away_score = away_score - 2)]   # C: +4 at home
  free <- mg_ratings_fit(g, cutoff = max(g$kickoff) + 1, halflife_weeks = Inf, team_hfa = "strength_free", shrink = 0.01)
  expect_gt(free$team_hfa[["C"]] - free$hfa, 3)
  expect_lt(abs(free$team_hfa[["A"]] - free$hfa), 1)
  expect_lt(abs(free$team_hfa[["A"]] - free$team_hfa[["F"]]), 1)
  # the engine's estimator (mean home margin shrunk n/(n+60), ~20 home games each): A (+7) against F (-5) comes out
  # about 0.25 * 14.4 = 3.6 points apart, all of it strength
  engine <- mg_ratings_fit(g, cutoff = max(g$kickoff) + 1, halflife_weeks = Inf, team_hfa = "engine")
  expect_gt(engine$team_hfa[["A"]] - engine$team_hfa[["F"]], 2.5)
})

test_that("Poisson scores give win, loss and tie probabilities that sum to 1, and a home edge", {
  s <- c(A = 0, B = 0, C = 0, D = 0)
  g <- synthetic_league(s, hfa = 3, weeks = 30, noise_sd = 7, seed = 3)
  g[, `:=`(home_score = pmax(0, round(home_score)), away_score = pmax(0, round(away_score)))]
  fit <- mg_poisson_fit(g, cutoff = max(g$kickoff) + 1, halflife_weeks = Inf)
  pr <- mg_poisson_predict(fit, data.table(home_franchise = c("A", "B"), away_franchise = c("C", "D"), neutral = FALSE))
  expect_equal(pr$p_win + pr$p_loss + pr$p_tie, c(1, 1), tolerance = 1e-9)
  expect_true(all(pr$p_home > 0.5 & pr$p_home < 0.75))
})

test_that("Kalman ratings track a step change, and a later result never changes an earlier prediction", {
  s <- c(A = 0, B = 0, C = 0, D = 0, E = 0, F = 0)
  g <- synthetic_league(s, hfa = 0, weeks = 40, noise_sd = 3, seed = 5)
  g[week > 20 & home_franchise == "A", home_score := home_score + 10]
  g[week > 20 & away_franchise == "A", away_score := away_score + 10]
  p <- mg_kalman_run(g, process_sd = 1, carry = 1, obs_sd = 13.5)
  a_home <- g[, .I[home_franchise == "A"]]
  expect_gt(mean(p$p_home[a_home[g$week[a_home] > 32]]), mean(p$p_home[a_home[g$week[a_home] <= 20]]) + 0.15)
  g2 <- copy(g); g2[nrow(g2), home_score := home_score + 50]
  p2 <- mg_kalman_run(g2, process_sd = 1, carry = 1, obs_sd = 13.5)
  expect_equal(p2$p_home, p$p_home)   # the last game's own prediction comes before its result
})

test_that("Kalman ratings predict every game of a kickoff before any of them updates the shared state", {
  s <- c(A = 0, B = 0, C = 0, D = 0, E = 0, F = 0)
  g <- synthetic_league(s, hfa = 0, weeks = 10, noise_sd = 3, seed = 6)
  g[week == 10, kickoff := min(kickoff)]   # the last week's three games kick off together
  setorder(g, kickoff, game_id)
  first <- g[week == 10, game_id][1]
  p <- mg_kalman_run(g, process_sd = 1, carry = 1, obs_sd = 13.5)
  g2 <- copy(g); g2[game_id == first, home_score := home_score + 40]   # an extreme result in one of them
  p2 <- mg_kalman_run(g2, process_sd = 1, carry = 1, obs_sd = 13.5)
  others <- g$week == 10 & g$game_id != first
  expect_equal(p2$p_home[others], p$p_home[others])   # not known at the others' kickoff
})

test_that("the drive simulator splits an even game, favours the better offence, and lands on 3 and 7", {
  even <- c(td = 0.22, fg = 0.15, def = 0.01, safety = 0.003)
  s1 <- mg_drive_sim(home_rates = even, away_rates = even, home_drives = 11.5, away_drives = 11.5, n_sims = 40000, seed = 7)
  expect_lt(abs(s1$p_home - 0.5), 0.01)
  strong <- c(td = 0.32, fg = 0.15, def = 0.01, safety = 0.003)
  s2 <- mg_drive_sim(home_rates = strong, away_rates = even, home_drives = 11.5, away_drives = 11.5, n_sims = 40000, seed = 7)
  expect_gt(s2$p_home, 0.65)
  m <- s1$margins
  share <- function(v) mean(abs(m) == v)
  expect_gt(share(7), share(5)); expect_gt(share(3), share(2))
})

synthetic_drives <- function() {
  t0 <- as.POSIXct("2015-09-13 17:00:00", tz = "UTC")
  rows <- list()
  teams <- c("A", "B", "C", "D")
  for (w in 1:20) {
    pairs <- list(c("A", "B"), c("C", "D"))
    if (w %% 2 == 0) pairs <- list(c("B", "A"), c("D", "C"))
    for (p in pairs) {
      gid <- sprintf("w%02d_%s_%s", w, p[2], p[1])   # p[1] at home
      for (side in 1:2) {
        team <- p[side]; opp <- p[3 - side]
        td <- if (team == "A") 4L else 2L
        rows[[length(rows) + 1]] <- data.table(game_id = gid, kickoff = t0 + (w - 1) * 7 * 86400, team = team, opp = opp,
                                               home = as.integer(side == 1), drives = 10L, td = td, fg = 2L, def = 0L, safety = 0L)
      }
    }
  }
  rbindlist(rows)
}

test_that("drive rates rate an offence above the league when it scores more, shrunk toward the league", {
  dr <- synthetic_drives()
  r <- mg_drive_rates(dr, cutoff = max(dr$kickoff) + 1, halflife_weeks = Inf, prior_drives = 60)
  raw_a <- 4 / 10
  expect_gt(r$off["A", "td"], r$league[["td"]])
  expect_lt(r$off["A", "td"], raw_a)                      # shrunk by the 60 pseudo-drives
  expect_equal(r$off["A", "td"], (200 * raw_a + 60 * r$league[["td"]]) / (200 + 60), tolerance = 1e-9)
  expect_equal(unname(r$pace["A"]), 10, tolerance = 1e-9)
})

test_that("drive predictions favour the better offence, drop the home factor on a neutral field, and count fallbacks", {
  dr <- synthetic_drives()
  dr[home == 1L & team %in% c("C", "D"), td := td + 1L]   # a home edge in the league
  r <- mg_drive_rates(dr, cutoff = max(dr$kickoff) + 1, halflife_weeks = Inf)
  newg <- data.table(home_franchise = c("A", "A", "Z"), away_franchise = c("C", "C", "C"), neutral = c(FALSE, TRUE, FALSE))
  pr <- mg_drive_predict(r, newg, n_sims = 20000L, seed = 3L)
  expect_gt(pr$p_home[1], 0.55)
  expect_gt(pr$p_home[1], pr$p_home[2])                   # the home factor applies only off a neutral field
  expect_equal(pr$fallback, c(0L, 0L, 1L))                # Z has no history: league rates, and counted
})

test_that("margin ratings count a team with no history as a fallback", {
  s <- c(A = 1, B = 0, C = -1, D = 0)
  g <- synthetic_league(s, hfa = 2, weeks = 10)
  fit <- mg_ratings_fit(g, cutoff = max(g$kickoff) + 1, halflife_weeks = Inf, team_hfa = "none")
  pr <- mg_ratings_predict(fit, data.table(home_franchise = c("A", "Z"), away_franchise = c("B", "Y"), neutral = FALSE))
  expect_equal(pr$fallback, c(0L, 2L))
})

test_that("drive rates combine an offence and a defence around the league, with shrinkage", {
  league <- c(td = 0.22, fg = 0.15, def = 0.01, safety = 0.003)
  r <- mg_drive_matchup(off = c(td = 0.30, fg = 0.15, def = 0.01, safety = 0.003), def = league, league = league)
  expect_equal(r[["td"]], 0.30, tolerance = 1e-9)
  expect_true(all(r > 0) && sum(r) < 1)
})

test_that("QB-adjusted Elo with weight 0 is C1's Elo, and a weaker starter lowers the home chance", {
  s <- c(A = 2, B = 1, C = -1, D = -2)
  g <- synthetic_league(s, hfa = 2, weeks = 20, noise_sd = 7, seed = 9)
  g[, `:=`(home_qb_id = paste0(home_franchise, "_qb1"), away_qb_id = paste0(away_franchise, "_qb1"))]
  qb <- rbindlist(lapply(seq_len(nrow(g)), function(i) data.table(game_id = g$game_id[i], team = c(g$home_franchise[i], g$away_franchise[i]),
                                                                  qb_id = c(g$home_qb_id[i], g$away_qb_id[i]), dropbacks = 30, qb_epa_sum = 3)))
  base <- bt_elo_run(g, K = 20, hfa = 40, regress = 1 / 3)
  q0 <- mg_qb_elo_run(g, qb, K = 20, hfa = 40, regress = 1 / 3, qb_weight = 0, qb_halflife = 8)
  expect_equal(q0$p_home, base$p_c1)
  g2 <- copy(g); last <- nrow(g2); g2[last, home_qb_id := "backup"]
  qb2 <- copy(qb); qb2[game_id == g2$game_id[last] & team == g2$home_franchise[last], `:=`(qb_id = "backup", qb_epa_sum = -9)]
  q1 <- mg_qb_elo_run(g2, qb2, K = 20, hfa = 40, regress = 1 / 3, qb_weight = 1, qb_halflife = 8)
  q1_same <- mg_qb_elo_run(g, qb, K = 20, hfa = 40, regress = 1 / 3, qb_weight = 1, qb_halflife = 8)
  expect_lt(q1$p_home[last], q1_same$p_home[last])   # an unproven backup starts at the replacement value
})

test_that("a stack given only the market reproduces the market", {
  set.seed(11)
  n <- 50000   # a and b are fitted too; at 3,000 games their sampling noise alone moves predictions about 0.02
  p0 <- stats::runif(n, 0.2, 0.8)
  y <- stats::rbinom(n, 1, p0)
  fit <- mg_stack_fit(p0, p0, y)
  expect_lt(abs(fit[["c"]]), 1e-6)
  expect_equal(mg_stack_predict(fit, p0, p0), p0, tolerance = 0.02)
})

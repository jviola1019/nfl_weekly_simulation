# Audit M22b: score SDs, NB sizes and the score correlation must come from the means the
# simulator uses. Until Plan 1b-1 they came from the legacy chain's total (22.4 for
# CHI @ MIN in 2024 week 15, against 50.3 simulated).
sim_path <- file.path(PROJECT_ROOT, "NFLsimulation.R")
v_env <- load_script_functions(sim_path, c("NB_SIZE_MIN", "NB_SIZE_MAX", "sd_total_curve", "nb_size_from_musd",
                                           "rho_from_game", "score_variance_from_mu"))
v_env$RHO_SCORE <- 0.05   # rho_from_game's default global, estimated from data in a real run

games <- data.frame(game_id = c("g1", "g2"), mu_home = c(27.4, 20.0), mu_away = c(22.9, 17.5),
                    sd_home_fit = c(10.2, 2.0), sd_away_fit = c(9.4, 8.0),
                    sd_home_adj = c(0, 0.6), sd_away_adj = c(0, -0.3))

test_that("SDs blend the fitted SD with the curve at the simulated total", {
  out <- v_env$score_variance_from_mu(games)
  goal <- v_env$sd_total_curve(games$mu_home + games$mu_away)
  expect_equal(out$total_mu, games$mu_home + games$mu_away)
  expect_equal(out$sd_goal, goal)
  expect_equal(out$sd_home, pmax(pmax(0.6 * games$sd_home_fit + 0.4 * goal / sqrt(2), 5) + games$sd_home_adj, 5))
  expect_equal(out$sd_away, pmax(pmax(0.6 * games$sd_away_fit + 0.4 * goal / sqrt(2), 5) + games$sd_away_adj, 5))
  expect_equal(out$sd_home[2], 5.6)   # the 5.0 floor binds before the environment shift
})

test_that("NB sizes and rho use the simulated means and the final SDs", {
  out <- v_env$score_variance_from_mu(games)
  expect_equal(out$k_home, mapply(v_env$nb_size_from_musd, games$mu_home, out$sd_home))
  expect_equal(out$k_away, mapply(v_env$nb_size_from_musd, games$mu_away, out$sd_away))
  expect_equal(out$rho_game, v_env$rho_from_game(out$total_mu, abs(games$mu_home - games$mu_away)))
})

test_that("the engine derives variance once, after composing the means (audit M22b)", {
  code <- readLines(sim_path, warn = FALSE)
  code <- code[!grepl("^\\s*#", code)]
  i_compose <- grep("compose_mu(mu_terms, MU_TERMS_ADMITTED)", code, fixed = TRUE)
  i_var <- grep("games_ready <- score_variance_from_mu(games_ready)", code, fixed = TRUE)
  expect_length(i_var, 1L)
  expect_true(length(i_compose) == 1L && i_var > i_compose)
  expect_false(any(grepl("sd_home\\s*=\\s*0\\.6\\s*\\*\\s*sd_home\\s*\\+", code)))          # legacy-total blend gone
  expect_false(any(grepl("sd_home\\s*=\\s*pmax\\(sd_home \\+ sd_home_adj", code)))         # env SD step moved
  expect_equal(sum(grepl("rho_from_game(total_mu, spread_est)", code, fixed = TRUE)), 1L)
})

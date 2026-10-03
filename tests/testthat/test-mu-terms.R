# Audit M22: the simulated means are the sum of named, admitted terms. Every other term the
# adjustment chain computes is kept in a table, so its size is visible, but not simulated.

mu_fixture <- function() {
  g <- as.data.frame(stats::setNames(replicate(length(MU_COMPONENT_COLUMNS), c(0, 0), simplify = FALSE),
                                     MU_COMPONENT_COLUMNS))
  g$game_id <- c("g1", "g2")
  g$exp_drives_home <- c(11.2, 10.4); g$exp_ppd_home <- c(2.31, 1.97)
  g$exp_drives_away <- c(10.9, 10.6); g$exp_ppd_away <- c(2.05, 2.12)
  g$mu_home_model <- g$exp_drives_home * g$exp_ppd_home
  g$mu_away_model <- g$exp_drives_away * g$exp_ppd_away
  g$HFA_pts <- c(1.72, -0.40)
  g$glmm_w <- c(0.35, 0.35); g$mu_home_glmm <- c(24, NA); g$mu_away_glmm <- c(20, 21)
  g$home_location_boost <- c(-23.1, 4.0)
  g$home_to_adj <- c(NA, NA); g$away_to_adj <- c(NA, NA)   # nflverse has no turnover columns (M22)
  g
}

test_that("every term is computed for both sides; the away side has no home field", {
  comp <- mu_components(mu_fixture(), pressure_pts = 0.6)
  expect_named(comp$home, c("game_id", MU_TERM_NAMES))
  expect_named(comp$away, c("game_id", MU_TERM_NAMES))
  expect_equal(comp$away$hfa, c(0, 0))
  expect_equal(comp$home$location, 0.7 * c(-23.1, 4.0))
  expect_equal(comp$home$glmm, c(0.35 * (24 - 11.2 * 2.31), 0))   # a missing GLMM prediction adds nothing
})

test_that("base + hfa reproduces the pre-fix simulated means bit for bit (audit M22)", {
  g <- mu_fixture()
  mu <- compose_mu(mu_components(g, 0.6), c("base", "hfa"))
  expect_identical(mu$mu_home, pmax(g$exp_drives_home * g$exp_ppd_home + dplyr::coalesce(g$HFA_pts, 0), 0))
  expect_identical(mu$mu_away, pmax(g$exp_drives_away * g$exp_ppd_away, 0))
  expect_identical(mu$game_id, g$game_id)
})

test_that("terms are summed in one fixed order, whatever order config lists them", {
  comp <- mu_components(mu_fixture(), 0.6)
  expect_identical(compose_mu(comp, c("hfa", "glmm", "base")), compose_mu(comp, c("base", "hfa", "glmm")))
})

test_that("a non-finite admitted term stops the run and names the term and games", {
  comp <- mu_components(mu_fixture(), 0.6)
  expect_error(compose_mu(comp, c("base", "turnover")), "home.*turnover \\[g1, g2\\]")
})

test_that("a non-finite term that is not admitted is ignored", {
  expect_silent(compose_mu(mu_components(mu_fixture(), 0.6), c("base", "hfa")))
})

test_that("unknown terms, a missing base and missing columns are rejected", {
  g <- mu_fixture()
  comp <- mu_components(g, 0.6)
  expect_error(compose_mu(comp, c("base", "turnovers")), "unknown term")
  expect_error(compose_mu(comp, "hfa"), "'base'")
  expect_error(mu_components(g[, setdiff(names(g), "HFA_pts")], 0.6), "HFA_pts")
})

test_that("a mean that is not positive stops instead of being clamped", {
  g <- mu_fixture()
  g$HFA_pts <- c(-30, 0)
  expect_error(compose_mu(mu_components(g, 0.6), c("base", "hfa")), "not positive.*g1")
})

test_that("every term matches the legacy chain's formula with distinct non-zero values", {
  # Build fixture with distinct non-zero values for all numeric columns
  g <- mu_fixture()
  col_idx <- which(names(g) != "game_id")
  for (i in seq_along(col_idx)) {
    col <- col_idx[i]
    g[[col]] <- c(0.1 * i, -0.05 * i)
  }
  # Keep mu_home_model/mu_away_model consistent
  g$mu_home_model <- g$exp_drives_home * g$exp_ppd_home
  g$mu_away_model <- g$exp_drives_away * g$exp_ppd_away
  # Keep one NA in mu_home_glmm to exercise coalesce
  g$mu_home_glmm[2] <- NA

  comp <- mu_components(g, pressure_pts = 0.6)

  # Legacy chain: the 13 terms before turnover and weather
  # home side: all terms from base through situational, excluding turnover and weather
  expected_home_13 <- (
    g$exp_drives_home * g$exp_ppd_home +  # base
    g$HFA_pts +                            # hfa
    g$glmm_w * (dplyr::coalesce(g$mu_home_glmm, g$mu_home_model) - g$mu_home_model) +  # glmm
    g$home_off_points_adj +                # qb
    g$home_rest_points +                   # rest
    (g$home_injury_off_total + g$away_injury_def_total) +  # injury
    dplyr::coalesce(g$travel_mu_adj_home, 0) +  # travel
    g$div_conf_adj +                       # div_conf
    -0.6 * g$home_press_mismatch +         # pressure
    0.16 * 5 * g$expl_edge_home +          # explosive
    0.7 * g$home_location_boost +          # location
    0.7 * g$st_impact_home +               # special_teams
    0.7 * (g$rz_impact_home + g$third_down_edge_home + g$to_edge_home +
           g$penalty_edge_home + g$situational_home + g$momentum_home + g$div_adjustment_home)  # situational
  )

  # away side: same but with no HFA, and with home_injury_def_total
  expected_away_13 <- (
    g$exp_drives_away * g$exp_ppd_away +  # base
    0 +                                    # hfa
    g$glmm_w * (dplyr::coalesce(g$mu_away_glmm, g$mu_away_model) - g$mu_away_model) +  # glmm
    g$away_off_points_adj +                # qb
    g$away_rest_points +                   # rest
    (g$away_injury_off_total + g$home_injury_def_total) +  # injury
    dplyr::coalesce(g$travel_mu_adj_away, 0) +  # travel
    g$div_conf_adj +                       # div_conf
    -0.6 * g$away_press_mismatch +         # pressure
    0.16 * 5 * g$expl_edge_away +          # explosive
    0.7 * g$away_location_penalty +        # location
    0.7 * g$st_impact_away +               # special_teams
    0.7 * (g$rz_impact_away + g$third_down_edge_away + g$to_edge_away +
           g$penalty_edge_away + g$situational_away + g$momentum_away + g$div_adjustment_away)  # situational
  )

  # Verify the 13 terms sum correctly (base through situational)
  home_13_sum <- comp$home$base + comp$home$hfa + comp$home$glmm + comp$home$qb + comp$home$rest +
                 comp$home$injury + comp$home$travel + comp$home$div_conf + comp$home$pressure +
                 comp$home$explosive + comp$home$location + comp$home$special_teams + comp$home$situational
  away_13_sum <- comp$away$base + comp$away$hfa + comp$away$glmm + comp$away$qb + comp$away$rest +
                 comp$away$injury + comp$away$travel + comp$away$div_conf + comp$away$pressure +
                 comp$away$explosive + comp$away$location + comp$away$special_teams + comp$away$situational

  expect_equal(home_13_sum, expected_home_13, tolerance = 1e-12)
  expect_equal(away_13_sum, expected_away_13, tolerance = 1e-12)

  # Verify turnover and weather terms separately
  expect_equal(comp$home$turnover, g$home_to_adj, tolerance = 1e-12)
  expect_equal(comp$away$turnover, g$away_to_adj, tolerance = 1e-12)
  expect_equal(comp$home$weather, g$env_total_adj / 2 + g$mu_home_adj + g$wind_interaction_home + g$cold_interaction_home, tolerance = 1e-12)
  expect_equal(comp$away$weather, g$env_total_adj / 2 + g$mu_away_adj + g$wind_interaction_away + g$cold_interaction_away, tolerance = 1e-12)
})

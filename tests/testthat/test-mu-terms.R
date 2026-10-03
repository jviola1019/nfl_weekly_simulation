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

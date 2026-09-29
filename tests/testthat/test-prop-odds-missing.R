library(testthat)

repo_root <- .test_project_root

props_config_path <- file.path(repo_root, "sports", "nfl", "props", "props_config.R")
source(props_config_path, local = FALSE)

passing_path <- file.path(repo_root, "sports", "nfl", "props", "passing_yards.R")
source(passing_path, local = FALSE)

test_that("missing odds are not synthesized when disabled", {
  skip_if_not(exists("passing_yards_over_under"), "passing_yards_over_under not loaded")

  old_allow <- if (exists("PROP_ALLOW_MODEL_ODDS")) PROP_ALLOW_MODEL_ODDS else NULL
  assign("PROP_ALLOW_MODEL_ODDS", FALSE, envir = .GlobalEnv)
  on.exit({
    if (is.null(old_allow)) {
      if (exists("PROP_ALLOW_MODEL_ODDS", envir = .GlobalEnv)) {
        rm("PROP_ALLOW_MODEL_ODDS", envir = .GlobalEnv)
      }
    } else {
      assign("PROP_ALLOW_MODEL_ODDS", old_allow, envir = .GlobalEnv)
    }
  }, add = TRUE)

  sim <- list(
    simulated_yards = rnorm(2000, mean = 250, sd = 35),
    projection = 250
  )

  res <- passing_yards_over_under(
    simulation = sim,
    line = 250,
    over_odds = NA_real_,
    under_odds = NA_real_
  )

  expect_true(is.na(res$over_odds) || !is.finite(res$over_odds))
  expect_true(is.na(res$under_odds) || !is.finite(res$under_odds))
  expect_true(is.na(res$ev_over) || !is.finite(res$ev_over))
  expect_true(is.na(res$ev_under) || !is.finite(res$ev_under))
  expect_equal(res$recommendation, "PASS")
})

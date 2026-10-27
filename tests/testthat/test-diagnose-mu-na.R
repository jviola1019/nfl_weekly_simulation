# F11 diagnosis (scripts/diagnose_mu_na.R): the capture finds the calibration
# game behind each "invalid mu" warning by its frames, records its mean terms,
# keeps sealed seasons out, and does not muffle the warning.

dm <- load_script_functions(file.path(PROJECT_ROOT, "scripts", "diagnose_mu_na.R"),
                            c("DMN_TERMS", "DMN_PATTERN", "dmn_find_game", "dmn_capture", "dmn_summarise"))

# The same frame structure as week_inputs_and_sim_2w(): g, cut_season and
# cut_week in the function's frame, i in the lapply() closure below it
fake_sim <- function(mu_home, mu_away) {
  if (!is.finite(mu_home)) warning(sprintf("simulate_game_nb: invalid mu_home=%.4f, using fallback 21.5", mu_home))
  if (!is.finite(mu_away)) warning(sprintf("simulate_game_nb: invalid mu_away=%.4f, using fallback 21.5", mu_away))
  1
}
fake_cal <- function(cut_season, cut_week, n_trials = 10) {
  g <- data.frame(game_id = c("a", "b"), home_team = c("LA", "KC"), away_team = c("SF", "BUF"),
                  neutral_site = c(FALSE, FALSE), home_hfa = c(NA, 1.2), away_hfa = c(1.0, 1.1),
                  mu_home = c(NA, 24), mu_away = c(NA, 21))
  lapply(seq_len(nrow(g)), function(i) fake_sim(g$mu_home[i], g$mu_away[i]))
}

test_that("each invalid-mu warning is traced to its game, deduplicated, and sealed seasons are kept out", {
  run <- function() { fake_cal(2023, 5); fake_cal(2025, 2); warning("an unrelated warning") }
  seen <- 0L
  withCallingHandlers(res <- dm$dmn_capture(run, sealed = 2025L),
                      warning = function(w) { seen <<- seen + 1L; invokeRestart("muffleWarning") })
  expect_equal(seen, 5L)                  # nothing was muffled by the capture
  expect_equal(nrow(res$rows), 1L)        # game a, once for both of its warnings
  expect_equal(res$rows$cut_season, 2023)
  expect_equal(res$rows$cut_week, 5)
  expect_true(is.na(res$rows$home_hfa))
  expect_equal(res$warnings_sealed, 2L)
  expect_equal(res$warnings_unlocated, 0L)
  s <- dm$dmn_summarise(res$rows)
  expect_equal(s[term == "home_hfa", n_na], 1L)
  expect_equal(s[term == "away_hfa", n_na], 0L)
})

test_that("a warning raised outside a calibration frame is counted as unlocated", {
  res <- suppressWarnings(dm$dmn_capture(function() fake_sim(NA, 20), sealed = 2025L))
  expect_equal(nrow(res$rows), 0L)
  expect_equal(res$warnings_unlocated, 1L)
})

test_that("the pattern matches the engine's warning text", {
  sim <- readLines(file.path(PROJECT_ROOT, "NFLsimulation.R"), warn = FALSE)
  msg <- grep("simulate_game_nb: invalid mu_home=", sim, value = TRUE, fixed = TRUE)
  expect_length(msg, 1L)
  expect_true(grepl(dm$DMN_PATTERN, sprintf("simulate_game_nb: invalid mu_home=%.4f, using fallback 21.5", NA)))
})

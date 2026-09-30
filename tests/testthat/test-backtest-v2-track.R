# Prospective tracking (backtest/v2/track_append.R): grading, the sealed-season
# refusal, the before-kickoff check and de-duplication.

tr_env <- new.env()
sys.source(file.path(PROJECT_ROOT, "backtest", "v2", "track_append.R"), envir = tr_env)
tr <- function(name) get(name, envir = tr_env)

make_bundle <- function(dir, generated = "2026-09-29T20:51:29Z") {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(list(bundle_kind = "weekly", week = 4L, generated_utc = generated), file.path(dir, "manifest.json"),
                       auto_unbox = TRUE)
  jsonlite::write_json(data.frame(game_id = c("2026_04_PIT_CLE", "2026_04_PIT_CLE", "2026_04_IND_WAS"),
                                  candidate = c("C0", "E1", "C0"), p_home_final = c(0.43, 0.51, 0.37),
                                  p_home_mkt_novig = c(0.43, 0.43, 0.37)),
                       file.path(dir, "game_predictions.json"))
  dir
}
results <- data.frame(game_id = c("2026_04_PIT_CLE", "2026_04_IND_WAS"), season = 2026L,
                      kickoff_utc = c("2026-10-02T00:15:00Z", "2026-10-04T13:30:00Z"),
                      home_score = c(20L, 17L), away_score = c(17L, 17L))

test_that("graded rows score the model and the market on the same games", {
  b <- make_bundle(file.path(withr::local_tempdir(), "b"))
  g <- tr("bt2_track_grade")(b, results)
  e1 <- g[game_id == "2026_04_PIT_CLE" & candidate == "E1"]
  expect_equal(e1$outcome, 1L)
  expect_equal(e1$brier, (0.51 - 1)^2)
  expect_equal(e1$brier_market, (0.43 - 1)^2)
  expect_true(is.na(g[game_id == "2026_04_IND_WAS", outcome]))   # a tie is recorded, not scored
})

test_that("any season before 2026 is refused (2025 is the sealed holdout)", {
  b <- make_bundle(file.path(withr::local_tempdir(), "b"))
  r <- results; r$season <- 2025L
  expect_error(tr("bt2_track_grade")(b, r), "refusing season 2025")
})

test_that("a bundle generated after kickoff is refused", {
  b <- make_bundle(file.path(withr::local_tempdir(), "b"), generated = "2026-10-03T00:00:00Z")
  expect_error(tr("bt2_track_grade")(b, results), "after a graded kickoff")
})

test_that("appending twice never duplicates a game and candidate", {
  tmp <- withr::local_tempdir()
  b <- make_bundle(file.path(tmp, "b"))
  out <- file.path(tmp, "track.csv")
  expect_equal(tr("bt2_track_append")(b, results, out), 3L)
  expect_equal(tr("bt2_track_append")(b, results, out), 0L)
  expect_equal(nrow(data.table::fread(out)), 3L)
  expect_false(any(readBin(out, "raw", file.size(out)) == as.raw(13)))
})

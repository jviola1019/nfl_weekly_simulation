# Evidence files are hash-locked and compared byte for byte across machines, so every
# writer must emit UTF-8 with LF line endings on every OS (audit T6). On Windows,
# data.table::fwrite, writeLines and jsonlite::write_json default to CRLF, which made
# the backtest's result_sha256 depend on the operating system.

lf_env <- new.env()
for (f in c("common.R", "walk_forward.R")) sys.source(file.path(.test_project_root, "backtest", f), envir = lf_env)
lf <- function(name) get(name, envir = lf_env)

bytes_of <- function(path) readBin(path, "raw", file.size(path))
has_cr <- function(path) any(bytes_of(path) == as.raw(13))
ends_lf <- function(path) utils::tail(bytes_of(path), 1) == as.raw(10)

test_that("backtest JSON writer emits LF only and ends with a newline", {
  tmp <- withr::local_tempdir()
  p <- file.path(tmp, "metrics.json")
  lf("bt_write_json")(list(a = 1:3, b = list(c = "x", d = 0.123456789012)), p)
  expect_false(has_cr(p))
  expect_true(ends_lf(p))
  expect_identical(jsonlite::read_json(p, simplifyVector = TRUE)$b$c, "x")
})

test_that("backtest CSV writer emits LF only", {
  tmp <- withr::local_tempdir()
  p <- file.path(tmp, "predictions.csv")
  lf("bt_write_csv")(data.table::data.table(game_id = c("g1", "g2"), p = c(0.25, 0.75)), p)
  expect_false(has_cr(p))
  expect_identical(readLines(p), c("game_id,p", "g1,0.25", "g2,0.75"))
})

test_that("bw_write_bundle emits LF only in every file it writes", {
  out <- withr::local_tempdir()
  tables <- list(
    teams = data.frame(team_id = c("CLE", "PIT"), full_name = c("Cleveland Browns", "Pittsburgh Steelers"), stringsAsFactors = FALSE),
    games = data.frame(game_id = "2026_04_PIT_CLE", season = 2026L, week = 4L, home_team_id = "CLE", away_team_id = "PIT",
                       kickoff_utc = "2026-10-02T00:15:00Z", neutral = FALSE, stringsAsFactors = FALSE),
    game_predictions = data.frame(game_id = "2026_04_PIT_CLE", candidate = "C0", p_home_final = 0.43, p_home_mkt_novig = 0.43,
                                  stringsAsFactors = FALSE),
    source_status = data.frame(source = "nflverse_schedules", status = "ok", last_success_utc = "2026-09-29T20:51:29Z",
                               stringsAsFactors = FALSE)
  )
  meta <- list(cycle_id = "lf-2026-w04", season = 2026L, week = 4L, model_label = "test",
               data_asof_utc = "2026-09-29T20:51:29Z", code_git_sha = "0123456789abcdef", code_dirty = FALSE,
               config = list(protocol_id = "test"), seed = NULL, n_sims = NULL)
  m <- bw_write_bundle(out, "weekly", meta, tables, contracts_dir = file.path(.test_project_root, "contracts", "schema"),
                       renv_lock = file.path(.test_project_root, "renv.lock"))
  for (f in list.files(m$dir, full.names = TRUE)) {
    expect_false(has_cr(f), info = basename(f))
    expect_true(ends_lf(f), info = basename(f))
  }
})

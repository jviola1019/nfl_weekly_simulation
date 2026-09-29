# =============================================================================
# R side of the R -> web contract (R/bundle_writer.R). The shared fixtures in
# contracts/fixtures/rows.json are also run by web/src/lib/contracts/bundle.test.ts,
# so the R validator and the zod schemas must agree on every case.
# =============================================================================

contracts_dir <- file.path(.test_project_root, "contracts", "schema")
fixtures <- jsonlite::read_json(file.path(.test_project_root, "contracts", "fixtures", "rows.json"), simplifyVector = FALSE)

# One fixture row as a one-row data frame, the shape bw_write_bundle validates
row_df <- function(row) as.data.frame(lapply(row, function(v) if (is.null(v)) NA else v), stringsAsFactors = FALSE)

test_that("the R validator accepts every valid shared fixture", {
  expect_gt(length(fixtures$valid), 0)
  for (case in fixtures$valid) {
    fails <- bw_validate_rows(row_df(case$row), bw_read_schema(case$table, contracts_dir), case$table)
    expect_identical(fails, character(), info = case$table)
  }
})

test_that("the R validator rejects every invalid shared fixture", {
  expect_gt(length(fixtures$invalid), 0)
  for (case in fixtures$invalid) {
    fails <- bw_validate_rows(row_df(case$row), bw_read_schema(case$table, contracts_dir), case$table)
    expect_true(length(fails) > 0, info = paste(case$table, case$why))
  }
})

test_that("bw_utc writes ISO-8601 UTC whatever the input zone", {
  t <- as.POSIXct("2026-10-04 13:00:00", tz = "America/New_York")
  expect_identical(bw_utc(t), "2026-10-04T17:00:00Z")
})

test_that("bw_config_hash is key-order independent", {
  expect_identical(bw_config_hash(list(a = 1, b = "x")), bw_config_hash(list(b = "x", a = 1)))
  expect_false(identical(bw_config_hash(list(a = 1)), bw_config_hash(list(a = 2))))
})

bundle_inputs <- function() {
  list(
    teams = data.frame(team_id = c("CLE", "PIT"), full_name = c("Cleveland Browns", "Pittsburgh Steelers"), stringsAsFactors = FALSE),
    games = data.frame(game_id = "2026_04_PIT_CLE", season = 2026L, week = 4L, home_team_id = "CLE", away_team_id = "PIT",
                       kickoff_utc = "2026-10-02T00:15:00Z", neutral = FALSE, stringsAsFactors = FALSE),
    game_predictions = data.frame(game_id = "2026_04_PIT_CLE", candidate = "C0", p_home_final = 0.43, p_home_mkt_novig = 0.43,
                                  stringsAsFactors = FALSE),
    source_status = data.frame(source = "nflverse_schedules", status = "ok", last_success_utc = "2026-09-29T20:51:29Z",
                               stringsAsFactors = FALSE)
  )
}
bundle_meta <- list(cycle_id = "test-2026-w04", season = 2026L, week = 4L, model_label = "test",
                    data_asof_utc = "2026-09-29T20:51:29Z", code_git_sha = "0123456789abcdef", code_dirty = FALSE,
                    config = list(protocol_id = "test"), seed = NULL, n_sims = NULL)

test_that("bw_write_bundle writes files whose sha256 and row counts the manifest pins", {
  out <- withr::local_tempdir()
  m <- bw_write_bundle(out, "weekly", bundle_meta, bundle_inputs(), contracts_dir = contracts_dir,
                       renv_lock = file.path(.test_project_root, "renv.lock"))
  expect_true(m$qa$ok)
  expect_length(m$qa$failures, 0)
  on_disk <- jsonlite::read_json(file.path(m$dir, "manifest.json"), simplifyVector = FALSE)
  expect_identical(on_disk$schema_version, BW_SCHEMA_VERSION)
  expect_identical(on_disk$bundle_kind, "weekly")
  for (f in on_disk$files) {
    path <- file.path(m$dir, f$name)
    expect_identical(f$sha256, digest::digest(file = path, algo = "sha256"), info = f$name)
    expect_identical(f$rows, length(jsonlite::read_json(path)), info = f$name)
  }
  expect_identical(m$bundle_sha256, digest::digest(file = file.path(m$dir, "manifest.json"), algo = "sha256"))
  expect_match(on_disk$generated_utc, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
})

test_that("an invalid row still writes the bundle but marks qa failed (the ingest keeps the pointer)", {
  out <- withr::local_tempdir()
  inputs <- bundle_inputs()
  inputs$game_predictions$p_home_final <- 1.3
  inputs$games$kickoff_utc <- "2026-10-02 00:15:00"
  m <- bw_write_bundle(out, "weekly", bundle_meta, inputs, contracts_dir = contracts_dir,
                       renv_lock = file.path(.test_project_root, "renv.lock"))
  expect_false(m$qa$ok)
  fails <- unlist(m$qa$failures)
  expect_true(any(grepl("game_predictions.p_home_final: above maximum", fails, fixed = TRUE)))
  expect_true(any(grepl("games.kickoff_utc: does not match", fails, fixed = TRUE)))
  expect_true(file.exists(file.path(m$dir, "manifest.json")))
})

test_that("a missing required table fails QA and a foreign table stops the write", {
  out <- withr::local_tempdir()
  inputs <- bundle_inputs()
  inputs$source_status <- NULL
  m <- bw_write_bundle(out, "weekly", bundle_meta, inputs, contracts_dir = contracts_dir,
                       renv_lock = file.path(.test_project_root, "renv.lock"))
  expect_false(m$qa$ok)
  expect_true(any(grepl("required table 'source_status' missing", unlist(m$qa$failures), fixed = TRUE)))
  inputs <- bundle_inputs()
  inputs$clv_picks <- data.frame(x = 1)
  expect_error(bw_write_bundle(out, "weekly", bundle_meta, inputs, contracts_dir = contracts_dir,
                               renv_lock = file.path(.test_project_root, "renv.lock")),
               "not allowed in a weekly bundle")
})

test_that("an unknown bundle kind is refused", {
  expect_error(bw_write_bundle(withr::local_tempdir(), "props", bundle_meta, bundle_inputs(), contracts_dir = contracts_dir),
               "unknown bundle kind")
})

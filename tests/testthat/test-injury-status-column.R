# Audit M19: nflverse injury reports carry the game designation (Out, Doubtful,
# Questionable) in report_status and practice participation in practice_status. The
# injury model must read the designation; practice_status never matches OUT, DOUBTFUL
# or QUESTIONABLE, so reading it scored every Out player as 0.
sim_path <- file.path(PROJECT_ROOT, "NFLsimulation.R")
inj_env <- load_script_functions(sim_path, c("inj_pick", "INJ_STATUS_CANDIDATES", "inj_status_col", "calc_injury_impacts"))

# Columns as nflreadr::load_injuries() returns them (no game_status or status column)
nflverse_week <- data.frame(
  season = 2024L, week = 15L, team = "AAA", position = c("WR", "T", "CB"),
  full_name = c("W One", "T Two", "C Three"),
  report_status = c("Out", "Questionable", NA),
  practice_status = c("Did Not Participate In Practice", "Limited Participation in Practice",
                      "Full Participation in Practice"),
  stringsAsFactors = FALSE
)

test_that("the game designation is read ahead of practice participation", {
  expect_equal(inj_env$inj_status_col(nflverse_week), "report_status")
})

test_that("the Sleeper fallback's status column is still found", {
  expect_equal(inj_env$inj_status_col(data.frame(team = "AAA", status = "Out")), "status")
})

test_that("practice participation is used only when no designation column exists", {
  expect_equal(inj_env$inj_status_col(nflverse_week[, c("team", "position", "practice_status")]), "practice_status")
})

test_that("an Out receiver and a Questionable tackle are penalised by their designations", {
  col <- inj_env$inj_status_col(nflverse_week)
  rows <- data.frame(team = nflverse_week$team, position = nflverse_week$position,
                     status = toupper(dplyr::coalesce(nflverse_week[[col]], "")))
  r <- inj_env$calc_injury_impacts(rows, group_vars = "team")
  expected <- (-0.50 * INJURY_POS_MULT_SKILL + -0.20 * INJURY_POS_MULT_TRENCH) * 3 / (3 + 8)
  expect_equal(r$inj_off_pts, expected, tolerance = 1e-12)
})

test_that("both injury readers in NFLsimulation.R use the shared status column choice", {
  src <- readLines(sim_path, warn = FALSE)
  code <- src[!grepl("^\\s*#", src)]
  expect_equal(sum(grepl("\"practice_status\"", code, fixed = TRUE)), 1L)
  expect_equal(sum(grepl("inj_status_col(inj_all)", code, fixed = TRUE)), 2L)
})

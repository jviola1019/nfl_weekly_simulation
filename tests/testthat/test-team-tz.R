# The engine's team time zones (NFLsimulation.R `team_tz`) cover every team code the schedule
# uses, each with the zone data/reference/teams.csv gives it. The table had "LAR" where nflverse
# schedules use "LA", so a Rams game got no zone: its travel term was 0 and its local kickoff fell
# back to Eastern (the game model's half of audit P9).

# NFLsimulation.R runs the whole pipeline when sourced, so evaluate only the named definitions
load_engine_defs <- function(names) {
  exprs <- parse(file.path(PROJECT_ROOT, "NFLsimulation.R"), keep.source = FALSE)
  env <- new.env(parent = globalenv())
  env$tribble <- tibble::tribble
  for (nm in names) {
    defs <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) &&
                     identical(e[[2]], as.name(nm)), exprs)
    if (length(defs) != 1) stop(sprintf("expected one %s definition in NFLsimulation.R", nm))
    eval(defs[[1]], env)
  }
  env
}

test_that("every schedule team has the time zone of the reference teams file", {
  team_tz <- load_engine_defs("team_tz")$team_tz
  ref <- utils::read.csv(file.path(PROJECT_ROOT, "data", "reference", "teams.csv"), stringsAsFactors = FALSE)
  expect_setequal(team_tz$team, ref$team_id)
  both <- merge(team_tz, ref[c("team_id", "tz")], by.x = "team", by.y = "team_id", suffixes = c("_engine", "_ref"))
  expect_equal(both$tz_engine, both$tz_ref, info = paste(both$team[both$tz_engine != both$tz_ref], collapse = ", "))
})

test_that("the Rams travelling east for a 1 pm kickoff get the travel penalty", {
  env <- load_engine_defs(c("team_tz", "tz_penalty"))
  zone <- function(team) env$team_tz$tz[match(team, env$team_tz$team)]
  expect_equal(env$tz_penalty(home_tz = zone("NYJ"), away_tz = zone("LA"), kick_et_hour = 13L), -0.4)
  expect_equal(env$tz_penalty(home_tz = zone("LA"), away_tz = zone("NYJ"), kick_et_hour = 13L), 0)
})

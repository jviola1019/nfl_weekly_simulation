# =============================================================================
# FILE: tests/testthat/test-prop-keys.R
# PURPOSE: P9, team and player keys. No network except the one LIVE test.
# =============================================================================

library(testthat)

source(file.path(.test_project_root, "R", "prop_keys.R"), local = FALSE)

test_that("normalize_team_abbr never turns a team into an empty string (P9: KC -> '')", {
  x <- c("KC", "kc", " KC ", "LAR", "LA", "Los Angeles Rams", "Kansas City Chiefs",
         "KCC", "NEP", "GBP", "SFO", "FA", "FA*", "", NA, "XYZ")
  expect_identical(
    normalize_team_abbr(x),
    c("KC", "KC", "KC", "LA", "LA", "LA", "KC", "KC", "NE", "GB", "SF",
      NA, NA, NA, NA, NA)
  )
  expect_false(any(normalize_team_abbr(c("KC", "LA", "SEA", "BUF")) == ""))
})

test_that("LA and LAR are the same team in a join (P9: 2025_21_LA_SEA lost its time zone)", {
  schedule <- data.frame(game_id = "2025_21_LA_SEA", away_team = "LA", home_team = "SEA")
  odds <- data.frame(event = "x", away_team = "LAR", home_team = "Seattle Seahawks")
  schedule$key <- paste(normalize_team_abbr(schedule$away_team), normalize_team_abbr(schedule$home_team))
  odds$key <- paste(normalize_team_abbr(odds$away_team), normalize_team_abbr(odds$home_team))
  joined <- merge(schedule, odds, by = "key")
  expect_equal(nrow(joined), 1)
  expect_equal(joined$game_id, "2025_21_LA_SEA")
})

test_that("every canonical team survives normalization unchanged", {
  expect_equal(length(CANONICAL_TEAMS), 32)
  expect_identical(normalize_team_abbr(CANONICAL_TEAMS), CANONICAL_TEAMS)
})

test_that("normalize_person_name makes comparable keys", {
  expect_identical(normalize_person_name("A.J. Brown"), "aj brown")
  expect_identical(normalize_person_name("Amon-Ra St. Brown"), "amon ra st brown")
  expect_identical(normalize_person_name("Marvin Harrison Jr."), "marvin harrison")
  expect_identical(normalize_person_name("A.St. Brown"), "ast brown")
  expect_identical(normalize_person_name("D'Andre Swift"), "dandre swift")
  expect_identical(normalize_person_name(c("", NA)), c(NA_character_, NA_character_))
})

xwalk_fixture <- function() {
  tibble::tibble(
    player_id = c("00-AJB", "00-ARSB", "00-JAQB", "00-JALB", "00-MHJ"),
    name = c("A.J. Brown", "Amon-Ra St. Brown", "Josh Allen", "Josh Allen", "Marvin Harrison Jr."),
    team = c("PHI", "DET", "BUF", "JAX", "ARI"),
    position = c("WR", "WR", "QB", "LB", "WR")
  )
}

test_that("A.St. Brown is not A.J. Brown (P9)", {
  r <- suppressMessages(resolve_player_ids(
    names = c("A.J. Brown", "A.St. Brown", "A.J. Brown", "Amon-Ra St. Brown"),
    teams = c("PHI", "DET", "DET", "DET"),
    xwalk = xwalk_fixture()
  ))
  expect_identical(r$player_id, c("00-AJB", NA, NA, "00-ARSB"))
  expect_identical(r$id_status, c("matched", "no_match", "no_match", "matched"))
})

test_that("same name on two teams resolves by team and is ambiguous without one", {
  r <- suppressMessages(resolve_player_ids(
    names = c("Josh Allen", "Josh Allen", "Josh Allen", "Josh Allen"),
    teams = c("BUF", "JAC", "KCC", NA),
    xwalk = xwalk_fixture()
  ))
  expect_identical(r$player_id, c("00-JAQB", "00-JALB", NA, NA))
  expect_identical(r$id_status, c("matched", "matched", "no_match", "ambiguous"))
})

test_that("suffixes, a missing team and an unmappable team", {
  r <- suppressMessages(resolve_player_ids(
    names = c("Marvin Harrison", "Amon-Ra St. Brown", "Amon-Ra St. Brown", NA),
    teams = c("ARI", NA, "Nowhere", "DET"),
    xwalk = xwalk_fixture()
  ))
  expect_identical(r$player_id, c("00-MHJ", "00-ARSB", NA, NA))
  expect_identical(r$id_status, c("matched", "matched", "bad_team", "no_match"))
})

test_that("unresolved players are reported, not hidden", {
  expect_message(
    resolve_player_ids("Nobody Real", "DET", xwalk_fixture()),
    "1 unresolved"
  )
  expect_equal(nrow(resolve_player_ids(character(), character(), xwalk_fixture())), 0)
})

test_that("build_player_xwalk canonicalizes ffverse teams and drops rows with no id or team", {
  ff <- data.frame(
    gsis_id = c("00-1", "00-2", NA, "00-4"),
    name = c("A", "B", "C", "D"),
    team = c("KCC", "FA", "DET", "LAR"),
    position = c("QB", "WR", "WR", "RB"),
    stringsAsFactors = FALSE
  )
  x <- build_player_xwalk(ff)
  expect_identical(x$player_id, c("00-1", "00-4"))
  expect_identical(x$team, c("KC", "LA"))
  expect_true(all(c("player_id", "name", "team", "position") %in% names(x)))
})

test_that("the live ffverse table maps to canonical teams", {
  skip_live("github.com")
  x <- with_live("github.com", build_player_xwalk())
  expect_gt(nrow(x), 1000)
  expect_true(all(x$team %in% CANONICAL_TEAMS))
})

# =============================================================================
# Tests for R/sleeper_api.R - Sleeper API Integration
# =============================================================================
# Tests the Sleeper API injury data loading functionality
# =============================================================================

# Skip all tests if sleeper_api.R is not available
skip_if_not_installed <- function() {
  sleeper_path <- file.path(.test_project_root, "R", "sleeper_api.R")
  if (!file.exists(sleeper_path) && !exists("load_injuries_sleeper")) {
    skip("R/sleeper_api.R not available")
  }
}

# =============================================================================
# CONFIGURATION TESTS
# =============================================================================

test_that("SLEEPER_PLAYERS_URL is defined and valid", {
  skip_if_not_installed()

  expect_true(exists("SLEEPER_PLAYERS_URL"))
  expect_type(SLEEPER_PLAYERS_URL, "character")
  expect_match(SLEEPER_PLAYERS_URL, "^https://")
  expect_match(SLEEPER_PLAYERS_URL, "sleeper\\.app")
})

test_that("SLEEPER_TEAM_MAP contains all NFL teams", {
  skip_if_not_installed()

  expect_true(exists("SLEEPER_TEAM_MAP"))

  # All 32 teams should be mappable
  nfl_teams <- c("ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE",
                 "DAL", "DEN", "DET", "GB", "HOU", "IND", "JAX", "KC",
                 "LV", "LAC", "LA", "MIA", "MIN", "NE", "NO", "NYG",
                 "NYJ", "PHI", "PIT", "SF", "SEA", "TB", "TEN", "WAS")

  for (team in nfl_teams) {
    expect_true(team %in% names(SLEEPER_TEAM_MAP) || team %in% SLEEPER_TEAM_MAP,
                info = sprintf("Team %s should be in SLEEPER_TEAM_MAP", team))
  }
})

test_that("SLEEPER_STATUS_MAP covers common injury statuses", {
  skip_if_not_installed()

  expect_true(exists("SLEEPER_STATUS_MAP"))

  required_statuses <- c("Active", "Questionable", "Doubtful", "Out", "IR")
  for (status in required_statuses) {
    expect_true(status %in% names(SLEEPER_STATUS_MAP),
                info = sprintf("Status '%s' should be in SLEEPER_STATUS_MAP", status))
  }

  # Active should be 1.0, Out should be 0.0
  expect_equal(SLEEPER_STATUS_MAP[["Active"]], 1.0)
  expect_equal(SLEEPER_STATUS_MAP[["Out"]], 0.0)
  expect_equal(SLEEPER_STATUS_MAP[["IR"]], 0.0)
})

# =============================================================================
# FUNCTION EXISTENCE TESTS
# =============================================================================

test_that("load_injuries_sleeper function exists", {
  skip_if_not_installed()

  expect_true(exists("load_injuries_sleeper"))
  expect_type(load_injuries_sleeper, "closure")
})

test_that("load_injuries_sleeper returns proper structure", {
  skip_if_not_installed()
  skip_live("api.sleeper.app")

  result <- load_injuries_sleeper(teams = c("KC"), use_cache = FALSE, verbose = FALSE)
  # load_injuries_sleeper() reports fetch failures as success = FALSE, not an error
  if (!isTRUE(result$success)) skip_live("api.sleeper.app")
  expect_true(result$success, info = result$message)

  # Should return a list with expected fields
  expect_type(result, "list")
  expect_true("data" %in% names(result))
  expect_true("source" %in% names(result))
  expect_true("success" %in% names(result))

  # Source should be "sleeper"
  expect_equal(result$source, "sleeper")
})

# =============================================================================
# DATA VALIDATION TESTS
# =============================================================================

test_that("normalize_sleeper_injuries produces correct schema", {
  skip_if_not_installed()

  # Mock data: the Sleeper /players payload is a list keyed by player_id.
  # R/sleeper_api.R normalizes in two steps: filter_sleeper_injuries() then
  # normalize_sleeper_injuries() (there is no normalize_sleeper_data()).
  mock_player <- list(
    player_id = "12345",
    first_name = "Patrick",
    last_name = "Mahomes",
    team = "KC",
    position = "QB",
    sport = "nfl",
    injury_status = "Questionable",
    status = "Active"
  )

  # Normalize
  result <- normalize_sleeper_injuries(filter_sleeper_injuries(list("12345" = mock_player)))

  expect_true(is.data.frame(result) || tibble::is_tibble(result))
  expect_equal(nrow(result), 1)
  expect_equal(result$player, "Patrick Mahomes")
  expect_equal(result$game_status, "Questionable")
  expect_equal(result$availability, SLEEPER_STATUS_MAP[["Questionable"]])

  # Check required columns exist
  expected_cols <- c("team", "player", "position", "game_status", "availability")
  for (col in expected_cols) {
    expect_true(col %in% names(result),
                info = sprintf("Column '%s' should be in normalized data", col))
  }
})

test_that("availability scores are in valid range", {
  skip_if_not_installed()
  skip_live("api.sleeper.app")

  result <- load_injuries_sleeper(teams = c("DEN"), use_cache = TRUE, verbose = FALSE)
  if (!isTRUE(result$success)) skip_live("api.sleeper.app")
  expect_true(result$success, info = result$message)

  if (nrow(result$data) > 0) {
    expect_true("availability" %in% names(result$data))
    # All availability scores should be 0-1
    expect_true(all(result$data$availability >= 0 & result$data$availability <= 1,
                    na.rm = TRUE))
  }
})

# =============================================================================
# CACHE TESTS
# =============================================================================

test_that("cache directory creation works", {
  skip_if_not_installed()

  expect_true(exists("SLEEPER_CACHE_DIR"))

  # Should be under ~/.cache
  expect_match(SLEEPER_CACHE_DIR, "\\.cache")
})

test_that("cache expiry is reasonable", {
  skip_if_not_installed()

  expect_true(exists("SLEEPER_CACHE_EXPIRY_HOURS"))
  expect_type(SLEEPER_CACHE_EXPIRY_HOURS, "double")

  # Should be between 1 and 24 hours
  expect_true(SLEEPER_CACHE_EXPIRY_HOURS >= 1)
  expect_true(SLEEPER_CACHE_EXPIRY_HOURS <= 24)
})

# =============================================================================
# INTEGRATION TESTS (require network)
# =============================================================================

test_that("Sleeper API returns real injury data", {
  skip_if_not_installed()
  skip_live("api.sleeper.app")

  result <- load_injuries_sleeper(teams = NULL, use_cache = FALSE, verbose = FALSE)
  if (!isTRUE(result$success)) skip_live("api.sleeper.app")
  expect_true(result$success, info = result$message)
  expect_true(nrow(result$data) > 0,
              info = "Sleeper should return at least some player data")

  # Should have injured players during season
  if ("status" %in% names(result$data)) {
    has_injuries <- any(grepl("Out|IR|Questionable|Doubtful",
                              result$data$status, ignore.case = TRUE))
    # Not guaranteed to have injuries, but log it
    if (!has_injuries) {
      message("Note: No injured players found in Sleeper data")
    }
  }
})

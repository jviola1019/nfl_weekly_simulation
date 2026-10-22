# =============================================================================
# FILE: tests/testthat/test-prop-governance.R
# PURPOSE: P1 (distinct tiers per row), P2/P3 (side, tier and stake agree), M11 (no price, no bet).
# =============================================================================

library(testthat)

source(file.path(.test_project_root, "sports", "nfl", "props", "props_config.R"), local = FALSE)
source(file.path(.test_project_root, "R", "correlated_props.R"), local = FALSE)

test_that("classify_prop_edge_quality gives each row its own tier (P1)", {
  tiers <- classify_prop_edge_quality(
    ev_over = c(0.04, 0.07, 0.12, -0.20),
    ev_under = c(0.01, 0.02, -0.01, 0.03),
    recommendation = c("OVER", "OVER", "OVER", "UNDER")
  )
  expect_identical(tiers, c("OK", "High", "Review", "OK"))
  expect_length(unique(tiers), 3)
  # scalar calls still work
  expect_identical(classify_prop_edge_quality(0.04, 0.01, "OVER"), "OK")
  expect_identical(classify_prop_edge_quality(NA_real_, NA_real_, "MODEL ERROR"), "MODEL ERROR")
  expect_identical(classify_prop_edge_quality(c(NA, 0.03), c(NA, NA), c("OVER", "OVER")), c("MODEL ERROR", "OK"))
  expect_length(classify_prop_edge_quality(numeric(), numeric(), character()), 0)
})

gov <- function(...) {
  args <- list(...)
  defaults <- list(ev_over = 0, ev_under = 0, p_over = 0.5, p_under = 0.5, over_odds = -110, under_odds = -110)
  do.call(govern_prop_rows, utils::modifyList(defaults, args))
}

test_that("an Under the model likes is governed on the Under side (P3)", {
  # Under: p 0.5683 at -110 is +8.5% EV, Kelly 0.0935, 1/8 Kelly = 0.0117 (above the 1% minimum)
  g <- gov(ev_over = -0.176, ev_under = 0.085, p_over = 0.4317, p_under = 0.5683)
  expect_identical(g$side, "UNDER")
  expect_identical(g$tier, "bet")
  expect_identical(g$recommendation, "UNDER")
  expect_identical(g$pass_reason, "")
  expect_gt(g$final_stake_pct, 0.01)
  expect_equal(g$final_stake_pct, g$capped_stake_pct)
  expect_identical(g$edge_quality, "High")
})

test_that("a positive-EV row below the minimum stake is a pass, never an OVER with stake 0 (P2)", {
  g <- gov(ev_over = 0.04, ev_under = -0.1, p_over = 0.5445, p_under = 0.4555)
  expect_identical(g$tier, "pass")
  expect_identical(g$recommendation, "PASS")
  expect_identical(g$pass_reason, "Stake below minimum")
  expect_equal(g$final_stake_pct, 0)
  expect_identical(g$edge_quality, "Pass")
})

test_that("an edge above the believable maximum is a review with no stake", {
  g <- gov(ev_over = 0.168, ev_under = -0.2, p_over = 0.61, p_under = 0.39)
  expect_identical(g$tier, "review")
  expect_identical(g$recommendation, "REVIEW")
  expect_match(g$pass_reason, "^Edge too large")
  expect_equal(g$final_stake_pct, 0)
})

test_that("one-sided markets (anytime TD) bet the Yes side", {
  # +250 at p 0.30 is +5% EV but Kelly 0.02 gives 1/8 Kelly = 0.0025, below the 1% minimum: a pass
  g <- gov(ev_over = 0.05, ev_under = NA_real_, p_over = 0.30, p_under = 0.70, over_odds = 250,
           under_odds = NA_real_, one_sided = TRUE)
  expect_identical(g$side, "YES")
  expect_identical(g$tier, "pass")
  expect_identical(g$pass_reason, "Stake below minimum")
  # -110 at p 0.5683 is +8.5% EV, Kelly 0.0935, stake 0.0117: a bet, labelled BET
  g2 <- gov(ev_over = 0.085, ev_under = 0.5, p_over = 0.5683, p_under = 0.4317, over_odds = -110,
            under_odds = -110, one_sided = TRUE)
  expect_identical(g2$side, "YES")        # the Under is never taken, whatever its EV
  expect_identical(g2$tier, "bet")
  expect_identical(g2$recommendation, "BET")
  expect_gt(g2$final_stake_pct, 0.01)
})

test_that("a prop without a market price is unpriced, with its reason, and cannot be a bet (M11)", {
  g <- gov(ev_over = c(0.09, 0.09), ev_under = c(0.2, 0.2), over_odds = c(-110, NA), under_odds = c(-110, NA),
           priced = c(FALSE, FALSE), unpriced_reason = c("No line captured before kickoff", ""))
  expect_true(all(is.na(g$ev_over)) && all(is.na(g$ev_under)))
  expect_identical(g$tier, c("pass", "pass"))
  expect_identical(g$recommendation, c("PASS", "PASS"))
  expect_identical(g$side, c("NONE", "NONE"))
  expect_equal(g$final_stake_pct, c(0, 0))
  expect_identical(g$pass_reason, c("No line captured before kickoff", "Market odds missing/placeholder"))
})

test_that("a model error never stakes", {
  g <- gov(ev_over = 0.085, ev_under = -0.1, p_over = 0.5683, p_under = 0.4317, model_error = TRUE)
  expect_identical(g$tier, "model_error")
  expect_identical(g$recommendation, "MODEL ERROR")
  expect_equal(g$final_stake_pct, 0)
})

test_that("zero rows and a non-positive minimum stake", {
  g <- govern_prop_rows(numeric(), numeric(), numeric(), numeric(), numeric(), numeric())
  expect_equal(nrow(g), 0)
  expect_true(all(c("side", "tier", "recommendation", "final_stake_pct", "pass_reason") %in% names(g)))
  expect_error(gov(min_stake = 0), "min_stake")
})

test_that("over 10,000 random rows: stake > 0 if and only if tier is bet (P2, P3)", {
  set.seed(2026)
  n <- 10000
  p_over <- runif(n, 0.05, 0.95)
  p_under <- pmin(pmax(1 - p_over - runif(n, 0, 0.03), 0), 1)
  odds_pool <- c(-250, -180, -150, -130, -120, -110, -105, 100, 110, 130, 180, 250, 400, NA)
  over_odds <- sample(odds_pool, n, replace = TRUE)
  under_odds <- sample(odds_pool, n, replace = TRUE)
  dec <- function(o) ifelse(is.na(o), NA_real_, ifelse(o > 0, 1 + o / 100, 1 + 100 / abs(o)))
  ev_over <- p_over * dec(over_odds) - 1
  ev_under <- p_under * dec(under_odds) - 1
  priced <- runif(n) > 0.15
  one_sided <- runif(n) > 0.8
  model_error <- runif(n) > 0.97

  g <- govern_prop_rows(ev_over, ev_under, p_over, p_under, over_odds, under_odds, priced = priced,
                        unpriced_reason = ifelse(priced, "", "No line for this player and game"),
                        one_sided = one_sided, model_error = model_error)

  expect_equal(nrow(g), n)
  expect_identical(g$final_stake_pct > 0, g$tier == "bet")
  expect_true(all(g$final_stake_pct >= 0 & g$final_stake_pct <= 0.02))
  expect_true(all(g$final_stake_pct[g$tier == "bet"] >= 0.01))
  expect_true(all(g$pass_reason[g$tier == "bet"] == ""))
  expect_true(all(nzchar(g$pass_reason[g$tier != "bet"])))
  expect_identical(g$recommendation == "PASS", g$tier == "pass")
  expect_identical(g$recommendation %in% c("OVER", "UNDER", "BET"), g$tier == "bet")
  # unpriced rows: no EV, no bet, no side
  expect_true(all(is.na(g$ev_over[!priced])) && all(is.na(g$ev_under[!priced])))
  expect_true(all(g$tier[!priced & !model_error] == "pass"))
  expect_true(all(g$side[!priced] == "NONE"))
  # the side taken is the larger-EV priced side; a one-sided market never takes the Under
  both <- priced & !one_sided & is.finite(ev_over) & is.finite(ev_under)
  expect_true(all(g$side[both & ev_under > ev_over] == "UNDER"))
  expect_true(all(g$side[both & ev_over >= ev_under] == "OVER"))
  expect_false(any(g$side[one_sided] == "UNDER"))
  # distinct tiers exist (P1)
  expect_gt(length(unique(g$edge_quality)), 3)
})

# --- through run_correlated_props ---

test_that("run_correlated_props applies the governance: tiers agree with stakes, unpriced rows say why", {
  set.seed(5)
  utc <- function(x) as.POSIXct(x, tz = "UTC")
  players <- tibble::tibble(
    player_id = c("00-JA", "00-DM"), player_name = c("Josh Allen", "Drake Maye"), position = "QB",
    recent_team = c("BUF", "NE"), avg_passing_yards = c(300, 220), avg_rushing_yards = c(40, 20),
    avg_receiving_yards = 0, avg_touchdowns = c(0.5, 0.3), is_projection = FALSE, is_baseline = FALSE
  )
  cache <- tibble::tibble(
    player_id = "00-JA", prop_type = "passing_yards", game_id = "2024_16_NE_BUF",
    captured_at = utc("2024-12-22 17:10:00"), book = "draftkings", line = 242.5, line_over = 242.5,
    line_under = 242.5, over_odds = -108, under_odds = -112, venue = "book"
  )
  schedule <- tibble::tibble(game_id = "2024_16_NE_BUF", home_team = "BUF", away_team = "NE", week = 16L,
                             gameday = "2024-12-22", gametime = "13:00")
  sims <- list("2024_16_NE_BUF" = list(game_id = "2024_16_NE_BUF", home_team = "BUF", away_team = "NE",
                                       week = 16L, home = rpois(2000, 24), away = rpois(2000, 21)))
  old_req <- get0("PROP_REQUIRE_MARKET_ODDS", envir = globalenv(), inherits = FALSE)
  assign("PROP_REQUIRE_MARKET_ODDS", FALSE, envir = globalenv())
  on.exit(assign("PROP_REQUIRE_MARKET_ODDS", old_req, envir = globalenv()), add = TRUE)

  res <- suppressMessages(suppressWarnings(run_correlated_props(
    sims, schedule_data = schedule, prop_types = "passing", season = 2024,
    prop_odds_cache = cache, players = players, now = utc("2026-10-13 12:00:00")
  )))
  expect_equal(nrow(res), 2)
  expect_true(all(c("side", "tier", "recommendation", "Final Stake (%)", "Pass Reason", "edge_quality",
                    "unpriced_reason", "price_venue") %in% names(res)))
  expect_identical(res[["Final Stake (%)"]] > 0, res$tier == "bet")
  maye <- res[res$player == "Drake Maye", ]
  expect_identical(maye$tier, "pass")
  expect_identical(maye$`Pass Reason`, "No line for this player and game")
  expect_true(is.na(maye$ev_over))
  allen <- res[res$player == "Josh Allen", ]
  expect_identical(allen$odds_source, "market")
  expect_false(allen$recommendation %in% c("OVER", "UNDER") && allen$`Final Stake (%)` == 0)
})

test_that("run_week.R's schedule (game_date, kickoff_time_raw) gives every game its kickoff (final review C1)", {
  set.seed(5)
  utc <- function(x) as.POSIXct(x, tz = "UTC")
  players <- tibble::tibble(
    player_id = "00-JA", player_name = "Josh Allen", position = "QB", recent_team = "BUF",
    avg_passing_yards = 300, avg_rushing_yards = 40, avg_receiving_yards = 0, avg_touchdowns = 0.5,
    is_projection = FALSE, is_baseline = FALSE
  )
  cache <- tibble::tibble(
    player_id = "00-JA", prop_type = "passing_yards", game_id = "2024_16_NE_BUF",
    captured_at = utc("2024-12-22 17:10:00"), book = "draftkings", line = 242.5, line_over = 242.5,
    line_under = 242.5, over_odds = -108, under_odds = -112, venue = "book"
  )
  # games_ready, as run_week.R passes it: no gameday or gametime, but game_date and the Eastern time
  schedule <- tibble::tibble(game_id = "2024_16_NE_BUF", home_team = "BUF", away_team = "NE", week = 16L,
                             game_date = as.Date("2024-12-22"), kickoff_time_raw = "13:00")
  sims <- list("2024_16_NE_BUF" = list(game_id = "2024_16_NE_BUF", home_team = "BUF", away_team = "NE",
                                       week = 16L, home = rpois(2000, 24), away = rpois(2000, 21)))
  old_req <- get0("PROP_REQUIRE_MARKET_ODDS", envir = globalenv(), inherits = FALSE)
  assign("PROP_REQUIRE_MARKET_ODDS", FALSE, envir = globalenv())
  on.exit(assign("PROP_REQUIRE_MARKET_ODDS", old_req, envir = globalenv()), add = TRUE)
  res <- suppressMessages(suppressWarnings(run_correlated_props(
    sims, schedule_data = schedule, prop_types = "passing", season = 2024,
    prop_odds_cache = cache, players = players, now = utc("2026-10-13 12:00:00")
  )))
  allen <- res[res$player == "Josh Allen", ]
  expect_identical(allen$odds_source, "market")
  expect_false(any(res$unpriced_reason == "Kickoff unknown"))
})

test_that("an edge at or below the minimum edge is a pass, whatever the stake (final review I4)", {
  # an Over at -500 (decimal 1.2) with p = 0.85: Kelly would stake, but 1.9% EV is below the 2% minimum
  g <- govern_prop_rows(ev_over = c(0.019, 0.03), ev_under = c(-0.05, -0.05),
                        p_over = c(0.85, 0.85), p_under = c(0.15, 0.15),
                        over_odds = c(-500, -500), under_odds = c(350, 350), min_edge = 0.02)
  expect_identical(g$tier, c("pass", "bet"))
  expect_identical(g$pass_reason[1], "Edge below minimum")
  expect_identical(g$final_stake_pct[1], 0)
  expect_gt(g$final_stake_pct[2], 0)
})

# =============================================================================
# FILE: tests/testthat/test-prop-pricing.R
# PURPOSE: P12, devig per venue, the Kalshi taker fee, EV at the best fresh price.
# =============================================================================

library(testthat)

source(file.path(.test_project_root, "R", "prop_keys.R"), local = FALSE)
source(file.path(.test_project_root, "R", "prop_odds_api.R"), local = FALSE)
source(file.path(.test_project_root, "R", "prop_pricing.R"), local = FALSE)
source(file.path(.test_project_root, "R", "correlated_props.R"), local = FALSE)

utc <- function(x) as.POSIXct(x, tz = "UTC")
COEF <- 0.07

test_that("devig_two_way: worked examples", {
  # -110/-110: each side implies 110/210 = 0.5238095, the overround is 1.047619, fair is 50/50
  d <- devig_two_way(-110, -110)
  expect_equal(d$p_over, 0.5)
  expect_equal(d$p_under, 0.5)
  expect_equal(d$overround, 2 * 110 / 210)
  # -120/+100: q_over = 120/220 = 0.5454545, q_under = 0.5; fair over = 0.5454545 / 1.0454545
  d <- devig_two_way(-120, 100)
  expect_equal(d$p_over, (120 / 220) / (120 / 220 + 0.5))
  expect_equal(d$p_over + d$p_under, 1)
  # vectorized; a missing side gives NA, not a made-up number
  d <- devig_two_way(c(-110, -120, NA), c(-110, 100, -110))
  expect_equal(d$p_over[1:2], c(0.5, (120 / 220) / (120 / 220 + 0.5)))
  expect_true(is.na(d$p_over[3]))
})

test_that("Kalshi taker fee: the schedule's figures at 50 and 10 cents", {
  expect_equal(kalshi_fee_per_contract(0.50, COEF), 0.0175)      # 1.75 cents
  expect_equal(kalshi_fee_per_contract(0.10, COEF), 0.0063)      # 0.63 cents
  expect_equal(kalshi_fee_per_contract(0.90, COEF), 0.0063)      # symmetric in P
  expect_equal(kalshi_fee_per_contract(0.50, 0), 0)
  expect_true(is.na(kalshi_fee_per_contract(1.2, COEF)))         # not a price
  expect_true(is.na(kalshi_fee_per_contract(0, COEF)))
})

test_that("Kalshi effective odds: worked example at 50 cents", {
  # pay 0.50 + 0.0175 = 0.5175 to collect 1: decimal 1 / 0.5175 = 1.932367
  expect_equal(kalshi_effective_decimal(0.50, COEF), 1 / 0.5175)
  expect_equal(kalshi_effective_decimal(0.50, 0), 2)
  # at p = 0.55 the contract is worth 0.55 * 1.932367 - 1 = +0.0628 per dollar after the fee
  expect_equal(round(0.55 * kalshi_effective_decimal(0.50, COEF) - 1, 4), 0.0628)
  expect_equal(decimal_to_american_exact(c(2, 3.5, 1.5, 1, NA)), c(100, 250, -200, NA, NA))
})

mk_book <- function(book, line, over, under, captured = "2024-12-22 17:00:00", prop_type = "passing_yards") {
  tibble::tibble(player_id = "00-JA", prop_type = prop_type, game_id = "2024_16_NE_BUF",
                 captured_at = utc(captured), book = book, line = line, line_over = line, line_under = line,
                 over_odds = over, under_odds = under, venue = "book")
}
mk_kalshi <- function(bid, ask, line = 242.5, captured = "2024-12-22 17:00:00", prop_type = "passing_yards") {
  tibble::tibble(player_id = "00-JA", prop_type = prop_type, game_id = "2024_16_NE_BUF",
                 captured_at = utc(captured), book = "kalshi", line = line, line_over = line, line_under = line,
                 over_odds = NA_real_, under_odds = NA_real_, yes_bid = bid, yes_ask = ask, venue = "kalshi")
}
bind <- function(...) dplyr::bind_rows(...)

# 100 simulated outcomes: 60 above 242.5 and 40 below, no pushes: p_over = 0.6, p_under = 0.4
SIM_OVER <- c(rep(300, 60), rep(200, 40))
# p_over = 0.2, p_under = 0.8
SIM_UNDER <- c(rep(300, 20), rep(200, 80))

test_that("quote_sides: books are devigged on their own, Kalshi uses the mid and the fee", {
  s <- quote_sides(bind(mk_book("draftkings", 242.5, -110, -110), mk_kalshi(0.50, 0.52)), COEF)
  expect_equal(s$fair_over, c(0.5, 0.51))                            # book: devig; Kalshi: (0.50 + 0.52) / 2
  expect_equal(s$over_dec[1], 1 + 100 / 110)
  expect_equal(s$over_dec[2], 1 / (0.52 + 0.07 * 0.52 * 0.48))       # Yes is bought at the ask
  expect_equal(s$under_dec[2], 1 / (0.50 + 0.07 * 0.50 * 0.50))      # No is bought at 1 - bid = 0.50
  bad <- quote_sides(bind(mk_kalshi(0.60, 0.50), mk_kalshi(NA, 0.5), mk_kalshi(0.5, 1)), COEF)
  expect_true(all(is.na(bad$over_dec)) && all(is.na(bad$under_dec)) && all(is.na(bad$fair_over)))
})

test_that("EV is taken at the best price for the side the model likes, after the Kalshi fee", {
  # book: over -130 (dec 1.769231), under +110; Kalshi: bid 0.50, ask 0.52; model p_over = 0.6
  #   book over EV   = 0.6 * 0.769231 - 0.4                           = 0.061538
  #   Kalshi over    = 0.6 / (0.52 + 0.07 * 0.52 * 0.48) - 1          = 0.116337 (fee 0.017472)
  cache <- bind(mk_book("draftkings", 242.5, -130, 110), mk_kalshi(0.50, 0.52))
  best <- select_best_quote(cache, sim_values = SIM_OVER, coef = COEF)
  expect_equal(best$venue, "kalshi")
  expect_true(best$fee_included)
  expect_equal(best$ev_over, 0.6 / (0.52 + 0.07 * 0.52 * 0.48) - 1)
  expect_equal(round(best$ev_over, 6), 0.116337)
  expect_equal(best$over_odds, -100 / (1 / (0.52 + 0.07 * 0.52 * 0.48) - 1))   # effective American (-116.2), unrounded
  # with no fee Kalshi is better still: 0.6 / 0.52 - 1
  free <- select_best_quote(cache, sim_values = SIM_OVER, coef = 0)
  expect_equal(free$ev_over, 0.6 / 0.52 - 1)
  expect_gt(free$ev_over, best$ev_over)
  # a large enough fee hands the quote back to the book: Kalshi EV falls to -0.032008 at coef 0.4
  costly <- select_best_quote(cache, sim_values = SIM_OVER, coef = 0.4)
  expect_equal(costly$venue, "book")
  expect_equal(round(costly$ev_over, 6), 0.061538)
})

test_that("the side the model likes can be the Under, bought as No at 1 - bid", {
  # model p_under = 0.8. Book: over +300, under -400 (dec 1.25): under EV = 0.8 * 0.25 - 0.2 = 0.
  # Kalshi bid 0.30, ask 0.32: No costs 0.70 (+ fee 0.0147): EV = 0.8 / 0.7147 - 1 = 0.119351
  cache <- bind(mk_book("draftkings", 242.5, 300, -400), mk_kalshi(0.30, 0.32))
  best <- select_best_quote(cache, sim_values = SIM_UNDER, coef = COEF)
  expect_equal(best$venue, "kalshi")
  expect_gt(best$ev_under, best$ev_over)
  expect_equal(best$ev_under, 0.8 / (0.70 + 0.07 * 0.70 * 0.30) - 1)
  expect_equal(round(best$ev_under, 6), 0.119351)
  # against a fair book under (-110) the book is the better price: 0.8 * 0.909091 - 0.2 = 0.527273
  cache2 <- bind(mk_book("draftkings", 242.5, -110, -110), mk_kalshi(0.30, 0.32))
  best2 <- select_best_quote(cache2, sim_values = SIM_UNDER, coef = COEF)
  expect_equal(best2$venue, "book")
  expect_equal(round(best2$ev_under, 6), 0.527273)
})

test_that("pushes are counted on each quote's own line", {
  sim <- c(rep(250, 10), rep(300, 50), rep(200, 40))      # 10 exactly on the line 250
  s <- select_best_quote(mk_book("draftkings", 250, -110, -110), sim_values = sim, coef = COEF)
  # p_over = 0.5, p_push = 0.1, p_under = 0.4: over EV = 0.5 * 0.909091 - (1 - 0.5 - 0.1) = 0.054545
  expect_equal(round(s$ev_over, 6), 0.054545)
})

test_that("one-way anytime TD: Yes only, fee included", {
  # model p = 0.30. Book Yes +250 (dec 3.5): EV 0.05. Kalshi ask 0.27 (+ fee 0.013797): EV 0.057094
  cache <- bind(mk_book("draftkings", NA_real_, 250, NA_real_, prop_type = "anytime_td"),
                mk_kalshi(0.25, 0.27, line = NA_real_, prop_type = "anytime_td"))
  best <- select_best_quote(cache, p_yes = 0.30, coef = COEF)
  expect_equal(best$venue, "kalshi")
  expect_equal(round(best$ev_over, 6), 0.057094)
  expect_true(is.na(best$ev_under))
  book_only <- select_best_quote(cache[1, ], p_yes = 0.30, coef = COEF)
  expect_equal(round(book_only$ev_over, 6), 0.05)
})

test_that("nothing priceable gives NULL, never a number (M11)", {
  expect_null(select_best_quote(mk_book("draftkings", 242.5, NA_real_, NA_real_), sim_values = SIM_OVER, coef = COEF))
  expect_null(select_best_quote(mk_kalshi(0.6, 0.5), sim_values = SIM_OVER, coef = COEF))
  expect_error(select_best_quote(mk_book("draftkings", 242.5, -110, -110), coef = COEF), "sim_values")
})

test_that("get_market_prop_line with the simulation honours freshness and the kickoff", {
  kick <- utc("2024-12-22 18:00:00")
  now <- utc("2026-10-13 12:00:00")
  cache <- bind(mk_book("draftkings", 242.5, -130, 110),
                mk_kalshi(0.50, 0.52, captured = "2024-12-22 17:00:00"),
                mk_kalshi(0.40, 0.42, captured = "2026-10-01 12:00:00"))     # a 2026 Kalshi quote
  logged <- character()
  best <- get_market_prop_line("00-JA", "passing_yards", cache, game_id = "2024_16_NE_BUF", kickoff = kick,
                               now = now, sim_values = SIM_OVER, on_unpriced = function(r) logged <<- r)
  expect_equal(best$venue, "kalshi")
  expect_equal(best$captured_at, utc("2024-12-22 17:00:00"))          # not the 2026 quote
  expect_equal(best$fair_over, mean(c((130 / 230) / (130 / 230 + 100 / 210), 0.51)))
  expect_identical(best$player, "00-JA")
  expect_identical(best$prop_type, "passing_yards")
  stale <- cache[2, ]
  stale$captured_at <- utc("2024-12-22 15:00:00")
  expect_null(get_market_prop_line("00-JA", "passing_yards", stale, game_id = "2024_16_NE_BUF", kickoff = kick,
                                   now = now, sim_values = SIM_OVER, on_unpriced = function(r) logged <<- r))
  expect_match(logged, "^Newest line is stale")
})

test_that("run_game_props reports the venue, the devigged market and the capture time", {
  set.seed(12)
  kick <- utc("2024-12-22 18:00:00")
  players <- tibble::tibble(
    player_id = "00-JA", player_name = "Josh Allen", position = "QB", recent_team = "BUF",
    avg_passing_yards = 300, avg_rushing_yards = 40, avg_receiving_yards = 0, avg_touchdowns = 0.5,
    is_projection = FALSE, is_baseline = FALSE
  )
  neutral <- tibble::tibble(team = c("BUF", "NE"), pass_def_multiplier = 1, rush_def_multiplier = 1,
                            recv_def_multiplier = 1)
  cache <- bind(mk_book("draftkings", 242.5, -130, 110), mk_kalshi(0.50, 0.52))
  res <- suppressMessages(run_game_props(
    list(home = rpois(2000, 24), away = rpois(2000, 21)), "BUF", "NE", 2024, prop_types = "passing",
    prop_odds_cache = cache, game_id = "2024_16_NE_BUF", kickoff = kick, week = 16L,
    players = players, defense_ranks = neutral, now = utc("2026-10-13 12:00:00")
  ))
  expect_equal(nrow(res), 1)
  expect_identical(res$price_venue, "kalshi")
  expect_identical(res$book, "kalshi")
  expect_equal(res$quote_captured_at, utc("2024-12-22 17:00:00"))
  expect_equal(res$mkt_fair_over, mean(c((130 / 230) / (130 / 230 + 100 / 210), 0.51)))
  # EV already includes the fee: recompute it from the row's own probability
  expect_lt(abs(res$ev_over - (res$p_over / (0.52 + 0.07 * 0.52 * 0.48) - 1)), 5e-4)
  expect_identical(res$unpriced_reason, "")
})

test_that("the market's fair probability is read at the chosen line, never averaged across lines (final review I3)", {
  # p_over is 0.60 at 242.5 and 0.30 at 299.5; Kalshi at 299.5 (mid 0.21) is the best quote
  sim <- c(rep(350, 30), rep(260, 30), rep(200, 40))
  cache <- bind(mk_book("draftkings", 242.5, -110, -110), mk_kalshi(0.20, 0.22, line = 299.5))
  best <- select_best_quote(cache, sim_values = sim, coef = COEF)
  expect_equal(best$line, 299.5)
  expect_equal(best$fair_over, 0.21)      # not (0.50 + 0.21) / 2 = 0.355
})

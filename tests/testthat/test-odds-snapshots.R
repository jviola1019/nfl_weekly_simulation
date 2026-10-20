# =============================================================================
# Tests: the odds_snapshots shape (R/odds/snapshots.R)
# =============================================================================

snap_row <- function(...) {
  base <- data.frame(
    game_id = "2024_01_ARI_BUF", market_id = "moneyline", venue_id = "espn_bet", side = "home",
    price_american = -275L, snapshot_kind = "open", source = "espn_core", raw_sha256 = "abc",
    player_key = NA_character_, captured_at = as.POSIXct(NA, tz = "UTC"), bid = NA_real_, ask = NA_real_,
    stringsAsFactors = FALSE
  )
  over <- list(...)
  for (nm in names(over)) base[[nm]] <- over[[nm]]
  base
}

test_that("the shape is the Drizzle odds_snapshots table plus lineage columns", {
  # web/src/db/schema.ts oddsSnapshots: game_id, market_id, venue_id, player_id, side, line,
  # price_american, bid, ask, last, volume, captured_at (fetch_id is assigned at ingest).
  # player_id is carried as the unresolved player_key until the alias tables exist.
  schema_ts <- readLines(file.path(PROJECT_ROOT, "web", "src", "db", "schema.ts"), warn = FALSE)
  start <- grep('export const oddsSnapshots', schema_ts)
  end <- start + which(grepl("^  \\},?$", schema_ts[-seq_len(start)]))[1]
  block <- paste(schema_ts[start:end], collapse = "\n")
  db_cols <- regmatches(block, gregexpr('"[a-z_]+"\\)', block))[[1]]
  db_cols <- gsub('[")]', "", db_cols)
  expect_true(all(setdiff(db_cols, c("snapshot_id", "fetch_id", "player_id")) %in% ODDS_SNAPSHOT_COLUMNS))
  expect_true(all(c("player_key", "snapshot_kind", "source", "raw_sha256") %in% ODDS_SNAPSHOT_COLUMNS))
})

test_that("the market and venue catalogs satisfy the contract schemas", {
  contracts <- file.path(PROJECT_ROOT, "contracts", "schema")
  expect_equal(bw_validate_rows(odds_markets_catalog(), bw_read_schema("markets", contracts), "markets"), character())
  expect_equal(bw_validate_rows(odds_venues_catalog(), bw_read_schema("venues", contracts), "venues"), character())
  expect_true(all(c("moneyline", "spread", "total", "anytime_td", "first_td", "td_2plus",
                    "passing_yards", "rushing_yards", "receiving_yards", "receptions") %in% odds_markets_catalog()$market_id))
  expect_true(all(c("nflverse_consensus", "espn_bet", "draftkings", "kalshi") %in% odds_venues_catalog()$venue_id))
})

test_that("american_to_int parses signed strings and rejects non-prices without warning", {
  expect_warning(out <- american_to_int(c("+225", "-275", "EVEN", "", NA, "OFF", "-110.0", 150)), NA)
  expect_identical(out, c(225L, -275L, 100L, NA, NA, NA, -110L, 150L))
  expect_identical(american_to_int(-0.5), NA_integer_)   # between -100 and +100 is not an American price
})

test_that("new_odds_snapshots completes missing columns with typed NAs and orders them", {
  s <- new_odds_snapshots(snap_row())
  expect_identical(names(s), ODDS_SNAPSHOT_COLUMNS)
  expect_true(is.integer(s$price_american))
  expect_true(is.numeric(s$line) && is.na(s$line))
  expect_s3_class(s$captured_at, "POSIXct")
  expect_equal(attr(s$captured_at, "tzone"), "UTC")
  expect_equal(nrow(odds_snapshots_empty()), 0)
  expect_identical(names(odds_snapshots_empty()), ODDS_SNAPSHOT_COLUMNS)
})

test_that("validation names every problem, and the constructor refuses invalid rows", {
  bad <- rbind(
    snap_row(market_id = "made_up"),
    snap_row(venue_id = "nowhere"),
    snap_row(side = "sideways"),
    snap_row(snapshot_kind = "observed"),                       # timed kinds need captured_at
    snap_row(price_american = -50L),                            # |price| must be >= 100
    snap_row(market_id = "anytime_td", venue_id = "kalshi", side = "yes", snapshot_kind = "candle",
             captured_at = as.POSIXct("2026-10-01 12:00", tz = "UTC"), bid = 0.6, ask = 0.5),   # crossed, and no player_key
    snap_row(market_id = "moneyline", player_key = "kalshi:x")  # game markets carry no player
  )
  problems <- validate_odds_snapshots(complete_odds_snapshots(bad))
  expect_true(any(grepl("market_id", problems)))
  expect_true(any(grepl("venue_id", problems)))
  expect_true(any(grepl("side", problems)))
  expect_true(any(grepl("captured_at", problems)))
  expect_true(any(grepl("price_american", problems)))
  expect_true(any(grepl("bid > ask", problems)))
  expect_true(any(grepl("player_key", problems)))
  expect_error(new_odds_snapshots(bad), "invalid odds_snapshots")
  expect_error(new_odds_snapshots(snap_row(surprise = 1)), "unknown column")
  expect_equal(validate_odds_snapshots(new_odds_snapshots(snap_row())), character())
})

test_that("bind_odds_snapshots stacks results and skips empty ones", {
  a <- new_odds_snapshots(snap_row())
  b <- new_odds_snapshots(snap_row(side = "away", price_american = 225L))
  all <- bind_odds_snapshots(list(a, odds_snapshots_empty(), b, NULL))
  expect_equal(nrow(all), 2)
  expect_equal(nrow(bind_odds_snapshots(list())), 0)
})

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

# -----------------------------------------------------------------------------
# Review fixes (Task 2, fix round 1): lossless times and prices, side by market,
# lineage, and a total american_to_int
# -----------------------------------------------------------------------------

# The rows a problem names: "side: ... (rows 2, 3)" gives c(2, 3). Empty when none does.
problem_rows <- function(problems, pattern) {
  hit <- problems[grepl(pattern, problems)]
  if (!length(hit)) return(integer())
  as.integer(strsplit(sub(".*\\(rows ([0-9, ]+)\\).*", "\\1", hit[1]), ",[[:space:]]*")[[1]])
}

# Each row is completed on its own, so rows built with different columns still bind
snap_rows <- function(...) do.call(rbind, lapply(list(...), complete_odds_snapshots))

test_that("american_to_int is total: a non-finite or out-of-range input is NA, never an error", {
  expect_warning(out <- american_to_int(c("-110", "Inf", "-Inf", "INFINITY", "1e400", "3000000000")), NA)
  expect_identical(out, c(-110L, NA, NA, NA, NA, NA))
  expect_identical(american_to_int(-Inf), NA_integer_)
  expect_identical(american_to_int("-2147483647"), -2147483647L)
  expect_identical(american_to_int("-2147483648"), NA_integer_)
})

test_that("captured_at keeps the time of day of an ISO string, fractional seconds included", {
  whole <- complete_odds_snapshots(snap_row(snapshot_kind = "observed", captured_at = "2026-10-12T19:45:30Z"))
  expect_equal(format(whole$captured_at, "%H:%M:%S", tz = "UTC"), "19:45:30")
  frac <- complete_odds_snapshots(snap_row(snapshot_kind = "observed", captured_at = "2026-10-12T19:45:30.5Z"))
  expect_equal(as.numeric(frac$captured_at) - as.numeric(whole$captured_at), 0.5)
  spaced <- complete_odds_snapshots(snap_row(snapshot_kind = "observed", captured_at = "2026-10-12 19:45:30"))
  expect_equal(as.numeric(spaced$captured_at), as.numeric(whole$captured_at))
})

test_that("an unreadable captured_at stops complete_odds_snapshots and names its row", {
  rows <- rbind(snap_row(snapshot_kind = "observed", captured_at = "2026-10-12T19:45:30Z"),
                snap_row(snapshot_kind = "observed", captured_at = "not a time"))
  expect_error(complete_odds_snapshots(rows), "rows 2")
})

test_that("POSIXct and epoch-second times round-trip; a POSIXct in another zone keeps its instant", {
  t <- as.POSIXct("2026-10-12 19:45:30", tz = "UTC")
  p <- complete_odds_snapshots(snap_row(snapshot_kind = "observed", captured_at = t))
  expect_equal(as.numeric(p$captured_at), as.numeric(t))
  expect_equal(attr(p$captured_at, "tzone"), "UTC")
  n <- complete_odds_snapshots(snap_row(snapshot_kind = "observed", captured_at = as.numeric(t)))
  expect_equal(as.numeric(n$captured_at), as.numeric(t))
  expect_equal(attr(n$captured_at, "tzone"), "UTC")
  ny <- t
  attr(ny, "tzone") <- "America/New_York"
  z <- complete_odds_snapshots(snap_row(snapshot_kind = "observed", captured_at = ny))
  expect_equal(as.numeric(z$captured_at), as.numeric(t))
  expect_equal(attr(z$captured_at, "tzone"), "UTC")
})

test_that("a fractional or out-of-range price stops complete_odds_snapshots with its rows; whole prices pass", {
  expect_error(complete_odds_snapshots(snap_row(price_american = -275.5)), "rows 1")
  expect_error(complete_odds_snapshots(rbind(snap_row(), snap_row(price_american = 3e9))), "rows 2")
  expect_identical(complete_odds_snapshots(snap_row(price_american = 225))$price_american, 225L)
  expect_identical(complete_odds_snapshots(snap_row(price_american = -110))$price_american, -110L)
})

test_that("validation flags a fractional price on a table built by hand", {
  df <- complete_odds_snapshots(snap_row())
  df$price_american <- -275.5
  expect_true(any(grepl("price_american", validate_odds_snapshots(df))))
  df$price_american <- 225
  expect_equal(validate_odds_snapshots(df), character())
})

test_that("the side must fit the market (home/away, over/under, yes/line)", {
  problems <- validate_odds_snapshots(snap_rows(
    snap_row(),                                                               # 1 moneyline/home: fine
    snap_row(side = "over"),                                                  # 2 moneyline/over
    snap_row(market_id = "total", side = "home"),                             # 3 total/home
    snap_row(market_id = "anytime_td", side = "home", player_key = "espn:1"), # 4 anytime_td/home
    snap_row(market_id = "total", side = "under")                             # 5 total/under: fine
  ))
  expect_equal(problem_rows(problems, "^side: not allowed"), c(2L, 3L, 4L))
})

test_that("raw_sha256 is required: an empty or missing digest is flagged with its row", {
  problems <- validate_odds_snapshots(snap_rows(
    snap_row(), snap_row(raw_sha256 = ""), snap_row(raw_sha256 = NA_character_)
  ))
  expect_equal(problem_rows(problems, "^raw_sha256"), c(2L, 3L))
})

test_that("valid rows pass: a price-only spread or total, an open row that carries a time, a player line", {
  valid <- snap_rows(
    snap_row(market_id = "spread", side = "home", line = -6.5),
    snap_row(market_id = "spread", side = "away", line = 6.5, price_american = NA_integer_),
    snap_row(market_id = "total", side = "over", price_american = -110L),
    snap_row(snapshot_kind = "open", captured_at = as.POSIXct("2026-10-01 12:00", tz = "UTC")),
    snap_row(market_id = "receptions", side = "line", player_key = "espn:1", line = 4.5,
             snapshot_kind = "observed", captured_at = as.POSIXct("2026-10-01 12:00", tz = "UTC"))
  )
  expect_equal(validate_odds_snapshots(valid), character())
})

test_that("the side table covers exactly the catalog's markets", {
  expect_setequal(names(ODDS_MARKET_SIDES), odds_markets_catalog()$market_id)
})

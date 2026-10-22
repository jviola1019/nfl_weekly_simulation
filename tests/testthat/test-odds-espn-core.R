# =============================================================================
# Tests: the ESPN core provider (R/odds/provider_espn_core.R)
# Fixtures in fixtures/odds/ are trimmed REAL responses (2024_01_ARI_BUF from the
# 2024 season, NE at SEA from 2026 week 1); the prop and scoreboard fixtures are in
# fixtures/capture/. Every fetch goes through odds_fake_fetch(): no network.
# The scoreboards of the capture tests are built here, like test-capture-raw.R does.
# =============================================================================

GAME_2024 <- data.frame(game_id = "2024_01_ARI_BUF", season = 2024L, espn = "401671617", stringsAsFactors = FALSE)
GAME_2026 <- data.frame(game_id = "2026_01_NE_SEA", season = 2026L, espn = "401872656", stringsAsFactors = FALSE)
odds_url <- function(event) espn_game_odds_url(event)

espn_provider <- function(routes, clock = odds_fake_clock(), log_path = NULL) {
  odds_http_reset()
  fake <- odds_fake_fetch(routes)
  list(provider = provider_espn_core(cfg = odds_http_config(), fetch_fn = fake$fn, log_path = log_path,
                                     now_fn = clock$now, sleep_fn = clock$sleep),
       fake = fake, clock = clock)
}

# A parsed fixture back to a route that serves it as inline text (for tests that edit a fixture)
json_route <- function(parsed) {
  list(text = as.character(jsonlite::toJSON(parsed, auto_unbox = TRUE, digits = NA, null = "null")))
}

test_that("ESPN BET open and close lines become snapshots for the moneyline, spread and total", {
  parsed <- odds_fixture_json("espn_game_odds_2024_01_ARI_BUF.json")
  s <- parse_espn_game_odds(parsed, "2024_01_ARI_BUF", sha256 = strrep("a", 64))
  expect_equal(validate_odds_snapshots(s), character())
  expect_equal(unique(s$venue_id), "espn_bet")
  expect_equal(nrow(s), 12)                                         # 3 markets x 2 sides x open/close
  expect_true(all(is.na(s$captured_at)))
  pick <- function(market, side, kind) s[s$market_id == market & s$side == side & s$snapshot_kind == kind, ]
  expect_equal(pick("moneyline", "home", "open")$price_american, -275L)
  expect_equal(pick("moneyline", "home", "close")$price_american, -320L)
  expect_equal(pick("moneyline", "away", "open")$price_american, 225L)
  expect_equal(pick("moneyline", "away", "close")$price_american, 260L)
  expect_equal(pick("spread", "home", "open")$line, -7)
  expect_equal(pick("spread", "home", "close")$line, -6.5)
  expect_equal(pick("spread", "home", "close")$price_american, -120L)
  expect_equal(pick("spread", "away", "close")$line, 6.5)
  expect_equal(pick("spread", "away", "close")$price_american, 100L)
  expect_equal(pick("total", "over", "open")$line, 48)
  expect_equal(pick("total", "under", "open")$price_american, -115L)
  expect_equal(pick("total", "over", "close")$line, 45.5)
  expect_equal(unique(s$raw_sha256), strrep("a", 64))
  # providers without an open and a close block are skipped and named, not guessed
  expect_setequal(attr(s, "skipped_providers"), c("2000 Bet 365", "59 ESPN Bet - Live Odds"))
  expect_equal(attr(s, "dropped"), 0L)
  expect_equal(attr(s, "line_only"), 0L)
})

test_that("DraftKings (provider 100) maps to its own venue", {
  s <- parse_espn_game_odds(odds_fixture_json("espn_game_odds_2026_01_NE_SEA.json"), "2026_01_NE_SEA", sha256 = "b")
  expect_equal(unique(s$venue_id), "draftkings")
  expect_equal(s$price_american[s$market_id == "moneyline" & s$side == "home" & s$snapshot_kind == "open"], -192L)
  expect_equal(s$line[s$market_id == "total" & s$side == "over" & s$snapshot_kind == "close"], 44.5)
})

test_that("a pick'em spread parses as a handicap of 0, and a missing side drops that market only", {
  parsed <- odds_fixture_json("espn_game_odds_2026_01_NE_SEA.json")
  parsed$items[[1]]$homeTeamOdds$open$pointSpread$american <- "PK"
  parsed$items[[1]]$awayTeamOdds$open$pointSpread$american <- "PK"
  parsed$items[[1]]$awayTeamOdds$close$moneyLine <- NULL
  s <- parse_espn_game_odds(parsed, "g", sha256 = "c")
  expect_equal(s$line[s$market_id == "spread" & s$snapshot_kind == "open" & s$side == "home"], 0)
  expect_false(any(s$market_id == "moneyline" & s$snapshot_kind == "close"))     # one side missing: no half market
  expect_true(any(s$market_id == "moneyline" & s$snapshot_kind == "open"))
  expect_equal(attr(s, "dropped"), 1L)                                           # and the drop is counted
})

test_that("a moneyline whose price cannot be read is dropped and counted, never stored without a price", {
  parsed <- odds_fixture_json("espn_game_odds_2026_01_NE_SEA.json")
  parsed$items[[1]]$homeTeamOdds$open$moneyLine$american <- "OFF"
  s <- parse_espn_game_odds(parsed, "g", sha256 = "c")
  expect_false(any(s$market_id == "moneyline" & s$snapshot_kind == "open"))
  expect_true(any(s$market_id == "moneyline" & s$snapshot_kind == "close"))
  expect_equal(attr(s, "dropped"), 1L)
})

test_that("a game with a close but no open keeps its close (80 of the 285 games of 2023)", {
  parsed <- odds_fixture_json("espn_game_odds_2024_01_ARI_BUF.json")
  espn_bet <- which(vapply(parsed$items, function(i) identical(i$provider$id, "58"), logical(1)))
  for (side in c("homeTeamOdds", "awayTeamOdds")) parsed$items[[espn_bet]][[side]]$open <- NULL
  parsed$items[[espn_bet]]$open <- NULL
  s <- parse_espn_game_odds(parsed, "g", sha256 = "c")
  expect_equal(unique(s$snapshot_kind), "close")
  expect_equal(nrow(s), 6)
  expect_equal(attr(s, "dropped"), 0L)                               # an absent phase is not a dropped block
})

test_that("a line whose price is missing keeps the line with an NA price (found in the real 2023-2024 responses)", {
  parsed <- odds_fixture_json("espn_game_odds_2026_01_NE_SEA.json")
  parsed$items[[1]]$homeTeamOdds$open$spread <- NULL
  parsed$items[[1]]$open$over <- NULL
  s <- parse_espn_game_odds(parsed, "g", sha256 = "c")
  sp <- s[s$market_id == "spread" & s$side == "home" & s$snapshot_kind == "open", ]
  expect_equal(c(sp$line, sp$price_american), c(-3.5, NA))
  tot <- s[s$market_id == "total" & s$side == "over" & s$snapshot_kind == "open", ]
  expect_equal(c(tot$line, tot$price_american), c(44.5, NA))
  expect_equal(attr(s, "line_only"), 2L)                             # R6: kept, and counted
  expect_equal(attr(s, "dropped"), 0L)
})

test_that("game_snapshots fetches each event once, records the raw hash and hands the raw body to on_raw", {
  e <- espn_provider(setNames(list("espn_game_odds_2024_01_ARI_BUF.json", "espn_game_odds_2026_01_NE_SEA.json"),
                              c(odds_url("401671617"), odds_url("401872656"))))
  seen <- list()
  res <- e$provider$game_snapshots(rbind(GAME_2024, GAME_2026), on_raw = function(key, body, rec) seen[[key]] <<- rec$sha256)
  expect_equal(res$source_status$status, "ok")
  expect_match(res$source_status$detail, "2 of 2 games fetched")
  expect_setequal(unique(res$snapshots$venue_id), c("espn_bet", "draftkings"))
  expect_equal(nrow(res$fetches), 2)
  expect_equal(res$fetches$raw_sha256[res$fetches$key == "401671617"],
               digest::digest(odds_fixture_raw("espn_game_odds_2024_01_ARI_BUF.json"), algo = "sha256", serialize = FALSE))
  expect_equal(seen[["401671617"]], res$fetches$raw_sha256[res$fetches$key == "401671617"])
  expect_equal(e$fake$state$urls, c(odds_url("401671617"), odds_url("401872656")))
  expect_equal(e$clock$state$sleeps, 1)                              # the second request waited out the 1 s budget
})

test_that("a failed game is reported by name and makes the result stale; the others are kept; nothing is substituted", {
  e <- espn_provider(setNames(list("espn_game_odds_2024_01_ARI_BUF.json", list(status = 404L)),
                              c(odds_url("401671617"), odds_url("401872656"))))
  res <- e$provider$game_snapshots(rbind(GAME_2024, GAME_2026))
  expect_equal(res$source_status$status, "stale")                    # R5: partial data is stale, not failed
  expect_match(res$source_status$detail, "2026_01_NE_SEA")
  expect_equal(unique(res$snapshots$game_id), "2024_01_ARI_BUF")
  expect_false(is.na(res$source_status$last_success_utc))
  all_bad <- espn_provider(setNames(list(list(status = 404L)), odds_url("401671617")))$provider$game_snapshots(GAME_2024)
  expect_equal(all_bad$source_status$status, "unavailable")          # R5: nothing for what was requested
  expect_equal(nrow(all_bad$snapshots), 0)
})

test_that("a game with no ESPN event id is counted, and a 403 stops the run", {
  no_id <- transform(GAME_2024, game_id = "2024_01_NOID", espn = NA_character_)
  e <- espn_provider(setNames(list(list(status = 403L)), odds_url("401671617")))
  res <- e$provider$game_snapshots(rbind(no_id, GAME_2024, GAME_2026))
  expect_match(res$source_status$detail, "1 game without an ESPN event id")
  expect_match(res$source_status$detail, "blocked")
  expect_equal(length(e$fake$state$urls), 1)                         # no request after the 403, and none for the third game
  expect_equal(res$source_status$status, "unavailable")
})

test_that("a game without an event id, or a block after some games, leaves the rest stale (R5)", {
  no_id <- transform(GAME_2024, game_id = "2024_01_NOID", espn = NA_character_)
  e <- espn_provider(setNames(list("espn_game_odds_2024_01_ARI_BUF.json"), odds_url("401671617")))
  res <- e$provider$game_snapshots(rbind(no_id, GAME_2024))
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "1 game without an ESPN event id")
  blocked <- espn_provider(setNames(list("espn_game_odds_2024_01_ARI_BUF.json", list(status = 403L)),
                                    c(odds_url("401671617"), odds_url("401872656"))))$provider$game_snapshots(rbind(GAME_2024, GAME_2026))
  expect_equal(blocked$source_status$status, "stale")
  expect_match(blocked$source_status$detail, "blocked")
  expect_equal(unique(blocked$snapshots$game_id), "2024_01_ARI_BUF")
})

test_that("a 200 response whose body is not JSON is a block: one request, named as a block, no '(NA)' (fix 2)", {
  html <- list(text = "<html><head><title>Just a moment...</title></head><body>challenge</body></html>")
  e <- espn_provider(setNames(list(html), odds_url("401671617")))
  res <- e$provider$game_snapshots(rbind(GAME_2024, GAME_2026))
  expect_equal(length(e$fake$state$urls), 1)                         # the run stopped at the first one: no request for the second game
  expect_equal(res$source_status$status, "unavailable")
  detail <- res$source_status$detail
  expect_match(detail, "blocked: HTTP 200 body is not JSON \\(a challenge or geo-fence page\\)")
  expect_match(detail, "2024_01_ARI_BUF")                            # and it says where
  expect_false(grepl("(NA)", detail, fixed = TRUE))
  expect_false(grepl("live only", detail, fixed = TRUE))
  # after good games the same page makes the result stale, and the good games are kept
  mid <- espn_provider(setNames(list("espn_game_odds_2024_01_ARI_BUF.json", html), c(odds_url("401671617"), odds_url("401872656"))))
  after <- mid$provider$game_snapshots(rbind(GAME_2024, GAME_2026, transform(GAME_2026, game_id = "2026_01_NEXT", espn = "401872657")))
  expect_equal(after$source_status$status, "stale")
  expect_match(after$source_status$detail, "blocked: HTTP 200 body is not JSON")
  expect_equal(unique(after$snapshots$game_id), "2024_01_ARI_BUF")
  expect_equal(length(mid$fake$state$urls), 2)                       # nothing was asked for after it
  # any other bad body keeps its real text, never "(NA)"
  e404 <- espn_provider(setNames(list(list(status = 404L)), odds_url("401671617")))$provider$game_snapshots(GAME_2024)
  expect_match(e404$source_status$detail, "2024_01_ARI_BUF \\(HTTP 404\\)")
  expect_false(grepl("(NA)", e404$source_status$detail, fixed = TRUE))
})

test_that("a fetched game with no usable line, or with a market missing, makes the result stale (R5)", {
  bet365_only <- odds_fixture_json("espn_game_odds_2024_01_ARI_BUF.json")
  bet365_only$items <- bet365_only$items[1]                          # Bet 365 carries no open/close blocks
  no_total <- odds_fixture_json("espn_game_odds_2026_01_NE_SEA.json")
  for (phase in c("open", "close", "current")) no_total$items[[1]][[phase]] <- NULL
  e <- espn_provider(setNames(list(json_route(bet365_only), json_route(no_total)),
                              c(odds_url("401671617"), odds_url("401872656"))))
  res <- e$provider$game_snapshots(rbind(GAME_2024, GAME_2026))
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "1 game\\(s\\) fetched with no ESPN BET or DraftKings line: 2024_01_ARI_BUF")
  expect_match(res$source_status$detail, "1 game\\(s\\) missing a moneyline, spread or total: 2026_01_NE_SEA")
  expect_equal(unique(res$snapshots$game_id), "2026_01_NE_SEA")
  # a game that fetched fine but has no lines at all, and nothing else: zero snapshots is unavailable
  none <- espn_provider(setNames(list(json_route(bet365_only)), odds_url("401671617")))$provider$game_snapshots(GAME_2024)
  expect_equal(none$source_status$status, "unavailable")
})

test_that("a market block with a side or a readable price missing makes the result stale and says so (R5)", {
  half <- odds_fixture_json("espn_game_odds_2026_01_NE_SEA.json")
  half$items[[1]]$awayTeamOdds$close$moneyLine <- NULL
  res <- espn_provider(setNames(list(json_route(half)), odds_url("401872656")))$provider$game_snapshots(GAME_2026)
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "1 market block\\(s\\) dropped .*: 2026_01_NE_SEA")   # M1: and names the game
  # M2: a spread price with no handicap line is price-only, dropped and counted like a total's
  price_only <- odds_fixture_json("espn_game_odds_2026_01_NE_SEA.json")
  price_only$items[[1]]$homeTeamOdds$open$pointSpread <- NULL
  price_only$items[[1]]$awayTeamOdds$open$pointSpread <- NULL
  s <- parse_espn_game_odds(price_only, "g", sha256 = "c")
  expect_false(any(s$market_id == "spread" & s$snapshot_kind == "open"))
  expect_true(any(s$market_id == "spread" & s$snapshot_kind == "close"))
  expect_equal(attr(s, "dropped"), 1L)
  res2 <- espn_provider(setNames(list(json_route(price_only)), odds_url("401872656")))$provider$game_snapshots(GAME_2026)
  expect_equal(res2$source_status$status, "stale")
})

test_that("a line with no price is kept, counted in the detail, and does not make the result stale (R6)", {
  parsed <- odds_fixture_json("espn_game_odds_2026_01_NE_SEA.json")
  parsed$items[[1]]$homeTeamOdds$open$spread <- NULL
  parsed$items[[1]]$open$over <- NULL
  res <- espn_provider(setNames(list(json_route(parsed)), odds_url("401872656")))$provider$game_snapshots(GAME_2026)
  expect_equal(res$source_status$status, "ok")
  expect_match(res$source_status$detail, "2 line-only row\\(s\\) kept")
  kept <- res$snapshots[res$snapshots$market_id == "spread" & res$snapshots$side == "home" &
                          res$snapshots$snapshot_kind == "open", ]
  expect_equal(c(kept$line, kept$price_american), c(-3.5, NA))
})

test_that("an error thrown while fetching or parsing is 'failed' with its message and carries no snapshots, but keeps the request lineage (R5, R7)", {
  clock <- odds_fake_clock()
  odds_http_reset()
  good <- odds_fake_fetch(setNames(list("espn_game_odds_2024_01_ARI_BUF.json"), odds_url("401671617")))
  throwing <- function(url, cfg) if (identical(url, odds_url("401872656"))) stop("socket exploded") else good$fn(url, cfg)
  p <- provider_espn_core(cfg = odds_http_config(), fetch_fn = throwing, now_fn = clock$now, sleep_fn = clock$sleep)
  res <- p$game_snapshots(rbind(GAME_2024, GAME_2026))
  expect_equal(res$source_status$status, "failed")
  expect_match(res$source_status$detail, "socket exploded")
  expect_equal(nrow(res$snapshots), 0)                               # R7: a failed result carries no rows, even those read before the throw
  expect_equal(nrow(res$fetches), 1)                                 # the request that did complete stays in the lineage
  # a body that parses as JSON but breaks the parser is a thrown parse error too
  bad <- espn_provider(setNames(list(list(text = '{"items": 5}')), odds_url("401671617")))$provider$game_snapshots(GAME_2024)
  expect_equal(bad$source_status$status, "failed")
  expect_equal(nrow(bad$snapshots), 0)
  expect_false(is.na(bad$source_status$detail))
})

test_that("live prop lines are normalized as line-only snapshots with the fetch time", {
  page <- odds_fixture_json(file.path("..", "capture", "espn_propbets_page1.json"))
  at <- as.POSIXct("2026-09-28 20:53:02", tz = "UTC")
  s <- parse_espn_prop_bets(page, "2026_03_PHI_CHI", fetched_at = at, sha256 = "d")
  expect_equal(validate_odds_snapshots(s), character())
  expect_equal(nrow(s), 6)                                           # 3 rows x (current + open)
  expect_equal(unique(s$venue_id), "draftkings")
  expect_equal(unique(s$market_id), "passing_yards")
  expect_equal(unique(s$side), "line")
  expect_true(all(is.na(s$price_american)))                          # ESPN prop rows carry lines, not prices
  cur <- s[s$snapshot_kind == "observed", ]
  expect_equal(cur$captured_at, rep(at, 3))
  expect_true(172.5 %in% cur$line)
  expect_true(165.5 %in% s$line[s$snapshot_kind == "open"])
  expect_true(all(is.na(s$captured_at[s$snapshot_kind == "open"])))
  expect_true("espn:15168" %in% s$player_key)
  # an unknown prop type is counted, not mapped by guess
  page$items[[1]]$type$name <- "Longest Reception"
  s2 <- parse_espn_prop_bets(page, "g", fetched_at = at, sha256 = "d")
  expect_equal(nrow(s2), 4)
  expect_equal(attr(s2, "unmapped_types"), "Longest Reception")
})

prop_page1_text <- function() {
  paste(readLines(testthat::test_path("fixtures", "capture", "espn_propbets_page1.json"), warn = FALSE), collapse = "\n")
}

test_that("prop_snapshots reads every page and reports a post-game 404 as unavailable", {
  one_page <- sub('"pageCount": 2', '"pageCount": 1', prop_page1_text(), fixed = TRUE)
  url <- espn_prop_bets_url("401872656", 100, 1)
  e <- espn_provider(setNames(list(list(text = one_page)), url))
  res <- e$provider$prop_snapshots(GAME_2026)
  expect_equal(res$source_status$status, "ok")
  expect_equal(nrow(res$snapshots), 6)
  expect_equal(unique(res$snapshots$game_id), "2026_01_NE_SEA")
  expect_match(res$source_status$detail, "6 prop line row")          # R6: the rows are lines without prices, and the detail says so
  gone <- espn_provider(setNames(list(list(status = 404L)), url))$provider$prop_snapshots(GAME_2026)
  expect_equal(gone$source_status$status, "unavailable")
  expect_match(gone$source_status$detail, "live only")
})

test_that("a missing prop page or a game without an event id leaves the prop result stale; no rows is unavailable (R5)", {
  p1 <- list(text = prop_page1_text())                               # pageCount 2
  url1 <- espn_prop_bets_url("401872656", 100, 1)
  url2 <- espn_prop_bets_url("401872656", 100, 2)
  page2_gone <- espn_provider(setNames(list(p1, list(status = 404L)), c(url1, url2)))$provider$prop_snapshots(GAME_2026)
  expect_equal(page2_gone$source_status$status, "stale")
  expect_equal(nrow(page2_gone$snapshots), 6)                        # page 1 is kept
  expect_match(page2_gone$source_status$detail, "2026_01_NE_SEA page 2")
  no_id <- transform(GAME_2026, game_id = "2026_01_NOID", espn = NA_character_)
  one_page <- list(text = sub('"pageCount": 2', '"pageCount": 1', prop_page1_text(), fixed = TRUE))
  skipped <- espn_provider(setNames(list(one_page), url1))$provider$prop_snapshots(rbind(no_id, GAME_2026))
  expect_equal(skipped$source_status$status, "stale")
  expect_match(skipped$source_status$detail, "1 game without an ESPN event id")
  empty <- espn_provider(setNames(list(list(text = '{"pageCount": 1, "items": []}')), url1))$provider$prop_snapshots(GAME_2026)
  expect_equal(empty$source_status$status, "unavailable")
  expect_equal(nrow(empty$snapshots), 0)
})

test_that("a 200 prop response that is not JSON is a block, and only a 404 gets the post-game note (fix 2)", {
  url1 <- espn_prop_bets_url("401872656", 100, 1)
  html <- list(text = "<html><body>Access denied from your region</body></html>")
  e <- espn_provider(setNames(list(html), url1))
  res <- e$provider$prop_snapshots(rbind(GAME_2026, GAME_2024))
  expect_equal(length(e$fake$state$urls), 1)
  expect_equal(res$source_status$status, "unavailable")
  detail <- res$source_status$detail
  expect_match(detail, "blocked: HTTP 200 body is not JSON \\(a challenge or geo-fence page\\)")
  expect_false(grepl("(NA)", detail, fixed = TRUE))
  expect_false(grepl("live only", detail, fixed = TRUE))
  # a server error is reported with its own status and is not blamed on the post-game 404
  err <- espn_provider(setNames(list(list(status = 500L)), url1))$provider$prop_snapshots(GAME_2026)
  expect_equal(err$source_status$status, "unavailable")
  expect_match(err$source_status$detail, "2026_01_NE_SEA page 1 \\(HTTP 500\\)")
  expect_false(grepl("live only", err$source_status$detail, fixed = TRUE))
  # a 404 keeps the note
  expect_match(espn_provider(setNames(list(list(status = 404L)), url1))$provider$prop_snapshots(GAME_2026)$source_status$detail,
               "live only")
})

test_that("prop rows that cannot be stored are counted by class; an unreadable athlete or a row with no line is stale, another venue is not (fix 3)", {
  page <- odds_fixture_json(file.path("..", "capture", "espn_propbets_page1.json"))
  page$pageCount <- 1L
  at <- as.POSIXct("2026-09-28 20:53:02", tz = "UTC")
  # direct: all three classes at once
  bad <- page
  bad$items[[1]]$athlete$`$ref` <- "http://sports.core.api.espn.com/v2/sports/football/leagues/nfl/athletes/not-a-number"
  bad$items[[2]]$current <- NULL
  bad$items[[2]]$open <- NULL
  bad$items[[3]]$provider$`$ref` <- "http://sports.core.api.espn.com/v2/sports/football/leagues/nfl/casinos/999?lang=en"
  s <- parse_espn_prop_bets(bad, "g", fetched_at = at, sha256 = "d")
  expect_equal(nrow(s), 0)
  expect_equal(attr(s, "bad_athlete_refs"), 1L)
  expect_equal(attr(s, "no_target_rows"), 1L)
  expect_equal(attr(s, "unmapped_venues"), "999")
  # a row with only a current line is ordinary: no open line is not a skip
  cur_only <- page
  cur_only$items[[1]]$open <- NULL
  s2 <- parse_espn_prop_bets(cur_only, "g", fetched_at = at, sha256 = "d")
  expect_equal(nrow(s2), 5)
  expect_equal(attr(s2, "no_target_rows"), 0L)
  # through the provider: one bad $ref and one targetless row, one good row left -> stale, both counts named
  drift <- page
  drift$items[[1]]$athlete$`$ref` <- "http://sports.core.api.espn.com/v2/sports/football/leagues/nfl/athletes/not-a-number"
  drift$items[[2]]$current <- NULL
  drift$items[[2]]$open <- NULL
  url1 <- espn_prop_bets_url("401872656", 100, 1)
  res <- espn_provider(setNames(list(json_route(drift)), url1))$provider$prop_snapshots(GAME_2026)
  expect_equal(nrow(res$snapshots), 2)
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "1 prop row\\(s\\) with an unreadable athlete reference")
  expect_match(res$source_status$detail, "1 prop row\\(s\\) with neither a current nor an open line")
  # another venue's rows are expected noise: counted in the detail, the result stays ok
  other <- page
  other$items[[4]] <- other$items[[3]]
  other$items[[4]]$provider$`$ref` <- "http://sports.core.api.espn.com/v2/sports/football/leagues/nfl/casinos/999?lang=en"
  noisy <- espn_provider(setNames(list(json_route(other)), url1))$provider$prop_snapshots(GAME_2026)
  expect_equal(nrow(noisy$snapshots), 6)
  expect_equal(noisy$source_status$status, "ok")
  expect_match(noisy$source_status$detail, "1 prop row\\(s\\) from other venues skipped \\(casino 999\\)")
})

test_that("a prop pageCount beyond the 20-page cap is read to the cap, reported, and stale (M5)", {
  game <- "401872656"
  page1 <- sub('"pageCount": 2', '"pageCount": 25', prop_page1_text(), fixed = TRUE)
  later <- vapply(2:20, function(p) espn_prop_bets_url(game, 100, p), "")
  routes <- c(list(list(text = page1)), rep(list(list(text = '{"pageCount": 25, "items": []}')), 19))
  e <- espn_provider(setNames(routes, c(espn_prop_bets_url(game, 100, 1), later)))
  res <- e$provider$prop_snapshots(GAME_2026)
  expect_equal(length(e$fake$state$urls), 20)                        # page 21 is never asked for (it has no route: asking would throw)
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "2026_01_NE_SEA has 25 pages, read the first 20")
  expect_equal(nrow(res$snapshots), 6)
})

test_that("a capped prop game that also loses a page reports both gaps (M5)", {
  game <- "401872656"
  page1 <- sub('"pageCount": 2', '"pageCount": 30', prop_page1_text(), fixed = TRUE)
  e <- espn_provider(setNames(list(list(text = page1), list(status = 404L)),
                              c(espn_prop_bets_url(game, 100, 1), espn_prop_bets_url(game, 100, 2))))
  res <- e$provider$prop_snapshots(GAME_2026)
  expect_equal(res$source_status$status, "stale")
  expect_match(res$source_status$detail, "2026_01_NE_SEA page 2")
  expect_match(res$source_status$detail, "read the first 20")
})

test_that("a refused prop request stops the run and is named as a block, not as a post-game 404; unmapped types are named", {
  url1 <- espn_prop_bets_url("401872656", 100, 1)
  e <- espn_provider(setNames(list(list(status = 403L)), url1))
  res <- e$provider$prop_snapshots(rbind(GAME_2026, GAME_2024))
  expect_equal(res$source_status$status, "unavailable")
  expect_match(res$source_status$detail, "blocked by the server")
  expect_false(grepl("live only", res$source_status$detail))
  expect_equal(length(e$fake$state$urls), 1)                         # nothing after the refusal, nothing for the second game
  odd_type <- gsub("Total Passing Yards (incl. overtime)", "Longest Reception", fixed = TRUE,
                   x = sub('"pageCount": 2', '"pageCount": 1', prop_page1_text(), fixed = TRUE))
  named <- espn_provider(setNames(list(list(text = odd_type)), url1))$provider$prop_snapshots(GAME_2026)
  expect_equal(named$source_status$status, "unavailable")            # every row was an unmapped type
  expect_match(named$source_status$detail, "1 prop type\\(s\\) not mapped, skipped: Longest Reception")
})

test_that("an error thrown while reading props is 'failed' with its message and carries no snapshots (R5, R7)", {
  clock <- odds_fake_clock()
  odds_http_reset()
  p <- provider_espn_core(cfg = odds_http_config(), fetch_fn = function(url, cfg) stop("pipe broke"),
                          now_fn = clock$now, sleep_fn = clock$sleep)
  res <- p$prop_snapshots(GAME_2026)
  expect_equal(res$source_status$status, "failed")
  expect_match(res$source_status$detail, "pipe broke")
  expect_equal(nrow(res$snapshots), 0)
  # a game read before the throw does not survive it: the first game parses, the second throws
  one_page <- sub('"pageCount": 2', '"pageCount": 1', prop_page1_text(), fixed = TRUE)
  odds_http_reset()
  good <- odds_fake_fetch(setNames(list(list(text = one_page)), espn_prop_bets_url("401872656", 100, 1)))
  mixed <- provider_espn_core(cfg = odds_http_config(), now_fn = clock$now, sleep_fn = clock$sleep,
                              fetch_fn = function(url, cfg) if (grepl("401671617", url, fixed = TRUE)) stop("pipe broke") else good$fn(url, cfg))
  after <- mixed$prop_snapshots(rbind(GAME_2026, GAME_2024))
  expect_equal(after$source_status$status, "failed")
  expect_equal(nrow(after$snapshots), 0)
  expect_equal(nrow(after$fetches), 1)                               # the completed request stays in the lineage
})

# --- capture(): the forward-capture pass ---------------------------------------
# A fetch stub that logs (source, key, url) and serves scoreboard bodies by URL. Any other source
# gets an empty page, so the pass can run to the end without a network.

espn_sb_json <- function(year, type, week, events) {
  as.character(jsonlite::toJSON(list(
    season = list(year = year, type = type), week = list(number = week),
    events = lapply(events, function(e) {
      list(id = e[["id"]], name = e[["name"]], date = e[["date"]], status = list(type = list(name = e[["status"]])))
    })
  ), auto_unbox = TRUE))
}

capture_stub <- function(bodies) {
  state <- new.env()
  state$calls <- list()
  fn <- function(source, key, url) {
    state$calls[[length(state$calls) + 1]] <- c(source = source, key = key, url = url)
    body <- bodies[[url]]
    if (!is.null(body)) return(body)
    if (source == "espn_propbets") return('{"pageCount": 1, "items": []}')
    "{}"
  }
  list(fn = fn, state = state,
       labels = function() vapply(state$calls, function(x) paste(x[["source"]], x[["key"]], sep = ":"), ""),
       urls = function() vapply(state$calls, function(x) x[["url"]], ""))
}

capture_cfg <- list(game_horizon_hours = 216, horizon_hours = 72, espn_prop_providers = 100L)

test_that("the forward-capture pass fetches odds and props for games inside the horizon only", {
  sb <- paste(readLines(testthat::test_path("fixtures", "capture", "espn_scoreboard.json"), warn = FALSE), collapse = "\n")
  week4 <- list(year = 2026L, type = 2L, week = 4L)                  # the fixture lists week 3, so the pass also asks for week 4
  stub <- capture_stub(setNames(list(sb, sb), c(espn_scoreboard_url(), espn_scoreboard_url(week4))))
  odds_http_reset()
  provider_espn_core()$capture(stub$fn, now = as.POSIXct("2026-09-28 20:53:00", tz = "UTC"),
                               cfg = list(game_horizon_hours = 36, horizon_hours = 36, espn_prop_providers = 100L))
  expect_equal(stub$labels(), c("espn_scoreboard:scoreboard", "espn_scoreboard:scoreboard_2026_t2_w04",
                                "espn_game_odds:401872963", "espn_propbets:401872963_100_p1"))
})

test_that("a Tuesday capture reads the coming week, sends game odds to every game target and props only to prop targets (R4, A0)", {
  now <- as.POSIXct("2026-10-20 21:23:20", tz = "UTC")
  week7 <- list(year = 2026L, type = 2L, week = 7L)
  bodies <- list()
  bodies[[espn_scoreboard_url()]] <- espn_sb_json(2026L, 2L, 6L, list(
    list(id = "601", name = "WSH at SF", date = "2026-10-20T00:15Z", status = "STATUS_FINAL")))
  bodies[[espn_scoreboard_url(week7)]] <- espn_sb_json(2026L, 2L, 7L, list(
    list(id = "701", name = "NE at CHI", date = "2026-10-23T00:15Z", status = "STATUS_SCHEDULED"),
    list(id = "714", name = "DAL at PHI", date = "2026-10-27T00:15Z", status = "STATUS_SCHEDULED")))
  stub <- capture_stub(bodies)
  expect_true(provider_espn_core()$capture(stub$fn, now = now, cfg = capture_cfg))

  expect_equal(stub$labels()[1:2], c("espn_scoreboard:scoreboard", "espn_scoreboard:scoreboard_2026_t2_w07"))
  urls <- stub$urls()
  # 701 kicks off in 51 h, 714 in 147 h, 601 is final: both coming games get their line, only 701 gets props
  expect_equal(urls[grepl("/odds$", urls)], c(espn_game_odds_url("701"), espn_game_odds_url("714")))
  expect_equal(urls[grepl("propBets", urls)], espn_prop_bets_url("701", 100, 1))
  expect_false(any(grepl("events/601/", urls, fixed = TRUE)))         # a final game is never fetched
})

test_that("an event listed on both scoreboards is fetched once", {
  now <- as.POSIXct("2026-10-20 21:23:20", tz = "UTC")
  week8 <- list(year = 2026L, type = 2L, week = 8L)
  bodies <- list()
  bodies[[espn_scoreboard_url()]] <- espn_sb_json(2026L, 2L, 7L, list(
    list(id = "701", name = "NE at CHI", date = "2026-10-23T00:15Z", status = "STATUS_SCHEDULED")))
  bodies[[espn_scoreboard_url(week8)]] <- espn_sb_json(2026L, 2L, 8L, list(
    list(id = "701", name = "NE at CHI", date = "2026-10-23T00:15Z", status = "STATUS_SCHEDULED"),
    list(id = "801", name = "GB at MIN", date = "2026-10-29T00:15Z", status = "STATUS_SCHEDULED")))
  stub <- capture_stub(bodies)
  provider_espn_core()$capture(stub$fn, now = now, cfg = capture_cfg)
  urls <- stub$urls()
  expect_equal(urls[grepl("/odds$", urls)], c(espn_game_odds_url("701"), espn_game_odds_url("801")))
})

test_that("no coming week to ask for means one scoreboard request (after the Super Bowl, or a response with no week)", {
  now <- as.POSIXct("2027-02-01 12:00:00", tz = "UTC")
  superbowl <- espn_sb_json(2026L, 3L, 5L, list(
    list(id = "901", name = "Super Bowl", date = "2027-02-08T23:30Z", status = "STATUS_SCHEDULED")))
  stub <- capture_stub(setNames(list(superbowl), espn_scoreboard_url()))
  provider_espn_core()$capture(stub$fn, now = now, cfg = capture_cfg)
  expect_equal(stub$labels()[1], "espn_scoreboard:scoreboard")
  expect_equal(sum(grepl("scoreboard", stub$urls(), fixed = TRUE)), 1)
  expect_true(espn_game_odds_url("901") %in% stub$urls())
  no_week <- capture_stub(setNames(list("{}"), espn_scoreboard_url()))
  provider_espn_core()$capture(no_week$fn, now = now, cfg = capture_cfg)
  expect_equal(no_week$labels(), "espn_scoreboard:scoreboard")
})

test_that("a scoreboard that cannot be fetched stops the pass without a game request", {
  calls <- 0L
  none <- function(source, key, url) {
    calls <<- calls + 1L
    NULL
  }
  expect_false(provider_espn_core()$capture(none, now = Sys.time(), cfg = capture_cfg))
  expect_equal(calls, 1L)
})

test_that("capture stops with a clear error when the game horizon is missing, before any request", {
  stub <- capture_stub(list())
  expect_error(provider_espn_core()$capture(stub$fn, now = Sys.time(),
                                            cfg = list(horizon_hours = 36, espn_prop_providers = 100L)),
               "game_horizon_hours")
  expect_length(stub$state$calls, 0)
})

test_that("the capture pass reads at most 20 prop pages of a game (M5)", {
  now <- as.POSIXct("2026-10-20 21:23:20", tz = "UTC")
  week7 <- list(year = 2026L, type = 2L, week = 7L)
  bodies <- list()
  bodies[[espn_scoreboard_url()]] <- espn_sb_json(2026L, 2L, 6L, list())
  bodies[[espn_scoreboard_url(week7)]] <- espn_sb_json(2026L, 2L, 7L, list(
    list(id = "701", name = "NE at CHI", date = "2026-10-23T00:15Z", status = "STATUS_SCHEDULED")))
  bodies[[espn_prop_bets_url("701", 100, 1)]] <- '{"pageCount": 25, "items": []}'
  stub <- capture_stub(bodies)
  provider_espn_core()$capture(stub$fn, now = now, cfg = capture_cfg)
  urls <- stub$urls()
  expect_equal(sum(grepl("propBets", urls)), 20)
  expect_false(espn_prop_bets_url("701", 100, 21) %in% urls)
})

test_that("capture stops with a clear error when the prop horizon or the prop providers are missing, before any request (M4)", {
  stub <- capture_stub(list())
  expect_error(provider_espn_core()$capture(stub$fn, now = Sys.time(),
                                            cfg = list(game_horizon_hours = 216, espn_prop_providers = 100L)),
               "cfg\\$horizon_hours is missing")
  expect_error(provider_espn_core()$capture(stub$fn, now = Sys.time(),
                                            cfg = list(game_horizon_hours = 216, horizon_hours = 36)),
               "cfg\\$espn_prop_providers is missing")
  expect_length(stub$state$calls, 0)
})

test_that("the ESPN provider satisfies the provider interface", {
  p <- provider_espn_core()
  expect_equal(validate_odds_provider(p), character())
  expect_setequal(p$venue_ids, c("espn_bet", "draftkings"))
  expect_true(is.function(p$game_snapshots) && is.function(p$prop_snapshots) && is.function(p$capture))
})

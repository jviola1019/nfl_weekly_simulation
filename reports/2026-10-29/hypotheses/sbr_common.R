# Shared by opener_spread_clv.R (T2) and opener_timing_elo.R: SBR's archived NFL season pages (opening and closing point
# spreads, closing moneylines), matched to nflverse's games, and the market's own exchange rate from a home spread to a
# home win probability. The pages are read from a private folder and never committed.
# Needs data.table and nflreadr.

SBR_TEAM <- c(Arizona = "ARI", Atlanta = "ATL", Baltimore = "BAL", Buffalo = "BUF", Carolina = "CAR", Chicago = "CHI", Cincinnati = "CIN",
              Cleveland = "CLE", Dallas = "DAL", Denver = "DEN", Detroit = "DET", GreenBay = "GB", Houston = "HOU", Indianapolis = "IND",
              Jacksonville = "JAX", KCChiefs = "KC", Kansas = "KC", KansasCity = "KC", LAChargers = "LAC", LARams = "LA", LVRaiders = "LV",
              LasVegas = "LV", Miami = "MIA", Minnesota = "MIN", NYGiants = "NYG", NYJets = "NYJ", NewEngland = "NE", NewOrleans = "NO",
              Oakland = "OAK", Philadelphia = "PHI", Pittsburgh = "PIT", SanFrancisco = "SF", Seattle = "SEA", Tampa = "TB", TampaBay = "TB",
              Tennessee = "TEN", Washingtom = "WAS", Washington = "WAS")
sbr_dec <- function(o) ifelse(o < 0, 1 + 100 / -o, 1 + o / 100)

# one row per team: date (MMDD), V/H/N, team, final, the Open and Close columns (a spread on the favourite's row, the total
# on the other) and the closing moneyline
sbr_read_season <- function(dir, season) {
  cell_text <- function(x) trimws(gsub("&nbsp;", " ", gsub("<[^>]+>", "", x), fixed = TRUE))
  f <- file.path(dir, sprintf("nfl-odds-%d-%02d.html", season, (season + 1) %% 100))
  t <- paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  rows <- regmatches(t, gregexpr("(?s)<tr.*?</tr>", t, perl = TRUE))[[1]]
  cells <- lapply(rows, function(r) cell_text(regmatches(r, gregexpr("(?s)<t[dh][^>]*>.*?</t[dh]>", r, perl = TRUE))[[1]]))
  cells <- Filter(function(z) length(z) >= 13 && z[1] != "Date", cells)
  x <- rbindlist(lapply(cells, function(z) as.list(z[c(1, 3, 4, 9, 10, 11, 12)])))
  setnames(x, c("date", "vh", "team", "final", "open", "close", "ml"))
  x[, `:=`(season = season, row = .I)]
}

# two rows per game (visitor, then home; N twice at a neutral site): t2's line is the points by which t2 is favoured
sbr_games <- function(x) {
  num <- function(v) { v <- tolower(trimws(v)); suppressWarnings(fifelse(v %in% c("pk", "p"), 0, as.numeric(v))) }
  stopifnot(nrow(x) %% 2 == 0, all(x$team %in% names(SBR_TEAM)))
  x[, `:=`(code = unname(SBR_TEAM[team]), game = (row + 1L) %/% 2L, o = num(open), c = num(close), m = num(ml))]
  a <- x[row %% 2L == 1L]; b <- x[row %% 2L == 0L]
  stopifnot(identical(a$game, b$game))
  mmdd <- sprintf("%04d", as.integer(a$date))
  month <- as.integer(substr(mmdd, 1, 2))
  g <- data.table(season = a$season, gameday = sprintf("%d-%s-%s", a$season + (month < 8), substr(mmdd, 1, 2), substr(mmdd, 3, 4)),
                  t1 = a$code, t2 = b$code, neutral = a$vh == "N", o1 = a$o, o2 = b$o, c1 = a$c, c2 = b$c, m1 = a$m, m2 = b$m)
  # in each column one value is the spread (under 30, given on the favourite's row) and the other the total
  sp <- function(v1, v2) fcase(is.finite(v1) & is.finite(v2) & v1 < 30 & v2 >= 30, -v1,
                               is.finite(v1) & is.finite(v2) & v2 < 30 & v1 >= 30, v2, default = NA_real_)
  g[, `:=`(t2_open = sp(o1, o2), t2_close = sp(c1, c2))]
  g[]
}

# SBR's games matched to nflverse's (season, date and the team pair in either order), with home lines (positive = the home
# team favoured, as nflverse's spread_line) and SBR's closing moneylines from the home side
sbr_matched <- function(dir, seasons, sched) {
  sbr <- rbindlist(lapply(seasons, function(s) sbr_games(sbr_read_season(dir, s))))
  g <- sched[season %in% seasons, .(game_id, season, week, gameday, home_team, away_team, spread_line, p_novig)]
  m1 <- merge(sbr, g, by.x = c("season", "gameday", "t1", "t2"), by.y = c("season", "gameday", "away_team", "home_team"))[, flip := FALSE]
  m2 <- merge(sbr, g, by.x = c("season", "gameday", "t1", "t2"), by.y = c("season", "gameday", "home_team", "away_team"))[, flip := TRUE]
  mm <- rbind(m1, m2, fill = TRUE)
  stopifnot(!anyDuplicated(mm$game_id))
  mm[, `:=`(home_open = fifelse(flip, -t2_open, t2_open), home_close = fifelse(flip, -t2_close, t2_close),
            sbr_ml_home = fifelse(flip, m1, m2), sbr_ml_away = fifelse(flip, m2, m1))]
  mm[, sbr_p_close_ml := (1 / sbr_dec(sbr_ml_home)) / (1 / sbr_dec(sbr_ml_home) + 1 / sbr_dec(sbr_ml_away))]
  list(parsed = nrow(sbr), games = mm[])
}

# nflverse 2006-2024 schedules with the proportional no-vig home probability of the closing moneylines (no 2025)
sbr_schedules <- function() {
  sched <- as.data.table(nflreadr::load_schedules(2006:2024))
  stopifnot(!any(sched$season == 2025))
  sched[, p_novig := (1 / sbr_dec(home_moneyline)) / (1 / sbr_dec(home_moneyline) + 1 / sbr_dec(away_moneyline))]
  sched[]
}

# the market's exchange rate: an isotonic fit of the no-vig closing probability on the closing home spread, every game with
# both (prices only, no outcomes); returns the function and the fitted rate by spread
spread_exchange_rate <- function(sched) {
  ex <- sched[is.finite(spread_line) & is.finite(p_novig)][order(spread_line)]
  iso <- stats::isoreg(ex$spread_line, ex$p_novig)
  exr <- data.table(spread = ex$spread_line, fit = iso$yf)[, .(p = mean(fit), games = .N), by = spread]
  list(f = stats::approxfun(exr$spread, exr$p, rule = 2), rate = exr, lines = nrow(ex))
}

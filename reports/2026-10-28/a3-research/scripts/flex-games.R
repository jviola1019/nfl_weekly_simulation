# Late schedule changes, 2018-2024: Wikipedia "Scheduling changes" bullets -> one row per changed game.
#   Rscript flex-games.R <bullets.json> <games.csv> <out.csv>      (run from the repository root)
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
b <- jsonlite::fromJSON(args[1], simplifyVector = FALSE)    # a local file the session wrote
games <- fread(args[2])
FR <- c(OAK = "LV", SD = "LAC", STL = "LA")
fr <- function(x) ifelse(x %in% names(FR), FR[x], x)
NAME <- c("Arizona Cardinals" = "ARI", "Atlanta Falcons" = "ATL", "Baltimore Ravens" = "BAL", "Buffalo Bills" = "BUF",
          "Carolina Panthers" = "CAR", "Chicago Bears" = "CHI", "Cincinnati Bengals" = "CIN", "Cleveland Browns" = "CLE",
          "Dallas Cowboys" = "DAL", "Denver Broncos" = "DEN", "Detroit Lions" = "DET", "Green Bay Packers" = "GB",
          "Houston Texans" = "HOU", "Indianapolis Colts" = "IND", "Jacksonville Jaguars" = "JAX", "Kansas City Chiefs" = "KC",
          "Las Vegas Raiders" = "LV", "Oakland Raiders" = "LV", "Los Angeles Chargers" = "LAC", "Los Angeles Rams" = "LA",
          "Miami Dolphins" = "MIA", "Minnesota Vikings" = "MIN", "New England Patriots" = "NE", "New Orleans Saints" = "NO",
          "New York Giants" = "NYG", "New York Jets" = "NYJ", "Philadelphia Eagles" = "PHI", "Pittsburgh Steelers" = "PIT",
          "San Francisco 49ers" = "SF", "Seattle Seahawks" = "SEA", "Tampa Bay Buccaneers" = "TB", "Tennessee Titans" = "TEN",
          "Washington Redskins" = "WAS", "Washington Football Team" = "WAS", "Washington Commanders" = "WAS")
g <- games[season >= 2018 & season <= 2024]
g[, `:=`(h = fr(home_team), a = fr(away_team))]
kick_col <- intersect(c("kickoff", "kickoff_utc", "gameday"), names(g))[1]
g[, kick := as.POSIXct(get(kick_col), tz = "UTC")]

kind_of <- function(t) {
  t <- tolower(t)
  if (grepl("cancel|no contest|declared a no", t)) return("canceled")
  if (grepl("relocat|moved to [a-z' .]*(stadium|field|park|dome|arena)|played at |neutral site", t)) return("venue")
  if (grepl("postpone|reschedul|delayed to", t)) return("date")
  if (grepl("8:1[05] ?p|8:20 ?p|7:15 ?p|night|primetime|prime time", t)) return("primetime")
  if (grepl("saturday|monday|tuesday|wednesday|thursday|friday", t)) return("day")
  if (grepl("cross-flex", t) && !grepl("from [0-9]{1,2}:[0-9]{2}[^.]*to [0-9]{1,2}:[0-9]{2}", t)) return("network only")
  if (grepl("from [0-9]{1,2}:[0-9]{2}[^.]*to (the )?[0-9]{1,2}:[0-9]{2}", t)) return("time")
  "other"
}
date_of <- function(x, season) {
  if (is.null(x) || !length(x)) return(as.Date(NA))
  d <- suppressWarnings(as.Date(x, tryFormats = c("%B %d, %Y", "%Y-%m-%d", "%d %B %Y", "%B %d")))
  if (!is.na(d) && !grepl("[0-9]{4}", x)) d <- as.Date(sprintf("%s-%s", season, format(d, "%m-%d")))
  d
}
rows <- list()
for (x in b) {
  codes <- unname(NAME[unlist(x$teams)])
  if (anyNA(codes)) stop("unmapped team name in: ", paste(unlist(x$teams), collapse = ", "))
  if (length(codes) < 2) next
  explicit <- date_of(x$explicit_date, x$season)
  cites <- suppressWarnings(vapply(unlist(x$cite_dates), function(d) as.numeric(date_of(d, x$season)), numeric(1)))
  announced <- if (!is.na(explicit)) explicit else if (length(cites) && any(is.finite(cites))) as.Date(min(cites[is.finite(cites)])) else as.Date(NA)
  src <- if (!is.na(explicit)) "text" else if (!is.na(announced)) "citation access-date" else "none"
  for (i in seq(1, length(codes) - 1, by = 2)) {
    pair <- codes[i:(i + 1)]
    cand <- g[(h == pair[1] & a == pair[2]) | (h == pair[2] & a == pair[1])][season == x$season]
    if (!nrow(cand)) next
    cand <- cand[which.min(abs(week - x$week))]     # division rivals meet twice: the nearer week
    rows[[length(rows) + 1L]] <- data.table(season = x$season, wiki_week = x$week, game_id = cand$game_id, week = cand$week,
                                            kind = kind_of(x$text), announced = announced, announced_source = src,
                                            kickoff = cand$kick, revid = x$revid, text = substr(x$text, 1, 300))
  }
}
res <- rbindlist(rows)
res[, days_before_kickoff := as.numeric(difftime(kickoff, as.POSIXct(announced, tz = "UTC"), units = "days"))]
res <- unique(res, by = c("game_id", "kind", "announced"))
fwrite(res, args[3])
cat(sprintf("%d changed-game rows, %d distinct games\n", nrow(res), uniqueN(res$game_id)))
print(res[, .N, by = .(season, kind)][order(season, kind)])
print(res[, .(game_id, kind, announced, src = substr(announced_source, 1, 4), days = round(days_before_kickoff, 1))][order(game_id)])

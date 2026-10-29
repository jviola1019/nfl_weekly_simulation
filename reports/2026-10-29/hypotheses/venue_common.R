# The preamble of venue_snapshot.R and props_snapshot.R (track K1): arguments, the snapshot's clock, the games still to
# kick off in the coming week, team codes, the capture GET with a saved copy of every response, and the venues' fees.
# Arguments: <out_dir> <raw_dir> [--offline [--stamp=<YYYYmmddTHHMMSSZ>]] [--no-kalshi]. --offline re-reads a snapshot
# saved in <raw_dir> (the newest, or the one --stamp names) instead of fetching.
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
offline <- "--offline" %in% args; no_kalshi <- "--no-kalshi" %in% args
want <- sub("^--stamp=", "", grep("^--stamp=", args, value = TRUE))
args <- grep("^--", args, value = TRUE, invert = TRUE)
out <- args[1]; raw <- args[2]
dir.create(out, recursive = TRUE, showWarnings = FALSE); dir.create(raw, recursive = TRUE, showWarnings = FALSE)
cfg <- new.env(); sys.source("config.R", envir = cfg); source("R/capture_raw.R")
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
`%||%` <- function(a, b) if (is.null(a)) b else a
num <- function(v) suppressWarnings(as.numeric(v %||% NA))
PM_TAKER_FEE <- 0.05
pm_fee <- function(p) PM_TAKER_FEE * p * (1 - p)
SM_COMMISSION <- 0.02
sm_cost <- function(p) p / (1 - SM_COMMISSION * (1 - p))   # a winning $1 contract bought at p nets 1 - 2% of the profit
dec <- function(o) ifelse(o < 0, 1 + 100 / -o, 1 + o / 100)
inv <- function(o) 1 / dec(num(o))
ok <- function(...) all(vapply(list(...), function(x) length(x) == 1L && is.finite(num(x)), TRUE))

now <- Sys.time(); stamp <- format(now, "%Y%m%dT%H%M%SZ", tz = "UTC")
if (offline) {
  saved <- sort(unique(sub("^.*__([0-9]{8}T[0-9]{6}Z)\\.json\\.gz$", "\\1", list.files(raw, pattern = "__[0-9]{8}T[0-9]{6}Z\\.json\\.gz$"))))
  stopifnot(length(saved) > 0, length(want) == 0 || want %in% saved)
  stamp <- if (length(want)) want else utils::tail(saved, 1); now <- as.POSIXct(stamp, format = "%Y%m%dT%H%M%SZ", tz = "UTC")
}

# the games still to kick off in the coming week
sched <- props_schedule()
wk <- sched[kick > now, min(week)]
games <- sched[week == wk & kick > now, .(game_id, home_team, away_team, kick)]
stopifnot(nrow(games) > 0, !any(format(games$kick, "%Y", tz = "UTC") == "2025"))
teams <- as.data.table(nflreadr::load_teams(current = TRUE))[, .(team_abbr, team_name, team_nick)]
ALIAS <- c(JAC = "JAX", WSH = "WAS", LAR = "LA", LVR = "LV")
code_of <- function(x) vapply(as.character(x), function(s) {
  s <- trimws(s); if (is.na(s) || !nzchar(s)) return(NA_character_)
  u <- toupper(s); if (u %in% teams$team_abbr) return(u); if (u %in% names(ALIAS)) return(unname(ALIAS[u]))
  i <- match(tolower(s), tolower(c(teams$team_name, teams$team_nick)))
  if (is.na(i)) NA_character_ else rep(teams$team_abbr, 2)[i]
}, "", USE.NAMES = FALSE)
# the schedule's game for a venue's two teams in either order; flip is TRUE when the venue's home is the schedule's away
match_game <- function(h, a) {
  if (length(h) != 1L || length(a) != 1L || is.na(h) || is.na(a)) return(NULL)
  i <- which((games$home_team == h & games$away_team == a) | (games$home_team == a & games$away_team == h))
  if (length(i) != 1L) NULL else list(gid = games$game_id[i], flip = games$home_team[i] != h)
}
# a player's name as a join key across venues (props_probe.R's rule)
norm_name <- function(x) { x <- tolower(iconv(x, to = "ASCII//TRANSLIT")); x <- gsub("[.'`-]", "", x)
  x <- gsub("\\b(jr|sr|ii|iii|iv|v)\\b", "", x); gsub("\\s+", " ", trimws(x)) }

# one response per endpoint: fetched and saved under <raw_dir>, or re-read from there offline
log_rows <- list()
note <- function(endpoint, status, bytes, error) log_rows[[length(log_rows) + 1L]] <<- data.table(endpoint = endpoint, status = status, bytes = bytes, error = error)
fetch <- function(name, url) {
  f <- file.path(raw, sprintf("%s__%s.json.gz", name, stamp))
  if (offline) {
    if (!file.exists(f)) return(NULL)
    con <- gzfile(f, "r"); on.exit(close(con)); return(paste(readLines(con, warn = FALSE, encoding = "UTF-8"), collapse = "\n"))
  }
  r <- capture_http_get(url, cfg$CAPTURE_USER_AGENT, cfg$CAPTURE_TIMEOUT_SEC, cfg$CAPTURE_MAX_TRIES, cfg$CAPTURE_MIN_INTERVAL_SEC)
  note(name, r$status, length(r$body), r$error %||% NA_character_)
  if (is.null(r$body)) return(NULL)
  con <- gzfile(f, "wb"); writeBin(r$body, con); close(con)
  txt <- rawToChar(r$body); Encoding(txt) <- "UTF-8"; txt
}
js <- function(txt) if (is.null(txt)) NULL else jsonlite::parse_json(txt)
# each venue's parser runs on its own, so one venue's schema drift is logged without losing the others (rows: the caller's)
parse_venue <- function(name, f) {
  n0 <- length(rows)
  res <- tryCatch({ f(); NA_character_ }, error = function(e) conditionMessage(e))
  note(paste0("parse_", name), NA_integer_, length(rows) - n0, res)
}

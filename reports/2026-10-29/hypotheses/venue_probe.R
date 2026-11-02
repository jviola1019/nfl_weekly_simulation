# Track K1's survey probe (VENUE_SURVEY.md): one keyless GET per venue endpoint, through the capture layer's GET
# (truthful user agent, 20 s timeout, one request a second, no retry), recording only the status and size. No keys,
# logins or cookies. A venue whose earlier probe was refused (any 4xx, a captcha or a geo-fence) is not asked again:
# pass that probe's table as --previous and its row is carried over. Bodies go to <raw_dir> (private: sportsbook payloads).
#   Rscript reports/2026-10-29/hypotheses/venue_probe.R <out.csv> <raw_dir> [--previous=<probe_status.csv>]
# BetOnline's offering API is a POST (the read its own page makes) and is listed separately.
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
prev_f <- sub("^--previous=", "", grep("^--previous=", args, value = TRUE)); args <- grep("^--", args, value = TRUE, invert = TRUE)
out <- args[1]; raw <- args[2]; dir.create(raw, recursive = TRUE, showWarnings = FALSE)
cfg <- new.env(); sys.source("config.R", envir = cfg); source("R/capture_raw.R")
`%||%` <- function(a, b) if (is.null(a)) b else a
ENDPOINTS <- c(
  action_network      = "https://api.actionnetwork.com/web/v1/scoreboard/nfl?period=game&bookIds=15,30,68,69,71,75,79,123&date=20261101",
  action_books        = "https://api.actionnetwork.com/web/v1/books",
  draftkings          = "https://sportsbook-nash.draftkings.com/api/sportscontent/dkusnj/v1/leagues/88808",
  kambi_betrivers     = "https://eu-offering-api.kambicdn.com/offering/v2018/rsiusnj/listView/american_football/nfl/all/all/matches.json?lang=en_US&market=US",
  caesars             = "https://api.americanwagering.com/regions/us/locations/nj/brands/czr/sb/v3/sports/americanfootball/events/schedule",
  bovada              = "https://www.bovada.lv/services/sports/event/coupon/events/A/description/football/nfl?marketFilterId=def&preMatchOnly=true&lang=en",
  polymarket_sports   = "https://gamma-api.polymarket.com/sports",
  polymarket_nfl      = "https://gamma-api.polymarket.com/events?series_id=12185&closed=false&limit=50",
  fanduel             = "https://sbapi.nj.sportsbook.fanduel.com/api/content-managed-page?page=CUSTOM&customPageId=nfl&timezone=America%2FNew_York",
  betmgm              = "https://sports.nj.betmgm.com/cds-api/bettingoffer/fixtures?lang=en-us&country=US&sportIds=11",
  pinnacle_matchups   = "https://guest.api.arcadia.pinnacle.com/0.1/leagues/889/matchups",
  pinnacle_markets    = "https://guest.api.arcadia.pinnacle.com/0.1/leagues/889/markets/straight",
  betonline_page      = "https://www.betonline.ag/sportsbook/football/nfl",
  fanatics            = "https://sportsbook.fanatics.com/",
  underdog            = "https://api.underdogfantasy.com/beta/v5/over_under_lines",
  prizepicks          = "https://api.prizepicks.com/projections?league_id=9&per_page=50",
  espn_odds           = "https://sports.core.api.espn.com/v2/sports/football/leagues/nfl/events/401873023/competitions/401873023/odds",
  kalshi_nfl_game     = "https://api.elections.kalshi.com/trade-api/v2/markets?series_ticker=KXNFLGAME&status=open&limit=1000",
  kalshi_incentives   = "https://api.elections.kalshi.com/trade-api/v2/incentive_programs?status=active&type=liquidity&limit=1000",
  sxbet_sports        = "https://api.sx.bet/sports",
  sxbet_markets       = "https://api.sx.bet/markets/active?sportIds=8&pageSize=50",
  smarkets_events     = "https://api.smarkets.com/v3/events/?type=american_football_match&state=upcoming&limit=50")
prev <- if (length(prev_f)) fread(prev_f) else data.table(endpoint = character(0), status = integer(0))
refused <- prev[!is.na(status) & status >= 400, endpoint]
rows <- lapply(names(ENDPOINTS), function(n) {
  if (n %in% refused) return(prev[endpoint == n][, carried_over := TRUE])
  r <- capture_http_get(ENDPOINTS[[n]], cfg$CAPTURE_USER_AGENT, cfg$CAPTURE_TIMEOUT_SEC, 1, cfg$CAPTURE_MIN_INTERVAL_SEC)
  if (!is.null(r$body)) { con <- gzfile(file.path(raw, paste0(n, ".body.gz")), "wb"); writeBin(r$body, con); close(con) }
  data.table(endpoint = n, host = sub("^https?://([^/]+).*$", "\\1", ENDPOINTS[[n]]), status = r$status, bytes = length(r$body),
             error = r$error %||% NA_character_, probed_utc = format(Sys.time(), "%Y-%m-%dT%H:%MZ", tz = "UTC"), carried_over = FALSE)
})
tab <- rbindlist(c(rows, list(prev[!endpoint %in% names(ENDPOINTS)][, carried_over := TRUE])), fill = TRUE)   # e.g. BetOnline's POST
fwrite(tab, out); print(tab)

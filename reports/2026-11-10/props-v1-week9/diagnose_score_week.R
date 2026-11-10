# Read-only diagnosis of score_week.R's props step for one week: the same inputs weekly_prospective.sh passes, and
# module_props()'s stages one by one with their row counts. Writes nothing. Run from the repository root:
#   Rscript reports/2026-11-10/props-v1-week9/diagnose_score_week.R <store week dir> <week>
suppressPackageStartupMessages(library(data.table))
a <- commandArgs(TRUE); store <- a[1]; WEEK <- as.integer(a[2])
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
source(file.path("reports", "2026-10-29", "hypotheses", "props_frame.R"))
read_gz <- function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE))
dec <- function(o) ifelse(o < 0, 1 + 100 / -o, 1 + o / 100)
say <- function(...) cat(sprintf(...), "\n")
Fd <- file.path("reports", "2026-10-28", "feasibility")
this <- file.path(store, "kalshi", "kalshi_settled.csv.gz")
others <- setdiff(Sys.glob(file.path(dirname(store), "w[0-9][0-9]", "kalshi", "kalshi_settled.csv.gz")), this)
settled <- c(file.path(Fd, "props", "kalshi_settled_w1-5.csv.gz"), file.path(Fd, "props", "kalshi_settled.csv.gz"), others, this)
say("settled files: %s", paste(basename(dirname(dirname(settled))), collapse = ", "))
run <- sort(Sys.glob(file.path(store, "run_*")))[1]; say("run: %s", basename(run))

sched <- as.data.table(nflreadr::load_schedules(2026))[game_type == "REG" & week == WEEK]
sched[, kick := as.POSIXct(paste(gameday, gametime), format = "%Y-%m-%d %H:%M", tz = "America/New_York")]; attr(sched$kick, "tzone") <- "UTC"
res <- sched[!is.na(result), .(game_id, home_team, away_team, kick, result, home_score, away_score)]
say("games in week %d: %d; with a result: %d", WEEK, nrow(sched), nrow(res))

st <- unique(rbindlist(lapply(settled, read_gz), fill = TRUE), by = "ticker")
cn <- unique(rbindlist(lapply(file.path(store, "kalshi", "kalshi_candles.csv.gz"), read_gz), fill = TRUE), by = "ticker")
say("settlements: %d; candles: %d", nrow(st), nrow(cn))
ev <- props_event_games(st$event_ticker, props_schedule())
say("events mapped to games: %d; of week %d: %d", nrow(ev), WEEK, nrow(ev[week == WEEK]))
k <- merge(st[, .(ticker, series, event_ticker, label, result_k = result, yk = settlement_value)], ev, by = "event_ticker")[week == WEEK]
say("week's settled contracts: %d", nrow(k))
k <- merge(k, cn[, .(ticker, bid = bid_close, ask = ask_close)], by = "ticker"); say("  with a candle row: %d", nrow(k))
k <- merge(k, res[, .(game_id, home_team, away_team)], by = "game_id"); say("  in a game with a result: %d", nrow(k))
k <- k[result_k %in% c("yes", "no") & is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid & ask - bid <= MAX_SPREAD][, mid := (bid + ask) / 2]
say("  yes/no, two-sided, spread <= %.2f: %d", MAX_SPREAD, nrow(k))
print(k[, .N, by = series][order(-N)])

# module_props(), stage by stage
norm <- function(x) { x <- tolower(iconv(x, to = "ASCII//TRANSLIT")); x <- gsub("[.'`-]", "", x); x <- gsub("\\b(jr|sr|ii|iii|iv|v)\\b", "", x); gsub("\\s+", " ", trimws(x)) }
abbr <- function(full) { z <- strsplit(norm(full), " ", fixed = TRUE); vapply(z, function(t) if (length(t) < 2) NA_character_ else paste(substr(t[1], 1, 1), paste(t[-1], collapse = " ")), "") }
pr <- k[series %in% names(LADDERS)][, `:=`(kk = as.numeric(sub("^.*: ([0-9]+)\\+$", "\\1", label)), name = sub(":.*$", "", label), stat = unname(LADDERS[series]),
                                         seg = substring(ticker, nchar(event_ticker) + 2L))]
say("\nprop contracts in LADDERS series: %d; with a parsed threshold: %d", nrow(pr), sum(!is.na(pr$kk)))
aliases <- function(x) c(x, switch(x, LA = "LAR", JAX = "JAC", WAS = "WSH", LV = "LVR", character(0)))
pr[, pteam := vapply(seq_len(.N), function(i) { cand <- c(stats::setNames(aliases(home_team[i]), rep(home_team[i], length(aliases(home_team[i])))),
                                                          stats::setNames(aliases(away_team[i]), rep(away_team[i], length(aliases(away_team[i])))))
  hit <- cand[startsWith(seg[i], cand)]; if (length(hit)) names(hit)[which.max(nchar(hit))] else NA_character_ }, character(1))]
say("  with a team from the ticker: %d", sum(!is.na(pr$pteam)))
pr <- pr[!is.na(kk) & !is.na(pteam)][, `:=`(key = norm(name), akey = abbr(name))]
say("  kept: %d (players %d)", nrow(pr), uniqueN(pr$akey))
mod <- fread(file.path(run, "baseline_props.csv"))
say("\nmodule rows: %d; columns: %s", nrow(mod), paste(names(mod), collapse = ", "))
mod[, `:=`(stat = fifelse(prop_type == "anytime_td", "touchdowns", prop_type), akey = norm(sub(".", " ", player, fixed = TRUE)))]
say("module stats: %s", paste(sprintf("%s=%d", names(table(mod$stat)), as.integer(table(mod$stat))), collapse = ", "))
say("kalshi stats: %s", paste(sprintf("%s=%d", names(table(pr$stat)), as.integer(table(pr$stat))), collapse = ", "))
cat("module keys (first 6):\n"); print(head(unique(mod[, .(akey, team, stat, player)]), 6))
cat("kalshi keys (first 6):\n"); print(head(unique(pr[, .(akey, pteam, stat, name)]), 6))
j <- merge(pr, mod[, .(akey, pteam = team, stat, mu_mod = projection, p_td_mod = p_over)], by = c("akey", "pteam", "stat"))
say("\njoined on akey + team + stat: %d", nrow(j))
say("  on akey alone: %d; on akey + stat: %d; on akey + team: %d", nrow(merge(unique(pr[, .(akey)]), unique(mod[, .(akey)]), by = "akey")),
    nrow(merge(unique(pr[, .(akey, stat)]), unique(mod[, .(akey, stat)]), by = c("akey", "stat"))),
    nrow(merge(unique(pr[, .(akey, pteam)]), unique(mod[, .(akey, pteam = team)]), by = c("akey", "pteam"))))

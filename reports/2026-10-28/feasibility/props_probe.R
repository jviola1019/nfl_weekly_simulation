# Could a model beat Kalshi's NFL prop prices? A first, prospective look at every per-game series the capture
# archive priced in 2026 weeks 6-7 (releases odds-capture-2026-W43 and -W44; the earlier 2026 captures need the
# 90-day backfill). Each contract's price is either its last two-sided capture before the schedule's kickoff (Kalshi's
# occurrence time falls 3 hours after kickoff, so it is not a cutoff) or, with --candles, its close at kickoff from
# Kalshi's hourly candles (kalshi_candles.R). The price is paired with Kalshi's own settlement (kalshi_settled.R):
# - 1 or 0 for a binary contract, 1/N for an N-way tie (most receiving or rushing yards);
# - the payout for a scalar contract (the ladders and escalators, which pay a fraction of $1 that grows with a stat);
# - no outcome for a contract settled at the pre-game fair price (a player who never took a snap, or a protected
#   contract's player out after the half), which is excluded.
# For each series, and pooled over player props, game props and game lines, it reports:
# - Brier, the calibration slope and calibration-in-the-large, clustered by game (players in one game share its
#   script; with ~30 games the intervals use HC1 and t with G - 1 df), BH over the series;
# - reliability, the bid-ask spread, and the price's movement between captures;
# - out of sample: a recalibration fit on week 6 and scored on week 7, as Brier and as a taker's return after the
#   spread and Kalshi's taker fee;
# - a check of Kalshi's settlements against outcomes rebuilt from nflverse's 2026 stats for the eleven
#   counting-stat ladders (the outcomes the first version of this probe used).
# Only 2026 is read. Run from the repository root, with each extracted archive in its own directory:
#   Rscript reports/2026-10-28/feasibility/props_probe.R <out_dir> <kalshi_settled.csv.gz> <capture_dir> [<capture_dir> ...]
#     [--candles=<kalshi_candles.csv.gz>]
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
candles_csv <- sub("^--candles=", "", grep("^--candles=", args, value = TRUE))   # optional: kalshi_candles.R's output
args <- grep("^--candles=", args, value = TRUE, invert = TRUE)
out <- args[1]; settled_csv <- args[2]; dirs <- args[-(1:2)]
PRICE <- if (length(candles_csv)) "the candle close at kickoff" else "the last capture before the scheduled kickoff"
dir.create(out, recursive = TRUE, showWarnings = FALSE)
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))   # the series groups, settlement and the tests

# --- the captured quotes -------------------------------------------------------------------------------------
files <- list.files(dirs, pattern = "^KXNFL[A-Z0-9]+_p[0-9]+__[0-9]{8}T[0-9]{6}Z\\.json\\.gz$", recursive = TRUE, full.names = TRUE)
info <- data.table(path = files, base = basename(files))
info[, `:=`(series = sub("_p[0-9]+__.*$", "", base), captured = as.POSIXct(sub("^.*__([0-9]{8}T[0-9]{6}Z)\\.json\\.gz$", "\\1", base),
                                                                         format = "%Y%m%dT%H%M%SZ", tz = "UTC"))]
num <- function(v) suppressWarnings(as.numeric(v))
mk <- rbindlist(lapply(seq_len(nrow(info)), function(i) {
  m <- jsonlite::fromJSON(gzfile(info$path[i]), simplifyVector = TRUE)$markets
  if (!length(m) || !NROW(m)) return(NULL)
  fld <- function(n) if (n %in% names(m)) as.character(m[[n]]) else rep(NA_character_, NROW(m))   # season markets lack some fields
  data.table(series = info$series[i], captured = info$captured[i], ticker = fld("ticker"), event_ticker = fld("event_ticker"),
             label = fld("no_sub_title"), bid = num(fld("yes_bid_dollars")), ask = num(fld("yes_ask_dollars")),
             occurrence = as.POSIXct(fld("occurrence_datetime"), format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
}), fill = TRUE)
mk <- unique(mk, by = c("ticker", "captured"))                      # one run sits in two weekly archives
stopifnot(!any(format(mk$occurrence, "%Y") == "2025", na.rm = TRUE))   # the seal: 2026 only

# --- each event's game, from its ticker's date and team codes; season and novelty events have none ------------------------
options(timeout = 600)
sched <- props_schedule()
mk <- merge(mk, props_event_games(mk$event_ticker, sched), by = "event_ticker", all.x = TRUE)

# --- Kalshi's settlement ------------------------------------------------------------------------------------------
st <- as.data.table(utils::read.csv(gzfile(settled_csv), stringsAsFactors = FALSE))
stopifnot(!any(substr(st$close_time, 1, 4) == "2025"))
mk <- merge(mk, st[, .(ticker, result, y = settlement_value)], by = "ticker", all.x = TRUE)
stopifnot(all(mk[result == "yes", y] == 1), all(mk[result == "no", y] == 0))
mk[, outcome := props_outcome(series, game_id, result, y)]

# --- each contract's last pre-kickoff quote, and its first ---------------------------------------------------------
mk[, cutoff := pmin(occurrence, kick, na.rm = TRUE)]
pre <- mk[!is.na(game_id) & captured < cutoff & is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid]
setorder(pre, ticker, captured)
last <- pre[, .SD[.N], by = ticker]
last <- merge(last, pre[, .SD[1], by = ticker][, .(ticker, first_captured = captured, first_mid = (bid + ask) / 2)], by = "ticker")
no_close <- 0L
if (length(candles_csv)) {   # the price at kickoff replaces the last capture; the first capture stays the start of each move
  cn <- as.data.table(utils::read.csv(gzfile(candles_csv), stringsAsFactors = FALSE))
  n0 <- nrow(last[outcome %in% c("settled", "payout")])
  last <- merge(last, cn[, .(ticker, close_end, bid_close, ask_close)], by = "ticker")
  last <- last[is.finite(bid_close) & is.finite(ask_close) & ask_close > 0 & ask_close >= bid_close]
  no_close <- n0 - nrow(last[outcome %in% c("settled", "payout")])
  last[, `:=`(bid = bid_close, ask = ask_close, captured = as.POSIXct(close_end, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))]
}
last[, `:=`(mid = (bid + ask) / 2, spread = ask - bid, name = sub(":.*$", "", label), group = group_of(series),
            hours_before = as.numeric(difftime(cutoff, captured, units = "hours")))]
last[, pg := paste(game_id, name)]   # the player-game: a player's ladder in one game moves together
ok <- last[outcome %in% c("settled", "payout") & spread <= MAX_SPREAD & mid > 0 & mid < 1]
ex <- props_exclusive(mk); ev_y <- ex$ev_y; exclusive <- ex$series

# --- calibration -----------------------------------------------------------------------------------------------
cal <- props_calibration(ok, exclusive); calib <- cal$calib; fittable <- cal$fittable
fwrite(signif_dt(calib), file.path(out, "props_calibration.csv"))
rel <- props_reliability(ok)
fwrite(signif_dt(rel), file.path(out, "props_reliability.csv"))

# --- movement: contracts first seen at least 24 h before their last pre-kickoff quote -----------------------------
mv <- ok[as.numeric(difftime(captured, first_captured, units = "hours")) >= 24]
mv[, `:=`(move = 1e4 * (mid - first_mid), unit = fifelse(group %in% c("player", "player scalar"), pg, game_id))]
movement <- mv[, .(contracts = .N, games = uniqueN(game_id), sd_bps = stats::sd(move), sd_logit = stats::sd(lg(mid) - lg(first_mid)),
                   median_abs_bps = stats::median(abs(move)), p90_abs_bps = stats::quantile(abs(move), 0.9), share_moved = mean(move != 0),
                   median_hours_between = stats::median(as.numeric(difftime(captured, first_captured, units = "hours"))),
                   # one move per unit (a player-game's ladder for player props, a game for game markets)
                   units = uniqueN(unit), sd_bps_unit = stats::sd(.SD[, .(m = mean(move)), by = unit]$m)), by = group]
# the picks a CLV test needs, one contract a pick (props_common.R's clv_picks), and the within-game ICC for the design effect
movement <- merge(movement, mv[, clv_power(.SD), by = group], by = "group")

# the last day's movement, from the candles: the price 24, 3 and 1 hours before kickoff against the price at kickoff
if (length(candles_csv)) {
  lm <- merge(ok[, .(ticker, group, game_id, unit = fifelse(group %in% c("player", "player scalar"), pg, game_id), mid)],
              cn[, .(ticker, bid_24h, ask_24h, bid_3h, ask_3h, bid_1h, ask_1h)], by = "ticker")
  late <- rbindlist(lapply(c("24h", "3h", "1h"), function(h) {
    b <- lm[[paste0("bid_", h)]]; a <- lm[[paste0("ask_", h)]]
    d <- lm[is.finite(b) & is.finite(a) & a > 0 & a >= b & a - b <= MAX_SPREAD]
    d[, move := 1e4 * (mid - (get(paste0("bid_", h)) + get(paste0("ask_", h))) / 2)]
    merge(d[, .(before_kickoff = h, contracts = .N, share_moved = mean(move != 0), median_abs_bps = stats::median(abs(move)),
                p90_abs_bps = stats::quantile(abs(move), 0.9), sd_bps = stats::sd(move), units = uniqueN(unit),
                sd_bps_unit = stats::sd(.SD[, .(m = mean(move)), by = unit]$m)), by = group], d[, clv_power(.SD), by = group], by = "group")
  }))
  fwrite(late[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 5) else v)], file.path(out, "props_late_movement.csv"))
}
fwrite(movement[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 5) else v)], file.path(out, "props_movement.csv"))

# --- out of sample: recalibrate on week 6, score week 7 -----------------------------------------------------------------
w_tr <- min(ok$week); w_te <- max(ok$week)
oos <- rbind(ok[, oos_one(.SD, w_tr, w_te), by = group], cbind(data.table(group = "all"), oos_one(ok, w_tr, w_te)), fill = TRUE)
fwrite(signif_dt(oos), file.path(out, "props_oos.csv"))

# --- coherence of the exclusive sets ----------------------------------------------------------------------------------------
# Buying Yes on every contract at its ask pays $1 for sure; buying No on every one pays n - 1. Either is a sure profit only if it
# costs less, after the taker fee, at one capture (the last one before kickoff that quotes every contract of the event). This
# uses the top of the book only; its depth is not checked.
snap <-pre[series %in% exclusive & outcome == "settled",
            .(n_quoted = uniqueN(ticker), sum_mid = sum((bid + ask) / 2), sum_ask = sum(ask), sum_bid = sum(bid),
              yes_all = 1 - sum(ask + fee(ask)), no_all = (.N - 1) - sum(1 - bid + fee(1 - bid))), by = .(series, event_ticker, captured)]
snap <- merge(snap, ev_y, by = c("series", "event_ticker"))[n_quoted == n_settled]
setorder(snap, event_ticker, captured)
co <- snap[, .SD[.N], by = event_ticker]
coherence <- co[, .(events = .N, mean_contracts = mean(n_quoted), mean_sum_mid = mean(sum_mid), mean_sum_ask = mean(sum_ask), mean_sum_bid = mean(sum_bid),
                    events_yes_all_pays = sum(yes_all > 0), events_no_all_pays = sum(no_all > 0), best_profit = max(pmax(yes_all, no_all))), by = series]
fwrite(coherence[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 5) else v)], file.path(out, "props_coherence.csv"))

# --- the first version's cutoff: Kalshi's occurrence time alone ------------------------------------------------------------
# If an event's occurrence time falls after the game's scheduled kickoff, a quote captured mid-game passed as pre-kickoff.
# This counts those events and quotes, and refits the first version's ten ladders under both cutoffs.
gaps <- unique(mk[!is.na(game_id) & !is.na(kick) & !is.na(occurrence), .(event_ticker, game_id, gap_min = as.numeric(difftime(occurrence, kick, units = "mins")))],
               by = "event_ticker")
pre_old <- mk[!is.na(game_id) & captured < occurrence & is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid]
setorder(pre_old, ticker, captured)
last_old <- pre_old[, .SD[.N], by = ticker]
last_old <- merge(last_old, pre_old[, .SD[1], by = ticker][, .(ticker, first_captured = captured, first_mid = (bid + ask) / 2)], by = "ticker")
last_old[, `:=`(mid = (bid + ask) / 2, spread = ask - bid, pg = paste(game_id, sub(":.*$", "", label)),
                hours_before = as.numeric(difftime(occurrence, captured, units = "hours")), in_game = !is.na(kick) & captured >= kick)]
ten <- setdiff(names(LADDERS), "KXNFLRRYDS")
move_pg <- function(d) { d <- d[as.numeric(difftime(captured, first_captured, units = "hours")) >= 24]
  c(median_abs_move_bps = stats::median(abs(1e4 * (d$mid - d$first_mid))), sd_move_bps_player_game = stats::sd(d[, .(m = mean(1e4 * (mid - first_mid))), by = pg]$m)) }
old_ok <- last_old[series %in% ten & outcome == "settled" & spread <= MAX_SPREAD & mid > 0 & mid < 1]
new_ok <- ok[series %in% ten]
cutoff_check <- rbind(cbind(data.table(cutoff = "occurrence time only (the first version)", in_game_quotes = sum(old_ok$in_game)), fit_one(old_ok, TRUE),
                            as.data.table(as.list(move_pg(old_ok)))),
                      cbind(data.table(cutoff = PRICE, in_game_quotes = 0L), fit_one(new_ok, TRUE), as.data.table(as.list(move_pg(new_ok)))))
cutoff_check[, `:=`(events = nrow(gaps), events_occurrence_after_kickoff = sum(gaps$gap_min > 0), games_affected = uniqueN(gaps[gap_min > 0, game_id]),
                    max_gap_minutes = max(gaps$gap_min))]
fwrite(cutoff_check[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 5) else v)], file.path(out, "props_cutoff_check.csv"))
fwrite(unique(gaps[, .(game_id, gap_min)])[order(-gap_min)][, .(events = .N), by = .(game_id, gap_min)], file.path(out, "props_occurrence_gaps.csv"))

# --- Kalshi's settlements against nflverse's 2026 stats, for the eleven counting-stat ladders ------------------------------
ps <- as.data.table(nflreadr::load_player_stats(seasons = 2026))
sn <- as.data.table(nflreadr::load_snap_counts(seasons = 2026))
fetched <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
if (!nrow(ps) || !nrow(sn)) stop("props_probe: no 2026 player stats or snap counts were loaded (nflreadr returns an empty frame when the release is unreachable)", call. = FALSE)
z0 <- function(v) fifelse(is.na(v), 0, v)
ps[, touchdowns := z0(rushing_tds) + z0(receiving_tds) + z0(special_teams_tds)]
ps[, rush_rec_yards := z0(rushing_yards) + z0(receiving_yards)]
norm <- function(x) { x <- tolower(iconv(x, to = "ASCII//TRANSLIT")); x <- gsub("[.'`-]", "", x)
  x <- gsub("\\b(jr|sr|ii|iii|iv|v)\\b", "", x); gsub("\\s+", " ", trimws(x)) }
ps[, key := norm(player_display_name)]
long <- melt(ps[, c("key", "week", "team", unique(LADDERS)), with = FALSE], id.vars = c("key", "week", "team"), variable.name = "stat",
             value.name = "value", variable.factor = FALSE)
sn <- sn[, .(snaps = sum(offense_snaps + st_snaps, na.rm = TRUE)), by = .(key = norm(player), week, team)]
gm_teams <- sched[, .(game_id, home_team, away_team)]
vd <- unique(mk[series %in% names(LADDERS) & !is.na(game_id) & outcome %in% c("settled", "settled at the fair price (no outcome)"),
                .(ticker, series, label, game_id, week, outcome, y)], by = "ticker")
vd <- merge(vd, gm_teams, by = "game_id")
vd[, `:=`(key = norm(sub(": [0-9]+\\+$", "", label)), k = num(sub("^.*: ([0-9]+)\\+$", "\\1", label)), stat = unname(LADDERS[series]))]
vd <- merge(vd, long, by = c("key", "week", "stat"), all.x = TRUE, allow.cartesian = TRUE)
vd <- vd[is.na(team) | team == home_team | team == away_team]
two <- vd[!is.na(value), .N, by = ticker][N > 1, ticker]
vd <- vd[!ticker %in% two]
miss <- merge(vd[is.na(value), !c("team", "value")], sn, by = c("key", "week"), all.x = TRUE, allow.cartesian = TRUE)
miss <- miss[is.na(team) | team == home_team | team == away_team]
miss[, rebuilt := fifelse(!is.na(snaps) & snaps > 0, "snap, no stat row: stat 0", "no snap: fair price")]
miss[, value := fifelse(rebuilt == "no snap: fair price", NA_real_, 0)]
vd <- rbind(vd[!is.na(value)][, rebuilt := "stat row"], unique(miss, by = "ticker")[, names(vd[0][, rebuilt := character()]), with = FALSE])
vd[, y_nfl := as.integer(value >= k)]
vd[, kalshi := fifelse(outcome == "settled", "outcome", "fair price")]
validation <- vd[, .(contracts = .N, both_outcome = sum(kalshi == "outcome" & !is.na(y_nfl)), agree = sum(kalshi == "outcome" & !is.na(y_nfl) & y_nfl == y),
                     kalshi_fair_rebuilt_no_snap = sum(kalshi == "fair price" & rebuilt == "no snap: fair price"),
                     kalshi_fair_rebuilt_outcome = sum(kalshi == "fair price" & rebuilt != "no snap: fair price"),
                     kalshi_outcome_rebuilt_no_snap = sum(kalshi == "outcome" & rebuilt == "no snap: fair price")), by = series]
validation <- rbind(validation, validation[, c(list(series = "all"), lapply(.SD, sum)), .SDcols = !"series"])
validation[, agreement := agree / both_outcome]
fwrite(validation[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 6) else v)], file.path(out, "props_validation.csv"))
fwrite(vd[kalshi == "outcome" & !is.na(y_nfl) & y_nfl != y, .(ticker, label, week, team, value, k, y_kalshi = y, y_nfl, rebuilt)],
       file.path(out, "props_validation_disagreements.csv"))

# --- every series in the captures: what it is and what happened to it -------------------------------------------------
inv <- mk[, .(markets = uniqueN(ticker), events = uniqueN(event_ticker), game_events = uniqueN(event_ticker[!is.na(game_id)]),
              settled_outcome = uniqueN(ticker[outcome %in% c("settled", "payout")]),
              fair_price = uniqueN(ticker[outcome == "settled at the fair price (no outcome)"]), sample_label = label[1]), by = series]
inv <- merge(inv, last[, .(quoted = .N), by = series], by = "series", all.x = TRUE)
inv <- merge(inv, ok[, .(fitted_contracts = .N, fitted_games = uniqueN(game_id)), by = series], by = "series", all.x = TRUE)
empty <- setdiff(unique(info$series), inv$series)
inv <- rbind(inv, data.table(series = empty, markets = 0L), fill = TRUE)
for (v in c("events", "game_events", "settled_outcome", "fair_price", "quoted", "fitted_contracts", "fitted_games")) set(inv, which(is.na(inv[[v]])), v, 0L)
inv[, group := fifelse(game_events > 0, group_of(series), "not a single game's market")]
inv[, status := fcase(markets == 0, "no markets in weeks 6-7", game_events == 0, "season, novelty or cross-game market: out of scope",
                      settled_outcome == 0, "no contract settled with an outcome in the window", fitted_contracts == 0, "no quote within the spread limit",
                      series %in% fittable, "fitted on its own and pooled", default = "pooled only (too few contracts for its own fit)")]
setorder(inv, group, -fitted_contracts, series)
fwrite(inv, file.path(out, "props_inventory.csv"))

coverage <- data.table(item = c("price", "contracts with an outcome and a capture but no two-sided candle close (dropped)","capture files read", "series captured","series with markets in weeks 6-7", "series tied to single games",
                                "contracts in single-game series", "  settled with an outcome (binary, tie share or scalar payout)",
                                "  settled at the pre-game fair price (no outcome, excluded)", "  not settled in the window (week 8, or voided)",
                                "contracts with a pre-kickoff two-sided quote and an outcome", "  of them with spread <= 0.10 (fitted)", "games fitted",
                                "2026 week 6-7 games in the schedule, and those with no fitted contract",
                                "series fitted on their own", "series set aside: fewer than 10 events or non-events", "Kalshi settlements fetched for",
                                "player stats and snap counts fetched (UTC)"),
                       value = c(PRICE, no_close, nrow(info), uniqueN(info$series),sum(inv$markets > 0), sum(inv$game_events > 0),
                                 uniqueN(mk[!is.na(game_id), ticker]), uniqueN(mk[outcome %in% c("settled", "payout"), ticker]),
                                 uniqueN(mk[outcome == "settled at the fair price (no outcome)", ticker]),
                                 uniqueN(mk[outcome == "not settled in the window (later games, or voided)", ticker]),
                                 uniqueN(last[outcome %in% c("settled", "payout"), ticker]), nrow(ok), uniqueN(ok$game_id),
                                 sprintf("%d; missing: %s", sched[week %in% unique(ok$week), .N],
                                         paste(setdiff(sched[week %in% unique(ok$week), game_id], ok$game_id), collapse = " ")),
                                 length(fittable), paste(cal$rare, collapse = "; "),
                                 "2026-10-13 to 2026-10-28 closes", fetched))
fwrite(coverage, file.path(out, "props_coverage.csv"))

options(width = 220)
print(coverage)
print(inv[markets > 0, .(series, group, markets, game_events, settled_outcome, fair_price, fitted_contracts, status)], nrows = 300)
cat("\n--- calibration (game-clustered, t with G - 1 df) ---\n")
print(calib[, .(series, group, exclusive, contracts, games, mean_y = signif(mean_y, 3), brier = signif(brier, 3), slope = signif(slope, 3), slope_lo = signif(slope_lo, 3),
                slope_hi = signif(slope_hi, 3), q_slope = signif(q_slope, 2), citl = signif(citl, 3), q_citl = signif(q_citl, 2), spread = signif(median_spread, 2))], nrows = 300)
cat("\n--- reliability ---\n"); print(rel[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 3) else v)], nrows = 100)
cat("\n--- movement ---\n"); print(movement[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 4) else v)])
cat("\n--- out of sample (week 6 -> week 7) ---\n"); print(oos[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 4) else v)])
cat("\n--- Kalshi's settlements against nflverse ---\n"); print(validation)
cat("\n--- the first version's cutoff against this one (the ten ladders) ---\n"); print(cutoff_check[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 4) else v)])
cat("\nhours from the last quote to kickoff, median by group:\n"); print(ok[, .(median_hours_before = stats::median(hours_before)), by = group])
cat("\n--- coherence of mutually exclusive sets ---\n"); print(coherence[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 4) else v)])
if (length(candles_csv)) { cat("\n--- the last day's movement (candles) ---\n"); print(late[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 4) else v)]) }

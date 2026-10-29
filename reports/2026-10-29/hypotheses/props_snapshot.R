# Track K1 for player props, the owner's request of 2026-10-29: the same player's prop at Kalshi, Smarkets and Pinnacle
# at one moment, checked for arbitrage, middles and price disparity (VENUE_SURVEY.md lists the endpoints).
# - Kalshi's ladders: YES on "k+" is the over (k - 0.5) and NO the under, at the ask plus the taker fee (or 1 - the bid
#   plus the fee).
# - Smarkets' player over/under markets, and its anytime-touchdown market, where backing a player is the over 0.5 and
#   laying him the under; Smarkets' 2% commission on net winnings is applied (an assumption, as in venue_snapshot.R).
# - Pinnacle's player-prop specials ("<Name> Total <stat>"), over/under at American odds.
# Players are joined within a game by name (props_probe.R's normalisation). Quotes wider than MAX_SPREAD count for
# arbitrage but are kept out of the no-vig comparisons. Prices stay in <raw_dir> (private); <out_dir> gets aggregates.
# Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/props_snapshot.R <out_dir> <raw_dir> [--offline [--stamp=<YYYYmmddTHHMMSSZ>]]
source(file.path("reports", "2026-10-29", "hypotheses", "venue_common.R"))   # arguments, clock, games, team codes, fetch, fees
STATS <- data.table(stat = c("passing_yards", "rushing_yards", "receiving_yards", "receptions", "passing_tds", "attempts", "completions", "carries",
                             "passing_interceptions", "touchdowns"),
                    kalshi = c("KXNFLPASSYDS", "KXNFLRSHYDS", "KXNFLRECYDS", "KXNFLREC", "KXNFLPASSTDS", "KXNFLPASSATT", "KXNFLPASSCOMP", "KXNFLRSHATT",
                               "KXNFLPASSINT", "KXNFLTD"),
                    smarkets = c("PLAYER_PASSING_YARDS", "PLAYER_RUSHING_YARDS", "PLAYER_RECEIVING_YARDS", "PLAYER_RECEPTIONS", "PLAYER_PASSING_TOUCHDOWNS",
                                 NA, NA, NA, NA, "ANYTIME_TOUCHDOWN_SCORER"),
                    pinnacle = c("Passing Yards", "Rushing Yards", "Receiving Yards", "Receptions", "Touchdown Passes", "Pass Attempts", "Pass Completions",
                                 "Rush Attempts", "Interceptions", "Touchdowns"),
                    max_gap = c(10, 10, 10, 2, 1, 3, 3, 3, 1, 1))   # the widest middle counted, in the stat's units
rows <- list()
add <- function(venue, gid, player, stat, line, side, cost, wide = FALSE)
  rows[[length(rows) + 1L]] <<- list(venue = venue, game_id = gid, player = player, stat = stat, line = as.numeric(line), side = side,
                                     cost = as.numeric(cost), wide = wide)

# Kalshi: each prop series' open markets, paged
ks <- list()
for (s in STATS$kalshi) {
  cursor <- ""
  for (pg in 1:10) {
    j <- js(fetch(sprintf("kalshi_%s_p%d", s, pg), sprintf("%s/markets?series_ticker=%s&status=open&limit=1000%s", KALSHI_BASE, s,
                                                           if (nzchar(cursor)) paste0("&cursor=", utils::URLencode(cursor, reserved = TRUE)) else "")))
    if (is.null(j)) break
    ks <- c(ks, j$markets); cursor <- j$cursor %||% ""; if (!nzchar(cursor)) break
  }
}
if (length(ks)) parse_venue("kalshi", function() {
  ev <- props_event_games(vapply(ks, function(m) m$event_ticker %||% "", ""), sched)
  for (m in ks) {
    gid <- ev$game_id[match(m$event_ticker, ev$event_ticker)]; if (!length(gid) || is.na(gid) || !gid %in% games$game_id) next
    st <- STATS$stat[match(sub("-.*$", "", m$ticker), STATS$kalshi)]; lab <- m$no_sub_title %||% ""
    k <- num(sub("^.*: ([0-9]+)\\+$", "\\1", lab)); if (is.na(st) || !is.finite(k)) next
    yb <- num(m$yes_bid_dollars); ya <- num(m$yes_ask_dollars)
    if (!is.finite(yb) || !is.finite(ya) || yb <= 0 || ya >= 1 || ya < yb) next
    pl <- norm_name(sub(": [0-9]+\\+$", "", lab)); wd <- ya - yb > MAX_SPREAD
    add("Kalshi", gid, pl, st, k - 0.5, "over", ya + fee(ya), wd); add("Kalshi", gid, pl, st, k - 0.5, "under", (1 - yb) + fee(1 - yb), wd)
  }
})

# Smarkets: the week's events, their player markets, and those markets' contracts and quotes, 40 markets a request
iso <- function(t) format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
sm_get <- function(name, path) js(fetch(name, paste0("https://api.smarkets.com/v3", path)))
sm_ev <- list(); path <- sprintf("/events/?type=american_football_match&state=upcoming&start_datetime_min=%s&start_datetime_max=%s&limit=50",
                                 iso(min(games$kick) - 3600), iso(max(games$kick) + 3600))
for (pg in 1:5) {
  j <- sm_get(sprintf("smarkets_events_p%d", pg), path); if (is.null(j)) break
  sm_ev <- c(sm_ev, j$events); nx <- j$pagination$next_page %||% ""; if (!nzchar(nx)) break
  path <- paste0("/events/", nx)
}
sm_games <- list()
for (e in sm_ev) {
  nm <- strsplit(e$name %||% "", " at ", fixed = TRUE)[[1]]
  if (length(nm) == 2) { m <- match_game(code_of(nm[2]), code_of(nm[1])); if (!is.null(m)) sm_games[[as.character(e$id)]] <- m }
}
if (length(sm_games)) {
  smk <- sm_get("smarkets_markets", sprintf("/events/%s/markets/", paste(names(sm_games), collapse = ",")))
  keep <- Filter(function(x) (x$market_type$name %||% "") %in% STATS$smarkets && identical(x$state, "open"), smk$markets %||% list())
  ids <- vapply(keep, function(x) as.character(x$id), ""); chunks <- split(ids, ceiling(seq_along(ids) / 40))
  sm_ct <- list(); sm_qt <- list()
  for (k in seq_along(chunks)) {
    a <- sm_get(sprintf("smarkets_pcontracts_%02d", k), sprintf("/markets/%s/contracts/", paste(chunks[[k]], collapse = ",")))
    b <- sm_get(sprintf("smarkets_pquotes_%02d", k), sprintf("/markets/%s/quotes/", paste(chunks[[k]], collapse = ",")))
    sm_ct <- c(sm_ct, a$contracts %||% list()); sm_qt <- c(sm_qt, b %||% list())
  }
  if (length(sm_ct)) parse_venue("smarkets", function() {
    mt <- rbindlist(lapply(keep, function(x) data.table(mid = as.character(x$id), event_id = as.character(x$event_id), type = x$market_type$name,
                                                        player = x$market_type$param$PLAYER_NAME %||% NA_character_, total = num(x$market_type$param$TOTAL))))
    top <- function(q, side) { v <- vapply(q[[side]] %||% list(), function(l) num(l$price), 1); if (!length(v)) NA_real_ else if (side == "offers") min(v) else max(v) }
    ct <- rbindlist(lapply(sm_ct, function(z) data.table(cid = as.character(z$id), mid = as.character(z$market_id), cname = z$name %||% "", ctype = z$contract_type$name %||% "")))
    ct[, `:=`(offer = vapply(cid, function(i) top(sm_qt[[i]], "offers"), 1) / 1e4, bid = vapply(cid, function(i) top(sm_qt[[i]], "bids"), 1) / 1e4)]
    ct <- merge(ct, mt, by = "mid")
    ct[, stat := STATS$stat[match(type, STATS$smarkets)]]
    for (id in unique(ct[type != "ANYTIME_TOUCHDOWN_SCORER", mid])) {   # over/under: back a side, or lay the other
      x <- ct[ct$mid == id]; m <- sm_games[[x$event_id[1]]]
      if (nrow(x) != 2 || is.null(m) || !setequal(x$ctype, c("OVER", "UNDER")) || !is.finite(x$total[1])) next
      ask <- pmin(x$offer, 1 - rev(x$bid), na.rm = TRUE); bidp <- pmax(x$bid, 1 - rev(x$offer), na.rm = TRUE)
      if (any(!is.finite(ask)) || any(ask <= 0 | ask >= 1)) next
      wd <- any(!is.finite(bidp)) || any(ask - bidp > MAX_SPREAD)
      for (i in 1:2) add("Smarkets", m$gid, norm_name(x$player[1]), x$stat[1], x$total[1], tolower(x$ctype[i]), sm_cost(ask[i]), wd)
    }
    td <- ct[type == "ANYTIME_TOUCHDOWN_SCORER" & ctype == "NAMED_COMPETITOR"]   # backing a player is the over 0.5, laying him the under
    for (i in seq_len(nrow(td))) {
      m <- sm_games[[td$event_id[i]]]; if (is.null(m)) next
      wd <- !is.finite(td$bid[i]) || !is.finite(td$offer[i]) || td$offer[i] - td$bid[i] > MAX_SPREAD
      if (is.finite(td$offer[i]) && td$offer[i] > 0 && td$offer[i] < 1) add("Smarkets", m$gid, norm_name(td$cname[i]), "touchdowns", 0.5, "over", sm_cost(td$offer[i]), wd)
      if (is.finite(td$bid[i]) && td$bid[i] > 0 && td$bid[i] < 1) add("Smarkets", m$gid, norm_name(td$cname[i]), "touchdowns", 0.5, "under", sm_cost(1 - td$bid[i]), wd)
    }
  })
}

# Pinnacle: player-prop specials hang off each game's matchup through parentId
pin_mu <- js(fetch("pinnacle_matchups", "https://guest.api.arcadia.pinnacle.com/0.1/leagues/889/matchups"))
pin_mk <- js(fetch("pinnacle_markets", "https://guest.api.arcadia.pinnacle.com/0.1/leagues/889/markets/straight"))
if (!is.null(pin_mu) && !is.null(pin_mk)) parse_venue("pinnacle", function() {
  pg <- list()
  for (mt in pin_mu) {
    if (!identical(mt$type, "matchup") || length(mt$participants) != 2 || !is.null(mt$special) || isTRUE(mt$isLive)) next
    al <- vapply(mt$participants, function(p) p$alignment %||% "", ""); nm <- vapply(mt$participants, function(p) p$name %||% "", "")
    if (!setequal(al, c("home", "away"))) next
    m <- match_game(code_of(nm[al == "home"]), code_of(nm[al == "away"])); if (!is.null(m)) pg[[as.character(mt$id)]] <- m
  }
  sp <- list()
  for (mt in pin_mu) {
    if (!identical(mt$special$category %||% "", "Player Props") || isTRUE(mt$isLive)) next
    m <- pg[[as.character(mt$parentId %||% "")]]; st <- STATS$stat[match(mt$units %||% "", STATS$pinnacle)]
    if (is.null(m) || is.na(st)) next
    side <- setNames(tolower(vapply(mt$participants, function(p) p$name %||% "", "")), vapply(mt$participants, function(p) as.character(p$id), ""))
    sp[[as.character(mt$id)]] <- list(gid = m$gid, stat = st, player = norm_name(sub(" Total .*$", "", mt$special$description %||% "")), side = side)
  }
  for (x in pin_mk) {
    s <- sp[[as.character(x$matchupId)]]
    if (is.null(s) || !identical(as.integer(x$period), 0L) || !identical(x$status %||% "open", "open")) next
    for (p in x$prices) {
      sd <- s$side[[as.character(p$participantId)]] %||% NA_character_
      if (sd %in% c("over", "under") && is.finite(num(p$points))) add("Pinnacle", s$gid, s$player, s$stat, num(p$points), sd, inv(p$price))
    }
  }
})

# --- normalise and compare --------------------------------------------------------------------------------------------------
px <- rbindlist(rows)[is.finite(cost) & cost > 0 & cost < 1 & is.finite(line) & nzchar(player)]
px <- px[order(cost)][, .(cost = cost[1], wide = wide[1]), by = .(venue, game_id, player, stat, line, side)]
stopifnot(nrow(px) > 0)
fwrite(px, file.path(raw, sprintf("props_prices__%s.csv.gz", stamp)))   # per-venue prices: private
k3 <- c("game_id", "player", "stat")
multi <- px[, .(venues = uniqueN(venue)), by = k3][venues >= 2]
pm <- merge(px, multi[, ..k3], by = k3)                                  # only props quoted at two venues or more
best <- pm[order(cost)][, .(cost = cost[1], venue = venue[1]), by = c(k3, "line", "side")]
bw <- dcast(best, game_id + player + stat + line ~ side, value.var = c("cost", "venue"))
for (cc in c("cost_over", "cost_under", "venue_over", "venue_under")) if (!cc %in% names(bw)) bw[, (cc) := NA]
two <- bw[is.finite(cost_over) & is.finite(cost_under)][, `:=`(sum_cost = cost_over + cost_under, profit = 1 - cost_over - cost_under)]
arbs <- two[sum_cost < 1 - 1e-9][order(-profit)]
ov <- pm[side == "over", c(k3, "line", "cost", "venue"), with = FALSE]; un <- pm[side == "under", c(k3, "line", "cost", "venue"), with = FALSE]
mid <- merge(ov, un, by = k3, suffixes = c("_over", "_under"), allow.cartesian = TRUE)[venue_over != venue_under & line_under > line_over]
mid <- merge(mid, STATS[, .(stat, max_gap)], by = "stat")[line_under - line_over <= max_gap][, cost := cost_over + cost_under]
nv <- dcast(pm[wide == FALSE], venue + game_id + player + stat + line ~ side, value.var = "cost")
for (cc in c("over", "under")) if (!cc %in% names(nv)) nv[, (cc) := NA_real_]
nv <- nv[is.finite(over) & is.finite(under)][, `:=`(p = over / (over + under), overround = over + under - 1)]
nv[, `:=`(n = .N, med = stats::median(p)), by = .(game_id, player, stat, line)]
shared <- nv[n >= 2]
disp_stat <- shared[, .(range_pp = 100 * (max(p) - min(p))), by = .(game_id, player, stat, line)][, .(lines = .N, median_range_pp = stats::median(range_pp),
  p90_range_pp = stats::quantile(range_pp, 0.9), max_range_pp = max(range_pp)), by = stat]
disp_venue <- merge(shared[, .(lines_shared = .N, mean_abs_dev_pp = mean(abs(100 * (p - med))), share_dev_over_3pp = mean(abs(100 * (p - med)) > 3)), by = .(venue, stat)],
                    nv[, .(lines = .N, median_overround = stats::median(overround)), by = .(venue, stat)], by = c("venue", "stat"), all = TRUE)
coverage <- px[, .(games = uniqueN(game_id), players = uniqueN(paste(game_id, player)), lines = uniqueN(paste(game_id, player, line)), quotes = .N), by = .(venue, stat)]
summ <- data.table(snapshot_utc = stamp, week = wk, games = nrow(games), quotes = nrow(px), props_at_2plus_venues = nrow(multi),
                   props_at_3_venues = multi[venues >= 3, .N], two_sided_lines = nrow(two), arbitrages = nrow(arbs),
                   best_arb_cents = if (nrow(arbs)) 100 * max(arbs$profit) else NA_real_, closest_two_sided_cost = if (nrow(two)) min(two$sum_cost) else NA_real_,
                   median_best_two_sided_cost = if (nrow(two)) stats::median(two$sum_cost) else NA_real_, middles = nrow(mid),
                   middles_cost_under_1 = sum(mid$cost < 1), cheapest_middle_cost = if (nrow(mid)) min(mid$cost) else NA_real_)
tag <- function(x) file.path(out, sprintf("%s__%s.csv", x, stamp))
fwrite(signif_dt(summ, 4), tag("props_summary")); fwrite(signif_dt(disp_stat, 4), tag("props_disparity_by_stat"))
fwrite(signif_dt(disp_venue, 4), tag("props_disparity_by_venue")); fwrite(coverage, tag("props_coverage"))
if (length(log_rows)) fwrite(rbindlist(log_rows), tag("props_requests"))
fwrite(arbs, file.path(raw, sprintf("props_arbitrages__%s.csv", stamp))); fwrite(mid[order(cost)], file.path(raw, sprintf("props_middles__%s.csv", stamp)))
options(width = 220)
print(summ); print(rbindlist(log_rows)[!is.na(error) | grepl("^parse_", endpoint)]); print(coverage[order(stat, venue)], nrows = 100)
print(signif_dt(disp_stat, 3)); print(signif_dt(disp_venue, 3)[order(stat, venue)], nrows = 100)
cat("\narbitrages:\n"); print(arbs[, .(game_id, player, stat, line, over = round(cost_over, 4), venue_over, under = round(cost_under, 4), venue_under, profit_cents = round(100 * profit, 2))], nrows = 40)
cat("\ncheapest middles:\n"); print(utils::head(mid[order(cost)][, .(game_id, player, stat, line_over, venue_over, line_under, venue_under, cost = round(cost, 4))], 15))

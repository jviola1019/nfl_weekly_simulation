# Track K1 (master plan), the owner's request of 2026-10-29: every keyless odds venue at one moment, checked for
# arbitrage, middles and price disparity on the coming week's games (moneyline, spread, total, team totals).
# - Venues (VENUE_SURVEY.md): Action Network's public scoreboard (DraftKings, FanDuel, BetMGM, Caesars, BetRivers and
#   bet365 at their NJ prices, plus its Consensus and Open lines), Pinnacle's guest API, Bovada, Polymarket, Smarkets and
#   Kalshi. No keys, logins or cookies; each request goes through the capture layer's GET (truthful user agent, 20 s
#   timeout, one request a second, retries only on 429/5xx), and a 4xx drops that endpoint from the snapshot.
# - Every price becomes a cost per $1 of payout: 1 / decimal odds at a book; on an exchange the ask plus the taker fee
#   (Kalshi 0.07 P (1 - P); Polymarket's sports rate 0.05 P (1 - P) where the market has fees enabled, per
#   docs.polymarket.com/trading/fees, read 2026-10-29; Smarkets' 2% commission on net winnings, an assumption from
#   third-party guides). The other side of a binary costs 1 - the bid, plus its fee.
# - Arbitrage: the cheapest costs of a market's two sides, across venues, sum below $1.
# - Middles: half-point lines on opposite sides at two venues, at most 3 points apart and within 3.5 of the consensus
#   line, leave a gap where both legs win. The gap's probability comes from the empirical key-number model of
#   key_numbers.R (2015-2024 closes, kernel bandwidth 1.5 around the consensus line), so the EV is model-dependent.
# - Disparity: each venue's no-vig price against the median venue at the same line, the line-shopping gain (the best
#   cost against the median venue's), and each venue's EV against Pinnacle's no-vig price (a sharp benchmark, not a
#   validated fair price).
# Raw responses and per-venue prices are sportsbook payloads, so they stay in <raw_dir> (private, never committed);
# <out_dir> gets aggregates only. Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/venue_snapshot.R <out_dir> <raw_dir> [--offline [--stamp=<YYYYmmddTHHMMSSZ>]] [--no-kalshi]
# --offline re-reads a snapshot saved in <raw_dir> (the newest, or the one --stamp names) instead of fetching.
source(file.path("reports", "2026-10-29", "hypotheses", "venue_common.R"))   # arguments, clock, games, team codes, fetch, fees
MIDDLE_MAX_GAP <- 3; MIDDLE_MAX_OFF <- 3.5; BANDWIDTH <- 1.5
BOOKS <- c(`68` = "DraftKings", `69` = "FanDuel", `71` = "BetRivers", `75` = "BetMGM", `79` = "bet365", `123` = "Caesars",
           `15` = "Consensus", `30` = "Open")
EXCHANGES <- c("Kalshi", "Polymarket", "Smarkets")
tt_of <- function(m, venue_side) if (xor(venue_side == "home", m$flip)) "tt_home" else "tt_away"

# --- rows: one per venue, game, market, line and side, priced as the cost of $1 of payout --------------------------------
# wide: an exchange quote whose bid-ask spread exceeds MAX_SPREAD (props_common.R); its ask still counts for arbitrage,
# but it is kept out of the no-vig comparisons, where a 2-98 market would read as a 50% price
# ref: the exchange contract a side buys (Kalshi ticker and yes/no, Polymarket token id), so its order book can be read later
rows <- list()
add <- function(venue, gid, market, line, side, cost, main = FALSE, size = NA_real_, updated = NA_character_, wide = FALSE, ref = NA_character_)
  rows[[length(rows) + 1L]] <<- list(venue = venue, game_id = gid, market = market, line = as.numeric(line), side = side,
                                     cost = as.numeric(cost), main = main, size = as.numeric(size), updated = as.character(updated), wide = wide,
                                     ref = as.character(ref))
pair <- function(venue, m, market, line_vh, cost_vh, cost_va, ...) {   # a home/away price in the venue's orientation
  ln <- if (market == "spread" && m$flip) -line_vh else line_vh
  add(venue, m$gid, market, ln, "home", if (m$flip) cost_va else cost_vh, ...)
  add(venue, m$gid, market, ln, "away", if (m$flip) cost_vh else cost_va, ...)
}
ou <- function(venue, gid, market, line, c_over, c_under, ...) {
  add(venue, gid, market, line, "over", c_over, ...); add(venue, gid, market, line, "under", c_under, ...)
}

# Action Network: one scoreboard request returns the NFL week; later dates are asked for only if games are missing
an_seen <- character(0); an_games <- character(0)
parse_an <- function(sb) for (g in sb$games) {
  if (as.character(g$id) %in% an_seen) next
  an_seen <<- c(an_seen, as.character(g$id))
  ids <- vapply(g$teams, function(t) as.character(t$id), ""); ab <- vapply(g$teams, function(t) t$abbr %||% "", "")
  m <- match_game(code_of(ab[ids == as.character(g$home_team_id)]), code_of(ab[ids == as.character(g$away_team_id)])); if (is.null(m)) next
  an_games <<- c(an_games, m$gid)
  for (o in g$odds) {
    if (!identical(o$type, "game")) next
    v <- unname(BOOKS[as.character(o$book_id)]); if (is.na(v)) next
    up <- o$inserted %||% NA_character_
    if (ok(o$ml_home, o$ml_away)) pair(v, m, "ml", 0, inv(o$ml_home), inv(o$ml_away), main = TRUE, updated = up)
    if (ok(o$spread_home, o$spread_home_line, o$spread_away_line))
      pair(v, m, "spread", num(o$spread_home), inv(o$spread_home_line), inv(o$spread_away_line), main = TRUE, updated = up)
    if (ok(o$total, o$over, o$under)) ou(v, m$gid, "total", num(o$total), inv(o$over), inv(o$under), main = TRUE, updated = up)
    if (ok(o$home_total, o$home_over, o$home_under)) ou(v, m$gid, tt_of(m, "home"), num(o$home_total), inv(o$home_over), inv(o$home_under), main = TRUE, updated = up)
    if (ok(o$away_total, o$away_over, o$away_under)) ou(v, m$gid, tt_of(m, "away"), num(o$away_total), inv(o$away_over), inv(o$away_under), main = TRUE, updated = up)
  }
}
for (dd in unique(format(games$kick, "%Y%m%d", tz = "America/New_York"))) {
  if (all(games$game_id %in% an_games)) break
  sb <- js(fetch(paste0("actionnetwork_", dd), sprintf("https://api.actionnetwork.com/web/v1/scoreboard/nfl?period=game&bookIds=%s&date=%s",
                                                       paste(names(BOOKS), collapse = ","), dd)))
  if (!is.null(sb)) parse_venue(paste0("actionnetwork_", dd), function() parse_an(sb))
}

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
  for (x in pin_mk) {
    m <- pg[[as.character(x$matchupId)]]
    if (is.null(m) || !identical(as.integer(x$period), 0L) || !identical(x$status, "open")) next
    d <- vapply(x$prices, function(p) p$designation %||% "", ""); pts <- vapply(x$prices, function(p) num(p$points), 1); pr <- vapply(x$prices, function(p) num(p$price), 1)
    lim <- num(x$limits[[1]]$amount); mn <- !isTRUE(x$isAlternate)
    if (identical(x$type, "moneyline") && setequal(d, c("home", "away"))) pair("Pinnacle", m, "ml", 0, inv(pr[d == "home"]), inv(pr[d == "away"]), main = TRUE, size = lim)
    if (identical(x$type, "spread") && setequal(d, c("home", "away"))) pair("Pinnacle", m, "spread", pts[d == "home"], inv(pr[d == "home"]), inv(pr[d == "away"]), main = mn, size = lim)
    if (identical(x$type, "total") && setequal(d, c("over", "under"))) ou("Pinnacle", m$gid, "total", pts[d == "over"], inv(pr[d == "over"]), inv(pr[d == "under"]), main = mn, size = lim)
    if (identical(x$type, "team_total") && setequal(d, c("over", "under")) && (x$side %||% "") %in% c("home", "away"))
      ou("Pinnacle", m$gid, tt_of(m, x$side), pts[d == "over"], inv(pr[d == "over"]), inv(pr[d == "under"]), main = mn, size = lim)
  }
})

bov <- js(fetch("bovada", "https://www.bovada.lv/services/sports/event/coupon/events/A/description/football/nfl?marketFilterId=def&preMatchOnly=true&lang=en"))
if (!is.null(bov)) parse_venue("bovada", function() for (grp in bov) for (e in grp$events) {
  if (isTRUE(e$live)) next
  nm <- vapply(e$competitors, function(c) c$name %||% "", ""); hm <- vapply(e$competitors, function(c) isTRUE(c$home), TRUE)
  if (length(nm) != 2 || sum(hm) != 1) next
  vh <- code_of(nm[hm]); va <- code_of(nm[!hm]); m <- match_game(vh, va); if (is.null(m)) next
  for (dg in e$displayGroups) for (mk in dg$markets) {
    if (!identical(mk$period$description, "Game") || isTRUE(mk$period$live) || !identical(mk$status, "O")) next
    oc <- mk$outcomes[vapply(mk$outcomes, function(o) identical(o$status, "O"), TRUE)]
    desc <- vapply(oc, function(o) o$description %||% "", ""); hcp <- vapply(oc, function(o) num(o$price$handicap), 1)
    am <- vapply(oc, function(o) num(sub("EVEN", "100", o$price$american %||% NA)), 1); tc <- code_of(desc)
    if (identical(mk$description, "Moneyline") && sum(tc == vh, na.rm = TRUE) == 1 && sum(tc == va, na.rm = TRUE) == 1)
      pair("Bovada", m, "ml", 0, inv(am[which(tc == vh)]), inv(am[which(tc == va)]), main = TRUE)
    if (identical(mk$description, "Point Spread") && sum(tc == vh, na.rm = TRUE) == 1 && sum(tc == va, na.rm = TRUE) == 1)
      pair("Bovada", m, "spread", hcp[which(tc == vh)], inv(am[which(tc == vh)]), inv(am[which(tc == va)]), main = TRUE)
    if (identical(mk$description, "Total") && sum(tolower(desc) == "over") == 1 && sum(tolower(desc) == "under") == 1 &&
        identical(hcp[tolower(desc) == "over"], hcp[tolower(desc) == "under"]))
      ou("Bovada", m$gid, "total", hcp[tolower(desc) == "over"], inv(am[tolower(desc) == "over"]), inv(am[tolower(desc) == "under"]), main = TRUE)
  }
})

pm <- js(fetch("polymarket", "https://gamma-api.polymarket.com/events?series_id=12185&closed=false&limit=50"))
if (!is.null(pm)) parse_venue("polymarket", function() for (e in pm) {
  if (isTRUE(e$closed)) next
  parts <- strsplit(sub("-[0-9]{4}-[0-9]{2}-[0-9]{2}$", "", sub("^nfl-", "", e$slug %||% "")), "-", fixed = TRUE)[[1]]
  if (length(parts) != 2) next
  m <- match_game(code_of(parts[2]), code_of(parts[1])); if (is.null(m)) next
  g <- games[game_id == m$gid]
  for (mk in e$markets) {
    if (!isTRUE(mk$active) || isTRUE(mk$closed) || !isTRUE(mk$acceptingOrders)) next
    bb <- num(mk$bestBid); ba <- num(mk$bestAsk)
    if (!is.finite(bb) || !is.finite(ba) || bb <= 0 || ba >= 1 || ba < bb) next
    f <- if (isTRUE(mk$feesEnabled)) pm_fee else function(p) 0
    c1 <- ba + f(ba); c2 <- (1 - bb) + f(1 - bb)    # the first outcome at its ask; the second at 1 - the first's bid
    oc <- tryCatch(unlist(jsonlite::parse_json(mk$outcomes %||% "[]")), error = function(e) character(0)); if (length(oc) != 2) next
    t <- mk$sportsMarketType %||% ""; ln <- num(mk$line); sz <- num(mk$liquidityNum); t1 <- code_of(oc[1]); wd <- ba - bb > MAX_SPREAD
    tok <- tryCatch(unlist(jsonlite::parse_json(mk$clobTokenIds %||% "[]")), error = function(e) character(0)); if (length(tok) != 2) tok <- c(NA_character_, NA_character_)
    two_sides <- function(market, line, s1, s2, main = FALSE) {   # s1: the first outcome's side, bought at its ask; s2 at 1 - its bid
      add("Polymarket", m$gid, market, line, s1, c1, main = main, size = sz, wide = wd, ref = tok[1])
      add("Polymarket", m$gid, market, line, s2, c2, main = main, size = sz, wide = wd, ref = tok[2])
    }
    if (t %in% c("moneyline", "spreads") && !t1 %in% c(g$home_team, g$away_team)) next
    hs <- if (identical(t1, g$home_team)) c("home", "away") else c("away", "home")
    if (t == "moneyline") two_sides("ml", 0, hs[1], hs[2], main = TRUE)
    if (t == "spreads" && is.finite(ln) && identical(num(sub("^.*\\(([-+0-9.]+)\\)$", "\\1", mk$question %||% "")), ln))
      two_sides("spread", if (t1 == g$home_team) ln else -ln, hs[1], hs[2])
    if (t == "totals" && is.finite(ln) && identical(tolower(oc[1]), "over")) two_sides("total", ln, "over", "under")
    if (t == "team_totals" && is.finite(ln) && identical(tolower(oc[1]), "over")) {
      tq <- code_of(sub("^(.*) Team Total: O/U [0-9.]+$", "\\1", mk$question %||% ""))
      if (identical(tq, g$home_team)) two_sides("tt_home", ln, "over", "under")
      if (identical(tq, g$away_team)) two_sides("tt_away", ln, "over", "under")
    }
  }
})

# Smarkets: the events in the week's kickoff window (paged), their moneyline (draw no bet), handicap and over/under
# markets, then those markets' contracts and quotes (sm_details, venue_common.R)
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
for (e in sm_ev) {   # "Away at Home"; college events match no NFL team
  nm <- strsplit(e$name %||% "", " at ", fixed = TRUE)[[1]]
  if (length(nm) == 2) { m <- match_game(code_of(nm[2]), code_of(nm[1])); if (!is.null(m)) sm_games[[as.character(e$id)]] <- m }
}
if (length(sm_games)) {
  smk <- sm_get("smarkets_markets", sprintf("/events/%s/markets/", paste(names(sm_games), collapse = ",")))
  keep <- Filter(function(x) (x$market_type$name %||% "") %in% c("WINNER_DNB", "HANDICAP", "OVER_UNDER") && identical(x$state, "open"), smk$markets %||% list())
  det <- sm_details("smarkets_", vapply(keep, function(x) as.character(x$id), "")); sm_ct <- det$contracts; sm_qt <- det$quotes
  if (length(sm_ct)) parse_venue("smarkets", function() {
    mt <- rbindlist(lapply(keep, function(x) data.table(mid = as.character(x$id), event_id = as.character(x$event_id), type = x$market_type$name, mname = x$name %||% "")))
    top <- function(q, side) { v <- vapply(q[[side]] %||% list(), function(l) num(l$price), 1); if (!length(v)) NA_real_ else if (side == "offers") min(v) else max(v) }
    ct <- rbindlist(lapply(sm_ct, function(z) data.table(cid = as.character(z$id), mid = as.character(z$market_id), cname = z$name %||% "", ctype = z$contract_type$name %||% "")))
    ct[, `:=`(offer = vapply(cid, function(i) top(sm_qt[[i]], "offers"), 1) / 1e4, bid = vapply(cid, function(i) top(sm_qt[[i]], "bids"), 1) / 1e4)]
    for (id in unique(ct$mid)) {
      x <- ct[ct$mid == id]; mk <- mt[mt$mid == id]; m <- sm_games[[mk$event_id]]
      if (nrow(x) != 2 || nrow(mk) != 1 || is.null(m)) next
      ask <- pmin(x$offer, 1 - rev(x$bid), na.rm = TRUE); bidp <- pmax(x$bid, 1 - rev(x$offer), na.rm = TRUE)   # back a side, or lay the other
      if (any(!is.finite(ask)) || any(ask <= 0 | ask >= 1)) next
      wd <- any(!is.finite(bidp)) || any(ask - bidp > MAX_SPREAD); cost <- sm_cost(ask)
      h <- x$ctype == "HOME"; a <- x$ctype == "AWAY"; o <- x$ctype == "OVER"; u <- x$ctype == "UNDER"
      if (mk$type == "WINNER_DNB" && sum(h) == 1 && sum(a) == 1) pair("Smarkets", m, "ml", 0, cost[h], cost[a], main = TRUE, wide = wd)
      if (mk$type == "HANDICAP" && sum(h) == 1 && sum(a) == 1)
        pair("Smarkets", m, "spread", num(sub("^.* ([-+]?[0-9.]+)$", "\\1", x$cname[h])), cost[h], cost[a], wide = wd)
      if (mk$type == "OVER_UNDER" && sum(o) == 1 && sum(u) == 1)
        ou("Smarkets", m$gid, "total", num(sub("^.* ([0-9.]+)$", "\\1", mk$mname)), cost[o], cost[u], wide = wd)
    }
  })
}

if (!no_kalshi) {
  ks <- list()
  for (s in c("KXNFLGAME", "KXNFLSPREAD", "KXNFLTOTAL", "KXNFLTEAMTOTAL")) {
    cursor <- ""
    for (pg in 1:5) {
      j <- js(fetch(sprintf("kalshi_%s_p%d", s, pg), sprintf("%s/markets?series_ticker=%s&status=open&limit=1000%s", KALSHI_BASE, s,
                                                             if (nzchar(cursor)) paste0("&cursor=", utils::URLencode(cursor, reserved = TRUE)) else "")))
      if (is.null(j)) break
      ks <- c(ks, j$markets); cursor <- j$cursor %||% ""; if (!nzchar(cursor)) break
    }
  }
  if (length(ks)) parse_venue("kalshi", function() {
    ev <- props_event_games(vapply(ks, function(m) m$event_ticker %||% "", ""), sched)
    for (m in ks) {
      gid <- ev$game_id[match(m$event_ticker, ev$event_ticker)]
      if (!length(gid) || is.na(gid) || !gid %in% games$game_id) next
      g <- games[game_id == gid]
      yb <- num(m$yes_bid_dollars); ya <- num(m$yes_ask_dollars)
      if (!is.finite(yb) || !is.finite(ya) || yb <= 0 || ya >= 1 || ya < yb) next
      cy <- ya + fee(ya); cn <- (1 - yb) + fee(1 - yb); sz <- num(m$liquidity_dollars); wd <- ya - yb > MAX_SPREAD
      tm <- code_of(sub("^.*-([A-Z]+)[0-9]*$", "\\1", m$ticker))
      side <- if (identical(tm, g$home_team)) "home" else if (identical(tm, g$away_team)) "away" else NA_character_
      x <- num(sub("^.*[Oo]ver ([0-9.]+)( points)?.*$", "\\1", m$no_sub_title %||% ""))
      yes_no <- function(market, line, s_yes, s_no, main = FALSE) {
        add("Kalshi", gid, market, line, s_yes, cy, main = main, size = sz, wide = wd, ref = paste0(m$ticker, ":yes"))
        if (!is.null(s_no)) add("Kalshi", gid, market, line, s_no, cn, main = main, size = sz, wide = wd, ref = paste0(m$ticker, ":no"))
      }
      # a tie settles both teams' contracts at $0.50 (2026's one tie, kalshi_settled_w1-5.csv.gz), so NO on one team is YES on the other
      if (startsWith(m$ticker, "KXNFLGAME-") && !is.na(side)) yes_no("ml", 0, side, setdiff(c("home", "away"), side), main = TRUE)
      if (startsWith(m$ticker, "KXNFLSPREAD-") && !is.na(side) && is.finite(x))   # YES: the team wins by more than x
        yes_no("spread", if (side == "home") -x else x, side, setdiff(c("home", "away"), side))
      if (startsWith(m$ticker, "KXNFLTOTAL-") && is.finite(x)) yes_no("total", x, "over", "under")
      if (startsWith(m$ticker, "KXNFLTEAMTOTAL-") && !is.na(side) && is.finite(x)) yes_no(paste0("tt_", side), x, "over", "under")
    }
  })
}

# --- normalise ------------------------------------------------------------------------------------------------------------------
px <- rbindlist(rows)[is.finite(cost) & cost > 0 & cost < 1 & is.finite(line)]
px[, line := round(line, 1)]
px <- px[order(cost)][, .(cost = cost[1], main = any(main), size = size[1], updated = updated[1], wide = wide[1], ref = ref[1]), by = .(venue, game_id, market, line, side)]
stopifnot(nrow(px) > 0)
fwrite(px, file.path(raw, sprintf("prices__%s.csv.gz", stamp)))                       # per-venue prices: private
venues <- setdiff(unique(px$venue), c("Consensus", "Open"))
pv <- px[venue %in% venues]
half <- function(x) abs(x %% 1 - 0.5) < 1e-9
side_cols <- function(d, prefix = "") for (s in c("home", "away", "over", "under")) if (!paste0(prefix, s) %in% names(d)) d[, (paste0(prefix, s)) := NA]

# each venue's two-way prices: the no-vig probability of home (or over) and the overround
nv <- dcast(pv[wide == FALSE], venue + game_id + market + line ~ side, value.var = "cost"); side_cols(nv)
nv[, `:=`(c1 = fifelse(market %in% c("ml", "spread"), home, over), c2 = fifelse(market %in% c("ml", "spread"), away, under))]
nv <- nv[is.finite(c1) & is.finite(c2)]
nv[, `:=`(p = c1 / (c1 + c2), overround = c1 + c2 - 1)]
# the power devig (c1^k + c2^k = 1) charges more of the margin to the longshot than the proportional one does; the two
# bracket the common methods, so an edge that survives both is less of a devig artefact
nv[, p_pow := mapply(function(a, b) a^stats::uniroot(function(k) a^k + b^k - 1, c(0.1, 50))$root, c1, c2)]
nv[pv[, .(main = any(main)), by = .(venue, game_id, market, line)], main := i.main, on = .(venue, game_id, market, line)]
nv[venue %in% EXCHANGES & market != "ml", main := abs(p - 0.5) == min(abs(p - 0.5)), by = .(venue, game_id, market)]   # a ladder's centre

# --- arbitrage: the cheapest two sides of a market across venues ----------------------------------------------------------------
best <- pv[order(cost)][, .(cost = cost[1], venue = venue[1], size = size[1], n_quotes = .N), by = .(game_id, market, line, side)]
bw <- dcast(best, game_id + market + line ~ side, value.var = c("cost", "venue")); side_cols(bw, "cost_"); side_cols(bw, "venue_")
two <- bw[, .(game_id, market, line, c1 = fifelse(market %in% c("ml", "spread"), cost_home, cost_over), c2 = fifelse(market %in% c("ml", "spread"), cost_away, cost_under),
              v1 = fifelse(market %in% c("ml", "spread"), venue_home, venue_over), v2 = fifelse(market %in% c("ml", "spread"), venue_away, venue_under))][is.finite(c1) & is.finite(c2)]
two[, `:=`(sum_cost = c1 + c2, profit = 1 - c1 - c2)]
arbs <- two[sum_cost < 1 - 1e-9][order(-profit)]   # the tolerance keeps an exact $1 pair (+100 / +100) out

# --- middles: opposite sides at two venues with a gap of margins (or totals) where both win -----------------------------------------
hist <- as.data.table(nflreadr::load_schedules(2015:2024))
stopifnot(!any(hist$season > 2024))   # the 2025 seal
hist <- hist[game_type == "REG" & !is.na(result) & !is.na(spread_line) & !is.na(total_line)]
HM <- rbind(hist[, .(c = spread_line, v = result)], hist[, .(c = -spread_line, v = -result)])   # c: the expected margin (nflverse sign)
HT <- hist[, .(c = total_line, v = home_score + away_score)]
tie_rate <- hist[, mean(result == 0)]
surv <- function(H, centre, x) { w <- stats::dnorm((H$c - centre) / BANDWIDTH); vapply(x, function(xx) sum(w[H$v > xx]) / sum(w), 1) }
centre <- merge(px[venue == "Consensus" & market %in% c("spread", "total"), .(cons = line[1]), by = .(game_id, market)],
                nv[main == TRUE & !venue %in% EXCHANGES & market %in% c("spread", "total"), .(med = stats::median(line)), by = .(game_id, market)],
                by = c("game_id", "market"), all = TRUE)[, .(game_id, market, centre = fifelse(is.finite(cons), cons, med))]
legs <- merge(pv[market %in% c("spread", "total") & half(line)], centre, by = c("game_id", "market"))[abs(line - centre) <= MIDDLE_MAX_OFF]
# spreads: home at home line l1 wins when margin > -l1, away at l2 when margin < -l2, so both win inside (-l1, -l2) when l1 > l2;
# totals: over at l1 and under at l2 both win inside (l1, l2) when l2 > l1
mid <- rbind(
  merge(legs[market == "spread" & side == "home", .(game_id, market, centre, l1 = line, c1 = cost, v1 = venue)],
        legs[market == "spread" & side == "away", .(game_id, l2 = line, c2 = cost, v2 = venue)], by = "game_id", allow.cartesian = TRUE)[l1 > l2 & l1 - l2 <= MIDDLE_MAX_GAP][, `:=`(lo = -l1, hi = -l2)],
  merge(legs[market == "total" & side == "over", .(game_id, market, centre, l1 = line, c1 = cost, v1 = venue)],
        legs[market == "total" & side == "under", .(game_id, l2 = line, c2 = cost, v2 = venue)], by = "game_id", allow.cartesian = TRUE)[l2 > l1 & l2 - l1 <= MIDDLE_MAX_GAP][, `:=`(lo = l1, hi = l2)])
mid <- mid[v1 != v2]
if (nrow(mid)) {
  mid[, p_mid := { s <- if (market[1] == "spread") surv(HM, -centre[1], c(lo, hi)) else surv(HT, centre[1], c(lo, hi)); s[seq_len(.N)] - s[.N + seq_len(.N)] }, by = .(game_id, market)]
  mid[, `:=`(cost = c1 + c2, ev = 1 + p_mid - c1 - c2)]
} else mid[, `:=`(p_mid = numeric(0), cost = numeric(0), ev = numeric(0))]

# --- disparity -------------------------------------------------------------------------------------------------------------------------
nv[, `:=`(n_venues = .N, med_p = stats::median(p)), by = .(game_id, market, line)]
d3 <- nv[n_venues >= 3][, dev_pp := 100 * (p - med_p)]
mtype <- function(m) fifelse(startsWith(m, "tt_"), "team_total", m)
disp_market <- d3[, .(range_pp = 100 * (max(p) - min(p))), by = .(game_id, market, line)][, .(lines = .N, median_range_pp = stats::median(range_pp),
  p90_range_pp = stats::quantile(range_pp, 0.9), max_range_pp = max(range_pp)), by = .(market = mtype(market))]
shop <- pv[, .(n = .N, best = min(cost), med = stats::median(cost), best_venue = venue[which.min(cost)]), by = .(game_id, market, line, side)][n >= 3]
shop_market <- shop[, .(sides = .N, mean_gain_cents = 100 * mean(med - best), p90_gain_cents = 100 * stats::quantile(med - best, 0.9),
                        max_gain_cents = 100 * max(med - best)), by = .(market = mtype(market))]
pin <- nv[venue == "Pinnacle", .(game_id, market, line, p_pin = p, p_pin_pow = p_pow, pin_main = main, pin_overround = overround)]
ev_pin <- merge(pv[venue != "Pinnacle"], pin, by = c("game_id", "market", "line"))
ev_pin[, `:=`(ev_prop = fifelse(side %in% c("home", "over"), p_pin, 1 - p_pin) / cost - 1,
              ev_pow = fifelse(side %in% c("home", "over"), p_pin_pow, 1 - p_pin_pow) / cost - 1)]
ev_pin[, ev := pmin(ev_prop, ev_pow)]   # the smaller of the two devigs
disp_venue <- Reduce(function(a, b) merge(a, b, by = c("venue", "market"), all = TRUE), list(
  d3[, .(lines_shared = .N, mean_abs_dev_pp = mean(abs(dev_pp)), share_dev_over_2pp = mean(abs(dev_pp) > 2)), by = .(venue, market = mtype(market))],
  nv[main == TRUE, .(median_overround_main = stats::median(overround)), by = .(venue, market = mtype(market))],
  shop[, .N, by = .(venue = best_venue, market = mtype(market))][, best_price_share := N / sum(N), by = market][, N := NULL],
  ev_pin[, .(vs_pinnacle_sides = .N, mean_ev_vs_pinnacle = mean(ev), share_ev_positive = mean(ev > 0), share_ev_over_2pct = mean(ev > 0.02)), by = .(venue, market = mtype(market))]))
coverage <- pv[, .(games = uniqueN(game_id), lines = uniqueN(paste(game_id, market, line)), quotes = .N), by = .(venue, market = mtype(market))]
main_lines <- nv[main == TRUE & !venue %in% EXCHANGES & market %in% c("spread", "total"), .(books = .N, distinct = uniqueN(line), width = max(line) - min(line)),
                 by = .(game_id, market)][, .(games = .N, share_books_disagree = mean(distinct > 1), mean_width = mean(width), max_width = max(width)), by = market]
staleness <- px[!is.na(updated), .(age_min = as.numeric(difftime(now, as.POSIXct(substr(updated, 1, 19), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC"), units = "mins"))), by = venue][
  , .(quotes = .N, median_age_min = stats::median(age_min), p90_age_min = stats::quantile(age_min, 0.9)), by = venue]

# --- outputs: aggregates (committed) and opportunity lists (private) -----------------------------------------------------------------
summ <- data.table(snapshot_utc = stamp, week = wk, games = nrow(games), first_kick_utc = format(min(games$kick), "%Y-%m-%dT%H:%MZ", tz = "UTC"),
                   venues = length(venues), quotes = nrow(pv), two_sided_markets = nrow(two), arbitrages = nrow(arbs),
                   best_arb_cents = if (nrow(arbs)) 100 * max(arbs$profit) else NA_real_, closest_two_sided_cost = min(two$sum_cost),
                   median_best_two_sided_cost = stats::median(two$sum_cost), middles = nrow(mid), middles_ev_positive = sum(mid$ev > 0),
                   best_middle_ev_cents = if (nrow(mid)) 100 * max(mid$ev) else NA_real_, sides_vs_pinnacle = nrow(ev_pin),
                   sides_ev_positive_vs_pinnacle = sum(ev_pin$ev > 0), sides_ev_over_2pct_vs_pinnacle = sum(ev_pin$ev > 0.02),
                   sides_vs_pinnacle_main = sum(ev_pin$pin_main), sides_ev_positive_vs_pinnacle_main = sum(ev_pin$pin_main & ev_pin$ev > 0),
                   sides_ev_positive_proportional_only = sum(ev_pin$ev_prop > 0 & ev_pin$ev <= 0), tie_rate_2015_2024 = tie_rate,
                   action_network_books = paste(sort(intersect(unique(px$venue), BOOKS)), collapse = "|"))
tag <- function(x) file.path(out, sprintf("%s__%s.csv", x, stamp))
fwrite(signif_dt(summ, 4), tag("snapshot_summary")); fwrite(signif_dt(disp_market, 4), tag("disparity_by_market"))
fwrite(signif_dt(disp_venue, 4), tag("disparity_by_venue")); fwrite(signif_dt(shop_market, 4), tag("line_shopping"))
fwrite(coverage, tag("coverage")); fwrite(signif_dt(main_lines, 4), tag("main_line_disagreement")); fwrite(signif_dt(staleness, 4), tag("quote_age"))
if (length(log_rows)) fwrite(rbindlist(log_rows), tag("requests"))
fwrite(arbs, file.path(raw, sprintf("arbitrages__%s.csv", stamp)))
fwrite(mid[order(-ev)], file.path(raw, sprintf("middles__%s.csv", stamp)))
fwrite(ev_pin[ev > 0][order(-ev)], file.path(raw, sprintf("ev_vs_pinnacle__%s.csv", stamp)))
options(width = 220)
print(summ); print(rbindlist(log_rows)); print(coverage[order(venue, market)], nrows = 200); print(signif_dt(disp_market, 3)); print(signif_dt(shop_market, 3))
print(signif_dt(disp_venue, 3)[order(market, venue)], nrows = 200); print(signif_dt(main_lines, 3)); print(signif_dt(staleness, 3))
cat("\narbitrages:\n"); print(arbs[, .(game_id, market, line, c1 = round(c1, 4), v1, c2 = round(c2, 4), v2, profit_cents = round(100 * profit, 2))], nrows = 50)
cat("\nbest middles:\n"); print(utils::head(mid[order(-ev)][, .(market, game_id, l1, v1, l2, v2, cost = round(cost, 4), p_mid = round(p_mid, 4), ev_cents = round(100 * ev, 2))], 15))
cat("\nlargest EV against Pinnacle's no-vig price (the smaller of the proportional and power devigs):\n")
print(utils::head(ev_pin[order(-ev)][, .(venue, game_id, market, line, side, cost = round(cost, 4), p_pin_home_over = round(p_pin, 4), pin_main, pin_overround = round(pin_overround, 3),
                                         ev_prop_pct = round(100 * ev_prop, 2), ev_pow_pct = round(100 * ev_pow, 2), size)], 20))

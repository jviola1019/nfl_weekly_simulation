# The testing program's weekly score (HYPOTHESES.md §14-15), for one 2026 week after its games. Inputs, each optional:
# - --run: a production run saved before the week's first kickoff by weekly_prospective.sh (game_predictions.json,
#   score_distributions.json, baseline_games.csv, baseline_props.csv, manifest.json);
# - --snaps: venue_snapshot.R's private prices__<stamp>.csv.gz; --decision: the snapshot stamps that are decision points
#   (default: the earliest);
# - --settled, --candles: Kalshi's settlements and hourly candles, the scored week's plus earlier weeks' (props_frame.R
#   fits its dispersion on earlier weeks).
# It scores:
# 1. games: the model's raw, blend and shown probabilities, the consensus at decision and at the close (nflverse), Kalshi's
#    close and each venue's last snapshot before kickoff, by Brier and log loss; the model's moneyline bets at each
#    venue's decision-time price, by result and by CLV to that venue's last snapshot; spreads and totals at the consensus
#    close's lines from the simulated distributions;
# 2. props: the module's projections against Kalshi's close and its 24-hour move (props_frame.R);
# 3. price-relative: each side that beat Pinnacle's no-vig price under both devigs at any snapshot before its game's last,
#    by its closing EV (Pinnacle's no-vig price at the same line in that last snapshot) and by its result.
# Prices stay private; only these aggregates are written. Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/score_week.R <out_dir> --week=<w> [--run=<dir>] [--snaps=<dir>] [--decision=<stamp>,...]
#       [--settled=<csv.gz>,...] [--candles=<csv.gz>,...]
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) { h <- grep(sprintf("^--%s=", name), args, value = TRUE)   # an empty value counts as absent
  if (length(h)) Filter(nzchar, strsplit(sub(sprintf("^--%s=", name), "", h[1]), ",", fixed = TRUE)[[1]]) else character(0) }
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
source(file.path("reports", "2026-10-29", "hypotheses", "props_frame.R"))
options(timeout = 600); set.seed(20261110)
`%||%` <- function(a, b) if (is.null(a)) b else a
WEEK <- as.integer(opt("week")); RUN <- opt("run"); SNAPS <- opt("snaps")
stopifnot(length(WEEK) == 1, is.finite(WEEK))
read_gz <- function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE))
dec <- function(o) ifelse(o < 0, 1 + 100 / -o, 1 + o / 100)
ll <- function(p, y) -mean(y * log(pmin(pmax(p, 1e-6), 1 - 1e-6)) + (1 - y) * log(1 - pmin(pmax(p, 1e-6), 1 - 1e-6)))
power_p <- function(a, b) mapply(function(x, z) x^stats::uniroot(function(k) x^k + z^k - 1, c(0.1, 50))$root, a, b)
gboot <- function(v, gid, B = 2000) { u <- unique(gid); if (length(u) < 2) return(c(NA_real_, NA_real_))
  s <- tapply(v, gid, sum)[u]; n <- tapply(v, gid, length)[u]
  b <- replicate(B, { i <- sample.int(length(u), replace = TRUE); sum(s[i]) / sum(n[i]) }); unname(stats::quantile(b, c(0.025, 0.975))) }
meta <- list(week = WEEK)

# --- the week's results ------------------------------------------------------------------------------------------------------------
sched <- as.data.table(nflreadr::load_schedules(2026))[game_type == "REG" & week == WEEK]
stopifnot(nrow(sched) > 0, all(sched$season == 2026))
sched[, kick := as.POSIXct(paste(gameday, gametime), format = "%Y-%m-%d %H:%M", tz = "America/New_York")]; attr(sched$kick, "tzone") <- "UTC"
res <- sched[!is.na(result), .(game_id, home_team, away_team, kick, result, home_score, away_score, total = home_score + away_score, spread_line, total_line,
                                home_moneyline, away_moneyline)]
res[, `:=`(y = fifelse(result > 0, 1, fifelse(result < 0, 0, 0.5)), cons_close = (1 / dec(home_moneyline)) / (1 / dec(home_moneyline) + 1 / dec(away_moneyline)))]
meta$games_played <- nrow(res)

# --- Kalshi's close, from the settlements and candles ----------------------------------------------------------------------------------
k <- NULL; st <- NULL; cn <- NULL; ev <- NULL
if (length(opt("settled")) && length(opt("candles"))) {
  st <- unique(rbindlist(lapply(opt("settled"), read_gz), fill = TRUE), by = "ticker")
  cn <- unique(rbindlist(lapply(opt("candles"), read_gz), fill = TRUE), by = "ticker")
  stopifnot(!any(substr(st$close_time, 1, 4) == "2025"))
  ev <- props_event_games(st$event_ticker, props_schedule())
  k <- merge(merge(st[, .(ticker, series, event_ticker, label, result_k = result, yk = settlement_value)], ev, by = "event_ticker")[week == WEEK],
             cn[, .(ticker, bid = bid_close, ask = ask_close)], by = "ticker")
  k <- merge(k, res[, .(game_id, home_team, away_team)], by = "game_id")
  k <- k[result_k %in% c("yes", "no") & is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid & ask - bid <= MAX_SPREAD][, mid := (bid + ask) / 2]
  k[, team := sub("^.*-([A-Z]+)[0-9]*$", "\\1", ticker)]
}
same <- function(a, b) a == b | (a == "LAR" & b == "LA") | (a == "LA" & b == "LAR") | (a == "JAC" & b == "JAX") | (a == "WSH" & b == "WAS") | (a == "LVR" & b == "LV")
kg <- if (!is.null(k)) k[series == "KXNFLGAME" & same(team, home_team), .(game_id, kalshi_close = mid)] else data.table(game_id = character(0), kalshi_close = numeric(0))

# --- the venue snapshots: each game's quotes before kickoff, and its last snapshot ---------------------------------------------------------
px <- NULL
if (length(SNAPS)) {
  pf <- sort(list.files(SNAPS, pattern = "^prices__[0-9]{8}T[0-9]{6}Z\\.csv\\.gz$", full.names = TRUE))
  if (length(pf)) {
    px <- rbindlist(lapply(pf, function(f) read_gz(f)[, stamp := sub("^prices__(.*)\\.csv\\.gz$", "\\1", basename(f))]), fill = TRUE)
    px <- px[game_id %in% res$game_id & !venue %in% c("Consensus", "Open")]
    px[, at := as.POSIXct(stamp, format = "%Y%m%dT%H%M%SZ", tz = "UTC")]
    px <- merge(px, res[, .(game_id, kick)], by = "game_id")[at < kick]
    px[, close_stamp := max(stamp), by = game_id]
    meta$snapshots <- paste(sort(unique(px$stamp)), collapse = "|")
  }
}
dec_stamps <- if (length(opt("decision"))) opt("decision") else if (!is.null(px)) min(px$stamp) else character(0)

# the outcome of a side, per $1 staked at cost c: a win pays 1/c - 1; books and Smarkets refund a push or a moneyline tie,
# and Kalshi and Polymarket pay half on a moneyline tie
side_units <- function(market, line, side, cost, venue, d) {
  margin <- d$home_score - d$away_score
  v <- fcase(market == "ml" & side == "home", sign(margin), market == "ml" & side == "away", -sign(margin),
             market == "spread" & side == "home", sign(margin + line), market == "spread" & side == "away", -sign(margin + line),
             market == "total" & side == "over", sign(d$total - line), market == "total" & side == "under", -sign(d$total - line),
             market == "tt_home" & side == "over", sign(d$home_score - line), market == "tt_home" & side == "under", -sign(d$home_score - line),
             market == "tt_away" & side == "over", sign(d$away_score - line), market == "tt_away" & side == "under", -sign(d$away_score - line))
  half <- market == "ml" & v == 0 & venue %in% c("Kalshi", "Polymarket")
  fifelse(v > 0, 1 / cost - 1, fifelse(v < 0, -1, fifelse(half, 0.5 / cost - 1, 0)))
}
outs <- list()

# --- 1. games --------------------------------------------------------------------------------------------------------------------------------
if (length(RUN)) {
  gp <- as.data.table(jsonlite::fromJSON(file.path(RUN, "game_predictions.json")))
  bg <- fread(file.path(RUN, "baseline_games.csv")); man <- jsonlite::fromJSON(file.path(RUN, "manifest.json"))
  sd <- jsonlite::fromJSON(file.path(RUN, "score_distributions.json"), simplifyVector = TRUE)
  run_at <- as.POSIXct(man$generated_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  meta$run_generated_utc <- man$generated_utc; meta$run_code <- man$code_git_sha; meta$run_code_dirty <- isTRUE(man$code_dirty)
  g <- merge(gp[candidate == "C3", .(game_id, raw = p_home_raw, final = p_home_final, cons_dec = p_home_mkt_novig)], bg[, .(game_id, blend = blend_home_prob)], by = "game_id")
  g <- merge(merge(g, res, by = "game_id"), kg, by = "game_id", all.x = TRUE)
  stopifnot(all(g$kick > run_at))   # the run came before every scored game's kickoff
  meta$games_scored <- nrow(g)
  fc <- rbind(g[, .(game_id, forecast = "simulator raw", p = raw)], g[, .(game_id, forecast = "blend", p = blend)], g[, .(game_id, forecast = "final (shown)", p = final)],
              g[, .(game_id, forecast = "consensus at decision", p = cons_dec)], g[, .(game_id, forecast = "consensus close", p = cons_close)],
              g[, .(game_id, forecast = "Kalshi close", p = kalshi_close)])
  if (!is.null(px)) {
    ml <- dcast(px[market == "ml" & wide == FALSE], venue + game_id + stamp ~ side, value.var = "cost")
    if (all(c("home", "away") %in% names(ml))) {
      ml <- ml[is.finite(home) & is.finite(away)][, p := home / (home + away)]
      vc <- merge(ml, unique(px[, .(game_id, close_stamp)]), by.x = c("game_id", "stamp"), by.y = c("game_id", "close_stamp"))
      fc <- rbind(fc, vc[game_id %in% g$game_id, .(game_id, forecast = paste(venue, "last snapshot"), p)])
    }
  }
  fc <- merge(fc, res[, .(game_id, y)], by = "game_id")[is.finite(p)]
  outs$games_accuracy <- fc[, .(games = .N, brier = mean((p - y)^2), logloss = ll(p, y)), by = forecast]
  # the model's moneyline bets at each venue's decision-time prices, and their CLV to the venue's last snapshot
  if (!is.null(px) && length(dec_stamps)) {
    q <- dcast(px[market == "ml" & stamp %in% dec_stamps], venue + game_id + stamp ~ side, value.var = "cost")
    if (all(c("home", "away") %in% names(q))) {
      q <- merge(q, g[, .(game_id, raw, blend, final)], by = "game_id")
      b <- rbindlist(lapply(c("raw", "blend", "final"), function(m) q[, .(stamp, model = m, venue, game_id, p = get(m), ch = home, ca = away)]))
      b[, `:=`(ev_h = p / ch - 1, ev_a = (1 - p) / ca - 1)]
      b[, side := fcase(is.finite(ev_h) & ev_h > 0 & (!is.finite(ev_a) | ev_h >= ev_a), "home", is.finite(ev_a) & ev_a > 0, "away", default = "none")]
      b <- b[side != "none"][, cost := fifelse(side == "home", ch, ca)]
      b <- merge(b, res[, .(game_id, home_score, away_score, total)], by = "game_id")
      b[, units := side_units("ml", 0, side, cost, venue, .SD)]
      if (exists("ml") && "p" %in% names(ml)) {
        pd <- ml[, .(venue, game_id, stamp, p_dec = p)]; pc <- merge(ml, unique(px[, .(game_id, close_stamp)]), by.x = c("game_id", "stamp"), by.y = c("game_id", "close_stamp"))[, .(venue, game_id, p_close = p)]
        b <- merge(merge(b, pd, by = c("venue", "game_id", "stamp"), all.x = TRUE), pc, by = c("venue", "game_id"), all.x = TRUE)
        b[, clv_bps := 10000 * fifelse(side == "home", p_close - p_dec, p_dec - p_close)]
      } else b[, clv_bps := NA_real_]
      outs$games_bets <- b[, .(bets = .N, wins = sum(units > 0), units = sum(units), roi = sum(units) / .N, mean_claimed_ev = mean(fifelse(side == "home", ev_h, ev_a)),
                               mean_clv_bps = mean(clv_bps, na.rm = TRUE)), by = .(stamp, model, venue)]
    }
  }
  # spreads and totals at the consensus close's lines, from the simulated distributions, at -110
  bins <- as.data.table(sd)[, rbindlist(bins), by = .(game_id, kind)]
  p_gt <- function(gid, kd, x) { bb <- bins[game_id == gid & kind == kd]; sum(bb$p[bb$x > x]) / sum(bb$p) }
  p_eq <- function(gid, kd, x) { bb <- bins[game_id == gid & kind == kd]; sum(bb$p[bb$x == x]) / sum(bb$p) }
  a <- g[is.finite(spread_line) & is.finite(total_line), .(game_id, line = spread_line, result, total, total_line)]
  a[, `:=`(q_home = mapply(function(i, l) p_gt(i, "margin", l), game_id, line) / (1 - mapply(function(i, l) p_eq(i, "margin", l), game_id, line)),
           q_over = mapply(function(i, t) p_gt(i, "total", t), game_id, total_line) / (1 - mapply(function(i, t) p_eq(i, "total", t), game_id, total_line)))]
  BE <- 110 / 210
  a[, `:=`(ats = fcase(q_home > BE, "home", 1 - q_home > BE, "away", default = "none"), ou = fcase(q_over > BE, "over", 1 - q_over > BE, "under", default = "none"))]
  a[, `:=`(ats_u = fcase(ats == "none" | result == line, 0, (ats == "home") == (result > line), 100 / 110, default = -1),
           ou_u = fcase(ou == "none" | total == total_line, 0, (ou == "over") == (total > total_line), 100 / 110, default = -1))]
  outs$games_spread_total <- data.table(market = c("spread at the consensus close, -110", "total at the consensus close, -110"),
                                        bets = c(sum(a$ats != "none"), sum(a$ou != "none")), units = c(sum(a$ats_u), sum(a$ou_u)),
                                        brier_model = c(mean((a$q_home - (a$result > a$line))[a$result != a$line]^2), mean((a$q_over - (a$total > a$total_line))[a$total != a$total_line]^2)))
  # --- 2. props --------------------------------------------------------------------------------------------------------------------------
  if (!is.null(k) && file.exists(file.path(RUN, "baseline_props.csv"))) {
    mp <- module_props(k, st, ev, WEEK, fread(file.path(RUN, "baseline_props.csv")), cn)
    outs$props_tests <- mp$tests; outs$props_bets <- mp$bets; outs$props_by_stat <- mp$by_stat; outs$props_timing <- mp$timing
    meta$props_contracts <- nrow(mp$pr)
    # the matched contracts (Kalshi's prices and our projections only), so the protocol can pool weeks after week 18
    fwrite(mp$pr[, .(ticker, game_id, stat, kk, bid, ask, mid, yk, p_mod, p_g)], file.path(out, sprintf("w%02d_props_contracts.csv.gz", WEEK)))
  }
}

# --- 3. price-relative: sides that beat Pinnacle's no-vig price, scored at the close and by result -------------------------------------------------
if (!is.null(px)) {
  pin <- dcast(px[venue == "Pinnacle" & wide == FALSE], game_id + stamp + market + line ~ side, value.var = "cost")
  for (s in c("home", "away", "over", "under")) if (!s %in% names(pin)) pin[, (s) := NA_real_]
  pin[, `:=`(c1 = fifelse(market %in% c("ml", "spread"), home, over), c2 = fifelse(market %in% c("ml", "spread"), away, under))]
  pin <- pin[is.finite(c1) & is.finite(c2)][, `:=`(p_prop = c1 / (c1 + c2), p_pow = power_p(c1, c2))][, .(game_id, stamp, market, line, p_prop, p_pow)]
  sides <- merge(px[venue != "Pinnacle"], pin, by = c("game_id", "stamp", "market", "line"))
  sides[, fair := pmin(fifelse(side %in% c("home", "over"), p_prop, 1 - p_prop), fifelse(side %in% c("home", "over"), p_pow, 1 - p_pow))]
  sides[, ev := fair / cost - 1]
  sides <- sides[stamp < close_stamp]                                         # a later snapshot is needed for the close
  pc <- pin[, .(game_id, close_stamp = stamp, market, line, pc_prop = p_prop, pc_pow = p_pow)]
  sides <- merge(sides, pc, by = c("game_id", "close_stamp", "market", "line"), all.x = TRUE)
  sides[, ev_close := pmin(fifelse(side %in% c("home", "over"), pc_prop, 1 - pc_prop), fifelse(side %in% c("home", "over"), pc_pow, 1 - pc_pow)) / cost - 1]
  sides <- merge(sides, res[, .(game_id, home_score, away_score, total)], by = "game_id")
  sides[, units := side_units(market, line, side, cost, venue, .SD)]
  summ <- function(d, label) { if (!nrow(d)) return(NULL); ci <- gboot(d$ev_close[is.finite(d$ev_close)], d$game_id[is.finite(d$ev_close)]); ri <- gboot(d$units, d$game_id)
    data.table(group = label, sides = nrow(d), games = uniqueN(d$game_id), mean_ev_at_decision = mean(d$ev), closing_ev_known = sum(is.finite(d$ev_close)),
               mean_closing_ev = mean(d$ev_close, na.rm = TRUE), closing_ev_lo = ci[1], closing_ev_hi = ci[2], share_closing_ev_positive = mean(d$ev_close > 0, na.rm = TRUE),
               roi = mean(d$units), roi_lo = ri[1], roi_hi = ri[2]) }
  first <- sides[ev > 0][order(stamp)][, .SD[1], by = .(venue, game_id, market, line, side)]
  outs$price_relative <- rbindlist(list(summ(sides[ev > 0], "beat Pinnacle at a snapshot (every snapshot)"), summ(first, "beat Pinnacle, first snapshot only"),
                                        summ(first[ev > 0.02], "beat Pinnacle by 2%+, first snapshot only"), summ(sides[ev <= 0], "every other side (reference)")))
  outs$price_relative_by_venue <- first[, .(sides = .N, mean_ev_at_decision = mean(ev), mean_closing_ev = mean(ev_close, na.rm = TRUE), roi = mean(units)), by = venue][order(-sides)]
}

fwrite(data.table(field = names(meta), value = vapply(meta, function(v) paste(v, collapse = "|"), "")), file.path(out, sprintf("w%02d_meta.csv", WEEK)))
for (nm in names(outs)) fwrite(signif_dt(outs[[nm]], 4), file.path(out, sprintf("w%02d_%s.csv", WEEK, nm)))
options(width = 220); print(meta); for (nm in names(outs)) { cat("\n==", nm, "\n"); print(signif_dt(outs[[nm]], 3)) }

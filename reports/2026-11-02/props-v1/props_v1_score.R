# nfl_props_v1's confirmatory score (PROTOCOL.md beside this file): P1-P6 one-sided, Holm at 5% over the six, then each
# hypothesis's after-cost return. It runs once, after week 18, on 2026 weeks 9-18. Every statistic is the exploration's
# own code, copied with only a filter to the scored weeks added:
#   P1, P2  kalshi_consistency.R (A3, A5)        P3  props_close.R with props_common.R's fit_one (KXNFLPASSINT)
#   P4      kalshi_behaviour.R (B1s)             P5, P6  props_frame.R's info_test and module_props' timing fit, on the
#           weekly matched contracts that score_week.R writes from the run saved before each week's first kickoff
# Run from the repository root:
#   Rscript reports/2026-11-02/props-v1/props_v1_score.R <out_dir> --weeks=<first>:<last> --settled=<csv.gz>,...
#       --candles=<csv.gz>,... --contracts=<wWW_props_contracts.csv.gz>,... --contract-candles=<csv.gz>,... [--known-answer]
# --settled, --candles: Kalshi's settlements and hourly candles (kalshi_settled.R, kalshi_candles.R) for the scored weeks
#   and the week before them (P4 looks at each player's previous game).
# --contracts: score_week.R's weekly props contracts; --contract-candles: the candles those weekly scores used (for P6's
#   24-hour price).
# --known-answer reruns the exploration (weeks 1-7; the module's week 7) to check this code against the effects the
#   protocol was built on. It skips the registration check, and its output says so. Without it the script stops unless
#   PROTOCOL.md and the registered code match backtest/eval_windows/nfl_props_v1.json and are committed unchanged.
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) { h <- grep(sprintf("^--%s=", name), args, value = TRUE)   # an empty value counts as absent
  if (length(h)) Filter(nzchar, strsplit(sub(sprintf("^--%s=", name), "", h[1]), ",", fixed = TRUE)[[1]]) else character(0) }
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
KNOWN <- "--known-answer" %in% args
wk <- as.integer(strsplit(opt("weeks"), ":", fixed = TRUE)[[1]]); stopifnot(length(wk) == 2, all(is.finite(wk)))
WEEKS <- wk[1]:wk[2]
REG <- file.path("backtest", "eval_windows", "nfl_props_v1.json")
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
source(file.path("reports", "2026-10-29", "hypotheses", "props_frame.R"))
options(timeout = 600)
SEED <- 20261102L; B <- 2000L

# --- the registration: PROTOCOL.md and every registered script unchanged and committed ----------------------------------------
git <- function(...) { o <- suppressWarnings(system2("git", c(...), stdout = TRUE, stderr = TRUE)); s <- attr(o, "status")
  list(status = if (is.null(s)) 0L else s, out = o) }
# a text file's sha256 as git stores it (LF), so a CRLF copy on Windows hashes the same
sha_lf <- function(f) { b <- readBin(f, "raw", file.size(f)); cr <- which(b == as.raw(13L))
  cr <- cr[cr < length(b) & b[pmin(cr + 1L, length(b))] == as.raw(10L)]
  digest::digest(if (length(cr)) b[-cr] else b, algo = "sha256", serialize = FALSE) }
check_registration <- function() {
  reg <- jsonlite::read_json(REG)
  files <- c(reg$protocol_path, vapply(reg$code, function(x) x$path, ""))
  want <- c(reg$protocol_sha256, vapply(reg$code, function(x) x$sha256, ""))
  for (i in seq_along(files)) {
    got <- sha_lf(files[i])
    if (!identical(got, want[i])) stop(sprintf("registration: sha256(%s) = %s, registered %s", files[i], got, want[i]), call. = FALSE)
  }
  for (f in c(files, REG)) {
    if (git("ls-files", "--error-unmatch", f)$status != 0) stop("registration: not committed: ", f, call. = FALSE)
    if (git("diff", "--quiet", "HEAD", "--", f)$status != 0) stop("registration: uncommitted changes in ", f, call. = FALSE)
  }
  if (!identical(as.integer(unlist(reg$weeks)), WEEKS)) stop("registration: --weeks must be ", paste(range(unlist(reg$weeks)), collapse = ":"), call. = FALSE)
  reg
}
reg <- if (KNOWN) NULL else check_registration()

read_gz <- function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE))
st <- unique(rbindlist(lapply(opt("settled"), read_gz), fill = TRUE), by = "ticker")
cn <- unique(rbindlist(lapply(opt("candles"), read_gz), fill = TRUE), by = "ticker")
stopifnot(!any(substr(st$close_time, 1, 4) == "2025"), !any(substr(cn$kick, 1, 4) == "2025"))   # the seal: 2026 only
sched <- props_schedule()
ev <- props_event_games(st$event_ticker, sched)
one_sided <- function(est, se, G, null = 0) stats::pt(-(est - null) / se, G - 1)   # H1: above the null
roi_ci <- function(b) { g <- unique(b$game_id); if (length(g) < 2) return(c(NA_real_, NA_real_)); set.seed(SEED)
  unname(stats::quantile(replicate(B, { bb <- b[data.table(game_id = sample(g, replace = TRUE)), on = "game_id", allow.cartesian = TRUE]
                                        sum(bb$pnl) / sum(bb$stake) }), c(0.025, 0.975))) }
econ <- function(b, measure) { if (!nrow(b)) return(data.table(econ_measure = measure, econ_n = 0L, econ_roi = NA_real_, econ_lo = NA_real_, econ_hi = NA_real_))
  ci <- roi_ci(b); data.table(econ_measure = measure, econ_n = nrow(b), econ_roi = sum(b$pnl) / sum(b$stake), econ_lo = ci[1], econ_hi = ci[2]) }
res <- list()

# --- P1 and P2: kalshi_consistency.R's A3 and A5 --------------------------------------------------------------------------------
d <- merge(st[, .(ticker, series, event_ticker, label, result, y = settlement_value)], ev, by = "event_ticker")
d <- merge(d, cn[, .(ticker, bid = bid_close, ask = ask_close)], by = "ticker")
d <- d[is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid & week %in% WEEKS]
d[, `:=`(mid = (bid + ask) / 2, seg = substring(ticker, nchar(event_ticker) + 2L),
         k = suppressWarnings(as.numeric(sub("^.*: ([0-9.]+)\\+$", "\\1", label))))]
norm <- function(x) { x <- tolower(iconv(x, to = "ASCII//TRANSLIT")); x <- gsub("[.'`-]", "", x)
  x <- gsub("\\b(jr|sr|ii|iii|iv|v)\\b", "", x); gsub("\\s+", " ", trimws(x)) }
d[, key := norm(sub(":.*$", "", label))]
base <- c("KXNFLTD", "KXNFLREC", "KXNFLRECYDS", "KXNFLRSHYDS", "KXNFLPASSYDS", "KXNFLPASSTDS")
pr <- merge(d[series %in% paste0(base, "PROT"), .(game_id, base = sub("PROT$", "", series), seg, bid_p = bid, ask_p = ask, mid_p = mid, y_p = y, result_p = result)],
            d[series %in% base, .(game_id, base = series, seg, bid_u = bid, ask_u = ask, mid_u = mid, y_u = y, result_u = result)], by = c("game_id", "base", "seg"))
pr[, `:=`(price_gap = mid_p - mid_u, payout_gap = y_p - y_u)]
prq <- pr[ask_p - bid_p <= MAX_SPREAD & ask_u - bid_u <= MAX_SPREAD]
a3_m <- stats::lm(I(payout_gap - price_gap) ~ 1, data = prq)
a3_se <- sqrt(sandwich::vcovCL(a3_m, cluster = prq$game_id, type = "HC1")[1, 1]); G3 <- uniqueN(prq$game_id); b3 <- unname(stats::coef(a3_m)[1])
maker_fee <- function(p) 0.0175 * p * (1 - p)
prq[, `:=`(pnl = payout_gap - (ask_p - bid_u) - fee(ask_p) - fee(1 - bid_u), stake = 1)]   # the taker pair, per pair
res$P1 <- cbind(data.table(id = "P1", hypothesis = "protected contracts are underpriced against their unprotected twins", n = nrow(prq), games = G3,
                           estimate = b3, lo = b3 - stats::qt(0.975, G3 - 1) * a3_se, hi = b3 + stats::qt(0.975, G3 - 1) * a3_se, p_one_sided = one_sided(b3, a3_se, G3)),
                econ(prq, "taker pair (both asks, both taker fees), pnl per pair"))
mk <- copy(prq)[, pnl := payout_gap - price_gap - maker_fee(mid_p) - maker_fee(1 - mid_u)]
res$P1[, `:=`(maker_pnl = mean(mk$pnl), maker_lo = roi_ci(mk)[1], maker_hi = roi_ci(mk)[2])]   # conditional on fills at the mids

pairs5 <- list(KXNFLLADDERREC = list(bin = "KXNFLREC", per = 0.05, cap = 20), KXNFLLADDERRECYDS = list(bin = "KXNFLRECYDS", per = 0.0025, cap = 400),
               KXNFLLADDERRSHYDS = list(bin = "KXNFLRSHYDS", per = 0.0025, cap = 400))
implied_mean <- function(k, s) {
  o <- order(k); k <- k[o]; s <- cummin(pmin(pmax(s[o], 0), 1))
  top <- max(k) + if (length(k) > 1) diff(utils::tail(k, 2)) else max(k)
  sum(stats::approx(c(0, k, top), c(1, s, 0), xout = seq_len(ceiling(top)), ties = mean)$y)
}
a5d <- rbindlist(lapply(names(pairs5), function(sc) {
  p <- pairs5[[sc]]
  scal <- d[series == sc & result == "scalar" & ask - bid <= MAX_SPREAD, .(game_id, week, key, mid_s = mid, bid_s = bid, ask_s = ask, y_s = y, per = p$per,
                                                                          realized = pmin(y / p$per, p$cap))]
  lad <- d[series == p$bin & !is.na(k) & result %in% c("yes", "no") & ask - bid <= MAX_SPREAD, .(e_ladder = implied_mean(k, mid), rungs = .N), by = .(game_id, key)][rungs >= 2]
  x <- merge(scal, lad, by = c("game_id", "key"))
  x[, `:=`(series = sc, e_scalar = mid_s / p$per)]
}), fill = TRUE)
a5_m <- stats::lm(I(realized - e_scalar) ~ I(e_ladder - e_scalar), data = a5d)
a5_se <- sqrt(sandwich::vcovCL(a5_m, cluster = a5d$game_id, type = "HC1")[2, 2]); G5 <- uniqueN(a5d$game_id); b5 <- unname(stats::coef(a5_m)[2])
a5d[, f := pmin(e_ladder * per, 1)]
a5d[, side := fcase(f > ask_s + fee(ask_s), "yes", 1 - f > 1 - bid_s + fee(1 - bid_s), "no", default = "none")]
a5d[, `:=`(pnl = fcase(side == "yes", y_s - ask_s - fee(ask_s), side == "no", bid_s - y_s - fee(1 - bid_s), default = 0),
           stake = fcase(side == "yes", ask_s + fee(ask_s), side == "no", 1 - bid_s + fee(1 - bid_s), default = 0))]
res$P2 <- cbind(data.table(id = "P2", hypothesis = "the binary ladder's mean predicts the stat beyond the scalar ladder's price", n = nrow(a5d), games = G5,
                           estimate = b5, lo = b5 - stats::qt(0.975, G5 - 1) * a5_se, hi = b5 + stats::qt(0.975, G5 - 1) * a5_se, p_one_sided = one_sided(b5, a5_se, G5)),
                econ(a5d[side != "none"], "taker on the scalar at the binary ladder's mean, return on stake"))

# --- P3: props_close.R's series fit for interceptions (slope > 1) ------------------------------------------------------------------
d3 <- merge(st[, .(ticker, series, event_ticker, label, result, y = settlement_value)], ev, by = "event_ticker", all.x = TRUE)
d3[, outcome := props_outcome(series, game_id, result, y)]
d3 <- merge(d3, cn[, .(ticker, close_end, bid = bid_close, ask = ask_close)], by = "ticker", all.x = TRUE)
d3[, `:=`(name = sub(":.*$", "", label), mid = (bid + ask) / 2, spread = ask - bid,
          hours_before = as.numeric(difftime(kick, as.POSIXct(close_end, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), units = "hours")))]
d3[, pg := paste(game_id, name)]
ok3 <- d3[outcome %in% c("settled", "payout") & is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid & spread <= MAX_SPREAD & mid > 0 & mid < 1 &
            week %in% WEEKS & series == "KXNFLPASSINT"]
f3 <- if (nrow(ok3) >= MIN_FIT && sum(ok3$y) >= 10 && sum(1 - ok3$y) >= 10) fit_one(ok3, TRUE) else NULL
res$P3 <- if (is.null(f3)) data.table(id = "P3", hypothesis = "the interception ladder is compressed (calibration slope > 1)", n = nrow(ok3), games = uniqueN(ok3$game_id),
                                      estimate = NA_real_, lo = NA_real_, hi = NA_real_, p_one_sided = 1) else {
  se3 <- (f3$slope_hi - f3$slope) / stats::qt(0.975, f3$games - 1)
  data.table(id = "P3", hypothesis = "the interception ladder is compressed (calibration slope > 1)", n = f3$contracts, games = f3$games,
             estimate = f3$slope, lo = f3$slope_lo, hi = f3$slope_hi, p_one_sided = one_sided(f3$slope, se3, f3$games, null = 1)) }
res$P3 <- cbind(res$P3, econ(data.table(game_id = character(0)), "none registered (a price relation only)"))

# --- P4: kalshi_behaviour.R's B1s ----------------------------------------------------------------------------------------------------
d4 <- merge(st[, .(ticker, series, event_ticker, label, result, y = settlement_value)], ev, by = "event_ticker")
d4[, outcome := props_outcome(series, game_id, result, y)]
d4 <- merge(d4, sched[, .(game_id, home_team, away_team)], by = "game_id")
d4 <- merge(d4, cn[, .(ticker, bid = bid_close, ask = ask_close)], by = "ticker", all.x = TRUE)
d4[, `:=`(group = group_of(series), mid = (bid + ask) / 2, spread = ask - bid)]
aliases <- function(x) c(x, switch(x, LA = c("LAR"), JAX = "JAC", WAS = "WSH", LV = "LVR", character(0)))
d4[, seg := substring(ticker, nchar(event_ticker) + 2L)]
d4[, team := vapply(seq_len(.N), function(i) {
  cand <- c(stats::setNames(aliases(home_team[i]), rep(home_team[i], length(aliases(home_team[i])))),
            stats::setNames(aliases(away_team[i]), rep(away_team[i], length(aliases(away_team[i])))))
  hit <- cand[startsWith(seg[i], cand)]
  if (length(hit)) names(hit)[which.max(nchar(hit))] else NA_character_ }, character(1))]
d4[, key := norm(sub(":.*$", "", label))]
player <- d4[group == "player" & !grepl("D/ST|No Touchdown", label) & !is.na(team)]
ok4 <- d4[outcome %in% c("settled", "payout") & is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid & spread <= MAX_SPREAD & mid > 0 & mid < 1]
okp <- ok4[ticker %in% player$ticker]
tg <- unique(player[, .(game_id, team)])[sched[, .(game_id, gameday)], on = "game_id", nomatch = 0]
setorder(tg, team, gameday)
tg[, prev_game := shift(game_id), by = team]
sn <- as.data.table(nflreadr::load_snap_counts(seasons = 2026))
if (!nrow(sn)) stop("props_v1_score: no 2026 snap counts were loaded", call. = FALSE)
stopifnot(all(sn$season == 2026))
sn <- sn[game_type == "REG", .(offense_snaps = sum(offense_snaps, na.rm = TRUE), position = position[1]), by = .(week, team, key = norm(player))]
sn[, pos_group := fcase(position %in% c("WR", "TE"), "receiver", position %in% c("RB", "FB"), "back", position == "QB", "qb", default = NA_character_)]
gw <- unique(player[, .(game_id, week, team)])
tg2 <- merge(tg, unique(gw[, .(game_id, week)]), by = "game_id")
tg2[, prev_week := shift(week), by = team]
had <- unique(player[outcome %in% c("settled", "payout"), .(game_id, team, key)])
rel <- merge(merge(tg2[!is.na(prev_game), .(game_id, week, team, prev_game, prev_week)], had[, .(prev_game = game_id, team, key)], by = c("prev_game", "team")),
             sn[offense_snaps > 0, .(prev_week = week, team, key, pos_group)], by = c("prev_week", "team", "key"))
rel <- merge(rel, sn[, .(week, team, key, snaps_now = offense_snaps)], by = c("week", "team", "key"), all.x = TRUE)
gone_s <- rel[(is.na(snaps_now) | snaps_now == 0) & !is.na(pos_group), .(game_id, team, key, pos_group)]
okp <- merge(okp, sn[, .(week, team, key, my_group = pos_group)], by = c("week", "team", "key"), all.x = TRUE)
okp[, teammate_absent_snaps := as.integer(paste(game_id, team, my_group) %in% gone_s[, paste(game_id, team, pos_group)] &
                                            !paste(game_id, team, key) %in% gone_s[, paste(game_id, team, key)])]
okp <- okp[week %in% WEEKS]   # earlier weeks only told us who played the game before
m4 <- stats::glm(y ~ offset(lg(mid)) + teammate_absent_snaps, family = stats::quasibinomial(), data = okp)
se4 <- sqrt(sandwich::vcovCL(m4, cluster = okp$game_id, type = "HC1")["teammate_absent_snaps", "teammate_absent_snaps"]); G4 <- uniqueN(okp$game_id)
b4 <- unname(stats::coef(m4)["teammate_absent_snaps"])
p4b <- okp[teammate_absent_snaps == 1][, `:=`(pnl = y - ask - fee(ask), stake = ask + fee(ask))]
res$P4 <- cbind(data.table(id = "P4", hypothesis = "position-group teammates of a player absent by snap counts are underpriced", n = nrow(okp), games = G4,
                           estimate = b4, lo = b4 - stats::qt(0.975, G4 - 1) * se4, hi = b4 + stats::qt(0.975, G4 - 1) * se4, p_one_sided = one_sided(b4, se4, G4)),
                econ(p4b, "taker buys YES at the ask on every flagged contract, return on stake"))
res$P4[, flagged := sum(okp$teammate_absent_snaps)]

# --- P5 and P6: the props module, from the weekly matched contracts ---------------------------------------------------------------
pc <- unique(rbindlist(lapply(opt("contracts"), fread), fill = TRUE), by = "ticker")
pc[, week := as.integer(substr(game_id, 6, 7))]
stopifnot(all(substr(pc$game_id, 1, 4) == "2026"))
pc <- pc[week %in% WEEKS]
t5 <- info_test(pc, "yk", "p_mod", "mid")
pc[, side := fcase(p_mod > ask + fee(ask), "yes", 1 - p_mod > 1 - bid + fee(1 - bid), "no", default = "none")]
pc[, `:=`(pnl = fcase(side == "yes", yk - ask - fee(ask), side == "no", bid - yk - fee(1 - bid), default = 0),
          stake = fcase(side == "yes", ask + fee(ask), side == "no", 1 - bid + fee(1 - bid), default = 0))]
res$P5 <- cbind(data.table(id = "P5", hypothesis = "the props module's projected means add information to Kalshi's close", n = t5$n, games = t5$games,
                           estimate = t5$coef, lo = t5$lo, hi = t5$hi, p_one_sided = t5$p_one_sided),
                econ(pc[side != "none"], "taker at the close when the module beats the ask or bid after the fee, return on stake"))
pcc <- unique(rbindlist(lapply(opt("contract-candles"), read_gz), fill = TRUE), by = "ticker")
tmv <- merge(pc[, .(ticker, game_id, mid, yk, p_mod)], pcc[, .(ticker, bid24 = bid_24h, ask24 = ask_24h)], by = "ticker")
tmv <- tmv[is.finite(bid24) & is.finite(ask24) & ask24 > 0 & ask24 >= bid24 & ask24 - bid24 <= MAX_SPREAD][, mid24 := (bid24 + ask24) / 2][mid24 > 0 & mid24 < 1]
tmv[, `:=`(move = lg(mid) - lg(mid24), lean = lg(p_mod) - lg(mid24))]
m6 <- stats::lm(move ~ lean, data = tmv); se6 <- sqrt(sandwich::vcovCL(m6, cluster = tmv$game_id, type = "HC1")["lean", "lean"]); G6 <- uniqueN(tmv$game_id)
b6 <- unname(stats::coef(m6)["lean"])
tmv[, side := fcase(p_mod - mid24 >= 0.05, "yes", p_mod - mid24 <= -0.05, "no", default = "none")]
tmv[, `:=`(pnl = fcase(side == "yes", yk - ask24 - fee(ask24), side == "no", bid24 - yk - fee(1 - bid24), default = 0),
           stake = fcase(side == "yes", ask24 + fee(ask24), side == "no", 1 - bid24 + fee(1 - bid24), default = 0))]
res$P6 <- cbind(data.table(id = "P6", hypothesis = "the props module's projection predicts Kalshi's move from 24 h before kickoff to the close", n = nrow(tmv), games = G6,
                           estimate = b6, lo = b6 - stats::qt(0.975, G6 - 1) * se6, hi = b6 + stats::qt(0.975, G6 - 1) * se6, p_one_sided = one_sided(b6, se6, G6)),
                econ(tmv[side != "none"], "taker at the 24-hour price when the module is 5+ points away, held to settlement, return on stake"))

# --- Holm over P1-P6, and the verdicts ---------------------------------------------------------------------------------------------
r <- rbindlist(res, fill = TRUE)
r[, p_holm := stats::p.adjust(p_one_sided, "holm")]
r[, `:=`(confirmed = p_holm < 0.05, economically_confirmed = p_holm < 0.05 & is.finite(econ_lo) & econ_lo > 0)]
r[, mode := if (KNOWN) "known-answer (exploration weeks; not a confirmatory result)" else "confirmatory"]
fwrite(signif_dt(r), file.path(out, "props_v1_results.csv"))
hashes <- function(fs) vapply(fs, function(f) digest::digest(file = f, algo = "sha256"), "")
meta <- data.table(field = c("mode", "weeks", "run_utc", "code_commit", "code_dirty", "protocol_sha256", "settled", "candles", "contracts", "contract_candles"),
                   value = c(r$mode[1], paste(range(WEEKS), collapse = "-"), format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), git("rev-parse", "HEAD")$out[1],
                             as.character(git("diff", "--quiet", "HEAD", "--", "reports")$status != 0), if (is.null(reg)) NA_character_ else reg$protocol_sha256,
                             paste(basename(opt("settled")), hashes(opt("settled")), collapse = "|"), paste(basename(opt("candles")), hashes(opt("candles")), collapse = "|"),
                             paste(basename(opt("contracts")), hashes(opt("contracts")), collapse = "|"),
                             paste(basename(opt("contract-candles")), hashes(opt("contract-candles")), collapse = "|")))
fwrite(meta, file.path(out, "props_v1_meta.csv"))
options(width = 220); print(signif_dt(r[, .(id, n, games, estimate, lo, hi, p_one_sided, p_holm, confirmed, econ_n, econ_roi, econ_lo, econ_hi, economically_confirmed)], 4))

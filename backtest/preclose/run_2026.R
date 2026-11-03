#!/usr/bin/env Rscript
# =============================================================================
# nfl_preclose_v1 in 2026 (PROTOCOL.md "Windows", "The Tuesday track"). 2025 enters only
# as history: its games and play-by-play feed the features and fits, and no 2025
# prediction is written or scored.
#   Rscript backtest/preclose/run_2026.R pilot <out_dir> --history=<dir> --odds=<csv> --kalshi=<csv> --weeks=1:8
#   Rscript backtest/preclose/run_2026.R predict <out_dir> --history=<dir> --week=<w>
#   Rscript backtest/preclose/run_2026.R prospective <out_dir> --history=<dir> --odds=<csv> --kalshi=<csv> --predictions=<dir>
# --history: build_history.R's private output (2025-2026 games, team_games, qb_games).
# --odds: fetch_espn_open_close.R's 2026 DraftKings opens and closes; --kalshi:
# fetch_kalshi_tuesday.R's Tuesday and closing KXNFLGAME prices (both private).
# The opener track scores PC-C2, OA[E1] (lambda from the score stage) and LM[E1] against
# DraftKings' no-vig opener; the Tuesday track scores C2 and E1 on IS-T against Kalshi's
# Tuesday mid, with CLV to Kalshi's close and a taker's return at the Tuesday ask.
# `predict` writes one week's predictions, stamped, before its games (prospective_dispatch.R
# runs it each Tuesday); `prospective` scores weeks 9-18 from those saved predictions.
# Every stage first checks the registration (PROTOCOL.md and the registered code).
# =============================================================================
suppressPackageStartupMessages(library(data.table))
for (f in c("backtest/common.R", "backtest/metrics.R", "backtest/blends.R", "backtest/candidates/elo.R", "backtest/candidates/epa_glm.R",
            "backtest/preclose/features.R", "backtest/preclose/elo.R", "backtest/preclose/candidates.R", "backtest/preclose/gates.R")) source(f)
args <- commandArgs(trailingOnly = TRUE)
stage <- args[1]; out <- args[2]
opt <- function(k) { v <- sub(sprintf("^--%s=", k), "", grep(sprintf("^--%s=", k), args, value = TRUE)); if (length(v)) v[1] else NULL }
stopifnot(stage %in% c("pilot", "predict", "prospective"), !is.null(opt("history")))
dir.create(out, recursive = TRUE, showWarnings = FALSE)
REG <- file.path("backtest", "eval_windows", "nfl_preclose_v1.json")
V1 <- jsonlite::read_json(file.path("backtest", "eval_windows", "nfl_games_v1.json"))
C1 <- list(K = 20, hfa = 30, regress = 0.45); C2 <- list(halflife = 8L, lambda = 100); SEALED <- 2025L
KALSHI_FEE <- function(p) 0.07 * p * (1 - p)

# --- the registration ---------------------------------------------------------------------------------------------------------------
sha_lf <- function(f) { b <- readBin(f, "raw", file.size(f)); cr <- which(b == as.raw(13L))
  cr <- cr[cr < length(b) & b[pmin(cr + 1L, length(b))] == as.raw(10L)]
  digest::digest(if (length(cr)) b[-cr] else b, algo = "sha256", serialize = FALSE) }
git <- function(...) { o <- suppressWarnings(system2("git", c(...), stdout = TRUE, stderr = TRUE)); s <- attr(o, "status"); list(status = if (is.null(s)) 0L else s, out = o) }
reg <- jsonlite::read_json(REG)
if (length(reg$code) == 0L) stop("registration: the scoring code is not registered yet (PROTOCOL.md: Code)", call. = FALSE)
files <- c(reg$protocol_path, vapply(reg$code, function(x) x$path, "")); want <- c(reg$protocol_sha256, vapply(reg$code, function(x) x$sha256, ""))
for (i in seq_along(files)) if (!identical(sha_lf(files[i]), want[i])) stop("registration: sha256 mismatch for ", files[i], call. = FALSE)
for (f in c(files, REG)) if (git("ls-files", "--error-unmatch", f)$status != 0 || git("diff", "--quiet", "HEAD", "--", f)$status != 0)
  stop("registration: not committed unchanged: ", f, call. = FALSE)

# --- inputs: v1's 2006-2024 and the private 2025-2026 history --------------------------------------------------------------------
inp <- bt_load_inputs(V1$data_dir, expected = V1$data_sha256)
h <- opt("history")
hg <- bt_prepare_games(fread(file.path(h, "games.csv"), colClasses = list(character = c("home_qb_id", "away_qb_id", "gametime")), na.strings = c("", "NA")))
stopifnot(all(hg$season %in% 2025:2026), !length(intersect(hg$game_id, inp$games$game_id)))
games <- rbind(inp$games, hg, fill = TRUE); setorder(games, kickoff, game_id)
tg <- rbind(inp$team_games, fread(file.path(h, "team_games.csv"))); qg <- rbind(inp$qb_games, fread(file.path(h, "qb_games.csv"), colClasses = list(character = "qb_id")))
now <- Sys.time()

#' Every 2026 prediction: the opener track (IS-A) and the Tuesday track (IS-T); OA and LM train on
#' 2023-2024 and earlier 2026 games with an opener (never 2025)
predict_2026 <- function(odds) {
  el <- pc_elo(games, C1$K, C1$hfa, C1$regress)[!game_id %in% games[season == SEALED, game_id]]
  fa <- pc_epa_features(games, tg, qg, C2$halflife, min(games$season):2026L, "A")
  pa <- pc_epa_walk_forward(fa, games, c(2023L, 2024L, 2026L), C2$lambda, "A"); setnames(pa, "p_c2", "p_pc2")
  ft <- pc_epa_features(games, tg, qg, C2$halflife, min(games$season):2026L, "T")
  pt <- pc_epa_walk_forward(ft, games, 2026L, C2$lambda, "T"); setnames(pt, "p_c2", "p_c2_t")
  d <- merge(games[season %in% c(2023L, 2024L, 2026L), .(game_id, season, week, wk, kickoff, y, home_score, away_score)], el, by = "game_id")
  d <- merge(merge(d, pa, by = "game_id", all.x = TRUE), pt, by = "game_id", all.x = TRUE)
  d[, `:=`(p_e1a = bt_e1(p_elo_a, p_pc2), p_e1_t = fifelse(is.finite(p_c2_t), bt_e1(p_elo_b, p_c2_t), NA_real_))]
  d <- merge(d, odds, by = "game_id", all.x = TRUE)[, p_close := p_close_venue]
  weeks <- merge(bt_week_schedule(games, c(2023L, 2024L, 2026L)), pc_isa_week_cutoffs(games)[, .(season, week, isa_cutoff)], by = c("season", "week"))
  weeks[, cutoff := isa_cutoff]; setorder(weeks, cutoff)
  lam <- as.numeric(fread(file.path("reports", "2026-11-02", "preclose-v1", "out", "run_meta.csv"))[field == "oa_lambda", value])
  stopifnot(length(lam) == 1L, lam %in% PC_OA_LAMBDA_GRID)
  oa <- pc_oa_walk_forward(d, weeks, lam); lm <- pc_lm_walk_forward(d, weeks)
  d <- merge(merge(d, oa[, .(game_id, p_oa)], by = "game_id", all.x = TRUE), lm[, .(game_id, p_lm, move_hat)], by = "game_id", all.x = TRUE)
  d[season == 2026L][]
}
odds_2026 <- function() {
  e <- fread(file.path("backtest", "data", "odds_archive", "espn_game_odds.csv"))[market_id == "moneyline" & venue_id == "espn_bet" & snapshot_kind %in% c("open", "close")]
  e[, key := paste(side, snapshot_kind, sep = "_")]
  e <- dcast(e, game_id ~ key, value.var = "price_american")[, .(game_id, h_open = home_open, a_open = away_open, h_close = home_close, a_close = away_close)]
  dk <- if (is.null(opt("odds"))) NULL else fread(opt("odds"))[, .(game_id, h_open, a_open, h_close, a_close)]
  o <- rbind(e, dk)
  stopifnot(!anyDuplicated(o$game_id), !any(o$game_id %like% "^2025_"))
  o[, `:=`(p_open = bt_novig_home(h_open, a_open), p_close_venue = bt_novig_home(h_close, a_close))][is.finite(p_open) & is.finite(p_close_venue)]
}
#' Kalshi's Tuesday and closing mids for the home team's KXNFLGAME contract
kalshi_home <- function() {
  k <- fread(opt("kalshi"))
  alias <- function(x) c(x, switch(x, LA = "LAR", JAX = "JAC", WAS = "WSH", LV = "LVR", character(0)))
  k[, code := sub("^.*-", "", ticker)]
  k[, is_home := mapply(function(cd, ht) cd %in% alias(ht), code, home_team)]
  k[is_home == TRUE, .(game_id, p_tue = (bid_tue + ask_tue) / 2, ask_tue, bid_tue, p_tue_state = (bid_tue_state + ask_tue_state) / 2,
                       p_kclose = (bid_close + ask_close) / 2, tue_end)]
}
#' The Tuesday track's CLV and taker return: buy the picked side's YES at its Tuesday ask (the away side as 1 - bid),
#' pay Kalshi's taker fee, hold to settlement (a tie pays half)
tuesday_clv <- function(x, col, B = PC_B, seed = PC_SEED) {
  x <- x[is.finite(get(col)) & is.finite(p_tue) & is.finite(p_kclose)]
  edge <- x[[col]] - x$p_tue; side <- fifelse(edge >= PC_TAU, "home", fifelse(edge <= -PC_TAU, "away", NA_character_)); k <- !is.na(side)
  if (!any(k)) return(data.table(picks = 0L))
  z <- x[k]; s <- side[k]
  clv <- 10000 * fifelse(s == "home", z$p_kclose - z$p_tue, z$p_tue - z$p_kclose)
  cost <- fifelse(s == "home", z$ask_tue, 1 - z$bid_tue); cost <- cost + KALSHI_FEE(cost)
  pay <- fifelse(z$home_score == z$away_score, 0.5, fifelse((s == "home") == (z$home_score > z$away_score), 1, 0))
  units <- pay / cost - 1
  wk_f <- factor(z$wk); counts <- bt_boot_counts(nlevels(wk_f), B, seed); n_w <- tabulate(as.integer(wk_f), nlevels(wk_f)); bn <- drop(counts %*% n_w)
  cb <- drop(counts %*% as.numeric(tapply(clv, wk_f, sum))) / bn; rb <- drop(counts %*% as.numeric(tapply(units, wk_f, sum))) / bn
  data.table(picks = nrow(z), mean_clv_bps = mean(clv), clv_lo = bt_quantile_ci(cb)[1], clv_hi = bt_quantile_ci(cb)[2], p_one_sided = mean(cb <= 0),
             roi = mean(units), roi_lo = bt_quantile_ci(rb)[1], roi_hi = bt_quantile_ci(rb)[2])
}
score_2026 <- function(d, label) {
  x <- d[!is.na(y) & !is.na(home_score)]
  op <- pc_score_window(x[is.finite(p_open)])
  mv <- pc_movement(x[is.finite(p_open)])
  tt <- x[is.finite(p_tue) & is.finite(p_kclose)][, `:=`(p_open = p_tue, p_close_venue = p_kclose)]
  ts <- rbindlist(lapply(c(C2 = "p_c2_t", E1 = "p_e1_t"), function(col) {
    z <- tt[is.finite(get(col))]
    s <- bt_score_window(copy(z), c(col, "p_close_venue"), "p_open", B = PC_B, seed = PC_SEED)
    cbind(data.table(track = "Tuesday", candidate = names(which(c(C2 = "p_c2_t", E1 = "p_e1_t") == col)), games = s[[col]]$n, brier = s[[col]]$brier,
                     brier_tue = s[["p_open"]]$brier, skill = s[[col]]$skill, skill_lo = s[[col]]$skill_ci[1], skill_hi = s[[col]]$skill_ci[2],
                     dm_p_better = s[[col]]$dm_p_better, slope = s[[col]]$slope, close_skill = s[["p_close_venue"]]$skill), tuesday_clv(z, col))
  }), fill = TRUE)
  # v1.1 (AMENDMENT_1_1.md): the Tuesday track's test is the CLV of tau-picks, one-sided, with BH across C2 and E1
  if ("p_one_sided" %in% names(ts)) ts[, `:=`(p_bh = stats::p.adjust(p_one_sided, "BH"), confirmed = stats::p.adjust(p_one_sided, "BH") < 0.05)]
  list(opener = op[, window := label], movement = mv[, window := label], tuesday = ts[, window := label])
}
s4 <- function(x) x[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 6) else v)]
stamp <- format(now, "%Y%m%dT%H%M%SZ", tz = "UTC")

if (stage == "predict") {
  w <- as.integer(opt("week")); stopifnot(length(w) == 1L, w %in% 1:22)
  d <- predict_2026(odds_2026())
  first_kick <- games[season == 2026L & week == w, min(kickoff)]
  p <- d[week %in% c(w, w + 1L), .(game_id, week, kickoff, p_elo_a, p_pc2, p_e1a, p_oa, p_lm, move_hat, p_elo_b, p_c2_t, p_e1_t)]
  p[, `:=`(made_utc = format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), before_first_kickoff_of_week = now < first_kick)]
  bt_write_csv(s4(p), file.path(out, sprintf("predictions_w%02d_%s.csv", w, stamp)))
  cat(sprintf("week %d: %d predictions written (weeks %d-%d), %s the week's first kickoff\n", w, nrow(p), w, w + 1L, if (now < first_kick) "before" else "AFTER"))
  quit(status = 0L)
}

od <- odds_2026(); kh <- kalshi_home()
d <- merge(predict_2026(od), kh, by = "game_id", all.x = TRUE)
if (stage == "pilot") {
  wr <- as.integer(strsplit(opt("weeks"), ":", fixed = TRUE)[[1]]); wks <- wr[1]:wr[length(wr)]
  stopifnot(all(wks <= 8L))   # the pilot is weeks 1-8; weeks 9-18 are scored only by `prospective`
  r <- score_2026(d[week %in% wks], sprintf("2026 weeks %d-%d (pilot)", min(wks), max(wks)))
  bt_write_csv(s4(r$opener), file.path(out, "pilot_opener_track.csv")); bt_write_csv(s4(r$movement), file.path(out, "pilot_lm_movement.csv"))
  bt_write_csv(s4(r$tuesday), file.path(out, "pilot_tuesday_track.csv"))
  cov <- d[week %in% wks, .(games = .N, played = sum(!is.na(y)), with_opener = sum(is.finite(p_open)), with_kalshi_tuesday = sum(is.finite(p_tue)),
                            pc2 = sum(is.finite(p_pc2)), oa = sum(is.finite(p_oa)), lm = sum(is.finite(p_lm)), c2_t = sum(is.finite(p_c2_t)))]
  bt_write_csv(cov, file.path(out, "pilot_coverage.csv"))
  options(width = 220); print(cov); print(s4(r$opener)); print(s4(r$movement)); print(s4(r$tuesday))
  quit(status = 0L)
}
# prospective: weeks 9-18 from the predictions saved before each week (the earliest saved file per game)
pf <- list.files(opt("predictions"), pattern = "^predictions_w[0-9]{2}_.*\\.csv$", full.names = TRUE)
sp <- rbindlist(lapply(pf, function(f) fread(f)[, file := basename(f)]))[before_first_kickoff_of_week == TRUE]
setorder(sp, game_id, made_utc); sp <- sp[, .SD[1], by = game_id]
keep <- c("game_id", "season", "week", "wk", "kickoff", "y", "home_score", "away_score", "p_open", "p_close_venue", "h_open", "a_open", "h_close", "a_close",
          "p_tue", "ask_tue", "bid_tue", "p_kclose")
x <- merge(d[week %in% 9:18, ..keep], sp[, .(game_id, p_pc2, p_oa, p_lm, move_hat, p_c2_t, p_e1_t)], by = "game_id")
r <- score_2026(x, "2026 weeks 9-18 (prospective, one look)")
# v1.1: the 2026 opener track is withdrawn (ESPN's 2026 DraftKings open is the preseason line); only the Tuesday track counts
bt_write_csv(s4(r$tuesday), file.path(out, "prospective_tuesday_track.csv"))
options(width = 220); print(s4(r$tuesday))

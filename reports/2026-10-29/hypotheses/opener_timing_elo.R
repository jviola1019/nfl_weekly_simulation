# Post-hoc, after T2 (PLAN.md): T2's control failed. Elo, which knows only past results, gained +210 bps at SBR's opening
# spreads, while in T1 (ESPN BET's opening moneylines) it gained nothing. Does a book's opener already know the previous
# week's results? v1's Elo (K 20, home field 30, regress 0.45) is run twice:
# - IS-B: ratings before each game, as v1 scores it (checked against v1's predictions.csv);
# - IS-A: the ratings as they stood after week w-2 of the same season (or at the season's start for weeks 1-2), which any
#   opener could know.
# Their difference is what week w-1's results taught Elo. Reported for SBR's spreads (2018-2021) and ESPN BET's moneylines
# (2023-2024):
# - each version's CLV at the opener (v1's pick rule and season-week block bootstrap, as T1 and T2);
# - the open-to-close move, (logit close - logit open), on (logit Elo IS-A - logit open) and (logit IS-B - logit IS-A),
#   clustered by season-week. If the opener already priced week w-1's results, the second coefficient is near 0; if it
#   predates them, the market moves with them during the week.
# No 2025 data. Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/opener_timing_elo.R <out_dir> --sbr=<private SBR pages> --odds=<T1's ESPN BET opens and closes>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) sub(sprintf("^--%s=", name), "", grep(sprintf("^--%s=", name), args, value = TRUE))
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
for (f in c("backtest/common.R", "backtest/metrics.R", "backtest/candidates/market.R", "backtest/candidates/elo.R",
            file.path("reports", "2026-10-29", "hypotheses", "sbr_common.R"))) source(f)
SEED <- 20260929L; TAU <- 0.03; K <- 20; HFA <- 30; REGRESS <- 0.45
options(timeout = 600)

# --- Elo, as v1 runs it (IS-B) and seeing only results through week w-2 (IS-A) --------------------------------------------------
games <- bt_prepare_games(fread(file.path("backtest", "data", "games.csv"), colClasses = list(character = c("home_qb_id", "away_qb_id", "gametime")),
                                na.strings = c("", "NA")))
stopifnot(!any(games$season == 2025))
elo_two <- function(g) {
  n <- nrow(g); teams <- sort(unique(c(g$home_franchise, g$away_franchise)))
  R <- setNames(rep(BT_ELO_MEAN, length(teams)), teams)
  pB <- pA <- numeric(n); snaps <- list(); s_now <- g$season[1]; w_now <- g$week[1]; snaps[[sprintf("%d_0", s_now)]] <- R
  for (i in seq_len(n)) {
    if (g$season[i] != s_now) {
      snaps[[sprintf("%d_%d", s_now, w_now)]] <- R
      R <- (1 - REGRESS) * R + REGRESS * BT_ELO_MEAN; s_now <- g$season[i]; w_now <- g$week[i]; snaps[[sprintf("%d_0", s_now)]] <- R
    } else if (g$week[i] != w_now) { snaps[[sprintf("%d_%d", s_now, w_now)]] <- R; w_now <- g$week[i] }
    h <- g$home_franchise[i]; a <- g$away_franchise[i]; hf <- if (g$neutral[i]) 0 else HFA
    pB[i] <- 1 / (1 + 10^(-(R[[h]] - R[[a]] + hf) / 400))
    # IS-A: the latest snapshot of this season at or before week w - 2 (the season's start if none)
    wk_have <- as.integer(sub("^[0-9]+_", "", grep(sprintf("^%d_", s_now), names(snaps), value = TRUE)))
    use <- max(wk_have[wk_have <= g$week[i] - 2L], 0L); RA <- snaps[[sprintf("%d_%d", s_now, use)]]
    pA[i] <- 1 / (1 + 10^(-(RA[[h]] - RA[[a]] + hf) / 400))
    if (is.na(g$home_score[i]) || is.na(g$away_score[i])) next
    margin <- g$home_score[i] - g$away_score[i]; result <- if (margin > 0) 1 else if (margin < 0) 0 else 0.5
    elo_diff <- R[[h]] - R[[a]] + hf
    denom <- if (result == 0.5) 1 else ((if (result == 1) elo_diff else -elo_diff) * 0.001 + 2.2)
    shift <- K * log(max(abs(margin), 1) + 1) * (2.2 / denom) * (result - pB[i])
    R[[h]] <- R[[h]] + shift; R[[a]] <- R[[a]] - shift
  }
  data.table(game_id = g$game_id, season = g$season, week = g$week, p_elo_b = pB, p_elo_a = pA)
}
el <- elo_two(games)
v1 <- bt_elo_run(games, K, HFA, REGRESS)
pr <- fread(file.path("reports", "2026-09-29", "backtest-games-v1", "predictions.csv"))[candidate %in% c("C1", "C2")]
pw <- dcast(pr, game_id ~ candidate, value.var = "p"); setnames(pw, c("C1", "C2"), c("p_c1_v1", "p_c2"))
chk <- merge(merge(el, v1, by = "game_id"), pw, by = "game_id")
same <- data.table(check = c("IS-B Elo equals bt_elo_run (max abs difference)", "IS-B Elo equals v1's C1 predictions, 2018-2024 (max abs difference)",
                             "IS-A differs from IS-B (share of 2018-2024 games)"),
                   value = c(max(abs(chk$p_elo_b - chk$p_c1)), max(abs(chk$p_elo_b - chk$p_c1_v1)), mean(abs(chk$p_elo_a - chk$p_elo_b) > 1e-12)))
stopifnot(same$value[1] < 1e-12, same$value[2] < 1e-9)

# --- the two books' openers and closes ------------------------------------------------------------------------------------------------------
sched <- sbr_schedules(); xr <- spread_exchange_rate(sched)
sb <- sbr_matched(opt("sbr"), 2018:2021, sched)$games[is.finite(home_open) & is.finite(home_close)]
sb <- sb[, .(game_id, season, week, p_open = xr$f(home_open), p_close = xr$f(home_close))]
od <- fread(opt("odds"))[market_id == "moneyline" & venue_id == "espn_bet" & snapshot_kind %in% c("open", "close")]
stopifnot(nrow(od) > 0, !any(od$season == 2025))
od[, key := paste(side, snapshot_kind, sep = "_")]
oc <- dcast(od, game_id + season + week ~ key, value.var = "price_american")
oc <- oc[, .(game_id, season, week, provider = 58L, provider_name = "ESPN BET", h_open = home_open, a_open = away_open, h_close = home_close, a_close = away_close)]
eb <- bt_market_open_close(oc)[, .(game_id, p_open, p_close = p_close_venue)]
eb <- merge(eb, unique(oc[, .(game_id, season, week)]), by = "game_id")
books <- list("SBR spreads 2018-2021" = sb, "ESPN BET moneylines 2023-2024" = eb)

clv_one <- function(x, col) {
  edge <- x[[col]] - x$p_open
  side <- fifelse(edge >= TAU, "home", fifelse(edge <= -TAU, "away", NA_character_)); k <- !is.na(side)
  clv <- 10000 * fifelse(side[k] == "home", x$p_close[k] - x$p_open[k], x$p_open[k] - x$p_close[k])
  wk_f <- factor(x$wk[k]); counts <- bt_boot_counts(nlevels(wk_f), BT_BOOT_B, SEED); n_w <- tabulate(as.integer(wk_f), nlevels(wk_f))
  b <- drop(counts %*% as.numeric(tapply(clv, wk_f, sum))) / drop(counts %*% n_w)
  data.table(picks = sum(k), mean_clv_bps = mean(clv), lo95 = stats::quantile(b, 0.025), hi95 = stats::quantile(b, 0.975), p_one_sided = mean(b <= 0))
}
lgt <- function(p) stats::qlogis(pmin(pmax(p, 0.005), 0.995))
MODELS <- c(p_elo_b = "Elo, results through week w-1 (v1's C1)", p_elo_a = "Elo, results through week w-2", p_c2 = "C2 (v1, IS-B)")
clv <- list(); mv <- list()
for (nm in names(books)) {
  x <- merge(merge(books[[nm]], el[, .(game_id, p_elo_b, p_elo_a)], by = "game_id"), pw[, .(game_id, p_c2)], by = "game_id")
  x[, wk := paste(season, sprintf("%02d", week))]
  for (col in names(MODELS)) clv[[length(clv) + 1L]] <- cbind(data.table(book = nm, model = MODELS[[col]], games = nrow(x)), clv_one(x, col))
  x[, `:=`(move = lgt(p_close) - lgt(p_open), lean_a = lgt(p_elo_a) - lgt(p_open), update = lgt(p_elo_b) - lgt(p_elo_a))]
  f <- stats::lm(move ~ lean_a + update, data = x); V <- sandwich::vcovCL(f, cluster = x$wk, type = "HC1"); G <- uniqueN(x$wk)
  for (term in c("lean_a", "update")) {
    b <- unname(stats::coef(f)[term]); se <- sqrt(V[term, term])
    mv[[length(mv) + 1L]] <- data.table(book = nm, term = c(lean_a = "Elo through w-2 minus the opener", update = "week w-1's Elo update (IS-B minus IS-A)")[[term]],
                                        games = nrow(x), clusters = G, estimate = b, lo = b - stats::qt(0.975, G - 1) * se, hi = b + stats::qt(0.975, G - 1) * se,
                                        p_two_sided = 2 * stats::pt(-abs(b / se), G - 1), r2 = summary(f)$r.squared)
  }
}
clv <- rbindlist(clv); mv <- rbindlist(mv)
s4 <- function(x) x[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 4) else v)]
fwrite(s4(same), file.path(out, "opener_timing_elo_checks.csv")); fwrite(s4(clv), file.path(out, "opener_timing_elo_clv.csv"))
fwrite(s4(mv), file.path(out, "opener_timing_elo_moves.csv"))
options(width = 220); print(same); print(s4(clv)); print(s4(mv))

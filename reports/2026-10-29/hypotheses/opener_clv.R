# Family T (timing), from the owner's request of 2026-11-02 to complete the tests: does the EPA model (C2) see where
# the line goes? nfl_games_v1 found C2's picks at the ESPN BET opener gained +93 bps of closing-line value in 2024, as a
# descriptive lead (reports/2026-09-29/backtest-games-v1/RESULT.md). This replicates the lead on 2023, a season it was
# not found in, with D1's ESPN BET 2023 openers and v1's own code: its walk-forward predictions (predictions.csv), its
# pick rule (model minus no-vig open of at least 0.03 either way) and bt_clv's CLV, flat ROI and season-week block
# bootstrap (B = 10,000, seed 20260929).
# - T1, the single pre-specified test: C2's mean CLV on 2023 is above 0 (one-sided, from the bootstrap).
# - Reported: the other decision-time candidates; 2024 recomputed, which must match RESULT.md; both seasons pooled; and
#   v1's starter caveat (PROTOCOL.md §9: C2 uses the game's actual starting QB, which the opener may not know), split by
#   whether either team's starter differs from its previous game's.
# No 2025 data. Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/opener_clv.R <out_dir> --odds=<espn_game_odds.csv> --check2024=<espn_open_close.csv>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) sub(sprintf("^--%s=", name), "", grep(sprintf("^--%s=", name), args, value = TRUE))
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
for (f in c("backtest/common.R", "backtest/metrics.R", "backtest/candidates/market.R")) source(f)
SEED <- 20260929L; TAU <- 0.03
DECISION <- c(C1 = "p_c1", C2 = "p_c2", E1 = "p_e1", "K[E1]" = "p_k_e1")

# ESPN BET moneyline opens and closes from D1's archive, in v1's espn_open_close layout
od <- fread(opt("odds"))[market_id == "moneyline" & venue_id == "espn_bet" & snapshot_kind %in% c("open", "close")]
stopifnot(nrow(od) > 0, !any(od$season == 2025))
od[, key := paste(side, snapshot_kind, sep = "_")]
stopifnot(!anyDuplicated(od[, .(game_id, key)]))
oc <- dcast(od, game_id + season + week ~ key, value.var = "price_american")
oc <- oc[, .(game_id, season, week, provider = 58L, provider_name = "ESPN BET", h_open = home_open, a_open = away_open, h_close = home_close, a_close = away_close)]
# D1's 2024 rows must agree with the inputs v1 scored
chk <- fread(opt("check2024"))[, lapply(.SD, function(v) suppressWarnings(as.numeric(sub("^\\+", "", as.character(v))))), .SDcols = c("h_open", "a_open", "h_close", "a_close"), by = game_id]
agree <- merge(oc[season == 2024, .(game_id, h_open, a_open, h_close, a_close)], chk, by = "game_id", suffixes = c("_d1", "_v1"))
agree_share <- agree[, mean(h_open_d1 == h_open_v1 & a_open_d1 == a_open_v1 & h_close_d1 == h_close_v1 & a_close_d1 == a_close_v1, na.rm = TRUE)]
mk <- bt_market_open_close(oc)

# v1's walk-forward predictions, wide, with scores and a season-week key for the block bootstrap
pr <- fread(file.path("reports", "2026-09-29", "backtest-games-v1", "predictions.csv"))
stopifnot(!any(pr$season == 2025))
pw <- dcast(pr[candidate %in% names(DECISION)], game_id + season + week ~ candidate, value.var = "p")
setnames(pw, names(DECISION), unname(DECISION))
gm <- fread(file.path("backtest", "data", "games.csv"))[, .(game_id, home_team, away_team, home_score, away_score, home_qb_id, away_qb_id, kickoff_utc)]
d <- merge(merge(pw, mk, by = "game_id"), gm, by = "game_id")[!is.na(home_score) & !is.na(away_score)]
d[, wk := paste(season, sprintf("%02d", week))]

# the starter caveat: did either team start a different QB from its previous game (any earlier season included)?
tg <- rbind(gm[, .(game_id, team = home_team, qb = home_qb_id, kickoff_utc)], gm[, .(game_id, team = away_team, qb = away_qb_id, kickoff_utc)])
setorder(tg, team, kickoff_utc)
tg[, changed := qb != shift(qb), by = team]
ch <- tg[, .(starter_changed = any(changed %in% TRUE)), by = game_id]
d <- merge(d, ch, by = "game_id", all.x = TRUE)

run <- function(x, label) rbindlist(lapply(names(DECISION), function(nm) {
  r <- bt_clv(copy(x), DECISION[[nm]], tau = TAU, seed = SEED)
  if (r$n == 0L) return(NULL)
  data.table(sample = label, candidate = nm, picks = r$n, home_picks = r$n_home, mean_clv_bps = r$mean_clv_bps, clv_lo = r$clv_ci[1], clv_hi = r$clv_ci[2],
             roi = r$roi, roi_lo = r$roi_ci[1], roi_hi = r$roi_ci[2], hit_rate = r$hit_rate)
}))
res <- rbindlist(list(run(d[season == 2024], "2024 (recomputed; must match RESULT.md)"), run(d[season == 2023], "2023 (replication)"),
                      run(d, "2023 and 2024 pooled"), run(d[starter_changed == FALSE], "both seasons, same starters as last game"),
                      run(d[starter_changed == TRUE], "both seasons, a starter changed")))
# T1: the one-sided bootstrap p of C2's mean CLV on 2023 (the share of week-block resamples at or below 0)
x23 <- d[season == 2023]; edge <- x23$p_c2 - x23$p_open
side <- ifelse(edge >= TAU, "home", ifelse(edge <= -TAU, "away", NA_character_)); keep <- !is.na(side)
clv <- 10000 * ifelse(side[keep] == "home", x23$p_close_venue[keep] - x23$p_open[keep], x23$p_open[keep] - x23$p_close_venue[keep])
wk_f <- factor(x23$wk[keep]); counts <- bt_boot_counts(nlevels(wk_f), BT_BOOT_B, SEED); n_w <- tabulate(as.integer(wk_f), nlevels(wk_f))
clv_b <- drop(counts %*% as.numeric(tapply(clv, wk_f, sum))) / drop(counts %*% n_w)
t1 <- data.table(id = "T1", test = "C2's mean CLV at the ESPN BET opener, 2023, is above 0 (one-sided)", picks = sum(keep), mean_clv_bps = mean(clv),
                 lo = stats::quantile(clv_b, 0.05), p_one_sided = mean(clv_b <= 0), games_2023 = nrow(x23), games_2024 = d[season == 2024, .N])
ovr <- d[, 1 / bt_amer_to_dec(h_open) + 1 / bt_amer_to_dec(a_open) - 1]   # the opener's margin: the two sides' implied probabilities sum to 1 plus this
data_chk <- data.table(check = c("2023 games with an ESPN BET moneyline open and close", "2024 games with one", "D1's 2024 prices identical to v1's inputs (share)",
                                 "ESPN BET's median moneyline overround at the open, 2023-2024 (bps of probability over both sides)"),
                       value = c(mk[game_id %in% d[season == 2023, game_id], .N], mk[game_id %in% d[season == 2024, game_id], .N], agree_share, 10000 * stats::median(ovr)))
# dose and response (descriptive): C2's CLV by the size of its disagreement with the opener, both seasons pooled
dr <- d[, .(game_id, season, wk, edge = p_c2 - p_open, p_open, p_close_venue)][abs(edge) >= TAU]
dr[, `:=`(band = cut(abs(edge), c(TAU, 0.05, 0.08, 1), right = FALSE, labels = c("3-5 points", "5-8 points", "8+ points")),
          clv = 10000 * fifelse(edge > 0, p_close_venue - p_open, p_open - p_close_venue))]
dose <- dr[, .(picks = .N, mean_clv_bps = mean(clv), se_bps = stats::sd(clv) / sqrt(.N)), by = band][order(band)]
fwrite(dose[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 4) else v)], file.path(out, "opener_clv_by_edge.csv"))
print(dose)
fwrite(res[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 4) else v)], file.path(out, "opener_clv.csv"))
fwrite(t1[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 4) else v)], file.path(out, "opener_clv_t1.csv"))
fwrite(data_chk, file.path(out, "opener_clv_data_checks.csv"))
options(width = 220); print(data_chk); print(t1); print(res[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 3) else v)])

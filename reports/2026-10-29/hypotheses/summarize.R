# One verdict for every hypothesis of PLAN.md, from each family's output in <out_dir>: the test's estimate, p and BH q
# within its family, the economic result where there is one, and the verdict by PLAN.md's rules (statistically
# promising: BH q < 0.05; economically promising: the return's 95% interval above 0).
# Run from the repository root:  Rscript reports/2026-10-29/hypotheses/summarize.R <out_dir>
suppressPackageStartupMessages(library(data.table))
o <- commandArgs(trailingOnly = TRUE)[1]
rd <- function(...) fread(file.path(o, ...))
v <- list()
e <- rd("classic", "classic_anomalies.csv")[period == "after the study (test)"]
v$E <- e[, .(family = "E", id, hypothesis = paste0(bet, " (", study, ")"), data = paste("nflverse", seasons), n = bets, estimate = rate, p = fifelse(id == "E10", p_roi, p_rate),
             q = q_bh, econ = roi, econ_lo = roi_lo, econ_hi = roi_hi)]
k <- rd("key", "key_numbers.csv")[model == "2015-2024, nflverse close (primary)"]
cs <- rd("consistency", "consistency_tests.csv")
a <- rbind(k[, .(family = "A", id = fcase(series == "KXNFLSPREAD", "A1", series == "KXNFLTOTAL", "A2 (totals)", default = "A2 (team totals)"),
                 hypothesis = paste("key-number model beats Kalshi's", series), data = "Kalshi 2026 w1-7, close", n = contracts, estimate = skill, p = p_model_better,
                 econ = roi, econ_lo = roi_lo, econ_hi = roi_hi)],
           cs[id == "A3", .(family = "A", id, hypothesis = "protected twins: protection premium mispriced", data = "Kalshi 2026 w1-7, close", n = pairs,
                            estimate = estimate, p = p, econ = maker_pnl_per_pair, econ_lo = maker_lo, econ_hi = maker_hi)],
           cs[id == "A5", .(family = "A", id, hypothesis = "binary ladder's mean predicts the stat beyond the scalar price", data = "Kalshi 2026 w1-7, close", n = pairs,
                            estimate = estimate, p = p, econ = roi, econ_lo = roi_lo, econ_hi = roi_hi)], fill = TRUE)
a[, q := stats::p.adjust(p, "BH")]
v$A <- a
v$A_counts <- cs[id %in% c("A4", "A6"), .(family = "A", id, hypothesis = fifelse(id == "A4", "touchdown family out of order (sure profits)", "ladder rungs out of order (sure profits)"),
                                         data = "Kalshi 2026 w1-7, close", n = fifelse(id == "A4", players, rung_pairs), estimate = sure_profits)]
b <- rd("behaviour", "behaviour_tests.csv")
v$B <- b[, .(family = "B", id, hypothesis, data = "Kalshi 2026 w1-7, close", n, estimate, p, q = q_bh)]
if (file.exists(file.path(o, "maker", "maker_taker_tests.csv"))) {
  cc <- rd("maker", "maker_taker_tests.csv")
  v$C <- cc[, .(family = "C", id, hypothesis = test, data = "Kalshi trades, sample", n, estimate, p, q = q_bh, econ = fifelse(id == "C1", estimate, NA_real_),
                econ_lo = fifelse(id == "C1", lo, NA_real_), econ_hi = fifelse(id == "C1", hi, NA_real_))]
}
lw <- rd("live", "live_wp_tests.csv")[buffer_s == 60]
dd <- data.table(family = "D", id = c("D1", "D2"), hypothesis = c("public win-probability model more accurate in-game (60 s buffer)", "model adds information to the live price (60 s buffer)"),
                 data = "Kalshi minute candles + nflfastR, 2026 w1-7", n = lw$games, estimate = c(lw$d1_estimate, lw$d2_estimate), p = c(lw$d1_p, lw$d2_p))
dd[, q := stats::p.adjust(p, "BH")]
v$D <- dd
f <- rd("cross_venue", "cross_venue_tests.csv")
v$F <- f[, .(family = "F", id, hypothesis = test, data = "DraftKings (ESPN) + Kalshi, 2026 w6-7", n = games, estimate = fifelse(id == "F1", locks, estimate), p = fifelse(id == "F2", p, NA_real_))]
v$F[id == "F2", q := p]
g <- rd("projection", "projection_tests.csv")
v$G <- g[, .(family = "G", id, hypothesis = test, data = "nflverse 2026 + Kalshi close, w2-7", n = contracts, estimate = fifelse(id == "G1", estimate, roi), p,
             q = fifelse(id == "G1", p, NA_real_), econ = fifelse(id == "G2", roi, NA_real_), econ_lo = fifelse(id == "G2", lo, NA_real_), econ_hi = fifelse(id == "G2", hi, NA_real_))]
h <- rd("opening", "opening_lines_tests.csv")
v$H <- h[, .(family = "H", id, hypothesis = test, data = "ESPN BET 2023-2024", n = games, estimate, p, q = q_bh, econ = clv_bps, econ_lo = clv_lo, econ_hi = clv_hi)]
res <- rbindlist(v, fill = TRUE)
res[, verdict := fcase(!is.na(q) & q < 0.05 & !is.na(econ_lo) & econ_lo > 0, "statistically and economically promising",
                       !is.na(q) & q < 0.05, "statistically promising, not economically (at the tested prices)",
                       !is.na(econ_lo) & econ_lo > 0, "economically positive, not significant after BH",
                       default = "not supported")]
res[id %in% c("A4", "A6", "F1"), verdict := fifelse(estimate > 0, "a few sure profits (see the counts)", "no sure profits")]
# A3's economic figure is the maker's P&L with both legs filled at the mid, which these data cannot show
res[id == "A3" & verdict == "statistically and economically promising", verdict := "statistically promising; economic only if both maker legs fill at the mid (untested)"]
fwrite(res[, lapply(.SD, function(x) if (is.numeric(x)) signif(x, 4) else x)], file.path(o, "verdicts.csv"))
options(width = 250)
print(res[, .(family, id, n, estimate = signif(estimate, 3), p = signif(p, 2), q = signif(q, 2), econ = signif(econ, 3), econ_lo = signif(econ_lo, 3), econ_hi = signif(econ_hi, 3), verdict)], nrows = 100)

# Where does the simulator's published win probability sit against the raw simulation and the no-vig market?
# For each simulator bundle (R/sim_bundle.R), per game with a market: the raw simulation (p_home_raw), the market
# (p_home_mkt_novig), the published value (p_home_final), what a plain 30/70 mix of the first two would give, and
# the blend the pipeline's shrink implies (published = 0.3 * blend + 0.7 * market, SHRINKAGE = 0.70).
# Run from the repository root:
#   Rscript reports/2026-11-10/published-vs-raw/published_vs_raw.R <bundle dir> [<bundle dir> ...]
W <- 0.70   # config.R SHRINKAGE, the weight on the market
for (dir in commandArgs(trailingOnly = TRUE)) {
  man <- jsonlite::fromJSON(file.path(dir, "manifest.json"))
  p <- jsonlite::fromJSON(file.path(dir, "game_predictions.json"))
  p <- p[p$candidate == "C3" & !is.na(p$p_home_mkt_novig) & !is.na(p$p_home_raw), ]
  lo <- pmin(p$p_home_raw, p$p_home_mkt_novig)
  hi <- pmax(p$p_home_raw, p$p_home_mkt_novig)
  out <- data.frame(game_id = p$game_id, raw = p$p_home_raw, market = p$p_home_mkt_novig, published = p$p_home_final,
                    mix_30_70 = (1 - W) * p$p_home_raw + W * p$p_home_mkt_novig,
                    implied_blend = (p$p_home_final - W * p$p_home_mkt_novig) / (1 - W),
                    outside = ifelse(p$p_home_final < lo - 1e-9 | p$p_home_final > hi + 1e-9, "OUTSIDE", ""))
  cat(sprintf("\n%s (code %s, data as of %s): %d games with a market\n", man$cycle_id, substr(man$code_git_sha, 1, 7),
              man$data_asof_utc, nrow(out)))
  num <- vapply(out, is.numeric, TRUE)
  shown <- out
  shown[num] <- lapply(out[num], function(v) sprintf("%.3f", v))
  print(shown, row.names = FALSE)
  cat(sprintf("published outside the raw-to-market range: %d of %d\n", sum(out$outside == "OUTSIDE"), nrow(out)))
  cat(sprintf("mean |gap to market|: raw %.3f, a 30/70 mix %.3f, published %.3f\n", mean(abs(out$raw - out$market)),
              mean(abs(out$mix_30_70 - out$market)), mean(abs(out$published - out$market))))
}

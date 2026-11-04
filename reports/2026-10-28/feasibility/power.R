# Can a model beat the market with statistical significance? The power side, from committed data only.
#   1. Accuracy against the close: each of #205's and #209's 39 candidates' per-game Brier differences against the
#      no-vig close on Tune 2018-2022 give the noise any accuracy test faces. That yields the minimum detectable
#      Brier skill (one-sided 5%, 80% power) at the Tune size and at every NFL game with a closing moneyline
#      through 2024, and the games each observed positive skill would need.
#   2. The opener's ceiling: ESPN BET's 2023 openers and closes (D1's archive; nfl_preclose_v1's Tune season).
#      A model that knew the close at the open would beat the opener by Brier(open) - Brier(close), the most a
#      pre-close accuracy edge can be.
# Nothing after 2024 is read. Run from the repository root with the branches fetched:
#   Rscript reports/2026-10-28/feasibility/power.R <out_dir> <ref #205> <ref #209> <ref D1>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
out <- args[1]; ref205 <- args[2]; ref209 <- args[3]; refD1 <- args[4]
dir.create(out, recursive = TRUE, showWarnings = FALSE)
git_csv <- function(ref, path) fread(text = system2("git", c("show", shQuote(sprintf("%s:%s", ref, path))), stdout = TRUE))
z <- stats::qnorm(0.95) + stats::qnorm(0.80)
say <- function(...) cat(sprintf(...), "\n", sep = "")

# --- 1. Accuracy against the close ---------------------------------------------------------------------
trk <- rbind(git_csv(ref205, "reports/2026-09-30/validation-sprint/tracking/moneyline_tune.csv")[, src := "#205"],
             git_csv(ref209, "reports/2026-10-01/blend-research/tracking/moneyline_tune_v3.csv")[, src := "#209"])
games <- fread(file.path("backtest", "data", "games.csv"))
stopifnot(max(games$season) <= 2024L)
ml <- games[is.finite(home_moneyline) & is.finite(away_moneyline) & !is.na(home_score) & home_score != away_score]
n_close <- nrow(ml)
seasons_close <- range(ml$season)
d <- trk[, .(n = .N, brier_market = mean(brier_market), mean_d = mean(brier - brier_market), sd_d = stats::sd(brier - brier_market)),
         by = .(src, candidate)]
d[, `:=`(skill = -mean_d / brier_market,
         mde_skill_tune = z * sd_d / sqrt(n) / brier_market,
         mde_skill_all = z * sd_d / sqrt(n_close) / brier_market)]
d[, games_needed := fifelse(skill > 0, ceiling((z * sd_d / (skill * brier_market))^2), NA_real_)]
setorder(d, -skill)
fwrite(d[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 5) else v)], file.path(out, "power_close.csv"))
say("# Power against the close (one-sided 5%%, 80%% power)")
say("candidates: %d; Tune games: %d; games with a closing moneyline %d-%d: %d", nrow(d), d$n[1], seasons_close[1], seasons_close[2], n_close)
say("per-game SD of the Brier difference against the close: median %.4f, range %.4f-%.4f", stats::median(d$sd_d), min(d$sd_d), max(d$sd_d))
say("minimum detectable Brier skill on Tune: median %.4f%%, range %.4f%%-%.4f%%", 100 * stats::median(d$mde_skill_tune),
    100 * min(d$mde_skill_tune), 100 * max(d$mde_skill_tune))
say("minimum detectable Brier skill on all %d games: median %.4f%%, range %.4f%%-%.4f%%", n_close, 100 * stats::median(d$mde_skill_all),
    100 * min(d$mde_skill_all), 100 * max(d$mde_skill_all))
pos <- d[skill > 0]
say("candidates with positive Tune skill: %d; best %s %+.4f%%, which would need %s games at its own noise (Tune has %d)",
    nrow(pos), pos$candidate[1], 100 * pos$skill[1], format(pos$games_needed[1], big.mark = ","), d$n[1])
say("games needed by each positive-skill candidate: %s", paste(sprintf("%s %s", pos$candidate, format(pos$games_needed, big.mark = ",")), collapse = "; "))

# --- 2. The opener's ceiling, 2023 ---------------------------------------------------------------------------
od <- git_csv(refD1, "backtest/data/odds_archive/espn_game_odds.csv")[season == 2023L & market_id == "moneyline" & is.finite(price_american)]
imp <- function(a) ifelse(a < 0, -a / (-a + 100), 100 / (a + 100))
w <- dcast(od, game_id + snapshot_kind ~ side, value.var = "price_american", fun.aggregate = function(v) v[1])
w[, p_home := imp(home) / (imp(home) + imp(away))]
pp <- dcast(w, game_id ~ snapshot_kind, value.var = "p_home")[is.finite(open) & is.finite(close)]
pp <- merge(pp, games[, .(game_id, week, kickoff_utc, y = as.integer(home_score > away_score), tie = home_score == away_score)], by = "game_id")
pp <- pp[tie == FALSE]
pp[, `:=`(br_open = (open - y)^2, br_close = (close - y)^2,
          ll_open = -(y * log(open) + (1 - y) * log(1 - open)), ll_close = -(y * log(close) + (1 - y) * log(1 - close)))]
dd <- pp$br_open - pp$br_close
tt <- stats::t.test(pp$br_open, pp$br_close, paired = TRUE)
set.seed(20261029L)
wk <- split(seq_len(nrow(pp)), pp$week)
bs <- replicate(10000L, { j <- unlist(wk[sample.int(length(wk), replace = TRUE)]); mean(dd[j]) })
move <- 1e4 * (pp$close - pp$open)
ceil <- data.table(season = 2023L, games = nrow(pp), brier_open = mean(pp$br_open), brier_close = mean(pp$br_close),
                   brier_gain = mean(dd), gain_ci_lo = stats::quantile(bs, 0.025), gain_ci_hi = stats::quantile(bs, 0.975),
                   gain_pct_of_open = 100 * mean(dd) / mean(pp$br_open), t_p_two_sided = tt$p.value,
                   logloss_open = mean(pp$ll_open), logloss_close = mean(pp$ll_close),
                   move_sd_bps = stats::sd(move), move_mean_abs_bps = mean(abs(move)), share_moved = mean(abs(move) > 0))
fwrite(ceil[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 6) else v)], file.path(out, "opener_ceiling.csv"))
say("\n# The opener's ceiling (ESPN BET moneyline, 2023, %d non-tie games with both prices)", nrow(pp))
say("Brier: open %.5f, close %.5f; the close beats the open by %.5f (week-block 95%% CI %.5f to %.5f; paired t p %.3f), %.2f%% of the open's Brier",
    ceil$brier_open, ceil$brier_close, ceil$brier_gain, ceil$gain_ci_lo, ceil$gain_ci_hi, ceil$t_p_two_sided, ceil$gain_pct_of_open)
say("log loss: open %.5f, close %.5f", ceil$logloss_open, ceil$logloss_close)
say("open-to-close move of the no-vig home probability: SD %.0f bps, mean |move| %.0f bps, %.1f%% of games moved",
    ceil$move_sd_bps, ceil$move_mean_abs_bps, 100 * ceil$share_moved)

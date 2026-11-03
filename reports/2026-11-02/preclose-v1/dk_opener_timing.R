# Exploratory, after the 2026 pilot (not part of nfl_preclose_v1's tests): is ESPN's 2026 DraftKings "open" a weekly
# opener, or the line DraftKings first posted for the game, perhaps months before? The pilot's opener-track CLV (PC-C2
# +572 bps) is several times T1's. The same check as opener_timing_elo.R: Elo through week w-1 and through w-2 at the
# opener, and the open-to-close move on what week w-1's games taught Elo; plus the move on what each team's whole 2026
# season so far taught Elo (season-start ratings to IS-B), which a preseason line could not know.
# Run from the repository root:
#   Rscript reports/2026-11-02/preclose-v1/dk_opener_timing.R <out_dir> --history=<private dir> --odds=<espn_open_close_2026.csv>
suppressPackageStartupMessages(library(data.table))
for (f in c("backtest/common.R", "backtest/metrics.R", "backtest/candidates/elo.R", "backtest/preclose/elo.R", "backtest/preclose/gates.R")) source(f)
args <- commandArgs(trailingOnly = TRUE); out <- args[1]
opt <- function(k) sub(sprintf("^--%s=", k), "", grep(sprintf("^--%s=", k), args, value = TRUE))
dir.create(out, recursive = TRUE, showWarnings = FALSE)
V1 <- jsonlite::read_json(file.path("backtest", "eval_windows", "nfl_games_v1.json"))
inp <- bt_load_inputs(V1$data_dir, expected = V1$data_sha256)
hg <- bt_prepare_games(fread(file.path(opt("history"), "games.csv"), colClasses = list(character = c("home_qb_id", "away_qb_id", "gametime")), na.strings = c("", "NA")))
games <- rbind(inp$games, hg, fill = TRUE); setorder(games, kickoff, game_id)
el <- pc_elo(games, 20, 30, 0.45)
# Elo as of the season's start for every 2026 game: the IS-A rating of a week-1 game, carried to all weeks
snap <- local({ g <- games[season <= 2026L]; R <- NULL
  n <- nrow(g); teams <- sort(unique(c(g$home_franchise, g$away_franchise))); R <- setNames(rep(BT_ELO_MEAN, length(teams)), teams); s_now <- g$season[1]
  for (i in seq_len(n)) { if (g$season[i] != s_now) { R <- 0.55 * R + 0.45 * BT_ELO_MEAN; s_now <- g$season[i] }
    if (g$season[i] == 2026L) break
    if (is.na(g$home_score[i]) || is.na(g$away_score[i])) next
    h <- g$home_franchise[i]; a <- g$away_franchise[i]; hf <- if (g$neutral[i]) 0 else 30
    p <- 1 / (1 + 10^(-(R[[h]] - R[[a]] + hf) / 400)); m <- g$home_score[i] - g$away_score[i]; r <- if (m > 0) 1 else if (m < 0) 0 else 0.5
    ed <- R[[h]] - R[[a]] + hf; den <- if (r == 0.5) 1 else ((if (r == 1) ed else -ed) * 0.001 + 2.2)
    sh <- 20 * log(max(abs(m), 1) + 1) * (2.2 / den) * (r - p); R[[h]] <- R[[h]] + sh; R[[a]] <- R[[a]] - sh }
  R })
g26 <- games[season == 2026L & !is.na(home_score)]
g26[, p_elo_0 := 1 / (1 + 10^(-(snap[home_franchise] - snap[away_franchise] + ifelse(neutral, 0, 30)) / 400))]
dk <- fread(opt("odds"))[, .(game_id, p_open = bt_novig_home(h_open, a_open), p_close = bt_novig_home(h_close, a_close), h_open, a_open)]
x <- merge(merge(g26[, .(game_id, season, week, wk, kickoff, y, home_score, away_score, p_elo_0)], el, by = "game_id"), dk, by = "game_id")
x <- x[is.finite(p_open) & is.finite(p_close)][, p_close_venue := p_close]
stopifnot(max(abs(x[week <= 2L, p_elo_0 - p_elo_a])) < 1e-9)   # weeks 1-2 on IS-A see only the season-start ratings
lgt <- function(p) stats::qlogis(pmin(pmax(p, 0.005), 0.995))
clv <- NULL
for (col in c("p_elo_0", "p_elo_a", "p_elo_b")) {
  r <- bt_clv(copy(x), col, tau = PC_TAU, B = PC_B, seed = PC_SEED)
  clv <- rbind(clv, data.table(model = col, picks = r$n, mean_clv_bps = r$mean_clv_bps, lo = r$clv_ci[1], hi = r$clv_ci[2]))
}
x[, `:=`(move = lgt(p_close) - lgt(p_open), lean_0 = lgt(p_elo_0) - lgt(p_open), season_update = lgt(p_elo_a) - lgt(p_elo_0), week_update = lgt(p_elo_b) - lgt(p_elo_a))]
f <- stats::lm(move ~ lean_0 + season_update + week_update, data = x); V <- sandwich::vcovCL(f, cluster = x$wk, type = "HC1"); G <- uniqueN(x$wk)
mv <- data.table(term = names(stats::coef(f)), estimate = unname(stats::coef(f)), se = sqrt(diag(V)))[, `:=`(lo = estimate - stats::qt(0.975, G - 1) * se, hi = estimate + stats::qt(0.975, G - 1) * se,
                                                                                                   p_two_sided = 2 * stats::pt(-abs(estimate / se), G - 1))]
mv[, `:=`(games = nrow(x), clusters = G, r2 = summary(f)$r.squared)]
by_week <- x[, .(games = .N, mean_abs_move_pp = 100 * mean(abs(p_close - p_open)), share_moved_3pp = mean(abs(p_close - p_open) >= 0.03)), by = week][order(week)]
s4 <- function(z) z[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 4) else v)]
fwrite(s4(clv), file.path(out, "dk_opener_elo_clv.csv"), eol = "\n"); fwrite(s4(mv), file.path(out, "dk_opener_moves.csv"), eol = "\n")
fwrite(s4(by_week), file.path(out, "dk_opener_moves_by_week.csv"), eol = "\n")
options(width = 200); print(s4(clv)); print(s4(mv)); print(s4(by_week))

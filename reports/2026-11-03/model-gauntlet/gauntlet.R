#!/usr/bin/env Rscript
# The NFL model gauntlet (PLAN.md): ten families and a market stack for each, selected walk-forward on 2012-2017
# and scored once on 2018-2022 against the no-vig close, with the controls that void the run on failure.
# Games after 2022 are dropped as soon as the inputs load.
#   Rscript reports/2026-11-03/model-gauntlet/gauntlet.R [--out=<dir>] [--sims=20000] [--repro=<a second run's out dir>]
# Control K5 needs two runs: the first without --repro (status "incomplete"), the second pointing at the first.
# Development only, never the scored run: --families=F1,F4 runs a subset; --select-only stops after the 2012-2017
# selection, so nothing of 2018-2022 is scored or seen.
suppressPackageStartupMessages(library(data.table))
for (f in c("common.R", "metrics.R", "controls.R", "candidates/elo.R", "candidates/epa_glm.R")) source(file.path("backtest", f))
MG_DIR <- file.path("reports", "2026-11-03", "model-gauntlet")
source(file.path(MG_DIR, "families.R"))

MG_SELECT <- 2012:2017
MG_GAUNTLET <- 2018:2022
MG_SEED <- 20261103L
MG_ALPHA <- 0.05
MG_IMPLAUSIBLE <- 0.05

args <- commandArgs(trailingOnly = TRUE)
opt <- function(k, d) { v <- sub(sprintf("^--%s=", k), "", grep(sprintf("^--%s=", k), args, value = TRUE)); if (length(v)) v[1] else d }
out_dir <- opt("out", file.path(MG_DIR, "out"))
n_sims <- as.integer(opt("sims", "20000"))
only <- opt("families", NA_character_)
select_only <- "--select-only" %in% args
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
t_start <- Sys.time()
say <- function(...) message(format(Sys.time(), "%H:%M:%S"), " ", sprintf(...))

# ---- inputs: rows after 2022 are dropped as each file is read, before any outcome or price is computed ---------
repro_dir <- opt("repro", NA_character_)
data_dir <- file.path("backtest", "data")
raw_games <- fread(file.path(data_dir, "games.csv"), na.strings = c("", "NA"),
                   colClasses = list(character = c("home_qb_id", "away_qb_id", "gametime")))[season <= max(MG_GAUNTLET)]
games <- bt_prepare_games(raw_games)
stopifnot(max(games$season) == 2022)
team_games <- fread(file.path(data_dir, "team_games.csv"), na.strings = c("", "NA"))[game_id %in% games$game_id]
qb_games <- fread(file.path(data_dir, "qb_games.csv"), na.strings = c("", "NA"))[game_id %in% games$game_id]
wanted <- if (is.na(only)) paste0("F", 1:10) else strsplit(only, ",")[[1]]
if ("F9" %in% wanted) {
  drives <- fread(file.path("backtest", "data", "drive_games.csv"))[game_id %in% games$game_id]
  drives[, kickoff := bt_parse_utc(kickoff_utc)]
}
weeks <- bt_week_schedule(games, c(MG_SELECT, MG_GAUNTLET))
wk_sel <- weeks[season %in% MG_SELECT]; wk_gnt <- weeks[season %in% MG_GAUNTLET]
target <- games[season %in% c(MG_SELECT, MG_GAUNTLET)]
scored <- function(ids, window) games[game_id %in% ids & season %in% window & !is.na(y) & is.finite(p_c0), game_id]
say("inputs: %d games to 2022, %d weeks to predict", nrow(games), nrow(weeks))

# every family returns data.table(game_id, p, margin) for the target games; `weekly()` refits at each week's cutoff
weekly <- function(fit_predict) {
  rbindlist(lapply(seq_len(nrow(weeks)), function(i) {
    tg <- target[wk == weeks$wk[i]]
    if (!nrow(tg)) return(NULL)
    r <- fit_predict(weeks$cutoff[i], tg)
    data.table(game_id = tg$game_id, p = r$p_home, margin = if (is.null(r$margin)) NA_real_ else r$margin,
               fallback = if (is.null(r$fallback)) 0L else r$fallback, sigma = if (is.null(r$sigma)) NA_real_ else r$sigma)
  }))
}
recent <- function(cutoff, years = 6) games[kickoff < cutoff & kickoff >= cutoff - years * 365.25 * 86400]

families <- list(
  F1 = list(grid = BT_ELO_GRID, run = function(s) {
    r <- bt_elo_run(games, s$K, s$hfa, s$regress); data.table(game_id = r$game_id, p = r$p_c1, margin = NA_real_) }),
  F2 = list(grid = CJ(qb_weight = c(0.5, 1, 1.5), qb_halflife = c(4, 8, 16)), run = function(s) {
    e <- MG_SELECTED$F1
    r <- mg_qb_elo_run(games, qb_games, e$K, e$hfa, e$regress, s$qb_weight, s$qb_halflife)
    data.table(game_id = r$game_id, p = r$p_home, margin = NA_real_) }),
  F3 = list(grid = BT_EPA_GRID, run = function(s) {
    f <- MG_EPA_FEATS[[as.character(s$halflife)]]
    r <- bt_epa_walk_forward(f, games, weeks, s$lambda)
    data.table(game_id = r$game_id, p = r$p_c2, margin = NA_real_) }),
  F4 = list(grid = data.table(halflife = c(4, 8, 16, 32)), run = function(s) weekly(function(cut, tg) {
    mg_ratings_predict(mg_ratings_fit(recent(cut), cut, s$halflife, "none"), tg) })),
  F5 = list(grid = CJ(halflife = c(4, 8, 16, 32), shrink = c(1, 4, 16)), run = function(s) weekly(function(cut, tg) {
    mg_ratings_predict(mg_ratings_fit(recent(cut), cut, s$halflife, "strength_free", s$shrink), tg) })),
  F6 = list(grid = data.table(halflife = c(4, 8, 16, 32)), run = function(s) weekly(function(cut, tg) {
    mg_ratings_predict(mg_ratings_fit(recent(cut), cut, s$halflife, "engine"), tg) })),
  F7 = list(grid = data.table(halflife = c(8, 16, 32)), run = function(s) weekly(function(cut, tg) {
    mg_poisson_predict(mg_poisson_fit(recent(cut), cut, s$halflife), tg) })),
  F8 = list(grid = CJ(process_sd = c(0.5, 1, 2), carry = c(0.5, 0.75, 1)), run = function(s) {
    r <- mg_kalman_run(games, s$process_sd, s$carry); data.table(game_id = r$game_id, p = r$p_home, margin = r$margin) }),
  F9 = list(grid = data.table(halflife = c(8, 16, 32)), run = function(s) weekly(function(cut, tg) {
    mg_drive_predict(mg_drive_rates(drives[kickoff >= cut - 6 * 365.25 * 86400], cut, s$halflife), tg, n_sims = n_sims) })),
  F10 = list(grid = CJ(depth = c(2, 3), rounds = c(100, 300)), run = function(s) mg_xgb_walk_forward(s))
)

# F10: trees on F1's rating difference, F3's EPA features, rest, division and neutral flags (selected F1 and F3)
mg_xgb_walk_forward <- function(s) {
  e <- MG_SELECTED$F1; h <- MG_SELECTED$F3
  elo <- bt_elo_run(games, e$K, e$hfa, e$regress)[, .(game_id, elo = 400 * log10(p_c1 / (1 - p_c1)))]
  X <- merge(MG_EPA_FEATS[[as.character(h$halflife)]], elo, by = "game_id")
  X <- merge(X, games[, .(game_id, y, div = as.numeric(div_game), neutral = as.numeric(neutral))], by = "game_id")
  cols <- c("elo", BT_EPA_FEATURES, "div", "neutral")
  setorder(X, kickoff, game_id)
  rbindlist(lapply(seq_len(nrow(weeks)), function(i) {
    tr <- X[kickoff < weeks$cutoff[i] & season >= BT_EPA_FIRST_TRAIN_SEASON & !is.na(y)]
    tg <- X[wk == weeks$wk[i]]
    if (!nrow(tg)) return(NULL)
    stopifnot(max(tr$kickoff) < weeks$cutoff[i])
    dtr <- xgboost::xgb.DMatrix(as.matrix(tr[, ..cols]), label = tr$y)
    m <- xgboost::xgb.train(params = list(objective = "binary:logistic", eta = 0.05, max_depth = s$depth, nthread = 2, seed = MG_SEED),
                            data = dtr, nrounds = s$rounds, verbose = 0)
    data.table(game_id = tg$game_id, p = predict(m, xgboost::xgb.DMatrix(as.matrix(tg[, ..cols]))), margin = NA_real_)
  }))
}

families <- families[wanted]
MG_EPA_FEATS <- lapply(setNames(nm = as.character(unique(BT_EPA_GRID$halflife))), function(h)
  bt_epa_features(games, team_games, qb_games, as.numeric(h), target_seasons = BT_EPA_FIRST_TRAIN_SEASON:max(MG_GAUNTLET)))

# ---- selection on 2012-2017, then the selected setting's predictions ---------------------------------------------
sel_ids <- scored(target$game_id, MG_SELECT)
MG_SELECTED <- list(); preds <- list(); selection <- list()
for (fam in names(families)) {
  grid <- families[[fam]]$grid
  res <- lapply(seq_len(nrow(grid)), function(j) {
    s <- grid[j]
    p <- families[[fam]]$run(s)[game_id %in% target$game_id]
    ll <- merge(p[game_id %in% sel_ids], games[, .(game_id, y)], by = "game_id")[, mean(bt_logloss_vec(p, y))]
    list(s = s, p = p, ll = ll)
  })
  lls <- vapply(res, `[[`, numeric(1), "ll")
  best <- which.min(lls)   # grids are ordered simplest first, so a tie goes to the simpler setting
  MG_SELECTED[[fam]] <- grid[best]
  preds[[fam]] <- res[[best]]$p
  selection[[fam]] <- cbind(family = fam, grid, logloss_2012_2017 = lls, selected = seq_along(lls) == best)
  say("%s: selected %s (log loss %.5f over %d settings)", fam, paste(names(grid), unlist(grid[best]), sep = "=", collapse = " "), lls[best], nrow(grid))
}
bt_write_csv(rbindlist(selection, fill = TRUE), file.path(out_dir, "selection.csv"))
if (select_only || !is.na(only)) {
  say("development run: selection only, 2018-2022 not scored")
  quit(save = "no", status = 0)
}

# ---- stacks: S[F] fitted on every scored game before the predicted week ------------------------------------------
all_p <- Reduce(function(a, b) merge(a, b, by = "game_id", all = TRUE),
                lapply(names(preds), function(f) setnames(copy(preds[[f]][, .(game_id, p)]), "p", f)))
all_p <- merge(games[game_id %in% target$game_id, .(game_id, season, wk, kickoff, y, p_c0, spread_line,
                                                     margin = home_score - away_score)], all_p, by = "game_id")
setorder(all_p, kickoff, game_id)
stack_walk <- function(col) {
  out <- rep(NA_real_, nrow(all_p))
  for (i in seq_len(nrow(wk_gnt))) {
    tr <- all_p[kickoff < wk_gnt$cutoff[i] & !is.na(y) & is.finite(p_c0) & is.finite(get(col))]
    at <- which(all_p$wk == wk_gnt$wk[i] & is.finite(all_p$p_c0) & is.finite(all_p[[col]]))
    if (!length(at)) next
    fit <- mg_stack_fit(tr$p_c0, tr[[col]], tr$y, lambda = 0)   # maximum likelihood, as PLAN.md registers
    out[at] <- mg_stack_predict(fit, all_p$p_c0[at], all_p[[col]][at])
  }
  out
}
for (fam in names(preds)) all_p[, (paste0("S_", fam)) := stack_walk(fam)]
say("stacks fitted")

# ---- controls ------------------------------------------------------------------------------------------------------
old_seed <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
set.seed(MG_SEED, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
all_p[, leak := stats::pnorm((margin + stats::rnorm(.N, 0, 7)) / 13.5)]                # K1: final margin + noise
all_p[, K2_market_copy := bt_expit(bt_logit(bt_clip(p_c0)) + stats::rnorm(.N, 0, 0.1))]
if (is.null(old_seed)) rm(".Random.seed", envir = globalenv()) else assign(".Random.seed", old_seed, envir = globalenv())
k1a <- tryCatch({ bt_assert_asof(all_p$kickoff + 3.5 * 3600, all_p$kickoff, "leak canary"); FALSE },
                error = function(e) grepl("as-of violation", conditionMessage(e)))
all_p[, K1_leak_stack := stack_walk("leak")]
games_scores_check <- games$home_score
sh <- bt_shuffle_scores(games, seed = BT_SHUFFLE_SEED)
e <- MG_SELECTED$F1; r4 <- MG_SELECTED$F4
all_p <- merge(all_p, bt_elo_run(sh, e$K, e$hfa, e$regress)[, .(game_id, K3_shuffled_F1 = p_c1)], by = "game_id", all.x = TRUE)
# the family closures read `games` from this environment: run F4 on the shuffled table, restoring it even on error
with_games <- function(g, fn) {
  true_games <- games
  on.exit(assign("games", true_games, envir = globalenv()), add = TRUE)
  assign("games", g, envir = globalenv())
  fn()
}
k3f4 <- with_games(sh, function() families$F4$run(r4))[, .(game_id, K3_shuffled_F4 = p)]
stopifnot(identical(games$home_score, games_scores_check))
all_p <- merge(all_p, k3f4, by = "game_id", all.x = TRUE)
setorder(all_p, kickoff, game_id)

# ---- score the gauntlet window once -------------------------------------------------------------------------------
cands <- c(names(preds), paste0("S_", names(preds)))
controls <- c("K1_leak_stack", "K2_market_copy", "K3_shuffled_F1", "K3_shuffled_F4")
d <- all_p[season %in% MG_GAUNTLET & !is.na(y) & is.finite(p_c0)]
keep <- d[, Reduce(`&`, lapply(c(cands, controls), function(cc) is.finite(get(cc))))]
if (any(!keep)) say("dropping %d games without every candidate's prediction", sum(!keep))
d <- d[keep]
score <- function(cols) {
  res <- bt_score_window(copy(d), cols, "p_c0", B = BT_BOOT_B, seed = MG_SEED)
  rbindlist(lapply(names(res), function(cc) with(res[[cc]], data.table(
    candidate = cc, n = n, weeks = weeks, brier = brier, logloss = logloss, ece = ece, slope = slope,
    skill = skill, skill_lo = skill_ci[1], skill_hi = skill_ci[2],
    brier_diff = brier_diff, brier_diff_lo = brier_diff_ci[1], brier_diff_hi = brier_diff_ci[2],
    logloss_diff = logloss_diff, logloss_diff_lo = logloss_diff_ci[1], logloss_diff_hi = logloss_diff_ci[2],
    dm_stat = dm_stat, dm_p_better = dm_p_better))))
}
res <- score(cands)
res[candidate != "p_c0", p_holm := stats::p.adjust(dm_p_better, method = "holm")]
res[, pass := candidate != "p_c0" & p_holm < MG_ALPHA & brier_diff_hi < 0]
mae <- function(col) if (all(is.na(preds[[col]]$margin))) NA_real_ else
  merge(d[, .(game_id, margin)], preds[[col]][, .(game_id, m = margin)], by = "game_id")[, mean(abs(m - margin))]
res[, margin_mae := vapply(candidate, function(cc) if (cc %in% names(preds)) mae(cc) else NA_real_, numeric(1))]
res[candidate == "p_c0", margin_mae := d[, mean(abs(spread_line - margin))]]
ctl <- score(controls)
ctl[candidate != "p_c0", p_holm := stats::p.adjust(dm_p_better, method = "holm")]
ctl[, pass := candidate != "p_c0" & p_holm < MG_ALPHA & brier_diff_hi < 0]

# ---- controls decide whether the run counts -------------------------------------------------------------------------
cv <- data.table(
  control = c("K1a leak rejected by the as-of assertion", "K1b leak stack passes", "K2 market copy does not pass",
              "K3 shuffled F1 does not pass", "K3 shuffled F4 does not pass", "K4 no implausible skill"),
  passed = c(k1a, ctl[candidate == "K1_leak_stack", pass], !ctl[candidate == "K2_market_copy", pass],
             !ctl[candidate == "K3_shuffled_F1", pass], !ctl[candidate == "K3_shuffled_F4", pass],
             !any(res[candidate != "p_c0", skill] > MG_IMPLAUSIBLE)))
num <- function(x) bt_round(x, 10)
res_out <- res[, lapply(.SD, function(x) if (is.numeric(x)) num(x) else x)]
bt_write_csv(res_out, file.path(out_dir, "results.csv"))
sha <- function(p) digest::digest(file = p, algo = "sha256")
# K5: a second, independent run must have written byte-identical results (--repro=<its out dir>)
k5 <- if (is.na(repro_dir)) NA else {
  other <- fread(file.path(repro_dir, "run_meta.csv"))
  identical(other[field == "result_sha256", value], sha(file.path(out_dir, "results.csv")))
}
cv <- rbind(cv, data.table(control = "K5 a second run gives the same result sha256", passed = k5))
status <- if (anyNA(cv$passed)) "incomplete: K5 not checked (run again with --repro=<a second run's out dir>)" else
  if (all(cv$passed)) "valid" else "void"
bt_write_csv(ctl[, lapply(.SD, function(x) if (is.numeric(x)) num(x) else x)], file.path(out_dir, "controls_scored.csv"))
bt_write_csv(cv, file.path(out_dir, "controls.csv"))
bt_write_csv(all_p[season %in% MG_GAUNTLET, c("game_id", "season", "wk", "y", "p_c0", cands), with = FALSE][
  , lapply(.SD, function(x) if (is.numeric(x)) num(x) else x)], file.path(out_dir, "predictions_2018_2022.csv"))
# fallbacks (a team with no history, predicted at league values) and the smallest fitted margin SD, per family
fb <- vapply(names(preds), function(f) sum(preds[[f]]$fallback, na.rm = TRUE), numeric(1))
min_sigma <- vapply(names(preds), function(f) suppressWarnings(min(preds[[f]]$sigma, na.rm = TRUE)), numeric(1))
if (any(fb > 0)) say("fallbacks to league values: %s", paste(sprintf("%s=%d", names(fb)[fb > 0], fb[fb > 0]), collapse = ", "))
code <- c(file.path(MG_DIR, c("PLAN.md", "families.R", "gauntlet.R")), file.path("backtest", c("common.R", "metrics.R", "controls.R", "candidates/elo.R", "candidates/epa_glm.R")))
inputs <- file.path("backtest", "data", c("games.csv", "team_games.csv", "qb_games.csv", "drive_games.csv"))
meta <- data.table(field = c("status", "run_utc", "seconds", "n_scored", "n_sims", "result_sha256",
                             paste0("fallbacks:", names(fb)), paste0("min_sigma:", names(min_sigma)[is.finite(min_sigma)]),
                             paste0("sha256:", c(code, inputs))),
                   value = c(status, format(t_start, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), round(as.numeric(difftime(Sys.time(), t_start, units = "secs"))),
                             nrow(d), n_sims, sha(file.path(out_dir, "results.csv")), as.character(fb),
                             as.character(round(min_sigma[is.finite(min_sigma)], 4)), vapply(c(code, inputs), sha, "")))
bt_write_csv(meta, file.path(out_dir, "run_meta.csv"))
say("status %s; %d games scored; %d of %d candidates pass; result sha256 %s", status, nrow(d), sum(res$pass), length(cands),
    sha(file.path(out_dir, "results.csv")))
print(res_out[, .(candidate, brier, brier_diff, brier_diff_lo, brier_diff_hi, logloss_diff, p_holm, pass, margin_mae)])
print(cv)

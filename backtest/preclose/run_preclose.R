#!/usr/bin/env Rscript
# =============================================================================
# nfl_preclose_v1 (reports/2026-11-02/preclose-v1/PROTOCOL.md).
#   Rscript backtest/preclose/run_preclose.R known-answer <out_dir>
#     v1's C2 rebuilt with this code on IS-B equals predictions.csv; Elo on IS-B equals
#     bt_elo_run and on IS-A reproduces opener_timing_elo.R's ESPN BET CLV; bt_clv
#     reproduces T1's 2023 number. No IS-A C2 is computed.
#   Rscript backtest/preclose/run_preclose.R score <out_dir>
#     Tune 2023 (OA's lambda) and Confirm 2024: every candidate, the gates P1-P5 and P7,
#     and the P6 controls. Refuses unless PROTOCOL.md and the registered code match
#     backtest/eval_windows/nfl_preclose_v1.json and are committed unchanged.
# Inputs: v1's backtest/data (2006-2024, sha256-locked) and D1's ESPN BET archive
# (backtest/data/odds_archive). The 2025 Holdout is never built or read here.
# =============================================================================
suppressPackageStartupMessages(library(data.table))
for (f in c("backtest/common.R", "backtest/metrics.R", "backtest/blends.R", "backtest/candidates/elo.R", "backtest/candidates/epa_glm.R",
            "backtest/candidates/market.R", "backtest/preclose/features.R", "backtest/preclose/elo.R", "backtest/preclose/candidates.R",
            "backtest/preclose/gates.R")) source(f)
args <- commandArgs(trailingOnly = TRUE)
stage <- args[1]; out <- args[2]
stopifnot(stage %in% c("known-answer", "score"), length(out) == 1L, !is.na(out))
dir.create(out, recursive = TRUE, showWarnings = FALSE)
REG <- file.path("backtest", "eval_windows", "nfl_preclose_v1.json")
V1 <- jsonlite::read_json(file.path("backtest", "eval_windows", "nfl_games_v1.json"))
C1 <- list(K = 20, hfa = 30, regress = 0.45); C2 <- list(halflife = 8L, lambda = 100)
TUNE <- 2023L; CONFIRM <- 2024L

# --- inputs ----------------------------------------------------------------------------------------------------------------------
inp <- bt_load_inputs(V1$data_dir, expected = V1$data_sha256)
games <- inp$games; stopifnot(max(games$season) <= 2024L)
od <- fread(file.path("backtest", "data", "odds_archive", "espn_game_odds.csv"))[market_id == "moneyline" & venue_id == "espn_bet" & snapshot_kind %in% c("open", "close")]
stopifnot(nrow(od) > 0, all(od$season %in% c(2023L, 2024L)))
od[, key := paste(side, snapshot_kind, sep = "_")]
stopifnot(!anyDuplicated(od[, .(game_id, key)]))
oc <- dcast(od, game_id + season + week ~ key, value.var = "price_american")
oc <- oc[, .(game_id, season, week, provider = 58L, provider_name = "ESPN BET", h_open = home_open, a_open = away_open, h_close = home_close, a_close = away_close)]
mk <- bt_market_open_close(oc)

sha_lf <- function(f) { b <- readBin(f, "raw", file.size(f)); cr <- which(b == as.raw(13L))
  cr <- cr[cr < length(b) & b[pmin(cr + 1L, length(b))] == as.raw(10L)]
  digest::digest(if (length(cr)) b[-cr] else b, algo = "sha256", serialize = FALSE) }
write_out <- function(x, name) bt_write_csv(x[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 6) else v)], file.path(out, name))

# --- known answers -------------------------------------------------------------------------------------------------------------------
if (stage == "known-answer") {
  pr <- fread(file.path("reports", "2026-09-29", "backtest-games-v1", "predictions.csv"))[candidate %in% c("C1", "C2")]
  fb <- pc_epa_features(games, inp$team_games, inp$qb_games, C2$halflife, min(games$season):2024L, "B")
  c2b <- pc_epa_walk_forward(fb, games, 2018:2024, C2$lambda, "B")
  k1 <- merge(c2b, pr[candidate == "C2", .(game_id, p_v1 = p)], by = "game_id")
  el <- pc_elo(games, C1$K, C1$hfa, C1$regress)
  k2 <- merge(merge(el, bt_elo_run(games, C1$K, C1$hfa, C1$regress), by = "game_id"), pr[candidate == "C1", .(game_id, p_v1 = p)], by = "game_id")
  d <- merge(merge(mk, games[, .(game_id, season, week, wk, kickoff, home_score, away_score, y)], by = "game_id"), el, by = "game_id")
  d <- merge(d, pr[candidate == "C2", .(game_id, p_c2 = p)], by = "game_id")
  ea <- bt_clv(copy(d), "p_elo_a", tau = PC_TAU, B = PC_B, seed = PC_SEED)
  t1 <- bt_clv(copy(d[season == 2023]), "p_c2", tau = PC_TAU, B = PC_B, seed = PC_SEED)
  ka_elo <- fread(file.path("reports", "2026-10-29", "hypotheses", "out", "timing", "opener_timing_elo_clv.csv"))[book == "ESPN BET moneylines 2023-2024" & model == "Elo, results through week w-2"]
  ka_t1 <- fread(file.path("reports", "2026-10-29", "hypotheses", "out", "timing", "opener_clv_t1.csv"))
  ka <- data.table(check = c("C2 on IS-B equals v1's predictions, 2018-2024 (max abs difference)", "C2 on IS-B: games compared",
                             "Elo on IS-B equals bt_elo_run (max abs difference)", "Elo on IS-B equals v1's C1 (max abs difference)",
                             "Elo on IS-A at ESPN BET 2023-2024: picks (opener_timing_elo.R)", "Elo on IS-A at ESPN BET 2023-2024: mean CLV bps",
                             "T1: C2's picks at ESPN BET 2023", "T1: mean CLV bps"),
                   got = c(max(abs(k1$p_c2 - k1$p_v1)), nrow(k1), max(abs(k2$p_elo_b - k2$p_c1)), max(abs(k2$p_elo_b - k2$p_v1)),
                           ea$n, ea$mean_clv_bps, t1$n, t1$mean_clv_bps),
                   want = c(0, nrow(pr[candidate == "C2"]), 0, 0, ka_elo$picks, ka_elo$mean_clv_bps, ka_t1$picks, ka_t1$mean_clv_bps))
  ka[, passed := c(got[1] < 1e-8, got[2] == want[2], got[3] < 1e-12, got[4] < 1e-9, got[5] == want[5], abs(got[6] - want[6]) < 0.01 * abs(want[6]) + 0.05,
                   got[7] == want[7], abs(got[8] - want[8]) < 0.01 * abs(want[8]) + 0.05)]
  write_out(ka, "known_answer.csv"); print(ka)
  if (!all(ka$passed)) quit(status = 1L)
  quit(status = 0L)
}

# --- score: the registration first -----------------------------------------------------------------------------------------------------
git <- function(...) { o <- suppressWarnings(system2("git", c(...), stdout = TRUE, stderr = TRUE)); s <- attr(o, "status"); list(status = if (is.null(s)) 0L else s, out = o) }
reg <- jsonlite::read_json(REG)
files <- c(reg$protocol_path, vapply(reg$code, function(x) x$path, ""))
want <- c(reg$protocol_sha256, vapply(reg$code, function(x) x$sha256, ""))
if (length(reg$code) == 0L) stop("registration: the scoring code is not registered yet (PROTOCOL.md: Code)", call. = FALSE)
for (i in seq_along(files)) if (!identical(sha_lf(files[i]), want[i])) stop("registration: sha256 mismatch for ", files[i], call. = FALSE)
for (f in c(files, REG)) {
  if (git("ls-files", "--error-unmatch", f)$status != 0) stop("registration: not committed: ", f, call. = FALSE)
  if (git("diff", "--quiet", "HEAD", "--", f)$status != 0) stop("registration: uncommitted changes in ", f, call. = FALSE)
}

#' Every candidate on the scored seasons; `games` may carry a replaced y (the anchor null),
#' `perm` permutes a model column within week before the anchored fits (the permuted-x null)
core <- function(games, perm = NULL, perm_seed = 20261028L) {
  el <- pc_elo(games, C1$K, C1$hfa, C1$regress)
  fa <- pc_epa_features(games, inp$team_games, inp$qb_games, C2$halflife, min(games$season):2024L, "A")
  pc2 <- pc_epa_walk_forward(fa, games, c(TUNE, CONFIRM), C2$lambda, "A")
  setnames(pc2, "p_c2", "p_pc2")
  d <- merge(games[season %in% c(TUNE, CONFIRM), .(game_id, season, week, wk, kickoff, y, home_score, away_score)], mk, by = "game_id")
  d <- merge(merge(d, el[, .(game_id, p_elo_a)], by = "game_id"), pc2, by = "game_id")
  d[, p_e1a := bt_e1(p_elo_a, p_pc2)]
  d[, p_close := p_close_venue]
  if (!is.null(perm)) {
    old <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
    set.seed(perm_seed)
    for (cc in perm) d[, (cc) := if (.N > 1L) get(cc)[sample.int(.N)] else get(cc), by = wk]
    if (is.null(old)) rm(".Random.seed", envir = globalenv()) else assign(".Random.seed", old, envir = globalenv())
  }
  weeks <- merge(bt_week_schedule(games, c(TUNE, CONFIRM)), pc_isa_week_cutoffs(games)[, .(season, week, isa_cutoff)], by = c("season", "week"))
  weeks[, cutoff := isa_cutoff]; setorder(weeks, cutoff)
  # OA's lambda: walk-forward log loss on Tune, on the games every lambda predicts; first in grid order on ties
  oa_all <- lapply(PC_OA_LAMBDA_GRID, function(l) pc_oa_walk_forward(d, weeks, l))
  common <- Reduce(intersect, lapply(oa_all, function(o) o[game_id %in% d[season == TUNE & !is.na(y), game_id], game_id]))
  tune_loss <- vapply(oa_all, function(o) { z <- merge(o[game_id %in% common], d[, .(game_id, y)], by = "game_id"); mean(bt_logloss_vec(z$p_oa, z$y)) }, numeric(1))
  lam <- PC_OA_LAMBDA_GRID[which.min(tune_loss)]
  oa <- oa_all[[which.min(tune_loss)]]
  lm <- pc_lm_walk_forward(d, weeks)
  d <- merge(merge(d, oa[, .(game_id, p_oa, oa_b_open, oa_b_model, oa_train)], by = "game_id", all.x = TRUE),
             lm[, .(game_id, p_lm, move_hat, lm_b, lm_train)], by = "game_id", all.x = TRUE)
  list(d = d[], lambda = lam, tune_loss = data.table(lambda = PC_OA_LAMBDA_GRID, tune_logloss = tune_loss, games = length(common)))
}
score_all <- function(r) {
  x <- r$d[!is.na(y)]
  list(tune = pc_score_window(x[season == TUNE]), confirm = pc_score_window(x[season == CONFIRM]),
       move_tune = pc_movement(x[season == TUNE]), move_confirm = pc_movement(x[season == CONFIRM]))
}
result_sha <- function(s) digest::digest(paste(vapply(s, function(t) paste(capture.output(fwrite(t[, lapply(.SD, function(v) if (is.numeric(v)) round(v, 10) else v)])),
                                                                         collapse = "\n"), ""), collapse = "\n"), algo = "sha256", serialize = FALSE)

run <- core(games)
sc <- score_all(run)
sha1 <- result_sha(sc)

# --- P6, the controls ------------------------------------------------------------------------------------------------------------------
controls <- list()
# leak canary: a 99-0 game a week after the last one changes no earlier IS-A feature or Elo
last <- games[which.max(kickoff)]
cg <- copy(last)[, `:=`(game_id = "CANARY_GAME", kickoff = kickoff + 7 * 86400, week = week + 1L, home_score = 99L, away_score = 0L, y = 1L)]
cg[, wk := season * 100L + week]
g2 <- rbind(games, cg, fill = TRUE); setorder(g2, kickoff, game_id)
tg2 <- rbind(inp$team_games, copy(inp$team_games[game_id == last$game_id])[, `:=`(game_id = "CANARY_GAME", epa_sum = epa_sum + 500)])
qg2 <- rbind(inp$qb_games, copy(inp$qb_games[game_id == last$game_id])[, `:=`(game_id = "CANARY_GAME", qb_epa_sum = qb_epa_sum + 500)])
fa1 <- pc_epa_features(games, inp$team_games, inp$qb_games, C2$halflife, c(TUNE, CONFIRM), "A")
fa2 <- pc_epa_features(g2, tg2, qg2, C2$halflife, c(TUNE, CONFIRM), "A")[game_id != "CANARY_GAME"]
e1 <- pc_elo(games, C1$K, C1$hfa, C1$regress); e2 <- pc_elo(g2, C1$K, C1$hfa, C1$regress)[game_id != "CANARY_GAME"]
controls$leak_canary <- list(passed = isTRUE(all.equal(fa1, fa2[match(fa1$game_id, fa2$game_id)], check.attributes = FALSE)) && identical(e1, e2))
# the anchor copy scores exactly 0
ac <- run$d[!is.na(y) & season %in% c(TUNE, CONFIRM)][, `:=`(p_copy = p_open)]
acs <- bt_score_window(copy(ac), "p_copy", "p_open", B = 200L, seed = PC_SEED)$p_copy
controls$anchor_copy <- list(passed = identical(acs$skill, 0) && identical(acs$skill_ci, c(0, 0)))
# reproducibility: a second run gives the same result hash
controls$reproducibility <- list(passed = identical(sha1, result_sha(score_all(core(games)))), sha = sha1)
# the anchor null: y redrawn from the opener, y* ~ Bernoulli(p_open), on every game with an opener; no candidate may be claimed
gs <- copy(games); idx <- which(gs$game_id %in% mk$game_id & !is.na(gs$y))
old <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
set.seed(20261028L); po <- mk$p_open[match(gs$game_id[idx], mk$game_id)]; set(gs, idx, "y", as.integer(stats::rbinom(length(idx), 1L, po)))
if (is.null(old)) rm(".Random.seed", envir = globalenv()) else assign(".Random.seed", old, envir = globalenv())
an <- score_all(core(gs))
controls$anchor_null <- list(passed = !length(c(pc_claims(an$tune), pc_claims(an$confirm))), claims = c(pc_claims(an$tune), pc_claims(an$confirm)))
# the permuted-x null: each model column permuted within week, y and the opener kept
px <- score_all(core(games, perm = c("p_pc2", "p_e1a")))
controls$permuted_x <- list(passed = !length(c(pc_claims(px$tune), pc_claims(px$confirm))), claims = c(pc_claims(px$tune), pc_claims(px$confirm)))
# the placebo band: VVF S1 on 200 noise features beyond the opener, Tune and Confirm
for (f in c("backtest/vvf/common.R", "backtest/vvf/registry.R", "backtest/vvf/s1_screen.R", "backtest/vvf/s3_skill.R", "backtest/vvf/s4_controls.R")) source(f)
pl <- run$d[!is.na(y), .(game_id, season, week, wk, y, lp_anchor = bt_logit(bt_clip(p_open)), p_anchor = p_open)]
controls$placebo <- vvf_control_placebo(pl)
p6 <- data.table(control = names(controls), passed = vapply(controls, function(z) isTRUE(z$passed), logical(1)))

# --- outputs ---------------------------------------------------------------------------------------------------------------------------
write_out(run$tune_loss, "oa_lambda_tune.csv")
write_out(sc$tune[, window := "Tune 2023"], "gates_tune_2023.csv"); write_out(sc$confirm[, window := "Confirm 2024"], "gates_confirm_2024.csv")
write_out(rbind(sc$move_tune[, window := "Tune 2023"], sc$move_confirm[, window := "Confirm 2024"], fill = TRUE), "movement_lm.csv")
write_out(p6, "controls_p6.csv")
write_out(run$d[, .(game_id, season, week, y, p_open, p_close, p_elo_a, p_pc2, p_e1a, p_oa, p_lm, move_hat)], "predictions.csv")
meta <- data.table(field = c("stage", "run_utc", "code_commit", "protocol_sha256", "oa_lambda", "result_sha256", "p6_status"),
                   value = c(stage, format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), git("rev-parse", "HEAD")$out[1], reg$protocol_sha256,
                             run$lambda, sha1, if (all(p6$passed)) "complete" else "void"))
bt_write_csv(meta, file.path(out, "run_meta.csv"))
options(width = 220); print(meta); print(p6); print(sc$tune); print(sc$confirm); print(sc$move_tune); print(sc$move_confirm)

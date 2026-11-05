# nfl_preclose_v1 (reports/2026-11-02/preclose-v1/PROTOCOL.md): the IS-A information set never sees week w-1's
# results, the previous game's starter is the QB used, the anchored fits train only on rows known at the cutoff, and
# the registration matches the frozen files.

pc_env <- local({
  e <- new.env()
  for (f in c("backtest/common.R", "backtest/metrics.R", "backtest/blends.R", "backtest/candidates/elo.R", "backtest/candidates/epa_glm.R",
              "backtest/preclose/features.R", "backtest/preclose/elo.R", "backtest/preclose/candidates.R"))
    sys.source(file.path(PROJECT_ROOT, f), envir = e)
  e
})
pc_inputs <- local({
  v1 <- jsonlite::read_json(file.path(PROJECT_ROOT, "backtest", "eval_windows", "nfl_games_v1.json"))
  pc_env$bt_load_inputs(file.path(PROJECT_ROOT, v1$data_dir))
})

test_that("each week's IS-A cutoff is the first kickoff of the week before (the season's first kickoff for week 1)", {
  g <- pc_inputs$games[season == 2008L]
  w <- pc_env$pc_isa_week_cutoffs(g)
  first <- g[, .(fk = min(kickoff)), by = week]
  expect_equal(w[week == 1L, isa_cutoff], first[week == 1L, fk])
  expect_equal(w[week == 2L, isa_cutoff], first[week == 1L, fk])
  expect_equal(w[week == 9L, isa_cutoff], first[week == 8L, fk])
})

test_that("the IS-A QB is the starter of the team's previous game", {
  g <- pc_inputs$games[season %in% 2008:2009]
  ps <- pc_env$pc_prev_starters(g)
  team <- g$home_franchise[50]
  tg <- g[home_franchise == team | away_franchise == team][order(kickoff)]
  qb_of <- function(r) if (r$home_franchise == team) r$home_qb_id else r$away_qb_id
  prev_qb <- qb_of(tg[4]); this <- tg[5]
  got <- ps[game_id == this$game_id, if (this$home_franchise == team) home_prev_qb else away_prev_qb]
  expect_identical(got, prev_qb)
})

test_that("IS-A features of week w ignore week w-1's results; IS-B features do not", {
  g <- pc_inputs$games; tg <- copy(pc_inputs$team_games); qg <- pc_inputs$qb_games
  w4 <- g[season == 2008L & week == 4L, game_id]
  base_a <- pc_env$pc_epa_features(g, tg, qg, 8, 2008L, "A")
  base_b <- pc_env$pc_epa_features(g, tg, qg, 8, 2008L, "B")
  tg[game_id %in% w4, epa_sum := epa_sum + 50]
  pert_a <- pc_env$pc_epa_features(g, tg, qg, 8, 2008L, "A")
  pert_b <- pc_env$pc_epa_features(g, tg, qg, 8, 2008L, "B")
  w5 <- g[season == 2008L & week == 5L, game_id]; w6 <- g[season == 2008L & week == 6L, game_id]
  expect_equal(pert_a[game_id %in% w5, d_off_epa], base_a[game_id %in% w5, d_off_epa])
  expect_false(isTRUE(all.equal(pert_b[game_id %in% w5, d_off_epa], base_b[game_id %in% w5, d_off_epa])))
  expect_false(isTRUE(all.equal(pert_a[game_id %in% w6, d_off_epa], base_a[game_id %in% w6, d_off_epa])))
  expect_true(all(as.numeric(base_a$src_end) - pc_env$BT_GAME_DURATION_SEC < as.numeric(base_a$isa_cutoff), na.rm = TRUE))
})

test_that("IS-T features see week w-1's results but use the previous game's starter, not the game's own", {
  g <- copy(pc_inputs$games); tg <- copy(pc_inputs$team_games); qg <- pc_inputs$qb_games
  w4 <- g[season == 2008L & week == 4L, game_id]; w5 <- g[season == 2008L & week == 5L, game_id]
  base_t <- pc_env$pc_epa_features(g, tg, qg, 8, 2008L, "T")
  tg[game_id %in% w4, epa_sum := epa_sum + 50]
  expect_false(isTRUE(all.equal(pc_env$pc_epa_features(g, tg, qg, 8, 2008L, "T")[game_id %in% w5, d_off_epa], base_t[game_id %in% w5, d_off_epa])))
  # a week-5 starter swapped for someone else changes IS-B's QB feature but not IS-T's
  g2 <- copy(g); i <- which(g2$game_id %in% w5)
  g2[i, home_qb_id := pc_inputs$qb_games$qb_id[1]]
  tg0 <- pc_inputs$team_games
  expect_equal(pc_env$pc_epa_features(g2, tg0, qg, 8, 2008L, "T")[game_id %in% w5, d_qb_epa],
               pc_env$pc_epa_features(g, tg0, qg, 8, 2008L, "T")[game_id %in% w5, d_qb_epa])
  expect_false(isTRUE(all.equal(pc_env$pc_epa_features(g2, tg0, qg, 8, 2008L, "B")[game_id %in% w5, d_qb_epa],
                                pc_env$pc_epa_features(g, tg0, qg, 8, 2008L, "B")[game_id %in% w5, d_qb_epa])))
})

test_that("Elo on IS-A for week w ignores week w-1's scores; on IS-B it is v1's bt_elo_run", {
  g <- pc_inputs$games[season %in% 2006:2009]
  e <- pc_env$pc_elo(g, 20, 30, 0.45)
  expect_equal(e$p_elo_b, pc_env$bt_elo_run(g, 20, 30, 0.45)$p_c1, tolerance = 1e-12)
  g2 <- copy(g); i <- which(g2$season == 2008L & g2$week == 4L)
  g2[i, `:=`(home_score = away_score + 30L)]
  e2 <- pc_env$pc_elo(g2, 20, 30, 0.45)
  w5 <- g[season == 2008L & week == 5L, game_id]; w6 <- g[season == 2008L & week == 6L, game_id]
  expect_equal(e2[game_id %in% w5, p_elo_a], e[game_id %in% w5, p_elo_a])
  expect_false(isTRUE(all.equal(e2[game_id %in% w6, p_elo_a], e[game_id %in% w6, p_elo_a])))
})

test_that("the anchored fits train only on games before the cutoff, never on 2025, and wait for 100 rows", {
  set.seed(1)
  n <- 300L
  k <- as.POSIXct("2023-09-10", tz = "UTC") + (seq_len(n) - 1) * 86400
  d <- data.table::data.table(game_id = sprintf("g%03d", seq_len(n)), kickoff = k, season = c(rep(2023L, 150), rep(2025L, 50), rep(2026L, 100)),
                              wk = rep(1:30, each = 10), y = rbinom(n, 1, 0.5), p_open = runif(n, 0.3, 0.7))
  d[, `:=`(p_close = pmin(pmax(p_open + rnorm(n, 0, 0.02), 0.05), 0.95), p_e1a = pmin(pmax(p_open + rnorm(n, 0, 0.05), 0.05), 0.95))]
  weeks <- d[, .(cutoff = min(kickoff)), by = wk]
  oa <- pc_env$pc_oa_walk_forward(d, weeks, 1)
  lm <- pc_env$pc_lm_walk_forward(d, weeks)
  first_w <- min(merge(oa, d[, .(game_id, wk)], by = "game_id")$wk)
  expect_equal(first_w, 11L)   # weeks 1-10 hold the first 100 rows
  # weeks 21-30 (2026) train on the 150 rows of 2023 and earlier 2026 weeks, never the 50 of 2025
  tr26 <- merge(oa, d[, .(game_id, wk, season)], by = "game_id")[season == 2026L]
  expect_equal(unique(tr26[wk == 21L, oa_train]), 150L)
  expect_equal(unique(merge(lm, d[, .(game_id, wk)], by = "game_id")[wk == 30L, lm_train]), 150L + 90L)
})

test_that("each prospective game is scored on its own week's prediction, saved before that week, never a stale earlier row", {
  sys.source(file.path(PROJECT_ROOT, "backtest", "preclose", "gates.R"), envir = pc_env)
  sys.source(file.path(PROJECT_ROOT, "backtest", "preclose", "prospective.R"), envir = pc_env)
  dir <- withr::local_tempdir()
  row <- function(gid, wk, made, before, p) data.table::data.table(game_id = gid, week = wk, kickoff = "2026-11-16T18:00:00Z", p_elo_a = p, p_pc2 = p, p_e1a = p,
    p_oa = p, p_lm = p, move_hat = 0, p_elo_b = p, p_c2_t = p, p_e1_t = p, made_utc = made, before_first_kickoff_of_week = before)
  # the week-9 run also carries a (stale) week-10 row, as runs before amendment 4 did; the week-10 run has the real one
  data.table::fwrite(rbind(row("g9", 9L, "2026-11-03T18:30:00Z", TRUE, 0.51), row("g10", 10L, "2026-11-03T18:30:00Z", TRUE, 0.11)),
                     file.path(dir, "predictions_w09_20261103T183000Z.csv"))
  data.table::fwrite(rbind(row("g10", 10L, "2026-11-10T18:30:00Z", TRUE, 0.61), row("g11", 10L, "2026-11-10T18:30:00Z", FALSE, 0.71)),
                     file.path(dir, "predictions_w10_20261110T183000Z.csv"))
  sel <- pc_env$pc_select_saved(list.files(dir, full.names = TRUE), c("g9", "g10", "g11"))
  expect_identical(sort(sel$predictions$game_id), c("g10", "g9"))
  expect_equal(sel$predictions[game_id == "g10", p_c2_t], 0.61)   # not the stale 0.11 from week 9's run
  expect_equal(sel$coverage$without, 1L)                            # g11 was saved after its week began
})

test_that("the Tuesday track's CLV has the picked side's sign, and its return pays the ask plus the fee, a tie paying half", {
  x <- data.table::data.table(wk = c(1L, 1L, 2L), p_c2_t = c(0.60, 0.40, 0.60), p_tue = c(0.50, 0.50, 0.50), ask_tue = c(0.51, 0.51, 0.51),
                              bid_tue = c(0.49, 0.49, 0.49), p_kclose = c(0.55, 0.45, 0.50), home_score = c(24L, 10L, 20L), away_score = c(17L, 17L, 20L))
  r <- pc_env$pc_tuesday_clv(x, "p_c2_t", B = 200L, seed = 1L)
  expect_equal(r$picks, 3L)
  expect_equal(r$ties, 1L)
  expect_equal(r$mean_clv_bps, (500 + 500 + 0) / 3)
  cost_home <- 0.51 + pc_env$PC_KALSHI_FEE(0.51); cost_away <- (1 - 0.49) + pc_env$PC_KALSHI_FEE(1 - 0.49)
  expect_equal(r$roi, mean(c(1 / cost_home - 1, 1 / cost_away - 1, 0.5 / cost_home - 1)))
})

test_that("Elo refuses weeks that run backwards in kickoff order", {
  g <- data.table::copy(pc_inputs$games[season == 2008L])
  i <- which(g$week == 5L)[1]; g[i, week := 3L]
  expect_error(pc_env$pc_elo(g, 20, 30, 0.45), "backwards")
})

test_that("nfl_preclose_v1's registration matches the frozen protocol", {
  reg <- jsonlite::read_json(file.path(PROJECT_ROOT, "backtest", "eval_windows", "nfl_preclose_v1.json"), simplifyVector = TRUE)
  sha_lf <- function(f) { b <- readBin(f, "raw", file.size(f)); cr <- which(b == as.raw(13L))
    cr <- cr[cr < length(b) & b[pmin(cr + 1L, length(b))] == as.raw(10L)]
    digest::digest(if (length(cr)) b[-cr] else b, algo = "sha256", serialize = FALSE) }
  expect_identical(reg$protocol_id, "nfl_preclose_v1")
  expect_identical(sha_lf(file.path(PROJECT_ROOT, reg$protocol_path)), reg$protocol_sha256)
  expect_true(isTRUE(reg$windows$holdout$sealed))
  expect_identical(as.integer(reg$windows$prospective$weeks), 9:18)
  if (length(reg$code)) for (i in seq_len(nrow(reg$code)))
    expect_identical(sha_lf(file.path(PROJECT_ROOT, reg$code$path[i])), reg$code$sha256[i], label = reg$code$path[i])
})

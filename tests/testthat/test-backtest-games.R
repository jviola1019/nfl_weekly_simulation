# Game backtest v1 harness (backtest/): math, point-in-time guards, determinism,
# and the integrity of the committed inputs and results.

bt_env <- new.env()
for (f in c("common.R", "candidates/market.R", "candidates/elo.R", "candidates/epa_glm.R",
            "blends.R", "calibrators.R", "metrics.R", "controls.R")) {
  sys.source(file.path(PROJECT_ROOT, "backtest", f), envir = bt_env)
}
bt <- function(name) get(name, envir = bt_env)

# Two-team synthetic schedule over two seasons (4 games each), results known
synthetic_games <- function() {
  kick <- sprintf("2020-09-%02dT17:00:00Z", c(10, 17, 24))
  kick <- c(kick, sprintf("2020-10-%02dT17:00:00Z", 1), sprintf("2021-09-%02dT17:00:00Z", c(9, 16, 23, 30)))
  g <- data.table::data.table(
    game_id = sprintf("g%d", 1:8), season = rep(c(2020L, 2021L), each = 4), game_type = "REG",
    week = rep(1:4, 2), kickoff_utc = kick,
    home_team = rep(c("AAA", "BBB"), 4), away_team = rep(c("BBB", "AAA"), 4),
    home_franchise = rep(c("AAA", "BBB"), 4), away_franchise = rep(c("BBB", "AAA"), 4),
    home_score = c(24, 10, 31, 17, 20, 13, 27, 14), away_score = c(17, 20, 14, 17, 21, 10, 3, 28),
    location = "Home", home_rest = 7, away_rest = 7, home_moneyline = -150, away_moneyline = 130,
    home_qb_id = rep(c("QA", "QB"), 4), away_qb_id = rep(c("QB", "QA"), 4)
  )
  bt("bt_prepare_games")(g)
}

synthetic_team_games <- function(games) {
  rbind(
    games[, .(game_id, team = home_franchise, opp = away_franchise, plays = 60L, epa_sum = home_score - away_score,
              success_sum = 28, pass_plays = 35L, pass_epa_sum = (home_score - away_score) / 2,
              rush_plays = 25L, rush_epa_sum = (home_score - away_score) / 2)],
    games[, .(game_id, team = away_franchise, opp = home_franchise, plays = 60L, epa_sum = away_score - home_score,
              success_sum = 26, pass_plays = 35L, pass_epa_sum = (away_score - home_score) / 2,
              rush_plays = 25L, rush_epa_sum = (away_score - home_score) / 2)]
  )
}

synthetic_qb_games <- function(games) {
  rbind(games[, .(game_id, team = home_franchise, qb_id = home_qb_id, dropbacks = 35L, qb_epa_sum = (home_score - away_score) / 2)],
        games[, .(game_id, team = away_franchise, qb_id = away_qb_id, dropbacks = 35L, qb_epa_sum = (away_score - home_score) / 2)])
}

test_that("ridge logistic with lambda = 0 matches glm", {
  set.seed(1)
  x <- cbind(1, rnorm(300), rnorm(300))
  y <- rbinom(300, 1, plogis(x %*% c(0.2, 1, -0.5)))
  b <- bt("bt_ridge_logistic")(x, y, lambda = 0)
  g <- stats::glm(y ~ x[, 2] + x[, 3], family = stats::binomial())
  expect_equal(unname(b), unname(stats::coef(g)), tolerance = 1e-8)
  # a penalty shrinks the penalized coefficients but not the unpenalized one's role
  b2 <- bt("bt_ridge_logistic")(x, y, lambda = 50, unpenalized = 1L)
  expect_lt(sum(b2[2:3]^2), sum(b[2:3]^2))
})

test_that("odds helpers devig and convert correctly", {
  expect_equal(bt("bt_amer_to_p")(c(-150, "+130", NA)), c(0.6, 100 / 230, NA))
  expect_equal(bt("bt_amer_to_dec")(c(-200, 150)), c(1.5, 2.5))
  p <- bt("bt_novig_home")(-150, 130)
  expect_equal(p, 0.6 / (0.6 + 100 / 230))
  expect_equal(bt("bt_novig_home")(-110, -110), 0.5)
})

test_that("the as-of assertion rejects sources that end at or after kickoff", {
  k <- as.POSIXct("2024-09-08 17:00:00", tz = "UTC")
  expect_true(bt("bt_assert_asof")(c(k - 3600, NA), c(k, k)))
  expect_error(bt("bt_assert_asof")(k, k), "as-of violation")
  expect_error(bt("bt_assert_asof")(k + 1, k), "as-of violation")
})

test_that("Elo follows the 538 update and regresses between seasons", {
  g <- synthetic_games()[1:2]
  g[, neutral := TRUE]
  p <- bt("bt_elo_run")(g, K = 20, hfa = 55, regress = 0.5)
  expect_equal(p$p_c1[1], 0.5)
  shift <- 20 * log(7 + 1) * (2.2 / (0 * 0.001 + 2.2)) * (1 - 0.5)   # AAA wins by 7 at equal ratings
  # game 2: BBB (home) vs AAA with AAA up by 2*shift
  expect_equal(p$p_c1[2], 1 / (1 + 10^(2 * shift / 400)))
  g3 <- synthetic_games()[c(1, 5)]
  g3[, neutral := TRUE]
  p3 <- bt("bt_elo_run")(g3, K = 20, hfa = 0, regress = 0.5)
  expect_equal(p3$p_c1[2], 1 / (1 + 10^(-(0.5 * 2 * shift) / 400)))   # regressed halfway
})

test_that("EPA features are point-in-time: changing a later game leaves earlier features unchanged", {
  g <- synthetic_games(); tg <- synthetic_team_games(g); qg <- synthetic_qb_games(g)
  f1 <- bt("bt_epa_features")(g, tg, qg, halflife = 4, target_seasons = 2020:2021)
  tg2 <- data.table::copy(tg); tg2[game_id == "g6", epa_sum := epa_sum * 1000]
  qg2 <- data.table::copy(qg); qg2[game_id == "g6", qb_epa_sum := qb_epa_sum * 1000]
  f2 <- bt("bt_epa_features")(g, tg2, qg2, halflife = 4, target_seasons = 2020:2021)
  cols <- get("BT_EPA_FEATURES", envir = bt_env)
  upto <- f1$game_id %in% sprintf("g%d", 1:6)     # g6 itself is predicted before it is played
  expect_equal(f1[upto, ..cols], f2[upto, ..cols])
  expect_false(isTRUE(all.equal(f1[game_id == "g7", ..cols], f2[game_id == "g7", ..cols])))
  expect_true(all(is.na(f1$src_end) | f1$src_end < f1$kickoff))
  # the first game has no history: every team difference is prior-only and zero
  expect_equal(unname(unlist(f1[game_id == "g1", .(d_off_epa, d_def_epa, d_qb_epa)])), c(0, 0, 0))
})

test_that("walk-forward C2 predictions ignore labels of games at or after the week cutoff", {
  set.seed(3)
  n <- 400
  feats <- data.table::data.table(game_id = sprintf("x%d", 1:n), season = rep(2010:2013, each = 100),
                                  week = rep(1:20, 20), kickoff = as.POSIXct("2010-09-01", tz = "UTC") + (1:n) * 86400 * 3)
  feats[, wk := season * 100L + week]
  for (f in get("BT_EPA_FEATURES", envir = bt_env)) data.table::set(feats, j = f, value = rnorm(n))
  feats[, home := 1]
  games <- feats[, .(game_id, y = rbinom(n, 1, 0.55))]
  weeks <- feats[season == 2013, .(cutoff = min(kickoff)), by = .(season, week, wk)]
  p1 <- bt("bt_epa_walk_forward")(feats, games, weeks, lambda = 1)
  games2 <- data.table::copy(games); games2[game_id %in% feats[season == 2013 & week == 20, game_id], y := 1L - y]
  p2 <- bt("bt_epa_walk_forward")(feats, games2, weeks, lambda = 1)
  expect_equal(p1, p2)   # flipping the last week's labels changes no prediction
})

test_that("B1 walk-forward never trains on the week being predicted", {
  set.seed(4)
  n <- 600
  d <- data.table::data.table(game_id = sprintf("b%d", 1:n), season = rep(2010:2015, each = 100),
                              kickoff = as.POSIXct("2010-09-01", tz = "UTC") + (1:n) * 86400 * 2)
  d[, wk := season * 100L + rep(1:20, each = 5, length.out = n)]
  d[, `:=`(p_mkt = runif(n, 0.2, 0.8), p_model = runif(n, 0.2, 0.8))]
  d[, y := rbinom(n, 1, p_mkt)]
  weeks <- d[season == 2015, .(cutoff = min(kickoff)), by = wk]
  a <- bt("bt_b1_walk_forward")(d, weeks, lambda = 1)
  d2 <- data.table::copy(d); d2[wk == max(wk), y := 1L - y]
  b <- bt("bt_b1_walk_forward")(d2, weeks, lambda = 1)
  expect_equal(a, b)
  expect_equal(nrow(a), 100L)
})

test_that("DM-HLN, ECE and the week bootstrap behave as specified", {
  dm0 <- bt("bt_dm_hln")(rep(0, 50))
  expect_equal(dm0$p_better, 1)
  d <- c(-0.02, -0.01, 0.00, -0.03, 0.01, -0.02, -0.01, -0.02)
  dm <- bt("bt_dm_hln")(d)
  n <- length(d); v <- mean((d - mean(d))^2)
  expect_equal(dm$stat, mean(d) / sqrt(v / n) * sqrt((n - 1) / n))
  expect_lt(dm$p_better, 0.05)
  expect_equal(bt("bt_ece")(rep(c(0.2, 0.8), each = 50), c(rep(c(1, 0, 0, 0, 0), 10), rep(c(1, 1, 1, 1, 0), 10))), 0)
  set.seed(99); before <- runif(1); set.seed(99)
  c1 <- bt("bt_boot_counts")(10, 50, seed = 7)
  expect_equal(runif(1), before)                    # the caller's RNG stream is untouched
  expect_identical(c1, bt("bt_boot_counts")(10, 50, seed = 7))
  expect_true(all(rowSums(c1) == 10))
})

test_that("scoring is paired: the reference scores zero skill and missing predictions fail loudly", {
  set.seed(5)
  d <- data.table::data.table(game_id = sprintf("s%d", 1:200), wk = rep(1:20, each = 10),
                              kickoff = as.POSIXct("2023-09-01", tz = "UTC") + 1:200)
  d[, p_c0 := runif(200, 0.2, 0.8)]; d[, y := rbinom(200, 1, p_c0)]; d[, p_a := p_c0]
  s <- bt("bt_score_window")(data.table::copy(d), c(A = "p_a"), c(C0 = "p_c0"), B = 100L, seed = 1)
  expect_equal(s$p_a$skill, 0); expect_equal(s$p_a$skill_ci, c(0, 0)); expect_equal(s$p_a$dm_p_better_bh, 1)
  d[3, p_a := NA]
  expect_error(bt("bt_score_window")(d, c(A = "p_a"), c(C0 = "p_c0"), B = 10L, seed = 1), "missing predictions")
})

test_that("CLV takes the side the model likes at the opener, measured against the same venue's close", {
  d <- data.table::data.table(game_id = c("a", "b", "c", "d"), wk = c(1, 1, 2, 2),
                              p = c(0.60, 0.40, 0.51, 0.55), p_open = c(0.55, 0.45, 0.50, 0.50),
                              p_close_venue = c(0.58, 0.40, 0.60, 0.50),
                              h_open = c("-120", "+120", "-100", "-100"), a_open = c("+100", "-140", "-120", "-120"),
                              home_score = c(20, 10, 30, 17), away_score = c(10, 20, 0, 17))
  r <- bt("bt_clv")(d, "p", tau = 0.03, B = 50L, seed = 1)
  expect_equal(r$n, 3L)                       # game c's 0.01 edge is below tau
  expect_equal(r$n_home, 2L)
  # a: home +300 bps; b: away (0.45 -> 0.40 home) +500 bps; d: home 0 bps
  expect_equal(r$mean_clv_bps, (300 + 500 + 0) / 3)
  # a wins at -120 (+0.8333), b away wins at -140 (+0.7143), d pushes (0)
  expect_equal(r$roi, (100 / 120 + 100 / 140 + 0) / 3)
})

test_that("calibrators are monotone, bounded and fit only on earlier weeks", {
  set.seed(6)
  p <- runif(2000, 0.05, 0.95); y <- rbinom(2000, 1, p)
  pl <- bt("bt_calib_fit")(p, y, "platt"); iso <- bt("bt_calib_fit")(p, y, "isotonic")
  q <- seq(0, 1, by = 0.01)
  expect_true(all(diff(pl(q)) >= 0)); expect_true(all(diff(iso(q)) >= 0))
  expect_true(all(iso(q) >= 0.01 & iso(q) <= 0.99))
  expect_error(bt("bt_calib_fit")(p, y, "beta"), "unknown method")
})

test_that("the shuffled-label control permutes whole results and keeps the caller's RNG", {
  g <- synthetic_games()
  set.seed(11); before <- runif(1); set.seed(11)
  s <- bt("bt_shuffle_scores")(g, seed = 1)
  expect_equal(runif(1), before)
  expect_equal(sort(paste(s$home_score, s$away_score)), sort(paste(g$home_score, g$away_score)))
  expect_identical(s, bt("bt_shuffle_scores")(g, seed = 1))
  expect_equal(s$y, ifelse(s$home_score == s$away_score, NA_integer_, as.integer(s$home_score > s$away_score)))
})

test_that("committed inputs match the eval window and the holdout stays sealed", {
  win <- jsonlite::read_json(file.path(PROJECT_ROOT, "backtest", "eval_windows", "nfl_games_v1.json"), simplifyVector = TRUE)
  for (nm in names(win$data_sha256)) {
    f <- file.path(PROJECT_ROOT, win$data_dir, paste0(nm, ".csv"))
    expect_identical(digest::digest(file = f, algo = "sha256"), win$data_sha256[[nm]])
  }
  games <- data.table::fread(file.path(PROJECT_ROOT, win$data_dir, "games.csv"), select = "season")
  expect_lte(max(games$season), win$max_input_season)
  expect_true(isTRUE(win$windows$holdout$sealed))
  expect_false(any(win$windows$holdout$seasons %in% c(win$windows$tune$seasons, win$windows$confirm$seasons)))
  proto <- file.path(PROJECT_ROOT, win$protocol_path)
  expect_true(file.exists(proto))
  expect_identical(digest::digest(file = proto, algo = "sha256"), win$protocol_sha256)
})

test_that("committed backtest results match their recorded result hash", {
  out <- file.path(PROJECT_ROOT, "reports", "2026-09-29", "backtest-games-v1")
  meta <- jsonlite::read_json(file.path(out, "run_meta.json"))
  h <- digest::digest(paste0(digest::digest(file = file.path(out, "predictions.csv"), algo = "sha256"),
                             digest::digest(file = file.path(out, "metrics.json"), algo = "sha256")),
                      algo = "sha256", serialize = FALSE)
  expect_identical(h, meta$result_sha256)
  controls <- jsonlite::read_json(file.path(out, "controls.json"))
  expect_true(controls$reproducibility$passed)
  expect_true(controls$run_status %in% c("complete", "void"))
})

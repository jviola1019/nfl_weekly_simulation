# =============================================================================
# R/sim_bundle.R: the simulator's weekly bundle (checkpoint A8; spec §3). The web
# fixture contracts/fixtures/bundles/weekly-sim-2024-w15 is written by
# scripts/write_sim_fixture.R with this builder, and must match what it writes.
# =============================================================================

sb_teams_csv <- file.path(.test_project_root, "data", "reference", "teams.csv")
sb_contracts <- file.path(.test_project_root, "contracts", "schema")

sb_test_inputs <- function() {
  final <- data.frame(
    game_id = c("2024_15_LA_SF", "2024_15_BUF_DET"), season = 2024L, week = 15L,
    home_team = c("SF", "DET"), away_team = c("LA", "BUF"),
    home_p_2w_model = c(0.48, 0.58), home_p_2w_blend = c(0.56, 0.55),
    # BUF_DET: the engine's M11 fill (the model probability) flagged market_available = FALSE
    home_p_2w_mkt = c(0.583, 0.58), market_available = c(TRUE, FALSE),
    margin_median = c(-1, 3), total_median = c(43, 54), stringsAsFactors = FALSE
  )
  draws <- function(h, a) list(home = h, away = a, total = h + a, margin = h - a, n_trials = length(h))
  sims <- list("2024_15_LA_SF" = draws(c(20, 24, 17, 27, 21, 10), c(17, 24, 20, 13, 21, 30)),
               "2024_15_BUF_DET" = draws(c(31, 28, 24, 35, 21, 17), c(27, 30, 24, 20, 38, 24)))
  schedule <- data.frame(
    game_id = c("2024_15_LA_SF", "2024_15_BUF_DET", "2024_15_BAL_NYG"), season = 2024L, week = 15L,
    game_type = "REG", gameday = c("2024-12-12", "2024-12-15", "2024-12-15"),
    gametime = c("20:15", "16:25", "13:00"), home_team = c("SF", "DET", "NYG"), away_team = c("LA", "BUF", "BAL"),
    roof = c("outdoors", "dome", "outdoors"), location = "Home",
    home_score = c(6L, 42L, 14L), away_score = c(12L, 48L, 35L), stringsAsFactors = FALSE
  )
  quality <- list(injury = list(status = "full", missing_seasons = character()),
                  weather = list(status = "partial_fallback", fallback_games = "2024_15_LA_SF"),
                  market = list(status = "partial", missing_games = "2024_15_BUF_DET"),
                  calibration = list(method = "none", leakage_free = FALSE))
  list(final = final, sims = sims, schedule = schedule, quality = quality)
}

sb_build <- function(i) build_sim_bundle_tables(i$final, i$sims, i$schedule, i$quality, teams_csv = sb_teams_csv)

test_that("sb_bins has one row per integer outcome over the central 99.9% of draws", {
  set.seed(1)
  d <- c(rep(0L, 5), stats::rpois(9990, 20), 200L, -150L, 75L, 80L, 90L)
  b <- sb_bins(d)
  expect_named(b, c("x", "p"))
  expect_identical(b$x, seq.int(min(b$x), max(b$x)))
  expect_gte(sum(b$p), 0.999)
  expect_lte(sum(b$p), 1)
  expect_false(any(c(-150, 75, 80, 90, 200) %in% b$x))
  expect_equal(b$p[b$x == 20], mean(d == 20))
})

test_that("sb_bins refuses draws that are not finite integers", {
  expect_error(sb_bins(c(1.5, 2)), "integers")
  expect_error(sb_bins(c(1, NA)), "finite")
  expect_error(sb_bins(numeric()), "non-empty")
})

test_that("C0 carries the market and C3 the simulator; a game without a market keeps NA market fields (M11)", {
  i <- sb_test_inputs()
  b <- sb_build(i)
  gp <- b$tables$game_predictions
  expect_setequal(paste(gp$game_id, gp$candidate),
                  c("2024_15_LA_SF C0", "2024_15_BUF_DET C0", "2024_15_LA_SF C3", "2024_15_BUF_DET C3"))
  row <- function(id, cand) gp[gp$game_id == id & gp$candidate == cand, ]
  sf0 <- row("2024_15_LA_SF", "C0"); sf3 <- row("2024_15_LA_SF", "C3")
  det0 <- row("2024_15_BUF_DET", "C0"); det3 <- row("2024_15_BUF_DET", "C3")
  expect_equal(c(sf0$p_home_raw, sf0$p_home_final, sf0$p_home_mkt_novig), rep(0.583, 3))
  expect_equal(c(sf3$p_home_raw, sf3$p_home_final, sf3$p_home_mkt_novig, sf3$margin_q50, sf3$total_q50),
               c(0.48, shrink_probability_toward_market(0.56, 0.583, SHRINKAGE), 0.583, -1, 43))
  expect_true(all(is.na(c(det0$p_home_raw, det0$p_home_final, det0$p_home_mkt_novig, det3$p_home_mkt_novig))))
  expect_equal(det3$p_home_final, 0.55)
  expect_identical(b$qa, character())
})

test_that("C3 p_home_final is the production pipeline's shrunk probability; a no-market game stays unshrunk and is named (O1)", {
  i <- sb_test_inputs()
  b <- sb_build(i)
  gp <- b$tables$game_predictions
  c3 <- gp[gp$candidate == "C3", ]
  mk <- i$final$market_available
  want <- shrink_probability_toward_market(i$final$home_p_2w_blend[mk], i$final$home_p_2w_mkt[mk], SHRINKAGE)
  got <- c3$p_home_final[match(i$final$game_id[mk], c3$game_id)]
  expect_equal(got, want, tolerance = 1e-12)
  expect_gt(abs(got - i$final$home_p_2w_blend[mk]), 1e-3)   # the shrink really moved it
  # raw stays the simulator's own probability
  expect_equal(c3$p_home_raw, i$final$home_p_2w_model[match(c3$game_id, i$final$game_id)])
  # no market: nothing to shrink toward, so the blend is kept and the game is named
  expect_equal(c3$p_home_final[c3$game_id == "2024_15_BUF_DET"], 0.55)
  expect_match(b$tables$source_status$detail[4], "C3 unshrunk (no market): 2024_15_BUF_DET", fixed = TRUE)
  # all games have a market: no such line
  j <- i; j$final$market_available <- TRUE
  expect_false(grepl("C3 unshrunk", sb_build(j)$tables$source_status$detail[4], fixed = TRUE))
  # the same number as the comparison table's blend_home_prob_shrunk (NFLmarket.R:2188-2190) is
  # shrink_probability_toward_market(blend_home_prob, market_home_prob, SHRINKAGE); the table itself
  # needs the full comparison result and cannot be built from this synthetic final.
})

test_that("games come from the schedule: UTC kickoff, roof, neutral flag, scores", {
  g <- sb_build(sb_test_inputs())$tables$games
  expect_identical(g$game_id, c("2024_15_LA_SF", "2024_15_BUF_DET"))
  expect_identical(g$kickoff_utc, c("2024-12-13T01:15:00Z", "2024-12-15T21:25:00Z"))
  expect_identical(c(g$home_team_id, g$away_team_id), c("SF", "DET", "LA", "BUF"))
  expect_identical(g$roof, c("outdoors", "dome"))
  expect_identical(g$neutral, c(FALSE, FALSE))
  expect_identical(c(g$home_score, g$away_score), c(6L, 42L, 12L, 48L))
})

test_that("relocated franchises map to current team ids and neutral sites are flagged", {
  s <- sb_test_inputs()$schedule
  s$home_team[1] <- "STL"
  s$location[2] <- "Neutral"
  g <- sb_games_table(s, c("2024_15_LA_SF", "2024_15_BUF_DET"))
  expect_identical(g$home_team_id[1], "LA")
  expect_identical(g$neutral, c(FALSE, TRUE))
})

test_that("score distributions: margin and total for every game, as {x, p} bins of all draws", {
  sd <- sb_build(sb_test_inputs())$tables$score_distributions
  expect_identical(paste(sd$game_id, sd$kind),
                   c("2024_15_LA_SF margin", "2024_15_LA_SF total", "2024_15_BUF_DET margin", "2024_15_BUF_DET total"))
  m <- sd$bins[[1]]   # LA_SF margins: 3, 0, -3, 14, 0, -20
  expect_named(m, c("x", "p"))
  expect_identical(range(m$x), c(-20L, 14L))
  expect_length(m$x, 35L)
  expect_equal(m$p[m$x == 0], 2 / 6)
  expect_equal(sum(m$p), 1)
})

test_that("source_status maps the data-quality tracker and names the games behind a partial status", {
  i <- sb_test_inputs()
  ss <- sb_build(i)$tables$source_status
  expect_identical(ss$source, c("nflverse_schedules", "injury_reports", "weather", "market_lines"))
  expect_identical(ss$status, c("ok", "ok", "stale", "stale"))
  expect_match(ss$detail[3], "fallback weather for 2024_15_LA_SF", fixed = TRUE)
  expect_match(ss$detail[4], "no market line for 2024_15_BUF_DET", fixed = TRUE)
  q <- i$quality
  q$injury$status <- "unknown"
  q$weather$status <- "all_fallback"
  q$market$status <- "unavailable"
  st <- sb_source_status(q)
  expect_identical(st$status, c("ok", "failed", "failed", "unavailable"))
  expect_true(all(is.na(st$last_success_utc[-1])))
})

test_that("every problem becomes a QA failure instead of a silent fix", {
  i <- sb_test_inputs()
  i$sims[["2024_15_BUF_DET"]] <- NULL
  i$schedule <- i$schedule[i$schedule$game_id != "2024_15_LA_SF", ]
  i$final$home_p_2w_blend[2] <- NA
  qa <- sb_build(i)$qa
  expect_true(any(grepl("no simulated draws for 2024_15_BUF_DET", qa, fixed = TRUE)))
  expect_true(any(grepl("not in the schedule: 2024_15_LA_SF", qa, fixed = TRUE)))
  expect_true(any(grepl("C3 p_home_final missing for 2024_15_BUF_DET", qa, fixed = TRUE)))
  i <- sb_test_inputs()
  i$sims[["2024_15_LA_SF"]]$margin <- i$sims[["2024_15_LA_SF"]]$margin + 0.5
  expect_true(any(grepl("2024_15_LA_SF margin: sb_bins: draws must be integers", sb_build(i)$qa, fixed = TRUE)))
})

test_that("a run whose draws were never exported is written with every game flagged, not a crash", {
  i <- sb_test_inputs()
  b <- build_sim_bundle_tables(i$final, NULL, i$schedule, i$quality, teams_csv = sb_teams_csv)
  expect_identical(nrow(b$tables$score_distributions), 0L)
  expect_true(any(grepl("no simulated draws for 2024_15_LA_SF, 2024_15_BUF_DET", b$qa, fixed = TRUE)))
  out <- withr::local_tempdir()
  m <- write_sim_bundle(i$final, NULL, i$schedule, i$quality, season = 2024, week = 15, seed = 1, n_sims = 6,
                        out_root = out, git = list(code_git_sha = "0123456789abcdef", code_dirty = FALSE),
                        teams_csv = sb_teams_csv, contracts_dir = sb_contracts,
                        renv_lock = file.path(.test_project_root, "renv.lock"))
  expect_false(m$qa$ok)
  expect_true(file.exists(file.path(m$dir, "manifest.json")))
})

test_that("a game without a kickoff time is shown at 1:00 PM ET and named in source_status, not filled silently", {
  i <- sb_test_inputs()
  i$schedule$gametime[2] <- NA
  b <- sb_build(i)
  expect_identical(b$tables$games$kickoff_utc[2], "2024-12-15T18:00:00Z")
  expect_match(b$tables$source_status$detail[1], "no kickoff time for 2024_15_BUF_DET (shown as 1:00 PM ET)", fixed = TRUE)
  expect_identical(sb_build(sb_test_inputs())$tables$source_status$detail[1],
                   "schedule, scores and consensus closing lines via nflreadr")
  expect_identical(b$qa, character())
})

test_that("a final without a required column stops loudly", {
  i <- sb_test_inputs()
  i$final$market_available <- NULL
  expect_error(sb_build(i), "final lacks market_available")
})

test_that("write_sim_bundle writes a valid weekly bundle named <season>-w<WW>-sim-<UTC stamp>", {
  out <- withr::local_tempdir()
  i <- sb_test_inputs()
  m <- write_sim_bundle(i$final, i$sims, i$schedule, i$quality, season = 2024, week = 15, seed = 471, n_sims = 6,
                        out_root = out, now = as.POSIXct("2026-10-03 12:00:00", tz = "UTC"),
                        git = list(code_git_sha = "0123456789abcdef", code_dirty = FALSE),
                        teams_csv = sb_teams_csv, contracts_dir = sb_contracts,
                        renv_lock = file.path(.test_project_root, "renv.lock"))
  expect_true(m$qa$ok)
  expect_identical(basename(m$dir), "2024-w15-sim-20261003T120000Z")
  man <- jsonlite::read_json(file.path(m$dir, "manifest.json"))
  expect_identical(man$model_label, "Game simulator C3 (unvalidated)")
  expect_equal(c(man$seed, man$n_sims), c(471, 6))
  expect_identical(man$data_asof_utc, "2026-10-03T12:00:00Z")
  expect_setequal(vapply(man$files, `[[`, "", "name"),
                  c("teams.json", "games.json", "game_predictions.json", "score_distributions.json", "source_status.json"))
  sd <- jsonlite::read_json(file.path(m$dir, "score_distributions.json"))
  expect_named(sd[[1]]$bins[[1]], c("x", "p"))
  gp <- jsonlite::read_json(file.path(m$dir, "game_predictions.json"))
  det_c0 <- Filter(function(r) r$game_id == "2024_15_BUF_DET" && r$candidate == "C0", gp)[[1]]
  expect_null(det_c0$p_home_mkt_novig)   # absent, never the model's number (M11)
})

test_that("report_sim_bundle prints the bundle path, its QA and how to view it offline", {
  ok <- list(dir = "bundles/2024-w15-sim-20261003T120000Z", qa = list(ok = TRUE, failures = list()))
  out <- capture.output(report_sim_bundle(ok))
  expect_identical(out, c("  Web bundle: bundles/2024-w15-sim-20261003T120000Z", "  QA: passed",
                          "  View it offline: cd web && npm run local   (then open http://127.0.0.1:3000)"))
  bad <- list(dir = "b", qa = list(ok = FALSE, failures = list("games: not in the schedule: X")))
  out <- capture.output(report_sim_bundle(bad))
  expect_match(out[2], "QA: FAILED (1)", fixed = TRUE)
  expect_identical(out[3], "    - games: not in the schedule: X")
})

test_that("a missing git sha is a QA failure, so the console says FAILED and not passed (M7)", {
  i <- sb_test_inputs()
  out <- withr::local_tempdir()
  write <- function(sha) write_sim_bundle(i$final, i$sims, i$schedule, i$quality, season = 2024, week = 15, seed = 1,
                                          n_sims = 6, out_root = out, git = list(code_git_sha = sha, code_dirty = NA),
                                          teams_csv = sb_teams_csv, contracts_dir = sb_contracts,
                                          renv_lock = file.path(.test_project_root, "renv.lock"),
                                          cycle_id = paste0("sha-", length(sha), is.na(sha[1])))
  for (sha in list(NA_character_, character(0), "")) {
    m <- write(sha)
    expect_false(m$qa$ok)
    expect_true(any(grepl("code_git_sha unavailable: run from a git checkout", unlist(m$qa$failures), fixed = TRUE)))
    expect_true(any(grepl("QA: FAILED", capture.output(report_sim_bundle(m)), fixed = TRUE)))
  }
})

test_that("sb_git_state ignores the tracked run outputs under artifacts/ but not code", {
  repo <- withr::local_tempdir()
  withr::with_dir(repo, {
    git <- function(...) system2("git", c(...), stdout = TRUE, stderr = TRUE)
    git("init", "-q")
    git("config", "user.email", "test@example.test")
    git("config", "user.name", "test")
    dir.create("artifacts")
    writeLines("a", "code.R")
    writeLines("1", file.path("artifacts", "baseline_games.csv"))
    git("add", ".")
    git("commit", "-q", "-m", "base")
    writeLines("2", file.path("artifacts", "baseline_games.csv"))
    s <- sb_git_state()
    expect_match(s$code_git_sha, "^[0-9a-f]{40}$")
    expect_false(s$code_dirty)
    writeLines("b", "code.R")
    expect_true(sb_git_state()$code_dirty)
  })
})

test_that("the committed web fixture holds exactly what scripts/write_sim_fixture.R writes", {
  committed <- file.path(.test_project_root, "contracts", "fixtures", "bundles", "weekly-sim-2024-w15")
  env <- new.env()
  withr::with_dir(.test_project_root, sys.source(file.path("scripts", "write_sim_fixture.R"), envir = env))
  out <- withr::local_tempdir()
  m <- withr::with_dir(.test_project_root, env$sf_write(out))
  expect_true(m$qa$ok)
  for (f in c("teams", "games", "game_predictions", "score_distributions", "source_status")) {
    expect_equal(jsonlite::read_json(file.path(m$dir, paste0(f, ".json"))),
                 jsonlite::read_json(file.path(committed, paste0(f, ".json"))), tolerance = 1e-12, info = f)
  }
  man <- jsonlite::read_json(file.path(committed, "manifest.json"))
  expect_true(man$qa$ok)
  expect_identical(c(man$bundle_kind, man$model_label), c("weekly", "Game simulator C3 (unvalidated)"))
})

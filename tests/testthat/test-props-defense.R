# =============================================================================
# FILE: tests/testthat/test-props-defense.R
# PURPOSE: P13 (opponent-defense multipliers apply) and its duplicate definition.
# No network: the arithmetic is tested on a synthetic 32-team play-by-play table.
# =============================================================================

library(testthat)

suppressMessages(source(file.path(.test_project_root, "config.R"), local = FALSE))
source(file.path(.test_project_root, "sports", "nfl", "props", "props_config.R"), local = FALSE)
source(file.path(.test_project_root, "R", "correlated_props.R"), local = FALSE)

DEF_TEAMS <- c("ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE", "DAL", "DEN", "DET",
               "GB", "HOU", "IND", "JAX", "KC", "LA", "LAC", "LV", "MIA", "MIN", "NE", "NO",
               "NYG", "NYJ", "PHI", "PIT", "SEA", "SF", "TB", "TEN", "WAS")

# Team i allows 200 + 10 * i passing yards and 80 + 4 * i rushing yards in week 1.
synthetic_pbp <- function() {
  i <- seq_along(DEF_TEAMS)
  rbind(
    data.frame(game_id = paste0("w1_", i), week = 1L, defteam = DEF_TEAMS, play_type = "pass",
               passing_yards = 200 + 10 * i, rushing_yards = NA_real_, stringsAsFactors = FALSE),
    data.frame(game_id = paste0("w1_", i), week = 1L, defteam = DEF_TEAMS, play_type = "run",
               passing_yards = NA_real_, rushing_yards = 80 + 4 * i, stringsAsFactors = FALSE),
    # a later week in which the first team (ARI) allows a huge number of yards
    data.frame(game_id = "w9_1", week = 9L, defteam = "ARI", play_type = "pass",
               passing_yards = 5000, rushing_yards = NA_real_, stringsAsFactors = FALSE)
  )
}

test_that("compute_defense_multipliers returns 32 distinct, bounded multipliers (P13)", {
  m <- compute_defense_multipliers(synthetic_pbp(), weeks = 1L)
  expect_s3_class(m, "data.frame")
  expect_equal(nrow(m), 32)
  expect_setequal(m$team, DEF_TEAMS)
  expect_true(all(c("team", "pass_def_multiplier", "rush_def_multiplier",
                    "recv_def_multiplier") %in% names(m)))
  expect_false(all(m$pass_def_multiplier == 1))
  expect_gt(length(unique(round(m$pass_def_multiplier, 6))), 10)
  expect_true(all(m$pass_def_multiplier >= 0.80 & m$pass_def_multiplier <= 1.20))
  expect_true(all(m$rush_def_multiplier >= 0.75 & m$rush_def_multiplier <= 1.25))
  expect_equal(m$recv_def_multiplier, m$pass_def_multiplier)
  # the team allowing the most yards has the largest multiplier, the fewest the smallest (ties at the clamp are allowed)
  expect_equal(m$pass_def_multiplier[m$team == "WAS"], max(m$pass_def_multiplier))
  expect_equal(m$pass_def_multiplier[m$team == "ARI"], min(m$pass_def_multiplier))
})

test_that("the weeks argument leaves out games played later (no future leak)", {
  early <- compute_defense_multipliers(synthetic_pbp(), weeks = 1:8)
  all_weeks <- compute_defense_multipliers(synthetic_pbp())
  ari_early <- early$pass_def_multiplier[early$team == "ARI"]
  ari_all <- all_weeks$pass_def_multiplier[all_weeks$team == "ARI"]
  expect_lt(ari_early, ari_all)
  expect_null(compute_defense_multipliers(synthetic_pbp(), weeks = 15L))
  expect_null(compute_defense_multipliers(NULL))
})

test_that("a bye week does not make a defense look better: yards allowed are per game (final review I5)", {
  # Every defense allows 250 passing and 100 rushing yards a game; DET had a bye in week 2.
  rows <- list()
  for (w in 1:3) for (i in seq_along(DEF_TEAMS)) {
    if (DEF_TEAMS[i] == "DET" && w == 2) next
    gid <- sprintf("w%d_%s", w, DEF_TEAMS[i])
    rows[[length(rows) + 1]] <- data.frame(game_id = gid, week = w, defteam = DEF_TEAMS[i], play_type = c("pass", "run"),
                                           passing_yards = c(250, NA), rushing_yards = c(NA, 100), stringsAsFactors = FALSE)
  }
  m <- compute_defense_multipliers(do.call(rbind, rows), weeks = 1:3)
  expect_equal(m$pass_def_multiplier, rep(1, 32), tolerance = 1e-12)
  expect_equal(m$rush_def_multiplier, rep(1, 32), tolerance = 1e-12)
  expect_error(compute_defense_multipliers(data.frame(week = 1L, defteam = "DET", play_type = "pass",
                                                      passing_yards = 1, rushing_yards = NA)), "game_id")
})

test_that("load_defense_rankings takes an injected table and apply_defense_adjustments uses it", {
  ranks <- load_defense_rankings(2024, weeks = 1L, pbp = synthetic_pbp())
  expect_equal(nrow(ranks), 32)

  players <- tibble::tibble(
    player_id = c("p1", "p2"), player_name = c("Home QB", "Away QB"), position = "QB",
    recent_team = c("KC", "SF"),
    avg_passing_yards = c(250, 250), avg_rushing_yards = c(10, 10), avg_receiving_yards = c(0, 0)
  )
  adj <- apply_defense_adjustments(players, home_team = "KC", away_team = "SF", season = 2024,
                                   defense_ranks = ranks)
  sf_mult <- ranks$pass_def_multiplier[ranks$team == "SF"]
  kc_mult <- ranks$pass_def_multiplier[ranks$team == "KC"]
  expect_false(isTRUE(all.equal(sf_mult, kc_mult)))
  # KC's QB faces SF's defense; SF's QB faces KC's defense
  expect_equal(adj$avg_passing_yards, c(250 * sf_mult, 250 * kc_mult))
  expect_true(any(adj$avg_passing_yards != 250))
})

test_that("with no rankings, adjustments are neutral and say so", {
  players <- tibble::tibble(
    player_id = "p1", player_name = "Home QB", position = "QB", recent_team = "KC",
    avg_passing_yards = 250, avg_rushing_yards = 10, avg_receiving_yards = 0
  )
  empty <- tibble::tibble(team = character(), pass_def_multiplier = numeric(),
                          rush_def_multiplier = numeric(), recv_def_multiplier = numeric())
  expect_message(
    adj <- apply_defense_adjustments(players, "KC", "SF", 2024, defense_ranks = empty),
    "NEUTRAL"
  )
  expect_equal(adj$avg_passing_yards, 250)
})

# --- the duplicate definition (audit P13): one definition, so source order cannot matter ---

top_level_functions <- function(path) {
  out <- character()
  for (e in parse(path, keep.source = FALSE)) {
    if (is.call(e) && (identical(e[[1]], as.name("<-")) || identical(e[[1]], as.name("="))) &&
        is.name(e[[2]]) && is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function"))) {
      out <- c(out, as.character(e[[2]]))
    }
  }
  out
}

test_that("load_defense_rankings is defined exactly once in R/ and sports/nfl/props/", {
  files <- c(list.files(file.path(.test_project_root, "R"), pattern = "[.]R$", full.names = TRUE),
             list.files(file.path(.test_project_root, "sports", "nfl", "props"),
                        pattern = "[.]R$", full.names = TRUE))
  defs <- unlist(lapply(files, function(f) {
    fn <- top_level_functions(f)
    if (length(fn)) paste0(basename(f), "::", fn)
  }))
  hits <- defs[grepl("::load_defense_rankings$", defs)]
  expect_equal(hits, "correlated_props.R::load_defense_rankings")
})

test_that("no function is defined in both R/ and sports/nfl/props/ (allowlist may only shrink)", {
  r_fns <- unlist(lapply(list.files(file.path(.test_project_root, "R"), pattern = "[.]R$",
                                    full.names = TRUE), top_level_functions))
  p_fns <- unlist(lapply(list.files(file.path(.test_project_root, "sports", "nfl", "props"),
                                    pattern = "[.]R$", full.names = TRUE), top_level_functions))
  known <- c("load_red_zone_efficiency")   # R/red_zone_data.R and data_sources.R; not a P1 item
  expect_equal(setdiff(intersect(r_fns, p_fns), known), character())
  expect_equal(setdiff(known, intersect(r_fns, p_fns)), character())
})

test_that("source order cannot change which load_defense_rankings runs", {
  paths <- c(file.path(.test_project_root, "R", "correlated_props.R"),
             file.path(.test_project_root, "sports", "nfl", "props", "data_sources.R"))
  load_in <- function(order) {
    env <- new.env(parent = globalenv())
    for (p in paths[order]) suppressMessages(sys.source(p, envir = env))
    env$load_defense_rankings
  }
  a <- load_in(1:2)
  b <- load_in(2:1)
  expect_identical(deparse(a), deparse(b))
  expect_equal(names(formals(a)), c("season", "weeks", "pbp"))
  expect_equal(nrow(a(2024, weeks = 1L, pbp = synthetic_pbp())), 32)
  expect_equal(nrow(b(2024, weeks = 1L, pbp = synthetic_pbp())), 32)
})

# Dry run of Plan 1b-1: apply the plan's code blocks, verbatim, to a throwaway worktree.
# Usage: Rscript apply_plan.R <plan.md> <worktree> <tasks, e.g. 1,2,3>
args <- commandArgs(trailingOnly = TRUE)
plan <- readLines(args[[1]], warn = FALSE, encoding = "UTF-8")
wt <- args[[2]]
tasks <- as.integer(strsplit(args[[3]], ",")[[1]])

# --- fenced code blocks (```r / ```markdown), in order ---
starts <- grep("^```(r|markdown)\\s*$", plan)
blocks <- lapply(starts, function(s) {
  e <- s + which(plan[(s + 1):length(plan)] == "```")[1]
  paste(plan[(s + 1):(e - 1)], collapse = "\n")
})
blk <- function(pattern, which = 1L) {
  hit <- which(vapply(blocks, function(b) grepl(pattern, b, fixed = TRUE), logical(1)))
  if (length(hit) < which) stop("block not found: ", pattern)
  blocks[[hit[which]]]
}
blk_eq <- function(text) {
  hit <- which(vapply(blocks, identical, logical(1), text))
  if (length(hit) != 1L) stop("exact block not found: ", text)
  blocks[[hit]]
}
path <- function(f) file.path(wt, f)
rd <- function(f) paste(readLines(path(f), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
wr <- function(f, txt) { force(txt); con <- file(path(f), open = "wb"); on.exit(close(con)); writeBin(charToRaw(enc2utf8(paste0(txt, "\n"))), con) }
replace_once <- function(f, old, new) {
  txt <- rd(f)
  n <- lengths(regmatches(txt, gregexpr(old, txt, fixed = TRUE)))
  if (n != 1L) stop(sprintf("%s: expected 1 match, found %d for:\n%s", f, n, substr(old, 1, 200)))
  wr(f, sub(old, new, txt, fixed = TRUE))
}
insert_after <- function(f, anchor, text) replace_once(f, anchor, paste0(anchor, "\n", text))
replace_range <- function(f, from, to, new) {
  x <- readLines(path(f), warn = FALSE, encoding = "UTF-8")
  i <- which(x == from); if (length(i) != 1L) stop(f, ": range start not unique: ", from)
  j <- i - 1L + which(x[i:length(x)] == to)[1]; if (is.na(j)) stop(f, ": range end not found: ", to)
  wr(f, paste(c(x[seq_len(i - 1L)], new, x[(j + 1L):length(x)]), collapse = "\n"))
}
append_to <- function(f, text) wr(f, paste0(rd(f), "\n", text))
done <- function(t) cat("applied task", t, "\n")

if (1 %in% tasks) {
  f <- "scripts/golden_master.R"
  insert_after(f, "GM_COMPARE_TOL <- 1e-6", paste0("\n", blk("gm_input_status <- function()")))
  replace_once(f, '       seconds = as.numeric(difftime(Sys.time(), started, units = "secs")))',
               blk("inputs = gm_input_status())") |> sub(pattern = "^.*\n", replacement = ""))
  insert_after(f, "  base <- gm_read(file.path(root, commits[1]))", blk("base_inputs <- gm_read_inputs"))
  insert_after(f, '    utils::write.csv(run$data, file.path(dir, "final_numeric.csv"), row.names = FALSE)', "    gm_write_inputs(run$inputs, dir)")
  replace_once(f, "                 run_seconds = round(run$seconds),", "                 run_seconds = round(run$seconds), inputs = run$inputs,")
  old_cmp <- paste(c('  } else if (mode == "compare") {',
                     '    d <- gm_diff(gm_read(dir), run$data, tol = GM_COMPARE_TOL)',
                     '    if (nrow(d)) print(d, row.names = FALSE) else cat("golden master: no differences\\n")',
                     '    if (nrow(d)) quit(status = 1)',
                     '  } else stop("mode must be record, compare or attribute")'), collapse = "\n")
  replace_once(f, old_cmp, blk("golden_inputs <- gm_read_inputs(dir)"))
  append_to("tests/testthat/test-golden-master-compare.R", paste0("\n", blk('test_that("gm_input_drift names the inputs that changed"')))
  done(1)
}
if (2 %in% tasks) {
  wr("R/mu_terms.R", blk("MU_TERM_NAMES <- c("))
  wr("tests/testthat/test-mu-terms.R", blk("mu_fixture <- function()"))
  done(2)
}
if (3 %in% tasks) {
  f <- "NFLsimulation.R"
  anchor <- paste(c("  if (file.exists(playoffs_path)) {",
                    "    tryCatch(source(playoffs_path), error = function(e) {",
                    '      message(sprintf("Note: Could not source R/playoffs.R: %s", conditionMessage(e)))',
                    "    })", "  }"), collapse = "\n")
  insert_after(f, anchor, blk("# Required modules (Plan 1b-1)"))
  insert_after("config.R", "CONFERENCE_GAME_ADJUST <- 0.0", blk("MU_TERMS_ADMITTED <- c(\"base\", \"hfa\")"))
  shrink <- paste(c("  # SHRINKAGE validation",
                    "  if (!is.numeric(SHRINKAGE) || SHRINKAGE < 0 || SHRINKAGE > 1) {",
                    '    errors <- c(errors, sprintf("SHRINKAGE=%s is invalid. Must be 0-1.", SHRINKAGE))',
                    "  }"), collapse = "\n")
  insert_after("config.R", shrink, paste0("\n", blk("# MU_TERMS_ADMITTED validation")))
  replace_once(f, blk("# If any mu is NA after all adjustments"), blk("# Simulated means: the sum of the admitted terms"))
  insert_after(f, 'saveRDS(games_ready, file.path(log_dir, paste0("games_ready_", run_id, ".rds")))', blk_eq('saveRDS(mu_terms, file.path(log_dir, paste0("mu_terms_", run_id, ".rds")))'))
  led <- readLines(path("docs/EVIDENCE_LEDGER.md"), warn = FALSE, encoding = "UTF-8")
  i <- grep("^\\| C-SHRINK \\|", led)
  wr("docs/EVIDENCE_LEDGER.md", paste(append(led, blk("| C-MU-TERMS |"), after = i), collapse = "\n"))
  append_to("tests/testthat/test-mu-terms.R", paste0("\n", blk("the engine simulates the composed means")))
  done(3)
}
if (4 %in% tasks) {
  f <- "NFLsimulation.R"
  replace_once(f, blk("    sd_home  = 0.6 * sd_home + 0.4 * (sd_goal / sqrt(2)),"), blk("dplyr::mutate(sd_home_fit = sd_home, sd_away_fit = sd_away)"))
  replace_once(f, blk("    rho_game   = rho_from_game(total_mu, spread_est)\n  )"), blk("score_variance_from_mu <- function(games) {"))
  replace_once(f, blk("    sd_home = pmax(sd_home + sd_home_adj, 5.0),"), blk("wind_interaction_away + cold_interaction_away, 0)\n  )"))
  insert_after(f, "  mutate(mu_home = mu_final$mu_home, mu_away = mu_final$mu_away)", "games_ready <- score_variance_from_mu(games_ready)")
  wr("tests/testthat/test-score-variance.R", blk("v_env <- load_script_functions"))
  done(4)
}
if (5 %in% tasks) {
  f <- "NFLsimulation.R"
  wr("R/schedule_context.R", blk("neutral_site_flag <- function(sched) {"))
  insert_after(f, '  source(file.path(base_path, "mu_terms.R"))', '  source(file.path(base_path, "schedule_context.R"))')
  insert_after(f, "  mutate(venue = if (!is.na(venue_col)) as.character(.data[[venue_col]]) else NA_character_)",
               paste0("\n", blk("# Neutral-site flag (audit M24): nflverse marks")))
  replace_once(f, "    home_team,\n    away_team,\n    venue = as.character(venue)   # <-- only the normalized column",
               blk("    neutral_site,\n    venue = as.character(venue)"))
  replace_once(f, blk("neutral_col <- intersect("), blk("# REG games in the target seasons, without neutral sites (audit M24)"))
  replace_once(f, blk("    HFA_pts = HFA_pts * .playoff_hfa_mult,"), blk("HFA_pts = home_field_points(home_hfa, league_hfa, .playoff_hfa_mult, neutral_site)"))
  replace_once(f, "    dplyr::select(game_id, game_date, home_team, away_team, home_score, away_score) |>",
               "    dplyr::select(game_id, game_date, home_team, away_team, home_score, away_score, neutral_site) |>")
  replace_once(f, "      margin_shift = (home_hfa - away_hfa)/2,",
               "      margin_shift = dplyr::if_else(neutral_site, 0, (home_hfa - away_hfa)/2),   # audit M24")
  wr("tests/testthat/test-schedule-context.R", blk("# Schedule context for the game model. Audit M24"))
  done(5)
}
if (6 %in% tasks) {
  f <- "NFLsimulation.R"
  append_to("R/schedule_context.R", blk("compute_rest_table <- function(slate, team_games, season, week,"))
  replace_once(f, "    neutral_site,\n    venue = as.character(venue)", "    neutral_site,\n    home_rest,\n    away_rest,\n    venue = as.character(venue)")
  replace_range(f, "# Compute days since last game for each team (before the slate week)", "  dplyr::select(team, days_rest, rest_points)",
                strsplit(blk("rest_tbl <- compute_rest_table(week_slate"), "\n")[[1]])
  replace_range(f, "  # rest effects at the cutpoint", "    dplyr::select(team, rest_points)",
                strsplit(blk("rest_tbl_cut <- compute_rest_table(cut_slate"), "\n")[[1]])
  append_to("tests/testthat/test-schedule-context.R", paste0("\n", blk("rest <- function(slate, tg, season = 2024L, week = 15L)")))
  done(6)
}
if (7 %in% tasks) {
  f <- "NFLsimulation.R"
  append_to("R/sleeper_api.R", blk("sleeper_fallback_allowed <- function(slate_dates, today = Sys.Date())"))
  insert_after(f, '  source(file.path(base_path, "schedule_context.R"))', '  source(file.path(base_path, "sleeper_api.R"))')
  replace_once(f, "safe_load_injuries <- function(seasons, prefer_fast = TRUE, ...) {", blk("allow_live_fallback = FALSE,\n                               stamp_season"))
  replace_range(f, "  # If nflreadr failed, try Sleeper API as fallback",
                "    message(\"  Tip: Set INJURY_MODE='sleeper' in config.R for real-time Sleeper data\")",
                strsplit(blk("Sleeper serves only today's report: use it only for a slate"), "\n")[[1]])
  replace_once(f, blk("inj_all <- safe_load_injuries(\n  seasons = sort(unique(sched$season)),\n  file_type"), blk("inj_all <- safe_load_injuries(\n  seasons = sort(unique(sched$season)),\n  allow_live_fallback"))
  replace_once(f, blk("  inj_all  <- safe_load_injuries(\n    seasons  = SEASON,\n    file_type"), blk("  inj_all  <- safe_load_injuries(\n    seasons  = SEASON,\n    allow_live_fallback"))
  wr("tests/testthat/test-sleeper-fallback.R", blk("# Audit M20: Sleeper serves only today's injury report."))
  done(7)
}

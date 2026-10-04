#!/usr/bin/env Rscript
# =============================================================================
# NFL Week Analysis Runner
# =============================================================================
#
# Usage:
#   Rscript run_week.R [week] [season]
#
# Examples:
#   Rscript run_week.R          # Uses defaults from config.R
#   Rscript run_week.R 15       # Week 15, current season
#   Rscript run_week.R 15 2024  # Week 15, 2024 season
#
# Output:
#   Web bundle:   bundles/<season>-w<WW>-sim-<UTC stamp>/  (view offline: cd web && npm run local)
#   Audit tables: artifacts/baseline_games.csv, artifacts/baseline_props.csv
#   Run logs:     run_logs/
#
# Debug mode:
#   options(nfl.ev_debug = TRUE)  # Shows EV calculation trace
#
# =============================================================================

# Parse command line arguments and publish them before config.R is sourced (audit M1:
# NFLsimulation.R re-sources config.R, so overrides must live in options, not globals)
source("R/run_config.R")
set_run_options(parse_run_args(commandArgs(trailingOnly = TRUE)))
source("config.R")

# Print run info
cat("\n")
cat("=================================================================\n")
cat("  NFL WEEK ANALYSIS\n")
cat("=================================================================\n")
cat(sprintf("  Season: %d | Week: %d\n", SEASON, WEEK_TO_SIM))
cat(sprintf("  Trials: %s | Seed: %d\n", format(N_TRIALS, big.mark = ","), SEED))
cat("=================================================================\n\n")

# Check for required packages
required_pkgs <- c("tidyverse", "nflreadr")
missing_pkgs <- required_pkgs[!sapply(required_pkgs, requireNamespace, quietly = TRUE)]

if (length(missing_pkgs) > 0) {
  cat("Installing missing packages:", paste(missing_pkgs, collapse = ", "), "\n")

  # Check if renv is active
  if (file.exists("renv.lock") && requireNamespace("renv", quietly = TRUE)) {
    message("Using renv for package management...")
    renv::restore()
  } else {
    install.packages(missing_pkgs, repos = "https://cloud.r-project.org")
  }
}

# Run the full simulation; its results go to a web bundle for the local app
message("Running NFLsimulation.R...")
message("This runs the Monte Carlo simulation and writes a web bundle (view it with: cd web && npm run local).\n")

tryCatch({
  # Bundle writer, and the code's git state before this run rewrites artifacts/
  source("R/bundle_writer.R")
  source("R/sim_bundle.R")
  run_git <- sb_git_state()

  source("NFLsimulation.R")

  # =============================================================================
  # CORRELATED PLAYER PROPS (if enabled in config.R)
  # =============================================================================
  if (exists("RUN_PLAYER_PROPS") && isTRUE(RUN_PLAYER_PROPS)) {
    cat("\n")
    cat("=================================================================\n")
    cat("  RUNNING CORRELATED PLAYER PROPS\n")
    cat("=================================================================\n")

    props_path <- file.path(getwd(), "R", "correlated_props.R")
    if (file.exists(props_path)) {
      source(props_path)

      # Run correlated props using exported simulation results
      if (exists("run_correlated_props", mode = "function") &&
          exists("last_simulation_results") &&
          length(last_simulation_results) > 0) {

        props_results <- tryCatch({
          run_correlated_props(
            game_sim_results = last_simulation_results,
            schedule_data = if (exists("schedule_for_props")) schedule_for_props else NULL,
            prop_types = if (exists("PROP_TYPES")) PROP_TYPES else c("passing", "rushing", "receiving", "td"),
            season = SEASON
          )
        }, error = function(e) {
          message(sprintf("Player props generation failed: %s", e$message))
          NULL
        })

        if (!is.null(props_results) && nrow(props_results) > 0) {
          # Export props results for artifacts/baseline_props.csv
          assign("props_results", props_results, envir = .GlobalEnv)

          # Show quick summary
          positive_ev <- props_results %>%
            dplyr::filter(recommendation != "PASS") %>%
            nrow()

          cat(sprintf("  Generated %d player props (%d with positive EV)\n",
                      nrow(props_results), positive_ev))
        } else {
          message("No player props were generated (possibly missing player data)")
        }
      } else {
        message("Simulation results not available for props correlation")
      }
    } else {
      message("correlated_props.R not found; skipping player props")
    }
  }

  # The game comparison table for artifacts/baseline_games.csv (built with or without props)
  if (exists("moneyline_report_inputs") && !is.null(moneyline_report_inputs) &&
      !is.null(moneyline_report_inputs$comparison)) {
    last_comparison_tbl <- build_moneyline_comparison_table(
      market_comparison_result = moneyline_report_inputs$comparison,
      enriched_schedule = if (exists("sched")) sched else NULL,
      join_keys = if (!is.null(moneyline_report_inputs$join_keys))
                    moneyline_report_inputs$join_keys else c("game_id", "season", "week"),
      vig = 0.10,
      verbose = FALSE
    )
  } else {
    message("No moneyline comparison inputs from NFLsimulation.R; artifacts/baseline_games.csv not written.")
  }

  # Export audit artifacts (baseline tables + run context)
  tryCatch({
    artifact_dir <- file.path(getwd(), "artifacts")
    if (!dir.exists(artifact_dir)) dir.create(artifact_dir, recursive = TRUE)
    if (exists("last_comparison_tbl") && is.data.frame(last_comparison_tbl)) {
      games_export <- last_comparison_tbl
      list_cols <- vapply(games_export, is.list, logical(1))
      if (any(list_cols)) {
        games_export[list_cols] <- lapply(games_export[list_cols], function(col) {
          vapply(col, function(v) {
            if (is.null(v) || length(v) == 0) return(NA_character_)
            if (is.atomic(v)) return(paste(v, collapse = ";"))
            paste(unlist(v), collapse = ";")
          }, character(1))
        })
      }
      utils::write.csv(games_export, file.path(artifact_dir, "baseline_games.csv"), row.names = FALSE)
    }
    if (exists("props_results") && is.data.frame(props_results)) {
      props_export <- props_results
      list_cols <- vapply(props_export, is.list, logical(1))
      if (any(list_cols)) {
        props_export[list_cols] <- lapply(props_export[list_cols], function(col) {
          vapply(col, function(v) {
            if (is.null(v) || length(v) == 0) return(NA_character_)
            if (is.atomic(v)) return(paste(v, collapse = ";"))
            paste(unlist(v), collapse = ";")
          }, character(1))
        })
      }
      utils::write.csv(props_export, file.path(artifact_dir, "baseline_props.csv"), row.names = FALSE)
    }

    log_dir <- file.path(getwd(), "run_logs")
    if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    commit_hash <- tryCatch(system("git rev-parse HEAD", intern = TRUE), error = function(e) NA_character_)
    trials <- if (exists("N_TRIALS")) format(N_TRIALS, big.mark = ",") else "NA"
    log_lines <- c(
      sprintf("timestamp=%s", timestamp),
      sprintf("season=%s", SEASON),
      sprintf("week=%s", WEEK_TO_SIM),
      sprintf("trials=%s", trials),
      sprintf("commit=%s", ifelse(length(commit_hash) > 0, commit_hash[1], NA_character_))
    )
    writeLines(log_lines, file.path(log_dir, sprintf("audit_context_%s.txt", timestamp)))
  }, error = function(e) {
    message(sprintf("Audit artifact export failed: %s", e$message))
  })

  # Web bundle: the results the local app shows (replaces the retired HTML report, A8)
  cat("\n")
  # draws missing (NFLsimulation.R's export failed) -> every game is a QA failure, not a crash
  sim_bundle <- write_sim_bundle(
    final = final, sims = get0("last_simulation_results", ifnotfound = NULL), schedule = sched, quality = get_data_quality(),
    season = SEASON, week = WEEK_TO_SIM, seed = SEED, n_sims = N_TRIALS, git = run_git
  )
  report_sim_bundle(sim_bundle)

  cat("\n")
  cat("=================================================================\n")
  cat("  ANALYSIS COMPLETE\n")
  cat("=================================================================\n")
  cat("  Check the run_logs/ folder for output files.\n")
  cat("  View the results offline: cd web && npm run local\n")
  if (exists("props_results") && !is.null(props_results)) {
    cat("  Player props included in analysis.\n")
  }
  cat("=================================================================\n")

}, error = function(e) {
  cat("\n")
  cat("=================================================================\n")
  cat("  ERROR DURING ANALYSIS\n")
  cat("=================================================================\n")
  cat(sprintf("  %s\n", conditionMessage(e)))
  cat("=================================================================\n")
  quit(status = 1)
})

cat("\nDone.\n")

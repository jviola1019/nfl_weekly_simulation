#!/usr/bin/env Rscript
# Golden master for the game model (audit plan Phase 1a).
#   record    <week> <season> <out_dir>      run the game model, store numeric outputs
#   compare   <week> <season> <golden_dir>   run again, print per-column differences
#   attribute <dirs_root> <commit>...        diff recorded runs commit by commit (no model run)
# The model is run by sourcing NFLsimulation.R directly (player props run from
# run_week.R, so they are not part of this run), which keeps the output deterministic.
# CI (.github/workflows/golden-master.yml) records every commit of a PR in parallel and
# runs `attribute`, because the model needs packages and network a local sandbox may lack.

# compare tolerance: the CI determinism check (baseline recorded twice) differs by up to
# 4e-9 in fitted SD / NB-size columns (optimizer noise); anything above 1e-6 is a change.
GM_COMPARE_TOL <- 1e-6

gm_diff <- function(golden, current, tol = 0) {
  if (!setequal(golden$game_id, current$game_id)) stop("gm_diff: game_id sets differ")
  current <- current[match(golden$game_id, current$game_id), , drop = FALSE]
  cols <- intersect(setdiff(names(golden), "game_id"), names(current))
  rows <- lapply(cols, function(cl) {
    a <- golden[[cl]]; b <- current[[cl]]
    diff <- abs(a - b); diff[is.na(a) & is.na(b)] <- 0; diff[xor(is.na(a), is.na(b))] <- Inf
    changed <- diff > tol
    if (!any(changed)) return(NULL)
    data.frame(column = cl, n_games_changed = sum(changed), max_abs_diff = max(diff))
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) data.frame(column = character(), n_games_changed = integer(), max_abs_diff = numeric()) else out
}

gm_run_model <- function(week, season) {
  source("R/run_config.R")
  set_run_options(list(week = as.integer(week), season = as.integer(season)))
  source("config.R")
  started <- Sys.time()
  source("NFLsimulation.R")
  latest <- list.files("run_logs", pattern = "^final_.*\\.rds$", full.names = TRUE)
  latest <- latest[file.mtime(latest) >= started]
  if (!length(latest)) stop("golden_master: NFLsimulation.R wrote no run_logs/final_*.rds")
  final <- readRDS(latest[which.max(file.mtime(latest))])
  num <- vapply(final, is.numeric, logical(1))
  list(data = as.data.frame(final[, c("game_id", names(final)[num & names(final) != "game_id"])]),
       seconds = as.numeric(difftime(Sys.time(), started, units = "secs")))
}

# Same check as tests/testthat/helper-live.R: any HTTP response counts as reachable
gm_host_reachable <- function(host, timeout = 5) {
  handle <- curl::new_handle(nobody = TRUE, connecttimeout = timeout, timeout = timeout)
  tryCatch({ curl::curl_fetch_memory(paste0("https://", host, "/"), handle = handle); TRUE }, error = function(e) FALSE)
}

gm_read <- function(dir) utils::read.csv(file.path(dir, "final_numeric.csv"), stringsAsFactors = FALSE)

gm_print_diff <- function(title, d) {
  cat("\n### ", title, "\n", sep = "")
  if (nrow(d)) print(d, row.names = FALSE) else cat("golden master: no differences\n")
}

gm_attribute <- function(root, commits) {
  base <- gm_read(file.path(root, commits[1]))
  rep_dir <- file.path(root, paste0(commits[1], "-rep2"))
  if (dir.exists(rep_dir)) gm_print_diff(sprintf("determinism: %s recorded twice", substr(commits[1], 1, 7)),
                                         gm_diff(base, gm_read(rep_dir)))
  prev <- base
  for (i in seq_along(commits)[-1]) {
    cur <- gm_read(file.path(root, commits[i]))
    gm_print_diff(sprintf("%s vs previous commit %s", substr(commits[i], 1, 7), substr(commits[i - 1], 1, 7)),
                  gm_diff(prev, cur))
    prev <- cur
  }
  gm_print_diff(sprintf("head %s vs baseline %s", substr(commits[length(commits)], 1, 7), substr(commits[1], 1, 7)),
                gm_diff(base, prev))
  for (cm in unique(c(commits[1], commits[length(commits)]))) {
    cat("\n### final_numeric.csv @ ", cm, "\n", sep = "")
    writeLines(readLines(file.path(root, cm, "final_numeric.csv")))
    cat("### meta.json @ ", cm, "\n", sep = "")
    writeLines(readLines(file.path(root, cm, "meta.json")))
  }
}

gm_main <- function(args) {
  mode <- args[[1]]
  if (mode == "attribute") return(invisible(gm_attribute(args[[2]], args[-(1:2)])))
  week <- args[[2]]; season <- args[[3]]; dir <- args[[4]]
  if (mode == "compare" && !gm_host_reachable("github.com")) {
    # nflverse data come from GitHub releases; offline is a LIVE skip, not a failure
    cat("LIVE: github.com unreachable; golden master not compared\n")
    quit(status = 3)
  }
  run <- gm_run_model(week, season)
  if (mode == "record") {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(run$data, file.path(dir, "final_numeric.csv"), row.names = FALSE)
    meta <- list(week = week, season = season, n_games = nrow(run$data),
                 git_sha = system2("git", c("rev-parse", "HEAD"), stdout = TRUE),
                 n_trials = N_TRIALS, seed = SEED, r_version = R.version.string,
                 nflreadr = as.character(utils::packageVersion("nflreadr")),
                 run_seconds = round(run$seconds),
                 csv_sha256 = digest::digest(file = file.path(dir, "final_numeric.csv"), algo = "sha256"))
    writeLines(jsonlite::toJSON(meta, auto_unbox = TRUE, pretty = TRUE), file.path(dir, "meta.json"))
    cat("recorded", nrow(run$data), "games to", dir, "\n")
  } else if (mode == "compare") {
    d <- gm_diff(gm_read(dir), run$data, tol = GM_COMPARE_TOL)
    if (nrow(d)) print(d, row.names = FALSE) else cat("golden master: no differences\n")
    if (nrow(d)) quit(status = 1)
  } else stop("mode must be record, compare or attribute")
}

if (sys.nframe() == 0L) gm_main(commandArgs(trailingOnly = TRUE))

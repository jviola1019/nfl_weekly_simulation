# =============================================================================
# Simulator bundle: NFLsimulation.R's results as a weekly R -> web bundle (spec §3)
# =============================================================================
# Replaces the retired HTML report (checkpoint A8). run_week.R writes this bundle and
# the local web app (cd web && npm run local) ingests and serves it with no network.
#   - game_predictions: per game a C0 row (the no-vig market) and a C3 row (the
#     simulator: p_home_raw = simulator two-way, p_home_final = after its market blend).
#   - score_distributions: margin and total, one bin per integer outcome over the
#     central SB_MASS of the simulated draws; p is the share of ALL draws.
#   - source_status: the run's data-quality tracker (R/data_validation.R) plus nflverse.
# Every problem found is a QA failure in the manifest (the ingest then stores the run
# as qa_failed and keeps the last good run); nothing is filled in silently. A game
# without a market line keeps NA market fields (audit M11).
# Needs R/bundle_writer.R.
# =============================================================================

SB_MASS <- 0.999
SB_MODEL_LABEL <- "Game simulator C3 (unvalidated)"
SB_FINAL_COLUMNS <- c("game_id", "home_p_2w_model", "home_p_2w_blend", "home_p_2w_mkt",
                      "market_available", "margin_median", "total_median")
# Relocated franchises share one team id, as backtest/build_inputs.R bt_franchise() maps them
SB_FRANCHISE <- c(OAK = "LV", SD = "LAC", STL = "LA")
# Data-quality tracker status -> source_status status (contract: ok | stale | failed | unavailable)
SB_STATUS <- list(
  injury = c(full = "ok", partial = "stale", unavailable = "unavailable"),
  weather = c(full = "ok", partial_fallback = "stale", all_fallback = "failed"),
  market = c(full = "ok", partial = "stale", unavailable = "unavailable")
)

sb_franchise <- function(team) {
  out <- unname(SB_FRANCHISE[team])
  ifelse(is.na(out), team, out)
}

# nflverse gameday/gametime are US Eastern; kickoff_utc is ISO-8601 UTC
sb_kickoff_utc <- function(gameday, gametime) {
  gametime[is.na(gametime) | !nzchar(gametime)] <- "13:00"
  lt <- as.POSIXct(paste(gameday, gametime), format = "%Y-%m-%d %H:%M", tz = "America/New_York")
  format(lt, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

sb_col <- function(df, col) if (col %in% names(df)) df[[col]] else rep(NA, nrow(df))

#' Integer-outcome histogram of simulated draws over their central `mass`:
#' data.frame(x, p), x every integer from the lower to the upper type-1 quantile and p
#' the share of ALL draws at x, so sum(p) is the covered share (at least `mass`).
sb_bins <- function(draws, mass = SB_MASS) {
  draws <- as.numeric(draws)
  if (!length(draws) || any(!is.finite(draws))) stop("sb_bins: draws must be finite and non-empty", call. = FALSE)
  if (any(abs(draws - round(draws)) > 1e-9)) stop("sb_bins: draws must be integers", call. = FALSE)
  draws <- round(draws)
  tail <- (1 - mass) / 2
  lo <- as.integer(stats::quantile(draws, tail, type = 1, names = FALSE))
  hi <- as.integer(stats::quantile(draws, 1 - tail, type = 1, names = FALSE))
  x <- seq.int(lo, hi)
  counts <- tabulate(as.integer(draws[draws >= lo & draws <= hi]) - lo + 1L, nbins = length(x))
  data.frame(x = x, p = counts / length(draws))
}

#' The games table (contract `games`) for `game_ids`, from nflverse schedule rows
sb_games_table <- function(schedule, game_ids) {
  s <- as.data.frame(schedule)[match(game_ids, schedule$game_id), , drop = FALSE]
  location <- sb_col(s, "location")
  data.frame(
    game_id = game_ids,
    season = as.integer(s$season),
    week = as.integer(s$week),
    game_type = as.character(sb_col(s, "game_type")),
    home_team_id = sb_franchise(as.character(s$home_team)),
    away_team_id = sb_franchise(as.character(s$away_team)),
    kickoff_utc = sb_kickoff_utc(as.character(s$gameday), as.character(sb_col(s, "gametime"))),
    roof = as.character(sb_col(s, "roof")),
    neutral = !is.na(location) & location == "Neutral",
    home_score = as.integer(sb_col(s, "home_score")),
    away_score = as.integer(sb_col(s, "away_score")),
    stringsAsFactors = FALSE
  )
}

#' C0 (market) and C3 (simulator) rows per game. The market is used only where the
#' engine flagged it available: NFLsimulation.R leaves the model probability in
#' home_p_2w_mkt when a line is missing (attach_market_probs), and that is not a market.
#' C3 p_home_final is the production pipeline's probability: the engine blend shrunk toward
#' the no-vig market with `shrinkage` (SHRINKAGE, config.R), the same call
#' build_moneyline_comparison_table makes for blend_home_prob_shrunk (NFLmarket.R). A game
#' without a market has nothing to shrink toward and keeps the unshrunk blend.
sb_predictions <- function(final, shrinkage = SHRINKAGE) {
  f <- as.data.frame(final)
  mkt <- ifelse(f$market_available %in% TRUE, f$home_p_2w_mkt, NA_real_)
  p_final <- ifelse(is.na(mkt), f$home_p_2w_blend,
                    shrink_probability_toward_market(f$home_p_2w_blend, mkt, shrinkage = shrinkage))
  c0 <- data.frame(game_id = f$game_id, candidate = "C0", p_home_raw = mkt, p_home_final = mkt,
                   p_home_mkt_novig = mkt, margin_q50 = NA_real_, total_q50 = NA_real_, stringsAsFactors = FALSE)
  c3 <- data.frame(game_id = f$game_id, candidate = "C3", p_home_raw = f$home_p_2w_model,
                   p_home_final = p_final, p_home_mkt_novig = mkt,
                   margin_q50 = f$margin_median, total_q50 = f$total_median, stringsAsFactors = FALSE)
  rbind(c0, c3)
}

#' Margin and total bins per game; a game whose draws cannot be binned is a QA failure
sb_distributions <- function(sims, game_ids, mass = SB_MASS) {
  rows <- list()
  qa <- character()
  for (id in game_ids) {
    for (kind in c("margin", "total")) {
      bins <- tryCatch(sb_bins(sims[[id]][[kind]], mass), error = function(e) {
        qa <<- c(qa, sprintf("score_distributions: %s %s: %s", id, kind, conditionMessage(e)))
        NULL
      })
      if (!is.null(bins)) rows[[length(rows) + 1]] <- list(game_id = id, kind = kind, bins = bins)
    }
  }
  table <- data.frame(game_id = vapply(rows, `[[`, "", "game_id"), kind = vapply(rows, `[[`, "", "kind"),
                      stringsAsFactors = FALSE)
  table$bins <- lapply(rows, `[[`, "bins")
  list(table = table, qa = qa)
}

sb_detail <- function(what, status, ids_label, ids) {
  base <- sprintf("%s: tracker status '%s'", what, status)
  if (length(ids)) sprintf("%s; %s %s", base, ids_label, paste(sort(as.character(ids)), collapse = ", ")) else base
}

#' source_status rows from get_data_quality(); a status the map does not know
#' (including "unknown": the run never recorded one) becomes "failed". Games whose
#' schedule row has no kickoff time are named, because sb_kickoff_utc() shows them at
#' 1:00 PM ET (as backtest/build_inputs.R does) and that must not pass silently. Games in
#' `unshrunk` have no market, so their C3 p_home_final is the unshrunk blend (sb_predictions).
sb_source_status <- function(quality, now = Sys.time(), kickoff_assumed = character(), unshrunk = character()) {
  map <- function(kind, s) {
    st <- unname(SB_STATUS[[kind]][s])
    if (length(st) != 1 || is.na(st)) "failed" else st
  }
  status <- c("ok", map("injury", quality$injury$status), map("weather", quality$weather$status),
              map("market", quality$market$status))
  data.frame(
    source = c("nflverse_schedules", "injury_reports", "weather", "market_lines"),
    status = status,
    last_success_utc = ifelse(status %in% c("ok", "stale"), bw_utc(now), NA_character_),
    detail = c(
      paste0("schedule, scores and consensus closing lines via nflreadr",
             if (length(kickoff_assumed)) sprintf("; no kickoff time for %s (shown as 1:00 PM ET)",
                                                  paste(sort(as.character(kickoff_assumed)), collapse = ", ")) else ""),
      sb_detail("injury reports", quality$injury$status, "seasons missing", quality$injury$missing_seasons),
      sb_detail("game-day weather", quality$weather$status, "fallback weather for", quality$weather$fallback_games),
      paste0(sb_detail("closing moneylines", quality$market$status, "no market line for", quality$market$missing_games),
             if (length(unshrunk)) sprintf("; C3 unshrunk (no market): %s", paste(sort(as.character(unshrunk)), collapse = ", ")) else "")
    ),
    stringsAsFactors = FALSE
  )
}

#' All tables of a simulator bundle plus the QA failures found while building them.
#' A `final` missing a required column is a programming error and stops.
build_sim_bundle_tables <- function(final, sims, schedule, quality,
                                    teams_csv = file.path("data", "reference", "teams.csv"), now = Sys.time(),
                                    shrinkage = SHRINKAGE) {
  missing <- setdiff(SB_FINAL_COLUMNS, names(final))
  if (length(missing)) stop("build_sim_bundle_tables: final lacks ", paste(missing, collapse = ", "), call. = FALSE)
  ids <- as.character(final$game_id)
  flag <- function(cond_ids, fmt) if (length(cond_ids)) sprintf(fmt, paste(cond_ids, collapse = ", ")) else character()
  qa <- c(
    flag(unique(ids[duplicated(ids)]), "game_predictions: duplicate game_id %s"),
    flag(setdiff(ids, schedule$game_id), "games: not in the schedule: %s"),
    flag(setdiff(ids, names(sims)), "score_distributions: no simulated draws for %s"),
    flag(setdiff(names(sims), ids), "score_distributions: draws for games not in final: %s"),
    flag(ids[!is.finite(final$home_p_2w_model)], "game_predictions: C3 p_home_raw missing for %s"),
    flag(ids[!is.finite(final$home_p_2w_blend)], "game_predictions: C3 p_home_final missing for %s")
  )
  teams <- utils::read.csv(teams_csv, stringsAsFactors = FALSE)[, c("team_id", "full_name", "division", "tz")]
  games <- sb_games_table(schedule, ids)
  gametime <- as.character(sb_col(as.data.frame(schedule), "gametime"))[match(ids, schedule$game_id)]
  kickoff_assumed <- ids[ids %in% schedule$game_id & (is.na(gametime) | !nzchar(gametime))]
  unknown <- setdiff(stats::na.omit(c(games$home_team_id, games$away_team_id)), teams$team_id)
  qa <- c(qa, flag(unknown, "games: team ids not in data/reference/teams.csv: %s"))
  dist <- sb_distributions(sims, intersect(ids, names(sims)))
  unshrunk <- ids[!(final$market_available %in% TRUE)]
  list(
    tables = list(teams = teams, games = games, game_predictions = sb_predictions(final, shrinkage),
                  score_distributions = dist$table,
                  source_status = sb_source_status(quality, now, kickoff_assumed, unshrunk)),
    qa = c(qa, dist$qa)
  )
}

#' git provenance for the bundle. run_week.R rewrites the tracked artifacts/*.csv on
#' every run; they are outputs, not code, so they do not mark the code dirty.
sb_git_state <- function() {
  sha <- tryCatch(system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
  status <- tryCatch(system2("git", c("status", "--porcelain", "--untracked-files=no", "--", ".", ":(exclude)artifacts"),
                             stdout = TRUE, stderr = FALSE), error = function(e) NULL)
  list(code_git_sha = if (length(sha)) sha[1] else NA_character_,
       code_dirty = if (is.null(status)) NA else length(status) > 0)
}

#' Write the simulator's weekly bundle to <out_root>/<cycle_id>/ and return its manifest
#' (bw_write_bundle; qa$ok is FALSE when anything above was flagged)
write_sim_bundle <- function(final, sims, schedule, quality, season, week, seed, n_sims,
                             out_root = "bundles", now = Sys.time(), git = sb_git_state(),
                             cycle_id = sprintf("%d-w%02d-sim-%s", as.integer(season), as.integer(week),
                                                format(now, "%Y%m%dT%H%M%SZ", tz = "UTC")),
                             teams_csv = file.path("data", "reference", "teams.csv"),
                             contracts_dir = file.path("contracts", "schema"), renv_lock = "renv.lock",
                             shrinkage = SHRINKAGE) {
  built <- build_sim_bundle_tables(final, sims, schedule, quality, teams_csv = teams_csv, now = now,
                                   shrinkage = shrinkage)
  # provenance is part of the contract; a run outside a git checkout must not look clean
  if (length(git$code_git_sha) != 1 || is.na(git$code_git_sha) || !nzchar(git$code_git_sha)) {
    built$qa <- c(built$qa, "manifest: code_git_sha unavailable: run from a git checkout")
  }
  meta <- list(
    cycle_id = cycle_id, season = as.integer(season), week = as.integer(week),
    model_label = SB_MODEL_LABEL, data_asof_utc = bw_utc(now),
    code_git_sha = git$code_git_sha, code_dirty = git$code_dirty,
    config = list(
      engine = "NFLsimulation.R (Monte Carlo: negative binomial scores, Gaussian copula)",
      candidates = list(C0 = "no-vig market",
                        C3 = "simulator two-way home win probability; p_home_final after the production pipeline's shrinkage toward the no-vig market (unshrunk where a game has no market)"),
      shrinkage = shrinkage,
      market_source = "nflverse consensus close: moneylines devigged proportionally (the spread mapped to a probability where a game has no moneyline)",
      calibration_method = quality$calibration$method,
      distribution_mass = SB_MASS
    ),
    seed = if (is.null(seed)) NULL else as.integer(seed),
    n_sims = as.integer(n_sims)
  )
  bw_write_bundle(out_root, "weekly", meta, built$tables, extra_qa_failures = built$qa,
                  contracts_dir = contracts_dir, renv_lock = renv_lock)
}

#' Console lines for run_week.R: where the bundle went, its QA and how to view it
report_sim_bundle <- function(manifest) {
  failures <- unlist(manifest$qa$failures)
  lines <- c(
    sprintf("  Web bundle: %s", manifest$dir),
    if (isTRUE(manifest$qa$ok)) "  QA: passed" else c(
      sprintf("  QA: FAILED (%d); the app stores this run as qa_failed and keeps showing the last good run:", length(failures)),
      paste0("    - ", failures)
    ),
    "  View it offline: cd web && npm run local   (then open http://127.0.0.1:3000)"
  )
  cat(paste0(lines, "\n"), sep = "")
  invisible(lines)
}

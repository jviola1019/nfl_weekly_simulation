# =============================================================================
# FILE: NFLmarket.R
# PURPOSE: Market comparison and betting analytics engine for NFL predictions.
#          Handles market data integration, probability shrinkage and Kelly staking.
#          The HTML report was retired at checkpoint A8: run_week.R writes a web
#          bundle (R/sim_bundle.R) that the local app serves (cd web && npm run local).
#
# AUTHOR: Data Analyst <analyst@example.com>
# VERSION: 2.7.0
# LAST UPDATED: 2026-02-02
#
# DEPENDENCIES:
#   - tidyverse: Data manipulation and visualization
#   - NFLbrier_logloss.R: Scoring metrics
#   - R/utils.R: Core utility functions
#
# EXPORTS:
#   - build_moneyline_comparison_table(): Main market comparison engine
#   - shrink_probability_toward_market(): Probability shrinkage (60% market)
#   - expected_value_units(): EV calculation for betting decisions
#   - conservative_kelly_stake(): 1/8 Kelly with edge caps
#
# KEY PARAMETERS:
#   - SHRINKAGE (config.R): Market weight for probability blending (default: 0.6)
#   - KELLY_FRACTION (config.R): Kelly criterion fraction (default: 0.125)
#   - MAX_EDGE (config.R): Maximum believable edge cap (default: 0.10)
#
# VALIDATION:
#   - Test file: tests/testthat/test-market.R
#   - Edge quality flags: >15% flagged as "Implausible"
#   - EV uses shrunk probabilities (build_moneyline_comparison_table)
# =============================================================================

suppressPackageStartupMessages({
  # Source canonical utilities from R/utils.R first
  local({
    utils_path <- if (file.exists("R/utils.R")) "R/utils.R" else file.path(getwd(), "R/utils.R")
    if (file.exists(utils_path)) {
      tryCatch(source(utils_path), error = function(e) {
        message(sprintf("Note: Could not source R/utils.R: %s", conditionMessage(e)))
      })
    }
  })
  source("NFLbrier_logloss.R")
  # Source props policy helpers if available
  local({
    props_config_path <- if (file.exists("sports/nfl/props/props_config.R")) {
      "sports/nfl/props/props_config.R"
    } else {
      file.path(getwd(), "sports", "nfl", "props", "props_config.R")
    }
    if (file.exists(props_config_path)) {
      tryCatch(source(props_config_path), error = function(e) {
        message(sprintf("Note: Could not source props_config.R: %s", conditionMessage(e)))
      })
    }
  })
  library(tidyverse)
})

# Provide a no-op join signal emitter when not available from logging utilities.
if (!exists("emit_safe_join_signal", mode = "function", inherits = TRUE)) {
  emit_safe_join_signal <- function(message, label = NULL, severity = "inform") {
    message(message)
  }
}

# ------------------------------------------------------------------------------
# Shared join-key metadata ------------------------------------------------------
# ------------------------------------------------------------------------------

if (!exists("JOIN_KEY_ALIASES", inherits = FALSE)) {
  JOIN_KEY_ALIASES <- list(
    game_id = c("game_id", "gameid", "gameId", "gid"),
    season  = c("season", "season_std", "Season", "season_year", "seasonYear", "year"),
    week    = c("week", "week_std", "Week", "game_week", "gameWeek", "gameday_week", "wk")
  )
}

if (!exists("PREDICTION_JOIN_KEYS", inherits = FALSE)) {
  PREDICTION_JOIN_KEYS <- names(JOIN_KEY_ALIASES)
}

# ------------------------------------------------------------------------------
# General-purpose helpers -------------------------------------------------------
# ------------------------------------------------------------------------------
# Note: first_non_missing_typed() is defined in NFLbrier_logloss.R (sourced above)

collapse_by_keys_relaxed <- function(df, keys, label = "data frame") {
  if (is.null(df) || !nrow(df) || !length(keys)) {
    return(df)
  }

  missing_keys <- setdiff(keys, names(df))
  if (length(missing_keys)) {
    emit_safe_join_signal(
      sprintf(
        "%s is missing required key columns: %s; skipping duplicate collapse.",
        label,
        paste(missing_keys, collapse = ", ")
      ),
      label,
      severity = "warn"
    )
    return(df)
  }

  complete_mask <- stats::complete.cases(df[keys])
  df_complete <- df[complete_mask, , drop = FALSE]
  df_incomplete <- df[!complete_mask, , drop = FALSE]

  if (!nrow(df_complete)) {
    return(df)
  }

  dup <- df_complete %>%
    dplyr::count(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::filter(.data$n > 1L)

  if (!nrow(dup)) {
    return(df)
  }

  message(sprintf(
    "%s: collapsing %d duplicate rows keyed by %s (relaxed).",
    label,
    nrow(dup),
    paste(keys, collapse = ", ")
  ))

  non_key_cols <- setdiff(names(df_complete), keys)

  collapsed_complete <- df_complete %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::summarise(
      dplyr::across(
        dplyr::all_of(non_key_cols),
        ~ first_non_missing_typed(.x),
        .names = "{.col}"
      ),
      .groups = "drop"
    )

  out <- dplyr::bind_rows(collapsed_complete, df_incomplete) %>%
    dplyr::select(dplyr::all_of(names(df)))

  dup_check <- out %>%
    dplyr::filter(dplyr::if_all(dplyr::all_of(keys), ~ !is.na(.))) %>%
    dplyr::count(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::filter(.data$n > 1L)

  if (nrow(dup_check)) {
    emit_safe_join_signal(
      sprintf(
        "%s: duplicates remain for %d key combinations after relaxed collapse.",
        label,
        nrow(dup_check)
      ),
      label,
      severity = "warn"
    )
  }

  out
}

ensure_unique_join_keys <- function(df, keys, label = "data frame") {
  if (is.null(df) || !inherits(df, "data.frame") || !nrow(df) || !length(keys)) {
    return(df)
  }

  missing_keys <- setdiff(keys, names(df))
  if (length(missing_keys)) {
    emit_safe_join_signal(
      sprintf(
        "%s: cannot check join uniqueness because keys are missing: %s",
        label,
        paste(missing_keys, collapse = ", ")
      ),
      label,
      severity = "warn"
    )
    return(df)
  }

  dup_keys <- df %>%
    dplyr::filter(dplyr::if_all(dplyr::all_of(keys), ~ !is.na(.))) %>%
    dplyr::count(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::filter(.data$n > 1L)

  if (!nrow(dup_keys)) {
    return(df)
  }

  emit_safe_join_signal(
    sprintf(
      "%s: detected %d duplicate join key combinations; keeping first occurrence after sorting.",
      label,
      nrow(dup_keys)
    ),
    label,
    severity = "inform"
  )

  df %>%
    dplyr::arrange(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::distinct(dplyr::across(dplyr::all_of(keys)), .keep_all = TRUE)
}

count_duplicate_join_rows <- function(df, keys) {
  if (is.null(df) || !inherits(df, "data.frame") || !nrow(df) || !length(keys)) {
    return(NA_integer_)
  }

  missing_keys <- setdiff(keys, names(df))
  if (length(missing_keys)) {
    return(NA_integer_)
  }

  df %>%
    dplyr::filter(dplyr::if_all(dplyr::all_of(keys), ~ !is.na(.))) %>%
    dplyr::count(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::filter(.data$n > 1L) %>%
    nrow()
}

infer_join_relationship <- function(x, y, keys, label = NULL, default = NULL) {
  result <- list(
    relationship = default,
    x_duplicates = NA_integer_,
    y_duplicates = NA_integer_
  )

  if (!length(keys)) {
    return(result)
  }

  dups_x <- count_duplicate_join_rows(x, keys)
  dups_y <- count_duplicate_join_rows(y, keys)

  result$x_duplicates <- dups_x
  result$y_duplicates <- dups_y

  if (is.na(dups_x) || is.na(dups_y)) {
    return(result)
  }

  relationship <- default
  if (dups_x > 0L && dups_y > 0L) {
    relationship <- "many-to-many"
  } else if (dups_x > 0L) {
    relationship <- "one-to-many"
  } else if (dups_y > 0L) {
    relationship <- "many-to-one"
  } else if (is.null(default)) {
    relationship <- "one-to-one"
  }

  result$relationship <- relationship

  if ((dups_x > 0L || dups_y > 0L) && !is.null(label)) {
    msg <- sprintf(
      "%s: inferred %s join on keys %s (duplicates: x=%d, y=%d).",
      label,
      relationship,
      paste(keys, collapse = ", "),
      dups_x,
      dups_y
    )
    if (exists("emit_safe_join_signal", mode = "function")) {
      emit_safe_join_signal(msg, label, severity = "inform")
    } else {
      message(msg)
    }
  }

  result
}

resolve_join_key_map <- function(by, x, y) {
  dplyr_ns <- asNamespace("dplyr")
  common_by <- NULL
  if (exists("common_by", envir = dplyr_ns, inherits = FALSE)) {
    common_by <- get("common_by", envir = dplyr_ns)
  }

  if (!is.null(common_by)) {
    mapped <- tryCatch(common_by(by, x, y), error = function(e) NULL)
    if (!is.null(mapped) && all(c("x", "y") %in% names(mapped))) {
      return(list(x = mapped$x, y = mapped$y))
    }
  }

  if (is.null(by)) {
    return(list(x = character(), y = character()))
  }

  if (is.character(by)) {
    if (is.null(names(by)) || !length(names(by))) {
      return(list(x = by, y = by))
    }
    return(list(x = names(by), y = unname(by)))
  }

  list(x = character(), y = character())
}

safe_left_join <- function(x, y, by = NULL, relationship = NULL, label = "left_join", ...) {
  join_args <- c(list(x = x, y = y, by = by), list(...))
  has_relationship <- !is.null(relationship) && "relationship" %in% names(formals(dplyr::left_join))
  if (has_relationship) {
    join_args$relationship <- relationship
  }

  join_exec <- function(args) {
    rlang::exec(dplyr::left_join, !!!args)
  }

  tryCatch(
    join_exec(join_args),
    error = function(e) {
      msg <- conditionMessage(e)
      dup_error <- grepl("Each row in `y` must be matched at most once", msg, fixed = TRUE) ||
        grepl("Many-to-many relationship", msg, fixed = TRUE)

      if (!dup_error) {
        stop(e)
      }

      key_map <- resolve_join_key_map(by, x, y)
      y_keys <- key_map$y

      if (!length(y_keys) || !all(y_keys %in% names(y))) {
        warning(sprintf(
          "%s: duplicate join keys detected but unable to determine right-table keys; retrying without relationship enforcement. Original error: %s",
          label,
          msg
        ))
        if (has_relationship) {
          join_args$relationship <- NULL
        }
        return(join_exec(join_args))
      }

      y_dedup <- y %>%
        dplyr::arrange(dplyr::across(dplyr::all_of(y_keys))) %>%
        dplyr::distinct(dplyr::across(dplyr::all_of(y_keys)), .keep_all = TRUE)

      removed <- nrow(y) - nrow(y_dedup)
      warning(sprintf(
        "%s: resolved %d duplicate rows on right join keys after %s; original error: %s",
        label,
        max(removed, 0L),
        label,
        msg
      ))

      join_args$y <- y_dedup
      if (has_relationship) {
        join_args$relationship <- relationship
      }

      join_exec(join_args)
    }
  )
}

standardize_join_keys <- function(df, key_alias = JOIN_KEY_ALIASES) {
  # NOTE: Canonical version is in R/utils.R. This definition exists for standalone

  # sourcing. Includes CRITICAL type coercion for reliable joins.
  if (is.null(df) || !inherits(df, "data.frame")) {
    return(df)
  }

  out <- df

  # Rename aliases to canonical names
  for (canonical in names(key_alias)) {
    if (canonical %in% names(out)) next
    alt_names <- unique(c(key_alias[[canonical]], canonical))
    alt_names <- alt_names[alt_names != canonical]
    match <- alt_names[alt_names %in% names(out)]
    if (length(match)) {
      out <- dplyr::rename(out, !!canonical := !!rlang::sym(match[1]))
    }
  }

  # CRITICAL: Coerce to standard types for reliable joins
  # Without this, integer vs character mismatches cause silent join failures
  if ("game_id" %in% names(out)) {
    out$game_id <- as.character(out$game_id)
  }
  if ("season" %in% names(out)) {
    out$season <- as.integer(out$season)
  }
  if ("week" %in% names(out)) {
    out$week <- as.integer(out$week)
  }
  if ("game_type" %in% names(out)) {
    out$game_type <- as.character(out$game_type)
  }

  out
}

select_first_column <- function(df, candidates) {
  intersect(candidates, names(df))[1]
}

copy_column_if_missing <- function(df, target, source, overwrite = FALSE) {
  if (!source %in% names(df)) {
    return(df)
  }
  needs_copy <- overwrite || !target %in% names(df) || all(is.na(df[[target]]))
  if (needs_copy) {
    df[[target]] <- df[[source]]
  }
  df
}

coerce_numeric_safely <- function(x) {
  if (is.numeric(x)) {
    return(x)
  }
  suppressWarnings(as.numeric(x))
}

ensure_columns_with_defaults <- function(df, defaults) {
  if (is.null(df)) {
    df <- tibble::tibble()
  }
  if (!inherits(df, "data.frame")) {
    df <- tibble::as_tibble(df)
  }
  missing <- setdiff(names(defaults), names(df))
  if (!length(missing)) {
    return(df)
  }
  for (col in missing) {
    df[[col]] <- defaults[[col]]
  }
  df
}

SCORE_DEFAULTS <- list(
  blend_home_prob = NA_real_,
  market_home_prob = NA_real_,
  home_team = NA_character_,
  away_team = NA_character_,
  game_date = as.Date(NA_character_),
  blend_home_median = NA_real_,
  blend_away_median = NA_real_,
  blend_total_median = NA_real_,
  blend_median_margin = NA_real_,
  actual_winner = NA_character_
)

SCHEDULE_DEFAULTS <- list(
  home_team_sched = NA_character_,
  away_team_sched = NA_character_,
  game_date_sched = as.Date(NA_character_),
  market_home_ml_sched = NA_real_,
  market_away_ml_sched = NA_real_,
  blend_home_median_sched = NA_real_,
  blend_away_median_sched = NA_real_,
  blend_total_median_sched = NA_real_,
  market_home_spread_sched = NA_real_,
  market_total_line_sched = NA_real_,
  winner_sched = NA_character_
)

ensure_score_defaults <- function(df) {
  ensure_columns_with_defaults(df, SCORE_DEFAULTS)
}

ensure_schedule_defaults <- function(df) {
  ensure_columns_with_defaults(df, SCHEDULE_DEFAULTS)
}

# NOTE: american_to_probability, american_to_decimal, clamp_probability,
# expected_value_units, shrink_probability_toward_market, classify_edge_magnitude
# are now defined in NFLbrier_logloss.R (sourced above) as canonical versions.

resolve_home_probability <- function(home_prob,
                                     home_ml = NA_real_,
                                     away_ml = NA_real_,
                                     home_spread = NA_real_,
                                     tolerance = 5e-03) {
  home_prob <- suppressWarnings(as.numeric(home_prob))
  ml_home <- coerce_numeric_safely(home_ml)
  ml_away <- coerce_numeric_safely(away_ml)
  spread_home <- coerce_numeric_safely(home_spread)

  needs_prob <- !is.finite(home_prob)
  if (any(needs_prob, na.rm = TRUE)) {
    fallback <- american_to_probability(ml_home)
    fallback <- clamp_probability(fallback)
    replace_mask <- needs_prob & is.finite(fallback)
    if (any(replace_mask, na.rm = TRUE)) {
      home_prob[replace_mask] <- fallback[replace_mask]
    }
  }

  needs_prob <- !is.finite(home_prob)
  if (any(needs_prob, na.rm = TRUE)) {
    fallback <- american_to_probability(ml_away)
    fallback <- clamp_probability(fallback)
    if (length(fallback)) {
      fallback <- 1 - fallback
      replace_mask <- needs_prob & is.finite(fallback)
      if (any(replace_mask, na.rm = TRUE)) {
        home_prob[replace_mask] <- fallback[replace_mask]
      }
    }
  }

  needs_prob <- !is.finite(home_prob)
  if (any(needs_prob, na.rm = TRUE)) {
    fallback <- spread_to_win_probability(spread_home)
    replace_mask <- needs_prob & is.finite(fallback)
    if (any(replace_mask, na.rm = TRUE)) {
      home_prob[replace_mask] <- fallback[replace_mask]
    }
  }

  prob <- clamp_probability(home_prob)

  ml_prob <- american_to_probability(ml_home)
  ml_prob <- clamp_probability(ml_prob)
  reconcile_mask <- is.finite(prob) & is.finite(ml_prob) & abs(prob - ml_prob) > tolerance
  if (any(reconcile_mask, na.rm = TRUE)) {
    prob[reconcile_mask] <- ml_prob[reconcile_mask]
  }

  ml_prob_away <- american_to_probability(ml_away)
  ml_prob_away <- clamp_probability(ml_prob_away)
  if (length(ml_prob_away)) {
    ml_prob_from_away <- clamp_probability(1 - ml_prob_away)
    reconcile_mask <- is.finite(prob) & is.finite(ml_prob_from_away) & abs(prob - ml_prob_from_away) > tolerance
    if (any(reconcile_mask, na.rm = TRUE)) {
      prob[reconcile_mask] <- ml_prob_from_away[reconcile_mask]
    }
  }

  prob
}

harmonize_home_spread <- function(spread, home_prob, tolerance = 5e-03) {
  spread <- coerce_numeric_safely(spread)
  home_prob <- suppressWarnings(as.numeric(home_prob))

  mask <- is.finite(spread) & is.finite(home_prob)
  if (!any(mask)) {
    return(spread)
  }

  prob <- home_prob[mask]
  spr <- spread[mask]
  flip_mask <- (spr < 0 & prob < 0.5 - tolerance) | (spr > 0 & prob > 0.5 + tolerance)
  if (any(flip_mask)) {
    spr[flip_mask] <- -spr[flip_mask]
    spread[mask] <- spr
  }
  spread
}

harmonize_home_margin <- function(margin, home_prob, tolerance = 5e-03) {
  margin <- coerce_numeric_safely(margin)
  home_prob <- suppressWarnings(as.numeric(home_prob))

  mask <- is.finite(margin) & is.finite(home_prob)
  if (!any(mask)) {
    return(margin)
  }

  prob <- home_prob[mask]
  mar <- margin[mask]
  flip_mask <- (mar < 0 & prob > 0.5 + tolerance) | (mar > 0 & prob < 0.5 - tolerance)
  if (any(flip_mask)) {
    mar[flip_mask] <- -mar[flip_mask]
    margin[mask] <- mar
  }
  margin
}

spread_to_win_probability <- function(spread, sigma = 13.86) {  # 13.86 = Historical NFL margin standard deviation
  spread <- coerce_numeric_safely(spread)
  sigma <- coerce_numeric_safely(sigma)
  if (!length(sigma) || !is.finite(sigma[[1L]]) || sigma[[1L]] <= 0) {
    sigma <- 13.86  # Historical NFL margin standard deviation
  } else {
    sigma <- sigma[[1L]]
  }

  implied <- rep(NA_real_, length(spread))
  mask <- is.finite(spread)
  if (any(mask)) {
    implied[mask] <- 1 - stats::pnorm(spread[mask] / sigma)
  }

  clamp_probability(implied)
}

summarize_probability_gap <- function(gap, prefix, tolerance = 0.005) {
  gap <- suppressWarnings(as.numeric(gap))
  if (!length(gap) || !is.finite(gap) || is.na(gap)) {
    return(NA_character_)
  }

  if (abs(gap) <= tolerance) {
    return(NA_character_)
  }

  delta <- round(gap * 100, 1)
  emphasis <- if (abs(gap) >= 0.1) {
    " (!!)"
  } else if (abs(gap) >= 0.05) {
    " (!)"
  } else {
    ""
  }

  sprintf("%s Δ %+.1fpp%s", prefix, delta, emphasis)
}

build_probability_alignment_note <- function(market_gap, blend_gap, tolerance = 0.005) {
  notes <- c(
    summarize_probability_gap(market_gap, "Market", tolerance = tolerance),
    summarize_probability_gap(blend_gap, "Blend", tolerance = tolerance)
  )

  notes <- notes[!is.na(notes) & nzchar(notes)]
  if (!length(notes)) {
    return(NA_character_)
  }

  paste(notes, collapse = " | ")
}

probability_to_american <- function(prob) {
  prob <- clamp_probability(prob)
  dplyr::case_when(
    is.na(prob) ~ NA_real_,
    prob == 0.5 ~ 100,
    prob > 0.5 ~ -round(100 * prob / (1 - prob)),
    TRUE ~ round(100 * (1 - prob) / prob)
  )
}

apply_moneyline_vig <- function(odds, vig = 0.10) {
  odds <- coerce_numeric_safely(odds)
  vig <- coerce_numeric_safely(vig)
  vig[is.na(vig)] <- 0
  dplyr::case_when(
    is.na(odds) ~ NA_real_,
    !is.finite(odds) ~ NA_real_,
    odds == 0 ~ NA_real_,
    odds < 0 ~ -as.numeric(round(abs(odds) * (1 + vig))),
    TRUE ~ as.numeric(round(odds / (1 + vig)))
  )
}

# ==============================================================================
# PROFESSIONAL ANALYTICS: CLV, Brier Score, Confidence Intervals, Market Movement
# ==============================================================================
# These functions implement professional-grade sports betting analytics to
# evaluate model performance and provide meaningful insights.

#' Calculate Closing Line Value (CLV)
#'
#' CLV measures whether the model consistently beats closing market prices.
#' Positive CLV over time is one of the strongest indicators of a winning model.
#'
#' @param model_prob Model's probability estimate at time of prediction
#' @param closing_prob Market closing probability (after all line movement)
#' @param opening_prob Optional: Market opening probability for movement analysis
#' @return List with CLV metrics
calculate_clv <- function(model_prob, closing_prob, opening_prob = NULL) {
  model_prob <- clamp_probability(model_prob)
  closing_prob <- clamp_probability(closing_prob)

  # Logit transformation for proper probability comparison
  logit <- function(p) log(p / (1 - p))

  # CLV in logit space (standard measure)
  clv_logit <- logit(model_prob) - logit(closing_prob)

  # CLV in probability points (more interpretable)
  clv_prob <- model_prob - closing_prob

  # Direction agreement: did model and closing price agree on favorite?
  model_favorite <- model_prob > 0.5
  closing_favorite <- closing_prob > 0.5
  direction_agree <- model_favorite == closing_favorite

  result <- list(
    clv_logit = clv_logit,
    clv_prob = clv_prob,
    direction_agree = direction_agree,
    model_prob = model_prob,
    closing_prob = closing_prob
  )

  # If opening line available, calculate line movement analysis
  if (!is.null(opening_prob)) {
    opening_prob <- clamp_probability(opening_prob)
    line_movement <- closing_prob - opening_prob
    model_captured_movement <- (model_prob > opening_prob & closing_prob > opening_prob) |
                               (model_prob < opening_prob & closing_prob < opening_prob)
    result$opening_prob <- opening_prob
    result$line_movement <- line_movement
    result$model_captured_movement <- model_captured_movement
  }

  result
}

#' Summarize CLV metrics across multiple games
#'
#' @param clv_results List of CLV results from calculate_clv()
#' @return Summary tibble with aggregate CLV statistics
summarize_clv <- function(clv_results) {
  if (!length(clv_results)) {
    return(tibble::tibble(
      mean_clv_logit = NA_real_,
      mean_clv_prob = NA_real_,
      clv_positive_pct = NA_real_,
      direction_agree_pct = NA_real_,
      n_games = 0L
    ))
  }

  clv_logits <- sapply(clv_results, function(x) x$clv_logit)
  clv_probs <- sapply(clv_results, function(x) x$clv_prob)
  direction_agree <- sapply(clv_results, function(x) x$direction_agree)

  tibble::tibble(
    mean_clv_logit = mean(clv_logits, na.rm = TRUE),
    mean_clv_prob = mean(clv_probs, na.rm = TRUE),
    clv_positive_pct = mean(clv_logits > 0, na.rm = TRUE),
    direction_agree_pct = mean(direction_agree, na.rm = TRUE),
    n_games = sum(!is.na(clv_logits))
  )
}

#' Calculate Brier Score with decomposition
#'
#' Brier score measures probabilistic calibration. Lower is better.
#' Decomposition shows reliability, resolution, and uncertainty components.
#'
#' @param prob Vector of predicted probabilities
#' @param outcome Vector of actual outcomes (0/1)
#' @param n_bins Number of bins for calibration analysis (default 10)
#' @return List with Brier score and components
calculate_brier_decomposition <- function(prob, outcome, n_bins = 10) {
  prob <- clamp_probability(prob)
  outcome <- as.numeric(outcome)

  valid <- !is.na(prob) & !is.na(outcome)
  prob <- prob[valid]
  outcome <- outcome[valid]

  n <- length(prob)
  if (n == 0) {
    return(list(
      brier_score = NA_real_,
      reliability = NA_real_,
      resolution = NA_real_,
      uncertainty = NA_real_,
      calibration_bins = tibble::tibble()
    ))
  }

  # Overall Brier score
  brier_score <- mean((prob - outcome)^2)

  # Base rate (uncertainty)
  base_rate <- mean(outcome)
  uncertainty <- base_rate * (1 - base_rate)

  # Bin predictions for calibration analysis
  breaks <- seq(0, 1, length.out = n_bins + 1)
  bin_idx <- cut(prob, breaks = breaks, include.lowest = TRUE, labels = FALSE)

  calibration_bins <- tibble::tibble(prob = prob, outcome = outcome, bin = bin_idx) %>%
    dplyr::group_by(bin) %>%
    dplyr::summarise(
      mean_prob = mean(prob),
      actual_rate = mean(outcome),
      n = dplyr::n(),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      deviation = actual_rate - mean_prob,
      abs_deviation = abs(deviation)
    )

  # Reliability (calibration error)
  reliability <- calibration_bins %>%
    dplyr::summarise(rel = sum(n * (mean_prob - actual_rate)^2) / sum(n)) %>%
    dplyr::pull(rel)

  # Resolution (how much predictions vary from base rate)
  resolution <- calibration_bins %>%
    dplyr::summarise(res = sum(n * (actual_rate - base_rate)^2) / sum(n)) %>%
    dplyr::pull(res)

  list(
    brier_score = brier_score,
    reliability = reliability,
    resolution = resolution,
    uncertainty = uncertainty,
    base_rate = base_rate,
    n_games = n,
    calibration_bins = calibration_bins
  )
}

#' Format Brier score results for display
#'
#' @param brier_result Result from calculate_brier_decomposition()
#' @return Character string with formatted metrics
format_brier_display <- function(brier_result) {
  if (is.na(brier_result$brier_score)) {
    return("Brier Score: N/A (insufficient data)")
  }

  sprintf(
    "Brier Score: %.4f (Reliability: %.4f, Resolution: %.4f, Uncertainty: %.4f) | N=%d",
    brier_result$brier_score,
    brier_result$reliability,
    brier_result$resolution,
    brier_result$uncertainty,
    brier_result$n_games
  )
}

#' Calculate confidence intervals using bootstrap
#'
#' @param estimate Point estimate (e.g., EV, probability)
#' @param se Standard error (if known)
#' @param n Sample size (for t-based CI if se provided)
#' @param conf_level Confidence level (default 0.95)
#' @return Named vector with lo, estimate, hi
calculate_confidence_interval <- function(estimate, se = NULL, n = NULL, conf_level = 0.95) {
  if (is.na(estimate)) {
    return(c(lo = NA_real_, estimate = NA_real_, hi = NA_real_))
  }

  alpha <- (1 - conf_level) / 2

  if (!is.null(se) && !is.na(se) && !is.null(n) && n > 1) {
    # t-based confidence interval
    df <- n - 1
    t_crit <- stats::qt(1 - alpha, df)
    margin <- t_crit * se
    c(lo = estimate - margin, estimate = estimate, hi = estimate + margin)
  } else if (!is.null(se) && !is.na(se)) {
    # Z-based confidence interval (large sample)
    z_crit <- stats::qnorm(1 - alpha)
    margin <- z_crit * se
    c(lo = estimate - margin, estimate = estimate, hi = estimate + margin)
  } else {
    # Return point estimate with NA bounds
    c(lo = NA_real_, estimate = estimate, hi = NA_real_)
  }
}

#' Calculate probability confidence interval using Wilson score
#'
#' Wilson score interval is better for probabilities near 0 or 1
#'
#' @param prob Probability estimate
#' @param n Sample size
#' @param conf_level Confidence level (default 0.95)
#' @return Named vector with lo, estimate, hi
wilson_confidence_interval <- function(prob, n, conf_level = 0.95) {
  if (is.na(prob) || is.na(n) || n <= 0) {
    return(c(lo = NA_real_, estimate = NA_real_, hi = NA_real_))
  }

  prob <- clamp_probability(prob)
  z <- stats::qnorm(1 - (1 - conf_level) / 2)
  z2 <- z^2

  # Wilson score interval
  denom <- 1 + z2 / n
  center <- (prob + z2 / (2 * n)) / denom
  margin <- z * sqrt((prob * (1 - prob) + z2 / (4 * n)) / n) / denom

  c(
    lo = clamp_probability(center - margin),
    estimate = prob,
    hi = clamp_probability(center + margin)
  )
}

#' Analyze market line movement
#'
#' Tracks how betting lines moved from open to close and compares to model
#'
#' @param open_prob Opening market probability
#' @param close_prob Closing market probability
#' @param model_prob Model's probability at time of prediction
#' @return List with movement analysis
analyze_line_movement <- function(open_prob, close_prob, model_prob) {
  open_prob <- clamp_probability(open_prob)
  close_prob <- clamp_probability(close_prob)
  model_prob <- clamp_probability(model_prob)

  # Raw movement
  movement <- close_prob - open_prob

  # Direction of movement
  movement_direction <- dplyr::case_when(
    is.na(movement) ~ NA_character_,
    abs(movement) < 0.005 ~ "stable",     # Less than 0.5pp movement
    movement > 0 ~ "toward_home",          # Line moved toward home team
    TRUE ~ "toward_away"                   # Line moved toward away team
  )

  # Did model agree with sharp money direction?
  model_vs_open <- model_prob - open_prob
  sharp_agreement <- (model_vs_open > 0 & movement > 0) |
                     (model_vs_open < 0 & movement < 0)

  # Movement magnitude classification
  movement_magnitude <- dplyr::case_when(
    is.na(movement) ~ NA_character_,
    abs(movement) < 0.01 ~ "minimal",      # <1pp
    abs(movement) < 0.03 ~ "moderate",     # 1-3pp
    abs(movement) < 0.05 ~ "significant",  # 3-5pp
    TRUE ~ "major"                          # >5pp
  )

  list(
    movement = movement,
    movement_pct = movement * 100,
    direction = movement_direction,
    magnitude = movement_magnitude,
    model_vs_open = model_vs_open,
    sharp_agreement = sharp_agreement,
    open_prob = open_prob,
    close_prob = close_prob,
    model_prob = model_prob
  )
}

#' Historical backtest framework
#'
#' Run model predictions against multiple historical seasons
#'
#' @param predictions Data frame with model predictions
#' @param actuals Data frame with actual outcomes
#' @param seasons Vector of seasons to include
#' @param join_keys Keys for joining predictions to actuals
#' @return List with backtest results by season and overall
run_historical_backtest <- function(predictions, actuals, seasons = NULL,
                                   join_keys = c("game_id", "season", "week")) {
  predictions <- standardize_join_keys(predictions)
  actuals <- standardize_join_keys(actuals)

  if (is.null(seasons) && "season" %in% names(predictions)) {
    seasons <- sort(unique(predictions$season))
  }

  if (!is.null(seasons) && "season" %in% names(predictions)) {
    predictions <- dplyr::filter(predictions, season %in% seasons)
    actuals <- dplyr::filter(actuals, season %in% seasons)
  }

  # Find probability column
  prob_col <- intersect(
    c("p2_cal", "home_p_2w_cal", "p_model", "home_prob", "blend_home_prob"),
    names(predictions)
  )[1]

  if (is.na(prob_col)) {
    warning("run_historical_backtest(): no probability column found")
    return(NULL)
  }

  # Join predictions with actuals
  combined <- dplyr::inner_join(predictions, actuals, by = join_keys) %>%
    dplyr::mutate(
      prob = clamp_probability(.data[[prob_col]]),
      outcome = dplyr::case_when(
        "home_win" %in% names(.) ~ as.numeric(home_win),
        "y2" %in% names(.) ~ as.numeric(y2),
        "home_score" %in% names(.) & "away_score" %in% names(.) ~
          as.numeric(home_score > away_score),
        TRUE ~ NA_real_
      )
    ) %>%
    dplyr::filter(!is.na(prob), !is.na(outcome))

  if (!nrow(combined)) {
    return(list(
      overall = tibble::tibble(),
      by_season = tibble::tibble(),
      n_games = 0L
    ))
  }

  # Overall metrics
  overall_brier <- calculate_brier_decomposition(combined$prob, combined$outcome)
  overall_accuracy <- mean((combined$prob > 0.5) == combined$outcome, na.rm = TRUE)
  overall_logloss <- -mean(
    combined$outcome * log(combined$prob) +
    (1 - combined$outcome) * log(1 - combined$prob),
    na.rm = TRUE
  )

  overall <- tibble::tibble(
    n_games = nrow(combined),
    brier_score = overall_brier$brier_score,
    log_loss = overall_logloss,
    accuracy = overall_accuracy,
    reliability = overall_brier$reliability,
    resolution = overall_brier$resolution
  )

  # By-season breakdown
  by_season <- combined %>%
    dplyr::group_by(season) %>%
    dplyr::summarise(
      n_games = dplyr::n(),
      brier_score = mean((prob - outcome)^2, na.rm = TRUE),
      log_loss = -mean(outcome * log(prob) + (1 - outcome) * log(1 - prob), na.rm = TRUE),
      accuracy = mean((prob > 0.5) == outcome, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::arrange(season)

  list(
    overall = overall,
    by_season = by_season,
    calibration_bins = overall_brier$calibration_bins,
    n_games = nrow(combined)
  )
}

#' Format backtest results for display
#'
#' @param backtest_result Result from run_historical_backtest()
#' @return Character string with formatted summary
format_backtest_display <- function(backtest_result) {
  if (is.null(backtest_result) || backtest_result$n_games == 0) {
    return("Backtest: No data available")
  }

  overall <- backtest_result$overall
  seasons <- backtest_result$by_season

  summary_lines <- c(
    sprintf("=== HISTORICAL BACKTEST RESULTS (%d games) ===", overall$n_games),
    sprintf("Overall Brier Score: %.4f", overall$brier_score),
    sprintf("Overall Log Loss: %.4f", overall$log_loss),
    sprintf("Overall Accuracy: %.1f%%", overall$accuracy * 100),
    "",
    "By Season:"
  )

  season_lines <- purrr::map_chr(seq_len(nrow(seasons)), function(i) {
    row <- seasons[i, ]
    sprintf("  %d: Brier=%.4f, LogLoss=%.4f, Accuracy=%.1f%% (n=%d)",
            row$season, row$brier_score, row$log_loss, row$accuracy * 100, row$n_games)
  })

  paste(c(summary_lines, season_lines), collapse = "\n")
}

realized_moneyline_units <- function(pick_side, winner_side, odds, stake = 1) {
  pick_side <- tolower(as.character(pick_side))
  winner_side <- tolower(as.character(winner_side))
  odds <- coerce_numeric_safely(odds)
  stake <- coerce_numeric_safely(stake)
  if (!length(stake)) {
    stake <- 1
  }
  stake <- rep(stake, length.out = length(odds))

  out <- rep(NA_real_, length(odds))

  valid <- pick_side %in% c("home", "away") &
    winner_side %in% c("home", "away") &
    is.finite(odds) & odds != 0 &
    is.finite(stake) & !is.na(stake)

  if (!any(valid)) {
    return(out)
  }

  dec <- american_to_decimal(odds[valid])
  stake_valid <- stake[valid]
  dec_invalid <- is.na(dec) | !is.finite(dec)
  wins <- pick_side[valid] == winner_side[valid]

  out_valid <- rep(NA_real_, sum(valid))
  out_valid[dec_invalid] <- NA_real_

  if (any(!dec_invalid & wins)) {
    out_valid[!dec_invalid & wins] <- stake_valid[!dec_invalid & wins] * (dec[!dec_invalid & wins] - 1)
  }

  if (any(!dec_invalid & !wins)) {
    out_valid[!dec_invalid & !wins] <- -stake_valid[!dec_invalid & !wins]
  }

  out[which(valid)] <- out_valid
  out
}

assess_blend_vs_market <- function(
    blend_actual_units,
    market_actual_units,
    blend_ev_units,
    market_ev_units,
    blend_prob_pick,
    market_prob_pick,
    blend_pick_label,
    blend_moneyline,
    market_moneyline,
    blend_edge_moneyline) {
  eps <- sqrt(.Machine$double.eps)

  fmt_units <- function(x) {
    ifelse(is.na(x), "n/a", sprintf("%+.3f", as.numeric(x)))
  }

  fmt_prob <- function(x) {
    ifelse(is.na(x), "n/a", sprintf("%.1f%%", 100 * as.numeric(x)))
  }

  fmt_odds <- function(x) {
    if (is.na(x) || !is.finite(x)) {
      return("n/a")
    }
    odds_int <- as.integer(round(x))
    if (odds_int > 0) {
      sprintf("+%d", odds_int)
    } else {
      sprintf("%d", odds_int)
    }
  }

  safe_label <- if (is.null(blend_pick_label) || is.na(blend_pick_label) || !nzchar(blend_pick_label)) {
    "the blend side"
  } else {
    blend_pick_label
  }

  basis <- NA_character_
  detail <- NA_character_
  result <- NA

  if (!is.na(blend_actual_units) && !is.na(market_actual_units)) {
    diff_units <- blend_actual_units - market_actual_units
    result <- ifelse(diff_units > eps, TRUE, ifelse(diff_units < -eps, FALSE, NA))
    basis <- "Final score"
    detail <- sprintf(
      "Final result: blend %s vs market %s units (diff %+.3f).",
      fmt_units(blend_actual_units),
      fmt_units(market_actual_units),
      diff_units
    )
    return(list(result = result, basis = basis, detail = detail))
  }

  if (!is.na(blend_actual_units)) {
    result <- ifelse(blend_actual_units > eps, TRUE, ifelse(blend_actual_units < -eps, FALSE, NA))
    basis <- "Final score"
    detail <- sprintf(
      "Blend realized %s units; market result unavailable.",
      fmt_units(blend_actual_units)
    )
    return(list(result = result, basis = basis, detail = detail))
  }

  if (!is.na(blend_ev_units)) {
    result <- ifelse(blend_ev_units > eps, TRUE, ifelse(blend_ev_units < -eps, FALSE, NA))
    basis <- "Expected value"
    detail <- sprintf(
      "EV on %s: blend %s units vs market %s.",
      safe_label,
      fmt_units(blend_ev_units),
      fmt_units(market_ev_units)
    )
    if (!is.na(result)) {
      return(list(result = result, basis = basis, detail = detail))
    }
  }

  if (!is.na(blend_prob_pick) && !is.na(market_prob_pick)) {
    prob_diff <- blend_prob_pick - market_prob_pick
    result <- ifelse(prob_diff > eps, TRUE, ifelse(prob_diff < -eps, FALSE, NA))
    basis <- "Win probability"
    detail <- sprintf(
      "%s win probability: blend %s vs market %s.",
      safe_label,
      fmt_prob(blend_prob_pick),
      fmt_prob(market_prob_pick)
    )
    if (!is.na(result)) {
      return(list(result = result, basis = basis, detail = detail))
    }
  }

  if (!is.na(blend_edge_moneyline)) {
    result <- ifelse(blend_edge_moneyline > eps, TRUE, ifelse(blend_edge_moneyline < -eps, FALSE, NA))
    basis <- "Moneyline price"
    detail <- sprintf(
      "Price comparison: market %s vs blend %s.",
      fmt_odds(market_moneyline),
      fmt_odds(blend_moneyline)
    )
    if (!is.na(result)) {
      return(list(result = result, basis = basis, detail = detail))
    }
  }

  list(
    result = NA,
    basis = "Insufficient data",
    detail = "No outcome, EV, probability, or pricing edge available."
  )
}

shorten_market_note <- function(note, max_chars = 72L) {
  if (is.null(note) || !length(note)) {
    return(note)
  }

  note_chr <- as.character(note)
  is_na <- is.na(note_chr)
  note_chr[is_na] <- NA_character_
  to_process <- !is_na & nzchar(trimws(note_chr))

  if (any(to_process)) {
    cleaned <- stringr::str_squish(note_chr[to_process])
    cleaned <- gsub("Final result:", "Result:", cleaned, fixed = TRUE)
    cleaned <- gsub("Blend realized", "Blend", cleaned, fixed = TRUE)
    cleaned <- gsub("Expected value", "EV", cleaned, fixed = TRUE)
    cleaned <- gsub("Win probability", "Win prob", cleaned, fixed = TRUE)
    cleaned <- gsub("Price comparison", "Price", cleaned, fixed = TRUE)
    cleaned <- gsub("market result unavailable", "market n/a", cleaned, fixed = TRUE)
    cleaned <- gsub(" units", "u", cleaned, fixed = TRUE)
    cleaned <- gsub("\u00a0", " ", cleaned, fixed = TRUE)
    cleaned <- gsub("\\s+", " ", cleaned)

    needs_trunc <- stringr::str_length(cleaned) > max_chars
    if (any(needs_trunc)) {
      cleaned[needs_trunc] <- stringr::str_trunc(cleaned[needs_trunc], max_chars, ellipsis = "…")
    }

    note_chr[to_process] <- cleaned
  }

  note_chr
}

devig_two_way_probabilities <- function(p_home_raw, p_away_raw) {
  p_home_raw <- coerce_numeric_safely(p_home_raw)
  p_away_raw <- coerce_numeric_safely(p_away_raw)
  total <- p_home_raw + p_away_raw
  valid <- is.finite(total) & total > 0
  tibble::tibble(
    p_home = dplyr::if_else(valid, p_home_raw / total, NA_real_),
    p_away = dplyr::if_else(valid, p_away_raw / total, NA_real_)
  )
}

# ------------------------------------------------------------------------------
# ESPN line preparation ---------------------------------------------------------
# ------------------------------------------------------------------------------

enrich_with_pre_kickoff_espn_lines <- function(sched,
                                               espn_lines = NULL,
                                               join_keys = PREDICTION_JOIN_KEYS,
                                               team_keys = c("home_team", "away_team"),
                                               verbose = TRUE) {
  if (is.null(sched) || !nrow(sched)) {
    if (verbose) message("enrich_with_pre_kickoff_espn_lines(): schedule empty; returning input unchanged.")
    return(sched)
  }

  sched_std <- standardize_join_keys(sched)

  join_args <- list(x = sched_std)

  if (!is.null(espn_lines) && nrow(espn_lines)) {
    espn_std <- standardize_join_keys(espn_lines)

    join_cols <- intersect(join_keys, intersect(names(sched_std), names(espn_std)))
    join_args$y <- espn_std

    if (length(join_cols)) {
      join_args$by <- join_cols
    } else {
      if (all(team_keys %in% names(sched_std)) &&
          all(team_keys %in% names(espn_std)) &&
          "game_date" %in% names(sched_std) &&
          any(c("date", "game_date", "match_date") %in% names(espn_std))) {
        date_col <- select_first_column(espn_std, c("game_date", "date", "match_date"))
        join_args$by <- c(game_date = date_col, setNames(team_keys, team_keys))
      } else if ("espn_game_id" %in% names(espn_std) && "espn_game_id" %in% names(sched_std)) {
        join_args$by <- "espn_game_id"
      } else {
        if (verbose) {
          message("enrich_with_pre_kickoff_espn_lines(): unable to determine join columns; skipping ESPN merge.")
        }
        join_args$by <- NULL
      }
    }

    if (!is.null(join_args$by)) {
      sched_std <- tryCatch(
        {
          safe_left_join(
            x = sched_std,
            y = join_args$y,
            by = join_args$by,
            relationship = "many-to-many",
            label = "enrich_with_pre_kickoff_espn_lines()",
            multiple = "all"
          )
        },
        error = function(e) {
          if (verbose) {
            message("enrich_with_pre_kickoff_espn_lines(): left_join failed; reason: ", conditionMessage(e))
          }
          sched_std
        }
      )
    }
  }

  column_map <- list(
    espn_final_home_ml = c(
      "espn_final_home_ml", "espn_home_moneyline_final", "espn_home_ml_final",
      "home_ml_final", "home_moneyline_final", "home_ml_close", "home_moneyline_close",
      "espn_home_moneyline"
    ),
    espn_final_away_ml = c(
      "espn_final_away_ml", "espn_away_moneyline_final", "espn_away_ml_final",
      "away_ml_final", "away_moneyline_final", "away_ml_close", "away_moneyline_close",
      "espn_away_moneyline"
    ),
    espn_final_home_spread = c(
      "espn_final_home_spread", "espn_home_spread_final", "home_spread_final",
      "spread_final", "home_spread_close", "spread_close", "espn_home_spread"
    ),
    espn_final_total = c(
      "espn_final_total", "espn_total_final", "total_final", "total_close",
      "market_total", "total_line", "total", "over_under", "over_under_close",
      "espn_total"
    )
  )

  for (canonical in names(column_map)) {
    existing <- select_first_column(sched_std, column_map[[canonical]])
    if (!is.na(existing)) {
      sched_std[[canonical]] <- coerce_numeric_safely(sched_std[[existing]])
    } else if (!canonical %in% names(sched_std)) {
      sched_std[[canonical]] <- NA_real_
    }
  }

  sched_std <- copy_column_if_missing(sched_std, "home_ml", "espn_final_home_ml")
  sched_std <- copy_column_if_missing(sched_std, "away_ml", "espn_final_away_ml")
  sched_std <- copy_column_if_missing(sched_std, "spread_line", "espn_final_home_spread")
  sched_std <- copy_column_if_missing(sched_std, "home_spread", "espn_final_home_spread")
  sched_std <- copy_column_if_missing(sched_std, "market_spread", "spread_line")
  sched_std <- copy_column_if_missing(sched_std, "total_line", "espn_final_total")
  sched_std <- copy_column_if_missing(sched_std, "market_total", "total_line")

  if ("espn_final_home_ml" %in% names(sched_std) &&
      "espn_final_away_ml" %in% names(sched_std)) {
    raw_probs <- tibble::tibble(
      p_home_raw = american_to_probability(sched_std$espn_final_home_ml),
      p_away_raw = american_to_probability(sched_std$espn_final_away_ml)
    )
    devig <- devig_two_way_probabilities(raw_probs$p_home_raw, raw_probs$p_away_raw)
    sched_std$espn_final_home_prob <- devig$p_home
    sched_std$espn_final_away_prob <- devig$p_away
  }

  sched_std
}

# ------------------------------------------------------------------------------
# Model blend helpers -----------------------------------------------------------
# ------------------------------------------------------------------------------

build_res_blend <- function(res,
                            blend_oos,
                            join_keys = PREDICTION_JOIN_KEYS,
                            prob_candidates = c("p2_cal", "home_p_2w_cal", "p2_home_cal", "home_p2w_cal"),
                            verbose = TRUE) {
  if (is.null(res) || !is.list(res) || !"per_game" %in% names(res)) {
    if (verbose) message("build_res_blend(): res lacks a per_game component; skipping blend attachment.")
    return(NULL)
  }
  if (is.null(blend_oos) || !nrow(blend_oos)) {
    if (verbose) message("build_res_blend(): no blend history available; skipping blend attachment.")
    return(NULL)
  }

  per_game <- standardize_join_keys(res$per_game)
  prob_col <- select_first_column(per_game, prob_candidates)
  if (is.na(prob_col)) {
    if (verbose) message("build_res_blend(): no calibrated probability column found on res$per_game; skipping blend attachment.")
    return(NULL)
  }

  base_per_game <- collapse_by_keys_relaxed(per_game, join_keys, label = "Backtest per-game table")
  base_cols <- names(base_per_game)

  # Compute available join keys by intersecting with columns present in blend_oos
  blend_oos_std <- standardize_join_keys(blend_oos)
  available_keys <- intersect(join_keys, names(blend_oos_std))
  if (length(available_keys) == 0) {
    if (verbose) message("build_res_blend(): no join keys available in blend_oos; skipping blend attachment.")
    return(NULL)
  }

  blend_join <- blend_oos_std %>%
    dplyr::filter(dplyr::if_all(dplyr::all_of(available_keys), ~ !is.na(.))) %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(available_keys))) %>%
    dplyr::summarise(p_blend = mean(p_blend, na.rm = TRUE), .groups = "drop") %>%
    dplyr::rename(.blend_prob = p_blend)

  if (!nrow(blend_join)) {
    if (verbose) message("build_res_blend(): blend history has no complete join keys; skipping blend attachment.")
    return(NULL)
  }

  cast_column <- function(col, template, col_name) {
    if (!requireNamespace("vctrs", quietly = TRUE)) {
      return(col)
    }
    tryCatch(
      vctrs::vec_cast(col, template),
      vctrs_error_incompatible_type = function(e) {
        warning(sprintf(
          "build_res_blend(): lossy cast prevented for column %s; keeping original type.",
          col_name
        ))
        col
      },
      error = function(e) {
        warning(sprintf(
          "build_res_blend(): unable to align column %s: %s",
          col_name,
          conditionMessage(e)
        ))
        col
      }
    )
  }

  for (col_name in join_keys) {
    if (!col_name %in% names(blend_join) || !col_name %in% names(base_per_game)) next
    blend_join[[col_name]] <- cast_column(blend_join[[col_name]], base_per_game[[col_name]], col_name)
  }

  per_game_with_blend <- tryCatch(
    {
      safe_left_join(
        x = base_per_game,
        y = blend_join,
        by = available_keys,
        relationship = "many-to-one",
        label = "build_res_blend()"
      )
    },
    error = function(e) {
      warning(sprintf("build_res_blend(): left_join failed; keeping original probabilities. Reason: %s", conditionMessage(e)))
      NULL
    }
  )

  if (is.null(per_game_with_blend)) {
    return(NULL)
  }

  blend_col <- ".blend_prob"
  if (!blend_col %in% names(per_game_with_blend)) {
    alt_cols <- intersect(c("p_blend", "p_blend.y", "p_blend.x"), names(per_game_with_blend))
    if (length(alt_cols)) {
      per_game_with_blend[[blend_col]] <- per_game_with_blend[[alt_cols[1L]]]
    }
  }

  if (!blend_col %in% names(per_game_with_blend)) {
    if (verbose) message("build_res_blend(): joined table missing p_blend column; skipping blend attachment.")
    return(NULL)
  }

  per_game_with_blend[[prob_col]] <- dplyr::if_else(
    is.finite(per_game_with_blend[[blend_col]]),
    per_game_with_blend[[blend_col]],
    per_game_with_blend[[prob_col]]
  )

  if ("p_blend" %in% base_cols) {
    per_game_with_blend$p_blend <- per_game_with_blend[[blend_col]]
  }

  per_game_with_blend <- dplyr::select(per_game_with_blend, -dplyr::any_of(c(blend_col, "p_blend.x", "p_blend.y")))

  missing_cols <- setdiff(base_cols, names(per_game_with_blend))
  if (length(missing_cols)) {
    for (col_name in missing_cols) {
      per_game_with_blend[[col_name]] <- base_per_game[[col_name]][0]
    }
  }

  per_game_with_blend <- dplyr::select(per_game_with_blend, dplyr::all_of(base_cols))

  res_out <- res
  res_out$per_game <- per_game_with_blend

  if (verbose) {
    message(sprintf("build_res_blend(): attached blended probabilities using column '%s'.", prob_col))
  }

  res_out
}

# ------------------------------------------------------------------------------
# File utilities ----------------------------------------------------------------
# ------------------------------------------------------------------------------

find_latest_rds <- function(prefix, directory = "run_logs") {
  files <- list.files(directory, pattern = sprintf("^%s_.*\\.rds$", prefix), full.names = TRUE)
  if (!length(files)) {
    return(NA_character_)
  }
  files[order(file.info(files)$mtime, decreasing = TRUE)][1]
}

load_latest_market_inputs <- function(directory = "run_logs") {
  paths <- list(
    config = find_latest_rds("config", directory),
    final  = find_latest_rds("final", directory),
    games  = find_latest_rds("games_ready", directory)
  )

  loaded <- purrr::compact(purrr::map(paths, ~ if (is.na(.x)) NULL else readRDS(.x)))
  c(loaded, list(paths = paths))
}

# ------------------------------------------------------------------------------
# Market evaluation -------------------------------------------------------------
# ------------------------------------------------------------------------------

evaluate_market_vs_blend <- function(res,
                                     blend_oos,
                                     sched,
                                     espn_lines = NULL,
                                     join_keys = PREDICTION_JOIN_KEYS,
                                     prob_candidates = c("p2_cal", "home_p_2w_cal", "p2_home_cal", "home_p2w_cal"),
                                     verbose = TRUE,
                                     ...) {
  res_blend <- build_res_blend(
    res = res,
    blend_oos = blend_oos,
    join_keys = join_keys,
    prob_candidates = prob_candidates,
    verbose = verbose
  )
  if (is.null(res_blend)) {
    if (verbose) message("evaluate_market_vs_blend(): unable to build res_blend; returning NULL.")
    return(NULL)
  }

  sched_prepared <- enrich_with_pre_kickoff_espn_lines(
    sched = sched,
    espn_lines = espn_lines,
    join_keys = join_keys,
    verbose = verbose
  )

  compare_args <- c(list(res_blend, sched_prepared), list(...))
  comparison <- rlang::exec(compare_to_market, !!!compare_args)

  comparison
}

extract_game_level_scores <- function(market_comparison_result) {
  if (is.null(market_comparison_result) ||
      !is.list(market_comparison_result) ||
      !"comp" %in% names(market_comparison_result)) {
    return(tibble::tibble())
  }

  comp <- tibble::as_tibble(market_comparison_result$comp)
  if (!nrow(comp)) {
    return(tibble::tibble())
  }

  # NOTE: This helper is also defined in NFLsimulation.R (lines ~495-507)
  # Intentionally duplicated as a local helper to avoid external dependencies
  coalesce_numeric_cols <- function(df, cols) {
    cols <- intersect(cols, names(df))
    if (!length(cols)) {
      return(rep(NA_real_, nrow(df)))
    }
    out <- coerce_numeric_safely(df[[cols[1L]]])
    if (length(cols) > 1L) {
      for (col in cols[-1L]) {
        out <- dplyr::coalesce(out, coerce_numeric_safely(df[[col]]))
      }
    }
    out
  }

  coalesce_character_cols <- function(df, cols) {
    cols <- intersect(cols, names(df))
    if (!length(cols)) {
      return(rep(NA_character_, nrow(df)))
    }
    as_chr <- function(x) {
      if (inherits(x, "Date")) {
        return(as.character(x))
      }
      if (inherits(x, "POSIXt")) {
        return(as.character(as.Date(x)))
      }
      as.character(x)
    }
    out <- as_chr(df[[cols[1L]]])
    out[is.na(out) | !nzchar(out)] <- NA_character_
    if (length(cols) > 1L) {
      for (col in cols[-1L]) {
        candidate <- as_chr(df[[col]])
        candidate[is.na(candidate) | !nzchar(candidate)] <- NA_character_
        out <- dplyr::coalesce(out, candidate)
      }
    }
    out
  }

  coalesce_date_cols <- function(df, cols) {
    cols <- intersect(cols, names(df))
    if (!length(cols)) {
      return(rep(as.Date(NA_character_), nrow(df)))
    }
    as_date <- function(x) {
      if (inherits(x, "Date")) {
        return(x)
      }
      if (inherits(x, "POSIXt")) {
        return(as.Date(x))
      }
      suppressWarnings(as.Date(as.character(x)))
    }
    out <- as_date(df[[cols[1L]]])
    if (length(cols) > 1L) {
      for (col in cols[-1L]) {
        candidate <- as_date(df[[col]])
        out <- dplyr::coalesce(out, candidate)
      }
    }
    out
  }

  blend_home_median <- coalesce_numeric_cols(comp, c(
    "blend_home_median", "home_median_blend", "home_median", "home_median_pts"
  ))
  blend_away_median <- coalesce_numeric_cols(comp, c(
    "blend_away_median", "away_median_blend", "away_median", "away_median_pts"
  ))
  blend_total_median <- coalesce_numeric_cols(comp, c(
    "blend_total_median", "total_median_blend", "total_median", "total_median_pts"
  ))
  blend_median_margin <- coalesce_numeric_cols(comp, c(
    "blend_median_margin", "margin_blend", "margin_median"
  ))

  home_team <- coalesce_character_cols(comp, c(
    "home_team", "home", "home_team_name", "home_abbr"
  ))
  away_team <- coalesce_character_cols(comp, c(
    "away_team", "away", "away_team_name", "away_abbr"
  ))
  matchup <- coalesce_character_cols(comp, c("matchup"))
  actual_winner <- coalesce_character_cols(comp, c("actual_winner", "winner"))
  game_date <- coalesce_date_cols(comp, c("game_date", "date", "gameDate", "match_date"))

  comp_aug <- comp %>%
    dplyr::mutate(
      blend_home_prob = clamp_probability(p_model),
      market_home_prob = clamp_probability(p_mkt),
      # legacy aliases retained for callers expecting `model_prob` / `market_prob`
      model_prob = blend_home_prob,
      market_prob = market_home_prob,
      actual_home_win = y2,
      brier_model = (blend_home_prob - actual_home_win)^2,
      brier_market = (market_home_prob - actual_home_win)^2,
      logloss_model = -(actual_home_win * log(blend_home_prob) +
        (1 - actual_home_win) * log(1 - blend_home_prob)),
      logloss_market = -(actual_home_win * log(market_home_prob) +
        (1 - actual_home_win) * log(1 - market_home_prob)),
      home_team = home_team,
      away_team = away_team,
      matchup = matchup,
      game_date = game_date,
      blend_home_median = blend_home_median,
      blend_away_median = blend_away_median,
      blend_total_median = blend_total_median,
      blend_median_margin = blend_median_margin,
      actual_winner = actual_winner
    )

  comp_aug$blend_median_margin <- dplyr::if_else(
    is.na(comp_aug$blend_median_margin) &
      is.finite(comp_aug$blend_home_median) &
      is.finite(comp_aug$blend_away_median),
    comp_aug$blend_home_median - comp_aug$blend_away_median,
    comp_aug$blend_median_margin
  )

  comp_aug$blend_total_median <- dplyr::if_else(
    is.na(comp_aug$blend_total_median) &
      is.finite(comp_aug$blend_home_median) &
      is.finite(comp_aug$blend_away_median),
    comp_aug$blend_home_median + comp_aug$blend_away_median,
    comp_aug$blend_total_median
  )

  comp_aug %>%
    dplyr::select(
      game_id,
      season,
      week,
      blend_home_prob,
      market_home_prob,
      model_prob,
      market_prob,
      actual_home_win,
      brier_model,
      brier_market,
      logloss_model,
      logloss_market,
      dplyr::any_of(c(
        "home_team",
        "away_team",
        "matchup",
        "game_date",
        "blend_home_median",
        "blend_away_median",
        "blend_total_median",
        "blend_median_margin",
        "actual_winner"
      ))
    )
}

#' Build comprehensive moneyline comparison table
#'
#' Core function that combines simulation predictions with market data to produce
#' betting recommendations. Applies probability shrinkage, calculates expected value,
#' and generates Kelly-optimal stake sizes.
#'
#' @param market_comparison_result Output from compare_to_market() function
#' @param enriched_schedule Schedule data enriched with market odds
#' @param join_keys Character vector of keys for joining (default: game_id, season, week)
#' @param vig Assumed market vig/juice (default: 0.10 = 10%)
#' @param verbose Print progress messages (default: TRUE)
#'
#' @return Tibble with columns:
#'   \item{game_id}{Unique game identifier}
#'   \item{season, week}{Game timing}
#'   \item{home_team, away_team}{Team abbreviations}
#'   \item{blend_home_prob}{Raw model probability}
#'   \item{blend_home_prob_shrunk}{Shrunk probability (60% market weight)}
#'   \item{market_home_prob}{Market-implied probability}
#'   \item{blend_ev_units_home}{Expected value in units (using shrunk prob)}
#'   \item{blend_recommendation}{"Bet" or "Pass" based on EV}
#'   \item{blend_confidence}{Kelly stake size (1/8 Kelly)}
#'
#' @details
#' The function applies professional-grade shrinkage to raw model probabilities:
#' - **Shrinkage formula**: shrunk = 0.4 × model + 0.6 × market
#' - **EV calculation**: Uses shrunk probabilities (not raw)
#' - **Staking**: 1/8 Kelly with 10% max edge cap
#'
#' Edge quality classification (a column of artifacts/baseline_games.csv):
#' - ≤5%: ✓ OK (realistic)
#' - ≤10%: ⚠ High (optimistic)
#' - ≤15%: ⚠⚠ Suspicious
#' - >15%: 🚫 Implausible
#'
#' @seealso \code{\link{compare_to_market}}
#' @export
build_moneyline_comparison_table <- function(market_comparison_result,
                                             enriched_schedule,
                                             join_keys = PREDICTION_JOIN_KEYS,
                                             vig = 0.10,
                                             verbose = TRUE) {
  scores <- extract_game_level_scores(market_comparison_result)
  if (!nrow(scores)) {
    if (verbose) message("build_moneyline_comparison_table(): no comparison scores available; returning empty tibble.")
    return(tibble::tibble())
  }

  # CRITICAL: Standardize scores join keys (type coercion for game_id, season, week)
  scores <- standardize_join_keys(scores)

  if (is.null(enriched_schedule) || !nrow(enriched_schedule)) {
    if (verbose) message("build_moneyline_comparison_table(): schedule input is empty; returning scores without context.")
    return(scores)
  }

  schedule_std <- standardize_join_keys(enriched_schedule)
  join_cols <- intersect(join_keys, intersect(names(schedule_std), names(scores)))

  if (!length(join_cols)) {
    if (verbose) message("build_moneyline_comparison_table(): no shared join keys between schedule and scores; returning scores.")
    return(scores)
  }

  schedule_collapsed <- collapse_by_keys_relaxed(
    schedule_std,
    keys = join_cols,
    label = "HTML schedule context"
  )

  pull_or_default <- function(df, col_name, default = NA) {
    if (is.na(col_name) || !col_name %in% names(df)) {
      rep(default, nrow(df))
    } else {
      df[[col_name]]
    }
  }

  home_team_col <- select_first_column(schedule_collapsed, c("home_team", "team_home", "home", "home_abbr"))
  away_team_col <- select_first_column(schedule_collapsed, c("away_team", "team_away", "away", "away_abbr"))
  date_col <- select_first_column(schedule_collapsed, c("game_date", "gameDate", "date", "match_date"))
  home_ml_col <- select_first_column(schedule_collapsed, c("espn_final_home_ml", "home_ml", "ml_home", "home_moneyline"))
  away_ml_col <- select_first_column(schedule_collapsed, c("espn_final_away_ml", "away_ml", "ml_away", "away_moneyline"))
  home_median_col <- select_first_column(schedule_collapsed, c("blend_home_median", "home_median_blend", "home_median"))
  away_median_col <- select_first_column(schedule_collapsed, c("blend_away_median", "away_median_blend", "away_median"))
  total_median_col <- select_first_column(schedule_collapsed, c("blend_total_median", "total_median_blend", "total_median"))
  spread_col <- select_first_column(schedule_collapsed, c(
    "espn_final_home_spread", "home_spread", "market_spread", "spread_line", "spread"
  ))
  total_col <- select_first_column(schedule_collapsed, c(
    "espn_final_total", "market_total", "total_line", "total", "over_under"
  ))
  game_type_col <- select_first_column(schedule_collapsed, c("game_type", "game_type_std", "season_type"))

  schedule_context <- schedule_collapsed %>%
    dplyr::mutate(
      home_team = as.character(pull_or_default(schedule_collapsed, home_team_col, NA_character_)),
      away_team = as.character(pull_or_default(schedule_collapsed, away_team_col, NA_character_)),
      game_date = suppressWarnings(as.Date(pull_or_default(schedule_collapsed, date_col, NA_character_))),
      game_type = as.character(pull_or_default(schedule_collapsed, game_type_col, "REG")),
      market_home_ml = coerce_numeric_safely(pull_or_default(schedule_collapsed, home_ml_col, NA_real_)),
      market_away_ml = coerce_numeric_safely(pull_or_default(schedule_collapsed, away_ml_col, NA_real_)),
      blend_home_median = coerce_numeric_safely(pull_or_default(schedule_collapsed, home_median_col, NA_real_)),
      blend_away_median = coerce_numeric_safely(pull_or_default(schedule_collapsed, away_median_col, NA_real_)),
      blend_total_median = coerce_numeric_safely(pull_or_default(schedule_collapsed, total_median_col, NA_real_)),
      market_home_spread = coerce_numeric_safely(pull_or_default(schedule_collapsed, spread_col, NA_real_)),
      market_total_line = coerce_numeric_safely(pull_or_default(schedule_collapsed, total_col, NA_real_))
    ) %>%
    dplyr::transmute(
      dplyr::across(dplyr::all_of(join_cols)),
      home_team,
      away_team,
      game_date,
      game_type,
      market_home_ml,
      market_away_ml,
      blend_home_median,
      blend_away_median,
      blend_total_median,
      market_home_spread,
      market_total_line
    ) %>%
    dplyr::rename_with(
      ~ paste0(.x, "_sched"),
      -dplyr::all_of(join_cols)
    )

  scores_collapsed <- collapse_by_keys_relaxed(
    scores,
    keys = join_cols,
    label = "Moneyline score table"
  )

  score_defaults <- list(
    blend_home_prob = NA_real_,
    market_home_prob = NA_real_,
    home_team = NA_character_,
    away_team = NA_character_,
    game_date = as.Date(NA_character_),
    blend_home_median = NA_real_,
    blend_away_median = NA_real_,
    blend_total_median = NA_real_,
    blend_median_margin = NA_real_,
    actual_winner = NA_character_
  )

  ensure_score_defaults <- function(df) {
    for (col in names(score_defaults)) {
      if (!col %in% names(df)) {
        df[[col]] <- score_defaults[[col]]
      }
    }
    df
  }

  schedule_defaults <- list(
    home_team_sched = NA_character_,
    away_team_sched = NA_character_,
    game_date_sched = as.Date(NA_character_),
    market_home_ml_sched = NA_real_,
    market_away_ml_sched = NA_real_,
    blend_home_median_sched = NA_real_,
    blend_away_median_sched = NA_real_,
    blend_total_median_sched = NA_real_,
    market_home_spread_sched = NA_real_,
    market_total_line_sched = NA_real_,
    winner_sched = NA_character_
  )

  ensure_schedule_defaults <- function(df) {
    for (col in names(schedule_defaults)) {
      if (!col %in% names(df)) {
        df[[col]] <- schedule_defaults[[col]]
      }
    }
    df
  }

  scores_ready <- scores_collapsed %>%
    ensure_score_defaults() %>%
    dplyr::mutate(
      blend_home_prob = dplyr::coalesce(blend_home_prob, model_prob),
      market_home_prob = dplyr::coalesce(market_home_prob, market_prob)
    )

  scores_ready <- ensure_unique_join_keys(
    scores_ready,
    keys = join_cols,
    label = "Moneyline score table (post-defaults)"
  )

  schedule_context <- ensure_unique_join_keys(
    schedule_context,
    keys = join_cols,
    label = "Schedule context table"
  )

  join_args <- list(x = scores_ready, y = schedule_context, by = join_cols)
  join_meta <- infer_join_relationship(
    scores_ready,
    schedule_context,
    join_cols,
    label = "build_moneyline_comparison_table()",
    default = "many-to-one"
  )
  if ("relationship" %in% names(formals(dplyr::inner_join))) {
    if (!is.null(join_meta$relationship)) {
      join_args$relationship <- join_meta$relationship
    }
    if ("multiple" %in% names(formals(dplyr::inner_join)) &&
        (isTRUE(join_meta$x_duplicates > 0L) || isTRUE(join_meta$y_duplicates > 0L))) {
      join_args$multiple <- "all"
    }
  }

  combined <- tryCatch(
    rlang::exec(dplyr::inner_join, !!!join_args),
    error = function(e) {
      warning(sprintf(
        "build_moneyline_comparison_table(): strict inner_join failed (%s); falling back to distinct join keys.",
        conditionMessage(e)
      ))
      fallback_scores <- scores_ready %>%
        dplyr::distinct(dplyr::across(dplyr::all_of(join_cols)), .keep_all = TRUE)
      fallback_sched <- schedule_context %>%
        dplyr::distinct(dplyr::across(dplyr::all_of(join_cols)), .keep_all = TRUE)
      fallback_args <- join_args
      fallback_args$x <- fallback_scores
      fallback_args$y <- fallback_sched
      rlang::exec(dplyr::inner_join, !!!fallback_args)
    }
  )

  # ===========================================================================
  # DIAGNOSTIC: Empty join result detection with actionable messaging
  # ===========================================================================
  if (!nrow(combined)) {
    # Gather diagnostic information for troubleshooting
    diag_info <- list(
      scores_n = nrow(scores_ready),
      schedule_n = nrow(schedule_context),
      join_cols = join_cols,
      scores_keys = if (nrow(scores_ready) > 0) {
        utils::head(scores_ready[join_cols], 5)
      } else {
        tibble::tibble()
      },
      schedule_keys = if (nrow(schedule_context) > 0) {
        utils::head(schedule_context[join_cols], 5)
      } else {
        tibble::tibble()
      }
    )

    # Check for type mismatches in join keys
    type_mismatches <- character()
    for (col in join_cols) {
      if (col %in% names(scores_ready) && col %in% names(schedule_context)) {
        t1 <- typeof(scores_ready[[col]])
        t2 <- typeof(schedule_context[[col]])
        if (t1 != t2) {
          type_mismatches <- c(type_mismatches, sprintf("  - %s: scores=%s, schedule=%s", col, t1, t2))
        }
      }
    }

    # Check for overlapping values
    overlap_info <- character()
    for (col in join_cols) {
      if (col %in% names(scores_ready) && col %in% names(schedule_context)) {
        v1 <- unique(scores_ready[[col]])
        v2 <- unique(schedule_context[[col]])
        overlap <- length(intersect(as.character(v1), as.character(v2)))
        overlap_info <- c(overlap_info, sprintf("  - %s: %d values in scores, %d in schedule, %d overlap",
                                                 col, length(v1), length(v2), overlap))
      }
    }

    diag_msg <- sprintf(
      paste0(
        "build_moneyline_comparison_table(): JOIN PRODUCED ZERO ROWS\n",
        "  Scores rows: %d\n",
        "  Schedule rows: %d\n",
        "  Join columns: %s\n",
        "%s%s",
        "  Possible causes:\n",
        "    1. No overlapping game_id/season/week between scores and schedule\n",
        "    2. Column type mismatch (e.g., integer vs character for week)\n",
        "    3. Different naming conventions for join keys\n",
        "  Resolution: Check that both tables have matching values in: %s"
      ),
      diag_info$scores_n,
      diag_info$schedule_n,
      paste(join_cols, collapse = ", "),
      if (length(type_mismatches)) paste0("  Type mismatches:\n", paste(type_mismatches, collapse = "\n"), "\n") else "",
      if (length(overlap_info)) paste0("  Key overlaps:\n", paste(overlap_info, collapse = "\n"), "\n") else "",
      paste(join_cols, collapse = ", ")
    )

    if (verbose) message(diag_msg)

    # Return empty tibble with diagnostic attribute
    empty_result <- tibble::tibble()
    attr(empty_result, "join_diagnostic") <- diag_info
    return(empty_result)
  }

  combined <- combined %>%
    ensure_schedule_defaults() %>%
    dplyr::mutate(
      market_home_ml = market_home_ml_sched,
      market_away_ml = market_away_ml_sched,
      market_home_spread = market_home_spread_sched,
      market_total_line = market_total_line_sched,
      home_team = dplyr::coalesce(home_team, home_team_sched),
      away_team = dplyr::coalesce(away_team, away_team_sched),
      game_date = dplyr::coalesce(game_date, game_date_sched),
      # game_type comes from schedule (authoritative source)
      game_type = game_type_sched,
      blend_home_median = dplyr::coalesce(blend_home_median, blend_home_median_sched),
      blend_away_median = dplyr::coalesce(blend_away_median, blend_away_median_sched),
      blend_total_median = dplyr::coalesce(
        blend_total_median,
        blend_total_median_sched,
        dplyr::if_else(
          is.finite(blend_home_median) & is.finite(blend_away_median),
          blend_home_median + blend_away_median,
          NA_real_
        )
      ),
      blend_median_margin = dplyr::coalesce(
        blend_median_margin,
        dplyr::if_else(
          is.finite(blend_home_median) & is.finite(blend_away_median),
          blend_home_median - blend_away_median,
          NA_real_
        )
      ),
      actual_winner = dplyr::coalesce(actual_winner, winner_sched)
    ) %>%
    dplyr::select(-dplyr::ends_with("_sched")) %>%
    dplyr::mutate(
      game_date = suppressWarnings(as.Date(game_date)),
      matchup = dplyr::if_else(
        is.na(home_team) | is.na(away_team),
        NA_character_,
        paste(away_team, "@", home_team)
      ),
      blend_home_prob = clamp_probability(blend_home_prob),
      blend_away_prob = clamp_probability(1 - blend_home_prob),
      market_home_spread = coerce_numeric_safely(market_home_spread),
      market_home_prob = resolve_home_probability(
        market_home_prob,
        market_home_ml,
        market_away_ml,
        market_home_spread
      ),
      market_away_prob = clamp_probability(1 - market_home_prob),
      # Raw implied probabilities from moneylines (pre-devig)
      market_home_prob_raw = clamp_probability(american_to_probability(market_home_ml)),
      market_away_prob_raw = clamp_probability(american_to_probability(market_away_ml)),
      # Devig fair probabilities (proportional normalization)
      market_home_prob_fair = devig_two_way_probabilities(market_home_prob_raw, market_away_prob_raw)$p_home,
      market_away_prob_fair = devig_two_way_probabilities(market_home_prob_raw, market_away_prob_raw)$p_away,
      # Use devig fair probabilities for betting math when available
      market_home_prob = dplyr::coalesce(market_home_prob_fair, market_home_prob),
      market_away_prob = dplyr::coalesce(market_away_prob_fair, market_away_prob),
      # Preserve raw implied for display (separate from spread-derived)
      ml_implied_home_prob = market_home_prob_raw,
      ml_implied_away_prob = market_away_prob_raw,
      # Flag if market_home_prob differs significantly from moneyline-implied (spread-derived)
      prob_source = dplyr::case_when(
        is.na(market_home_ml) | !is.finite(market_home_ml) ~ "spread",
        is.na(ml_implied_home_prob) | !is.finite(ml_implied_home_prob) ~ "spread",
        abs(market_home_prob - ml_implied_home_prob) < 0.01 ~ "moneyline",
        TRUE ~ "moneyline"  # We prioritize moneyline when available
      ),
      market_home_spread = harmonize_home_spread(market_home_spread, market_home_prob),
      market_total_line = coerce_numeric_safely(market_total_line),
      blend_median_margin = dplyr::if_else(
        is.na(blend_home_median) | is.na(blend_away_median),
        NA_real_,
        blend_home_median - blend_away_median
      ),
      # Note: harmonize_home_margin moved to AFTER shrunk probability computation (v2.9.4 G8 fix)
      # Raw margin kept here for internal spread calculations
      blend_spread_equiv = dplyr::if_else(
        is.na(blend_median_margin),
        NA_real_,
        -blend_median_margin
      ),
      market_spread_win_prob = spread_to_win_probability(market_home_spread),
      blend_spread_win_prob = spread_to_win_probability(blend_spread_equiv),
      market_spread_win_prob_away = clamp_probability(1 - market_spread_win_prob),
      blend_spread_win_prob_away = clamp_probability(1 - blend_spread_win_prob),
      market_prob_spread_gap_home = market_home_prob - market_spread_win_prob,
      market_prob_spread_gap_away = market_away_prob - market_spread_win_prob_away,
      blend_prob_spread_gap_home = blend_home_prob - blend_spread_win_prob,
      blend_prob_spread_gap_away = blend_away_prob - blend_spread_win_prob_away,
      market_implied_margin = dplyr::if_else(
        is.na(market_home_spread),
        NA_real_,
        -market_home_spread
      ),
      market_total = market_total_line,
      market_home_ml = dplyr::if_else(
        is.na(market_home_ml),
        probability_to_american(market_home_prob),
        market_home_ml
      ),
      market_away_ml = dplyr::if_else(
        is.na(market_away_ml),
        probability_to_american(market_away_prob),
        market_away_ml
      ),

      # ===========================================================================
      # PROFESSIONAL CALIBRATION: Shrink probabilities toward market consensus
      # ===========================================================================
      # NFL markets are extremely efficient. Raw model probabilities that diverge
      # significantly from market are almost certainly overfit. We shrink toward
      # market to produce more realistic betting recommendations.
      #
      # One market weight for every game type (audit M2/M3): SHRINKAGE from config.R,
      # unvalidated until the backtest supports a value (docs/EVIDENCE_LEDGER.md C-SHRINK).
      # Playoff and Super Bowl variants were removed with no evidence behind them.
      .game_shrinkage = SHRINKAGE,
      blend_home_prob_shrunk = shrink_probability_toward_market(
        blend_home_prob, market_home_prob, shrinkage = .game_shrinkage
      ),
      blend_away_prob_shrunk = shrink_probability_toward_market(
        blend_away_prob, market_away_prob, shrinkage = .game_shrinkage
      ),

      # v2.9.4 G8 fix: Harmonize margin with SHRUNK probability for display coherence
      # sign(margin) must agree with sign(shrunk_prob - 0.5) to avoid contradictions
      blend_median_margin = harmonize_home_margin(blend_median_margin, blend_home_prob_shrunk),

      # Model MLs derived from SHRUNK probabilities for consistency with displayed probabilities
      # (v2.9.3 fix: ensures ML and displayed probability match)
      blend_home_ml = probability_to_american(blend_home_prob_shrunk),
      blend_home_ml_vig = apply_moneyline_vig(blend_home_ml, vig = vig),
      blend_away_ml = probability_to_american(blend_away_prob_shrunk),
      blend_away_ml_vig = apply_moneyline_vig(blend_away_ml, vig = vig),

      # Raw probability edge (for display - shows model's raw view)
      blend_edge_prob_home = blend_home_prob - market_home_prob,
      blend_edge_prob_away = blend_away_prob - market_away_prob,

      # Shrunk probability edge (for betting decisions - more conservative)
      blend_edge_prob_home_shrunk = blend_home_prob_shrunk - market_home_prob,
      blend_edge_prob_away_shrunk = blend_away_prob_shrunk - market_away_prob,

      # EV calculations using SHRUNK probabilities (more realistic)
      blend_ev_units_home = expected_value_units(blend_home_prob_shrunk, market_home_ml),
      blend_ev_units_away = expected_value_units(blend_away_prob_shrunk, market_away_ml),

      # Also calculate raw EV for comparison/display
      blend_ev_units_home_raw = expected_value_units(blend_home_prob, market_home_ml),
      blend_ev_units_away_raw = expected_value_units(blend_away_prob, market_away_ml),
      blend_favorite_side = dplyr::if_else(blend_home_prob >= blend_away_prob, "home", "away"),
      blend_favorite = dplyr::if_else(blend_favorite_side == "home", home_team, away_team),
      blend_best_ev = dplyr::case_when(
        !is.na(blend_ev_units_home) | !is.na(blend_ev_units_away) ~ pmax(
          dplyr::coalesce(blend_ev_units_home, -Inf),
          dplyr::coalesce(blend_ev_units_away, -Inf)
        ),
        TRUE ~ NA_real_
      ),
      blend_best_ev = dplyr::if_else(
        is.na(blend_best_ev) | blend_best_ev == -Inf,
        NA_real_,
        blend_best_ev
      ),
      blend_ev_units = blend_best_ev,
      blend_pick_side = dplyr::case_when(
        is.na(blend_best_ev) ~ NA_character_,
        blend_best_ev <= 0 ~ NA_character_,
        dplyr::near(blend_best_ev, blend_ev_units_home) ~ "home",
        dplyr::near(blend_best_ev, blend_ev_units_away) ~ "away",
        TRUE ~ NA_character_
      ),
      blend_pick_side = dplyr::if_else(
        is.na(blend_pick_side) & !is.na(blend_best_ev) & blend_best_ev > 0,
        dplyr::if_else(
          dplyr::coalesce(blend_ev_units_home, -Inf) >= dplyr::coalesce(blend_ev_units_away, -Inf),
          "home",
          "away"
        ),
        blend_pick_side
      ),
      # blend_pick now shows the team with best EV, or falls back to blend's favorite for Pass games
      blend_pick = dplyr::case_when(
        blend_pick_side == "home" ~ home_team,
        blend_pick_side == "away" ~ away_team,
        # For Pass games (negative EV), show the blend's favorite team for reference
        blend_favorite_side == "home" ~ home_team,
        blend_favorite_side == "away" ~ away_team,
        TRUE ~ NA_character_
      ),
      # Track whether this is an EV-based pick or just the blend's favorite
      blend_pick_type = dplyr::case_when(
        !is.na(blend_pick_side) ~ "ev_positive",
        !is.na(blend_favorite_side) ~ "favorite_only",
        TRUE ~ NA_character_
      ),
      # Raw blend probability for the picked side (for display)
      blend_prob_pick = dplyr::case_when(
        blend_pick_side == "home" ~ blend_home_prob,
        blend_pick_side == "away" ~ blend_away_prob,
        # For Pass games, use the favorite's probability
        blend_favorite_side == "home" ~ blend_home_prob,
        blend_favorite_side == "away" ~ blend_away_prob,
        TRUE ~ NA_real_
      ),
      # Shrunk probability for the picked side (for betting decisions)
      blend_prob_pick_shrunk = dplyr::case_when(
        blend_pick_side == "home" ~ blend_home_prob_shrunk,
        blend_pick_side == "away" ~ blend_away_prob_shrunk,
        blend_favorite_side == "home" ~ blend_home_prob_shrunk,
        blend_favorite_side == "away" ~ blend_away_prob_shrunk,
        TRUE ~ NA_real_
      ),
      blend_moneyline = dplyr::case_when(
        blend_pick_side == "home" ~ blend_home_ml,
        blend_pick_side == "away" ~ blend_away_ml,
        TRUE ~ NA_real_
      ),
      blend_moneyline_vig = dplyr::case_when(
        blend_pick_side == "home" ~ blend_home_ml_vig,
        blend_pick_side == "away" ~ blend_away_ml_vig,
        TRUE ~ NA_real_
      ),
      market_moneyline = dplyr::case_when(
        blend_pick_side == "home" ~ market_home_ml,
        blend_pick_side == "away" ~ market_away_ml,
        TRUE ~ NA_real_
      ),
      market_moneyline = dplyr::if_else(
        is.na(market_moneyline) & !is.na(blend_pick_side),
        probability_to_american(
          dplyr::case_when(
            blend_pick_side == "home" ~ market_home_prob,
            blend_pick_side == "away" ~ market_away_prob,
            TRUE ~ NA_real_
          )
        ),
        market_moneyline
      ),
      market_prob_pick = dplyr::case_when(
        blend_pick_side == "home" ~ dplyr::coalesce(
          market_home_prob,
          market_home_prob_raw,
          american_to_probability(market_home_ml)
        ),
        blend_pick_side == "away" ~ dplyr::coalesce(
          market_away_prob,
          market_away_prob_raw,
          american_to_probability(market_away_ml)
        ),
        # For Pass games, use market prob for blend's favorite
        blend_favorite_side == "home" ~ dplyr::coalesce(
          market_home_prob,
          market_home_prob_raw,
          american_to_probability(market_home_ml)
        ),
        blend_favorite_side == "away" ~ dplyr::coalesce(
          market_away_prob,
          market_away_prob_raw,
          american_to_probability(market_away_ml)
        ),
        TRUE ~ NA_real_
      ),
      market_prob_pick = clamp_probability(market_prob_pick),
      blend_prob_fav = dplyr::case_when(
        is.na(blend_home_prob) & is.na(blend_away_prob) ~ NA_real_,
        blend_home_prob >= blend_away_prob ~ blend_home_prob,
        TRUE ~ blend_away_prob
      ),
      market_prob_fav = dplyr::case_when(
        is.na(market_home_prob) & is.na(market_away_prob) ~ NA_real_,
        market_home_prob >= market_away_prob ~ market_home_prob,
        TRUE ~ market_away_prob
      ),
      market_pick_side = dplyr::case_when(
        is.na(market_home_prob) ~ NA_character_,
        market_home_prob >= market_away_prob ~ "home",
        TRUE ~ "away"
      ),
      market_pick = dplyr::case_when(
        market_pick_side == "home" ~ home_team,
        market_pick_side == "away" ~ away_team,
        TRUE ~ NA_character_
      ),
      market_pick_moneyline = dplyr::case_when(
        market_pick_side == "home" ~ market_home_ml,
        market_pick_side == "away" ~ market_away_ml,
        TRUE ~ NA_real_
      ),
      actual_winner_side = dplyr::case_when(
        is.na(actual_home_win) ~ NA_character_,
        actual_home_win == 1L ~ "home",
        actual_home_win == 0L ~ "away",
        TRUE ~ NA_character_
      ),
      blend_actual_units = realized_moneyline_units(
        pick_side = blend_pick_side,
        winner_side = actual_winner_side,
        odds = market_moneyline
      ),
      market_actual_units = realized_moneyline_units(
        pick_side = market_pick_side,
        winner_side = actual_winner_side,
        odds = market_pick_moneyline
      ),
      blend_edge_prob = dplyr::case_when(
        is.na(blend_prob_pick) | is.na(market_prob_pick) ~ NA_real_,
        TRUE ~ blend_prob_pick - market_prob_pick
      ),
      blend_edge_moneyline = dplyr::case_when(
        is.na(blend_pick_side) ~ NA_real_,
        blend_pick_side == "home" ~ market_home_ml - blend_home_ml,
        blend_pick_side == "away" ~ market_away_ml - blend_away_ml,
        TRUE ~ NA_real_
      ),
      market_ev_units = expected_value_units(market_prob_pick, market_moneyline),
      blend_beats_market_assessment = purrr::pmap(
        list(
          blend_actual_units = blend_actual_units,
          market_actual_units = market_actual_units,
          blend_ev_units = blend_ev_units,
          market_ev_units = market_ev_units,
          blend_prob_pick = blend_prob_pick,
          market_prob_pick = market_prob_pick,
          blend_pick_label = blend_pick,
          blend_moneyline = blend_moneyline,
          market_moneyline = market_moneyline,
          blend_edge_moneyline = blend_edge_moneyline
        ),
        assess_blend_vs_market
      ),
      blend_beats_market = purrr::map_lgl(
        blend_beats_market_assessment,
        ~ {
          res <- .x$result
          if (is.na(res)) NA else as.logical(res)
        }
      ),
      blend_beats_market_basis = purrr::map_chr(
        blend_beats_market_assessment,
        ~ .x$basis
      ),
      blend_beats_market_note_raw = purrr::map_chr(
        blend_beats_market_assessment,
        ~ .x$detail
      ),
      market_winning = {
        realized_market <- dplyr::case_when(
          is.na(market_actual_units) ~ NA,
          market_actual_units > 0 ~ TRUE,
          market_actual_units < 0 ~ FALSE,
          TRUE ~ NA
        )
        dplyr::coalesce(
          realized_market,
          dplyr::case_when(
            is.na(market_ev_units) ~ NA,
            market_ev_units > 0 ~ TRUE,
            TRUE ~ FALSE
          )
        )
      },
      blend_recommendation = dplyr::case_when(
        is.na(blend_ev_units) ~ "No Play",
        blend_ev_units <= 0 ~ "Pass",
        is.na(blend_pick) | !nzchar(blend_pick) ~ "Bet moneyline",
        TRUE ~ paste("Bet", blend_pick, "moneyline")
      ),
      # FIXED: Override blend_beats_market for Pass/No Play recommendations
      # Passing on negative EV is CORRECT behavior, not a "loss" to the market
      blend_beats_market = dplyr::case_when(
        blend_recommendation %in% c("Pass", "No Play") ~ NA,
        TRUE ~ blend_beats_market
      ),
      blend_beats_market_basis = dplyr::case_when(
        blend_recommendation %in% c("Pass", "No Play") ~ NA_character_,
        TRUE ~ blend_beats_market_basis
      ),
      # Add explanatory note for Pass recommendations with negative EV
      blend_beats_market_note_raw = dplyr::case_when(
        blend_recommendation == "Pass" & is.finite(blend_ev_units) & blend_ev_units < 0 ~
          sprintf("Pass: correctly avoided %.1f%% negative EV", abs(blend_ev_units * 100)),
        blend_recommendation == "No Play" ~
          "No Play: insufficient data",
        TRUE ~ blend_beats_market_note_raw
      ),
      blend_prob_pick_spread_prob = dplyr::case_when(
        blend_pick_side == "home" ~ blend_spread_win_prob,
        blend_pick_side == "away" ~ blend_spread_win_prob_away,
        TRUE ~ NA_real_
      ),
      market_prob_pick_spread_prob = dplyr::case_when(
        blend_pick_side == "home" ~ market_spread_win_prob,
        blend_pick_side == "away" ~ market_spread_win_prob_away,
        TRUE ~ NA_real_
      ),
      blend_prob_spread_gap_pick = dplyr::case_when(
        blend_pick_side == "home" ~ blend_prob_spread_gap_home,
        blend_pick_side == "away" ~ blend_prob_spread_gap_away,
        TRUE ~ NA_real_
      ),
      market_prob_spread_gap_pick = dplyr::case_when(
        blend_pick_side == "home" ~ market_prob_spread_gap_home,
        blend_pick_side == "away" ~ market_prob_spread_gap_away,
        TRUE ~ NA_real_
      ),
      probability_alignment_note = purrr::map2_chr(
        market_prob_spread_gap_pick,
        blend_prob_spread_gap_pick,
        ~ build_probability_alignment_note(.x, .y)
      ),
      probability_alignment_note = dplyr::if_else(
        is.na(blend_pick_side) | blend_recommendation %in% c("Pass", "No Play"),
        NA_character_,
        probability_alignment_note
      ),
      blend_beats_market_note = dplyr::case_when(
        is.na(probability_alignment_note) ~ blend_beats_market_note_raw,
        is.na(blend_beats_market_note_raw) ~ probability_alignment_note,
        !nzchar(blend_beats_market_note_raw) ~ probability_alignment_note,
        TRUE ~ paste(blend_beats_market_note_raw, probability_alignment_note, sep = " | ")
      ),
      blend_beats_market_note = shorten_market_note(blend_beats_market_note),
      # ===========================================================================
      # CONSERVATIVE KELLY STAKING
      # ===========================================================================
      # Use 1/8 Kelly with edge skepticism to account for model uncertainty.
      # Larger "edges" are more likely model errors, so we apply progressive
      # penalties for implausibly large edges.

      # Raw Kelly (for reference only - NOT used for staking)
      blend_kelly_fraction_raw = dplyr::case_when(
        is.na(blend_pick_side) ~ NA_real_,
        TRUE ~ {
          dec <- american_to_decimal(market_moneyline)
          b <- dec - 1
          stake <- (blend_prob_pick * b - (1 - blend_prob_pick)) / b
          invalid <- is.na(dec) | !is.finite(dec) | b <= 0 | abs(b) < 1e-6 | is.na(stake)
          stake[invalid] <- NA_real_
          stake
        }
      ),

      # Conservative Kelly using SHRUNK probabilities
      # Uses 1/8 Kelly (12.5%), max 10% believable edge, max 2% stake
      blend_confidence = dplyr::case_when(
        is.na(blend_pick_side) ~ NA_real_,
        TRUE ~ conservative_kelly_stake(
          prob = blend_prob_pick_shrunk,
          odds = market_moneyline,
          kelly_fraction = 0.125,   # 1/8 Kelly
          max_edge = 0.10,          # Cap believable edge at 10%
          max_stake = 0.02          # Max 2% of bankroll per bet
        )
      ),

      # Edge magnitude classification for display warnings
      edge_classification = classify_edge_magnitude(blend_ev_units),
      edge_classification_raw = classify_edge_magnitude(
        dplyr::case_when(
          blend_pick_side == "home" ~ blend_ev_units_home_raw,
          blend_pick_side == "away" ~ blend_ev_units_away_raw,
          TRUE ~ NA_real_
        )
      ),
      actual_winner = dplyr::case_when(
        is.na(actual_home_win) ~ actual_winner,
        actual_home_win == 1L  ~ home_team,
        actual_home_win == 0L  ~ away_team,
        TRUE ~ actual_winner
      ),
      blend_home_median = coerce_numeric_safely(blend_home_median),
      blend_away_median = coerce_numeric_safely(blend_away_median),
      blend_total_median = coerce_numeric_safely(blend_total_median),
      # legacy aliases preserved for downstream code expecting model_* naming
      model_prob = blend_home_prob,
      market_prob = market_home_prob,
      model_home_ml = blend_home_ml,
      model_home_ml_vig = blend_home_ml_vig,
      model_away_ml = blend_away_ml,
      model_away_ml_vig = blend_away_ml_vig,
      model_edge_prob = blend_edge_prob_home,
      model_ev_units = blend_ev_units_home,
      market_beats_model = brier_market < brier_model
    ) %>%
    dplyr::select(-dplyr::any_of(c(
      "blend_best_ev",
      "blend_spread_equiv",
      "blend_prob_pick_spread_prob",
      "market_prob_pick_spread_prob",
      "probability_alignment_note",
      "blend_beats_market_note_raw"
    ))) %>%
    dplyr::arrange(season, week, game_date, matchup)

  # ===========================================================================
  # INVARIANT CHECKS: Validate EV/pick/odds alignment

  # These assertions ensure the calculations are internally consistent
  # Enable debug trace with: options(nfl.ev_debug = TRUE)
  # ===========================================================================

  ev_debug <- getOption("nfl.ev_debug", default = FALSE)

  if (ev_debug && nrow(combined) > 0) {
    message("\n=== EV CALCULATION DEBUG TRACE ===")
    sample_rows <- head(combined, 3)
    for (i in seq_len(nrow(sample_rows))) {
      r <- sample_rows[i, ]
      message(sprintf("\nGame: %s @ %s", r$away_team, r$home_team))
      message(sprintf("  Pick side: %s", ifelse(is.na(r$blend_pick_side), "NA (Pass)", r$blend_pick_side)))
      message(sprintf("  Shrunk prob (pick): %.4f", ifelse(is.na(r$blend_prob_pick_shrunk), NA, r$blend_prob_pick_shrunk)))
      message(sprintf("  Market moneyline: %+d", ifelse(is.na(r$market_moneyline), NA, as.integer(r$market_moneyline))))
      message(sprintf("  Decimal odds: %.4f", american_to_decimal(r$market_moneyline)))
      message(sprintf("  Expected EV: %.4f", r$blend_prob_pick_shrunk * american_to_decimal(r$market_moneyline) - 1))
      message(sprintf("  Actual EV: %.4f", r$blend_ev_units))
      message(sprintf("  Recommendation: %s", r$blend_recommendation))
    }
    message("\n=== END DEBUG TRACE ===\n")
  }

  # Check 1: For Bet recommendations (positive EV), verify pick_side matches odds
  bet_rows <- !is.na(combined$blend_pick_side) & combined$blend_ev_units > 0
  if (any(bet_rows, na.rm = TRUE)) {
    # Verify home pick uses home odds
    home_picks <- combined$blend_pick_side == "home" & bet_rows
    if (any(home_picks, na.rm = TRUE)) {
      odds_match <- all(
        combined$market_moneyline[home_picks] == combined$market_home_ml[home_picks],
        na.rm = TRUE
      )
      if (!odds_match) {
        warning("INVARIANT VIOLATION: Home picks using wrong odds! Check market_moneyline vs market_home_ml")
      }
    }

    # Verify away pick uses away odds
    away_picks <- combined$blend_pick_side == "away" & bet_rows
    if (any(away_picks, na.rm = TRUE)) {
      odds_match <- all(
        combined$market_moneyline[away_picks] == combined$market_away_ml[away_picks],
        na.rm = TRUE
      )
      if (!odds_match) {
        warning("INVARIANT VIOLATION: Away picks using wrong odds! Check market_moneyline vs market_away_ml")
      }
    }
  }

  # Check 2: Verify EV calculation matches formula: EV = prob × decimal_odds - 1
  # Allow small tolerance for floating point
  if (any(bet_rows, na.rm = TRUE)) {
    ev_tolerance <- 0.001
    decimal_odds <- american_to_decimal(combined$market_moneyline[bet_rows])
    expected_ev <- combined$blend_prob_pick_shrunk[bet_rows] * decimal_odds - 1
    actual_ev <- combined$blend_ev_units[bet_rows]
    ev_mismatch <- abs(expected_ev - actual_ev) > ev_tolerance
    if (any(ev_mismatch, na.rm = TRUE)) {
      n_mismatches <- sum(ev_mismatch, na.rm = TRUE)
      warning(sprintf(
        "INVARIANT VIOLATION: %d games have EV mismatch! Expected EV != prob × odds - 1",
        n_mismatches
      ))
    }
  }

  # Check 3: Sanity bounds - if shrunk prob is low (<25%), EV can't be huge (>20%)
  # unless odds are extremely high (which we'll warn about)
  extreme_ev_low_prob <- bet_rows &
    !is.na(combined$blend_prob_pick_shrunk) &
    combined$blend_prob_pick_shrunk < 0.25 &
    combined$blend_ev_units > 0.20
  if (any(extreme_ev_low_prob, na.rm = TRUE)) {
    n_extreme <- sum(extreme_ev_low_prob, na.rm = TRUE)
    message(sprintf(
      "INFO: %d games have low probability (<25%%) but high EV (>20%%). These are underdog bets - verify odds are correct.",
      n_extreme
    ))
  }

  combined
}

if (interactive()) {
  message(
    "NFLmarket.R loaded. Use load_latest_market_inputs(), enrich_with_pre_kickoff_espn_lines(), and evaluate_market_vs_blend() as needed."
  )
}

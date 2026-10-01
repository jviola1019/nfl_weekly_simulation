# =============================================================================
# Game backtest v1: shared helpers (inputs, probabilities, ridge logistic,
# point-in-time assertions). Sourced by backtest/walk_forward.R and tests.
# =============================================================================

suppressPackageStartupMessages(library(data.table))

bt_logit <- function(p) log(p / (1 - p))
bt_expit <- function(x) 1 / (1 + exp(-x))
bt_clip <- function(p, eps = 1e-6) pmin(pmax(p, eps), 1 - eps)

# American odds -> implied probability (with vig)
bt_amer_to_p <- function(ml) {
  ml <- suppressWarnings(as.numeric(sub("^\\+", "", as.character(ml))))
  ifelse(is.na(ml), NA_real_, ifelse(ml < 0, -ml / (-ml + 100), 100 / (ml + 100)))
}

# American odds -> decimal odds
bt_amer_to_dec <- function(ml) {
  ml <- suppressWarnings(as.numeric(sub("^\\+", "", as.character(ml))))
  ifelse(is.na(ml), NA_real_, ifelse(ml < 0, 1 + 100 / -ml, 1 + ml / 100))
}

# Proportional devig of a two-way moneyline: home win probability
bt_novig_home <- function(home_ml, away_ml) {
  ph <- bt_amer_to_p(home_ml); pa <- bt_amer_to_p(away_ml)
  ph / (ph + pa)
}

bt_parse_utc <- function(x) as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

# Seconds a game's result becomes known after kickoff (conservative: 4 hours)
BT_GAME_DURATION_SEC <- 4 * 3600

#' Point-in-time guard: every source used for a row must have finished before
#' the row's kickoff. `src_end` and `kickoff` are POSIXct vectors; NA src_end
#' means "no source used" (prior only) and passes.
bt_assert_asof <- function(src_end, kickoff, what = "features") {
  bad <- !is.na(src_end) & !(src_end < kickoff)
  if (any(bad)) {
    stop(sprintf("as-of violation in %s: %d row(s) use data not final before kickoff", what, sum(bad)),
         call. = FALSE)
  }
  invisible(TRUE)
}

#' Load the committed inputs and verify them against the window's sha256s
bt_load_inputs <- function(data_dir, expected = NULL) {
  paths <- c(games = "games.csv", team_games = "team_games.csv", qb_games = "qb_games.csv",
             espn_open_close = "espn_open_close.csv")
  out <- list()
  for (nm in names(paths)) {
    f <- file.path(data_dir, paths[[nm]])
    if (!file.exists(f)) stop("bt_load_inputs: missing ", f, call. = FALSE)
    if (!is.null(expected[[nm]])) {
      got <- digest::digest(file = f, algo = "sha256")
      if (!identical(got, expected[[nm]])) {
        stop(sprintf("bt_load_inputs: %s sha256 %s != window %s", paths[[nm]], got, expected[[nm]]), call. = FALSE)
      }
    }
    cc <- if (nm == "espn_open_close") list(character = c("h_open", "a_open", "h_close", "a_close")) else
      if (nm == "games") list(character = c("home_qb_id", "away_qb_id", "gametime")) else NULL
    out[[nm]] <- fread(f, colClasses = cc, na.strings = c("", "NA"))
  }
  out$games <- bt_prepare_games(out$games)
  out
}

#' Derived game columns used everywhere
bt_prepare_games <- function(g) {
  g <- copy(g)
  g[, kickoff := bt_parse_utc(kickoff_utc)]
  g[, wk := season * 100L + week]
  g[, phase := fifelse(game_type == "REG", "REG", "POST")]
  g[, neutral := !is.na(location) & location == "Neutral"]
  g[, played := !is.na(home_score) & !is.na(away_score)]
  g[, tie := played & home_score == away_score]
  g[, y := fifelse(played & !tie, as.integer(home_score > away_score), NA_integer_)]
  g[, p_c0 := bt_novig_home(home_moneyline, away_moneyline)]
  setorder(g, kickoff, game_id)
  g[]
}

#' Ridge logistic regression by Newton-Raphson.
#' Minimizes -loglik + (lambda / 2) * sum(beta[penalized]^2).
#' `unpenalized` are column indices of X left unpenalized.
bt_ridge_logistic <- function(X, y, lambda, unpenalized = integer(), max_iter = 100L, tol = 1e-10) {
  X <- as.matrix(X)
  k <- ncol(X)
  pen <- rep(lambda, k)
  pen[unpenalized] <- 0
  beta <- rep(0, k)
  for (it in seq_len(max_iter)) {
    eta <- drop(X %*% beta)
    p <- bt_expit(eta)
    w <- p * (1 - p)
    grad <- drop(crossprod(X, p - y)) + pen * beta
    H <- crossprod(X, X * w) + diag(pen, k)
    step <- solve(H, grad)
    beta <- beta - step
    if (max(abs(step)) < tol) break
  }
  if (it == max_iter) warning("bt_ridge_logistic: no convergence in ", max_iter, " iterations", call. = FALSE)
  names(beta) <- colnames(X)
  beta
}

#' Weeks to predict, in order, with each week's cutoff (first kickoff)
bt_week_schedule <- function(games, seasons) {
  w <- games[season %in% seasons, .(cutoff = min(kickoff)), by = .(season, week, wk)]
  setorder(w, cutoff)
  w[]
}

#' Write text as UTF-8 with LF line endings on every OS. Evidence files are hash-locked,
#' and writeLines/fwrite default to CRLF on Windows (audit T6).
bt_write_text <- function(text, path) {
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeBin(charToRaw(enc2utf8(paste0(paste(text, collapse = "\n"), "\n"))), con)
  invisible(path)
}

bt_write_csv <- function(x, path) data.table::fwrite(x, path, eol = "\n")

#' Canonical rounding before hashing so a result hash is stable to print noise
bt_round <- function(x, digits = 10) round(x, digits)

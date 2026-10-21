# =============================================================================
# FILE: R/prop_pricing.R
# PURPOSE: Prices a prop at the best fresh quote (audit P12).
#   Devig per venue; Kalshi uses the bid/ask mid and pays a taker fee; EV is taken at the
#   best price for the side the model likes. Pure functions, no network.
# =============================================================================

#' Proportional two-way devig
#'
#' @param over_odds,under_odds American prices of the two sides (vectors; NA allowed)
#' @return list(p_over, p_under, overround); NA where a price is missing
devig_two_way <- function(over_odds, under_odds) {
  q_over <- american_odds_to_implied_prob(over_odds)
  q_under <- american_odds_to_implied_prob(under_odds)
  total <- q_over + q_under
  list(p_over = q_over / total, p_under = q_under / total, overround = total)
}

#' Kalshi taker fee per contract: coef * P * (1 - P), P in dollars, NA outside (0, 1)
kalshi_fee_per_contract <- function(price, coef = get0("KALSHI_TAKER_FEE_COEF", ifnotfound = NULL)) {
  if (is.null(coef) || length(coef) != 1 || !is.finite(coef) || coef < 0) {
    stop("kalshi_fee_per_contract: KALSHI_TAKER_FEE_COEF is not set (config.R)", call. = FALSE)
  }
  price <- suppressWarnings(as.numeric(price))
  out <- rep(NA_real_, length(price))
  ok <- is.finite(price) & price > 0 & price < 1
  out[ok] <- coef * price[ok] * (1 - price[ok])
  out
}

#' Decimal odds of a Kalshi contract that pays 1, after the taker fee: 1 / (P + fee)
kalshi_effective_decimal <- function(price, coef = get0("KALSHI_TAKER_FEE_COEF", ifnotfound = NULL)) {
  1 / (suppressWarnings(as.numeric(price)) + kalshi_fee_per_contract(price, coef))
}

#' Decimal to American odds without rounding; NA when dec <= 1
decimal_to_american_exact <- function(dec) {
  dec <- suppressWarnings(as.numeric(dec))
  out <- rep(NA_real_, length(dec))
  ok <- is.finite(dec) & dec > 1
  big <- ok & dec >= 2
  small <- ok & dec < 2
  out[big] <- (dec[big] - 1) * 100
  out[small] <- -100 / (dec[small] - 1)
  out
}

#' Decimal odds and fair probability of each side of every quote
#'
#' @param quotes Quotes of one player's prop in one game (from get_market_prop_quotes)
#' @param coef Kalshi taker fee coefficient
#' @return Tibble venue, book, captured_at, line_over, line_under, over_dec, under_dec, fair_over.
#'   Sportsbook rows: decimal odds of the quoted prices, fair_over by proportional devig (NA for a
#'   one-way market). Kalshi rows: Yes at yes_ask and No at 1 - yes_bid, both after the fee; fair_over
#'   is the bid/ask mid. A Kalshi row with a crossed or out-of-range book has NA everywhere.
quote_sides <- function(quotes, coef = get0("KALSHI_TAKER_FEE_COEF", ifnotfound = NULL)) {
  n <- nrow(quotes)
  num <- function(nm) if (nm %in% names(quotes)) suppressWarnings(as.numeric(quotes[[nm]])) else rep(NA_real_, n)
  venue <- if ("venue" %in% names(quotes)) ifelse(is.na(quotes$venue), "book", quotes$venue) else rep("book", n)
  line <- num("line")
  line_over <- if ("line_over" %in% names(quotes)) num("line_over") else line
  line_under <- if ("line_under" %in% names(quotes)) num("line_under") else line

  over_odds <- num("over_odds")
  under_odds <- num("under_odds")
  over_dec <- american_to_decimal_odds(over_odds)
  under_dec <- american_to_decimal_odds(under_odds)
  fair_over <- devig_two_way(over_odds, under_odds)$p_over

  is_kalshi <- venue == "kalshi"
  bid <- num("yes_bid")
  ask <- num("yes_ask")
  valid <- is_kalshi & is.finite(bid) & is.finite(ask) & bid > 0 & ask < 1 & bid <= ask
  over_dec[is_kalshi] <- NA_real_
  under_dec[is_kalshi] <- NA_real_
  fair_over[is_kalshi] <- NA_real_
  if (any(valid)) {
    over_dec[valid] <- kalshi_effective_decimal(ask[valid], coef)
    under_dec[valid] <- kalshi_effective_decimal(1 - bid[valid], coef)
    fair_over[valid] <- (bid[valid] + ask[valid]) / 2
  }

  tibble::tibble(
    venue = venue,
    book = as.character(quotes$book),
    captured_at = quotes$captured_at,
    line_over = line_over,
    line_under = line_under,
    over_dec = over_dec,
    under_dec = under_dec,
    fair_over = fair_over
  )
}

#' The quote and side with the highest model EV, after fees
#'
#' @param quotes Fresh quotes (from get_market_prop_quotes)
#' @param sim_values Simulated stat values (two-way market: over and under)
#' @param p_yes Model probability of Yes (one-way market, e.g. anytime TD)
#' @param coef Kalshi taker fee coefficient
#' @return list shaped like get_market_prop_line() plus fair_over (mean over quotes), ev_over, ev_under,
#'   fee_included; over_odds and under_odds are the effective American prices (Kalshi: net of fee).
#'   NULL when no quote can be priced.
select_best_quote <- function(quotes, sim_values = NULL, p_yes = NULL,
                              coef = get0("KALSHI_TAKER_FEE_COEF", ifnotfound = NULL)) {
  if (is.null(sim_values) && is.null(p_yes)) {
    stop("select_best_quote: give sim_values (two-way) or p_yes (one-way)", call. = FALSE)
  }
  sides <- quote_sides(quotes, coef)
  n <- nrow(sides)
  ev_over <- rep(NA_real_, n)
  ev_under <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (!is.null(sim_values)) {
      if (is.finite(sides$over_dec[i]) && is.finite(sides$line_over[i])) {
        p <- mean(sim_values > sides$line_over[i])
        p_push <- mean(sim_values == sides$line_over[i])
        ev_over[i] <- p * (sides$over_dec[i] - 1) - (1 - p - p_push)
      }
      if (is.finite(sides$under_dec[i]) && is.finite(sides$line_under[i])) {
        p <- mean(sim_values < sides$line_under[i])
        p_push <- mean(sim_values == sides$line_under[i])
        ev_under[i] <- p * (sides$under_dec[i] - 1) - (1 - p - p_push)
      }
    } else if (is.finite(sides$over_dec[i])) {
      ev_over[i] <- p_yes * (sides$over_dec[i] - 1) - (1 - p_yes)
    }
  }

  best_ev <- pmax(ev_over, ev_under, na.rm = TRUE)
  if (all(is.na(best_ev))) return(NULL)
  i <- which.max(best_ev)
  r <- sides[i, ]

  line_value <- if (is.finite(r$line_over) && is.finite(r$line_under) &&
                    abs(r$line_over - r$line_under) <= 0.25) {
    mean(c(r$line_over, r$line_under))
  } else if (is.finite(r$line_over)) {
    r$line_over
  } else {
    r$line_under
  }

  list(
    player = NA_character_,
    prop_type = NA_character_,
    line = line_value,
    line_over = r$line_over,
    line_under = r$line_under,
    over_odds = decimal_to_american_exact(r$over_dec),
    under_odds = decimal_to_american_exact(r$under_dec),
    book = r$book,
    books = unique(sides$book),
    n_books = length(unique(sides$book)),
    captured_at = r$captured_at,
    venue = r$venue,
    fair_over = if (all(is.na(sides$fair_over))) NA_real_ else mean(sides$fair_over, na.rm = TRUE),
    ev_over = ev_over[i],
    ev_under = ev_under[i],
    fee_included = identical(r$venue, "kalshi")
  )
}

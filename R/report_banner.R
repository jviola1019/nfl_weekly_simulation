# =============================================================================
# Report status banner + HTML escaping (used by NFLmarket.R's HTML report)
# =============================================================================

#' HTML-escape one cell value; NA becomes an empty string
html_escape_cell <- function(x) {
  if (length(x) == 1 && is.na(x)) return("")
  htmltools::htmlEscape(as.character(x))
}

#' Model status banner for the HTML report. Every number comes from arguments.
render_model_status_banner <- function(shrinkage, kelly_fraction, max_stake, staking_mode) {
  if (!is.numeric(shrinkage) || length(shrinkage) != 1 || is.na(shrinkage) || shrinkage < 0 || shrinkage > 1)
    stop("render_model_status_banner: shrinkage must be a number in [0, 1]", call. = FALSE)
  if (!is.numeric(kelly_fraction) || is.na(kelly_fraction) || kelly_fraction <= 0 || kelly_fraction > 1)
    stop("render_model_status_banner: kelly_fraction must be in (0, 1]", call. = FALSE)
  if (!is.numeric(max_stake) || is.na(max_stake) || max_stake <= 0 || max_stake > 1)
    stop("render_model_status_banner: max_stake must be in (0, 1]", call. = FALSE)
  if (!identical(staking_mode, "paper") && !identical(staking_mode, "live"))
    stop("render_model_status_banner: staking_mode must be 'paper' or 'live'", call. = FALSE)
  kelly_label <- if (abs(1 / kelly_fraction - round(1 / kelly_fraction)) < 1e-9)
    sprintf("1/%d Kelly", as.integer(round(1 / kelly_fraction))) else sprintf("%.3g Kelly", kelly_fraction)
  stake_line <- if (staking_mode == "paper")
    "<li><strong>Paper stakes</strong>: stakes are tracking units, not betting advice.</li>" else ""
  paste0(
    "<div class=\"risk-box\">",
    "<h3>Unvalidated model: research output</h3>",
    "<p>No backtest has passed the promotion gates yet. See docs/EVIDENCE_LEDGER.md.</p>",
    "<ul>",
    sprintf("<li>%.0f%% market weight applied to the model probability</li>", shrinkage * 100),
    sprintf("<li>%s staking, %.0f%% max stake per game</li>", kelly_label, max_stake * 100),
    stake_line,
    "</ul></div>"
  )
}

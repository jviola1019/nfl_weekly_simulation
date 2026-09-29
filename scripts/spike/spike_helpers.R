# Spike helpers: measurement code for reports/<date>/DATA_SOURCES_SPIKE.md.
# Not production code; Phase 2 provider code replaces it.

kalshi_event_date <- function(event_ticker) {
  m <- regmatches(event_ticker, regexpr("-[0-9]{2}[A-Z]{3}[0-9]{2}", event_ticker))
  if (length(m) == 0) return(as.Date(NA))
  s <- sub("^-", "", m)
  months <- c(JAN = 1, FEB = 2, MAR = 3, APR = 4, MAY = 5, JUN = 6, JUL = 7, AUG = 8, SEP = 9, OCT = 10, NOV = 11, DEC = 12)
  as.Date(sprintf("20%s-%02d-%s", substr(s, 1, 2), months[[substr(s, 3, 5)]], substr(s, 6, 7)))
}

espn_row_is_priced <- function(item) {
  has_price <- function(side) !is.null(side) && !is.null(side$american) && nzchar(side$american)
  any(vapply(list(item$open$over, item$open$under, item$current$over, item$current$under), has_price, logical(1)))
}

bias_test <- function(priced_hits, priced_n, unpriced_hits, unpriced_n) {
  pt <- stats::prop.test(c(priced_hits, unpriced_hits), c(priced_n, unpriced_n), correct = FALSE)
  list(diff = priced_hits / priced_n - unpriced_hits / unpriced_n, p_value = unname(pt$p.value))
}

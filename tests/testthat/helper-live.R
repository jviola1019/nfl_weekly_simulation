# =============================================================================
# Live-network test helpers
# =============================================================================
# A "LIVE: <host> unreachable" skip is allowed by tests/skip_allowlist.txt, so it
# must only happen after a real connectivity check to that host fails. Test files
# must not call skip("LIVE: ...") directly (enforced by test-skip-hygiene.R).
# =============================================================================

#' TRUE when an HTTPS request to the host gets any HTTP response within `timeout` seconds
live_host_reachable <- function(host, timeout = 5) {
  handle <- curl::new_handle(nobody = TRUE, connecttimeout = timeout, timeout = timeout)
  tryCatch({
    curl::curl_fetch_memory(paste0("https://", host, "/"), handle = handle)
    TRUE
  }, error = function(e) FALSE)
}

#' Skip the current test as LIVE only if the host is unreachable right now
skip_live <- function(host, timeout = 5) {
  if (!live_host_reachable(host, timeout)) {
    testthat::skip(paste0("LIVE: ", host, " unreachable"))
  }
  invisible(TRUE)
}

#' Evaluate a network call; if it errors, skip as LIVE when the host is
#' unreachable, otherwise re-raise the error so a real failure still fails.
#' Wrap only the network call, never expectations.
with_live <- function(host, expr) {
  tryCatch(expr, error = function(e) {
    skip_live(host)
    stop(e)
  })
}

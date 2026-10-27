#!/usr/bin/env Rscript
# =============================================================================
# Raw odds forward capture: a thin caller of the provider layer (R/odds/)
# =============================================================================
# Usage (from repo root):
#   Rscript scripts/capture_odds_raw.R                 # ESPN + Kalshi
#   Rscript scripts/capture_odds_raw.R --sources=espn  # one source
#   Rscript scripts/capture_odds_raw.R --root=/tmp/cap
#
# Writes gzipped raw responses under CAPTURE_ROOT/YYYY-MM-DD/<source>/ and appends one
# line per request (status, sha256) to CAPTURE_ROOT/manifest.ndjson. All HTTP goes
# through R/odds/http.R: truthful user agent, 20 s timeout, at most 1 request per
# second per domain, backoff on 429/5xx, no workaround for a 403 or a challenge page.
# Exit status 1 if no request succeeded (so schedulers notice).
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(name, default) {
  hit <- grep(sprintf("^--%s=", name), args, value = TRUE)
  if (length(hit) == 0) default else sub(sprintf("^--%s=", name), "", hit[[1]])
}

if (!file.exists("config.R") || !dir.exists("R/odds")) {
  stop("Run from the repository root (config.R and R/odds not found)")
}

cfg_env <- new.env()
sys.source("config.R", envir = cfg_env)
source("R/capture_raw.R")
for (f in sort(list.files("R/odds", pattern = "\\.R$", full.names = TRUE))) source(f)

cfg <- list(
  user_agent = cfg_env$CAPTURE_USER_AGENT,
  timeout_sec = cfg_env$CAPTURE_TIMEOUT_SEC,
  max_tries = cfg_env$CAPTURE_MAX_TRIES,
  min_interval_sec = cfg_env$CAPTURE_MIN_INTERVAL_SEC,
  horizon_hours = cfg_env$CAPTURE_HORIZON_HOURS,
  game_horizon_hours = cfg_env$CAPTURE_ESPN_GAME_HORIZON_HOURS,
  espn_prop_providers = cfg_env$CAPTURE_ESPN_PROP_PROVIDERS
)
root <- arg_value("root", cfg_env$CAPTURE_ROOT)
sources <- strsplit(arg_value("sources", "espn,kalshi"), ",", fixed = TRUE)[[1]]

started <- Sys.time()
message(sprintf("Capture start %s UTC -> %s (%s)",
                format(started, "%Y-%m-%d %H:%M:%S", tz = "UTC"), root,
                paste(sources, collapse = ",")))
summary <- run_capture(root = root, cfg = cfg, sources = sources)

if (nrow(summary) == 0) {
  message("No requests were made")
  quit(status = 1)
}

# a request is ok when it returned a usable body: a block or an empty body is not
ok <- !is.na(summary$status) & summary$status < 400 & is.na(summary$error)
by_source <- aggregate(
  cbind(requests = 1, ok = ok, bytes = summary$bytes) ~ source,
  data = transform(summary, ok = ok), FUN = sum
)
print(by_source, row.names = FALSE)
message(sprintf("Done in %.0fs: %d/%d requests ok, %.1f MB raw",
                as.numeric(difftime(Sys.time(), started, units = "secs")),
                sum(ok), nrow(summary), sum(summary$bytes) / 1e6))
if (!any(ok)) quit(status = 1)

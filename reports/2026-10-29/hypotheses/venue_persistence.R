# Track K1, across venue_snapshot.R's snapshots: does a price that beats Pinnacle's no-vig line last, and when it goes,
# who moved? For each side with EV > 0 against Pinnacle (the smaller of the proportional and power devigs) in one
# snapshot, the next snapshot shows it still positive, no longer positive or gone (the line or the game is no longer
# quoted). When it stops being positive, the move is put on whichever price changed more in log terms: the venue's
# cost, or Pinnacle's fair probability for that side. The snapshot summaries are stacked into one table as well.
# Reads the private per-venue prices in <raw_dir>; writes aggregates only. Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/venue_persistence.R <out_dir> <raw_dir>
suppressPackageStartupMessages(library(data.table))
a <- commandArgs(trailingOnly = TRUE); out <- a[1]; raw <- a[2]
files <- sort(list.files(raw, pattern = "^prices__[0-9]{8}T[0-9]{6}Z\\.csv\\.gz$", full.names = TRUE))
stopifnot(length(files) >= 2)
stamp_of <- function(f) sub("^prices__(.*)\\.csv\\.gz$", "\\1", basename(f))
power_p <- function(a, b) mapply(function(x, y) x^stats::uniroot(function(k) x^k + y^k - 1, c(0.1, 50))$root, a, b)
ev_of <- function(f) {
  px <- as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE))[!venue %in% c("Consensus", "Open")]
  pin <- dcast(px[venue == "Pinnacle"], game_id + market + line ~ side, value.var = "cost")
  for (s in c("home", "away", "over", "under")) if (!s %in% names(pin)) pin[, (s) := NA_real_]
  pin[, `:=`(c1 = fifelse(market %in% c("ml", "spread"), home, over), c2 = fifelse(market %in% c("ml", "spread"), away, under))]
  pin <- pin[is.finite(c1) & is.finite(c2)][, `:=`(p = c1 / (c1 + c2), p_pow = power_p(c1, c2))]
  ev <- merge(px[venue != "Pinnacle", .(venue, game_id, market, line, side, cost)], pin[, .(game_id, market, line, p, p_pow)], by = c("game_id", "market", "line"))
  ev[, `:=`(fair_prop = fifelse(side %in% c("home", "over"), p, 1 - p), fair_pow = fifelse(side %in% c("home", "over"), p_pow, 1 - p_pow))]
  ev[, `:=`(ev = pmin(fair_prop, fair_pow) / cost - 1, fair = fifelse(fair_prop / cost <= fair_pow / cost, fair_prop, fair_pow))]
  ev[, stamp := stamp_of(f)][]
}
evs <- lapply(files, ev_of)
key <- c("venue", "game_id", "market", "line", "side")
trans <- rbindlist(lapply(seq_len(length(evs) - 1L), function(k) {
  a0 <- evs[[k]][ev > 0]; a1 <- evs[[k + 1L]]
  x <- merge(a0, a1[, c(key, "cost", "fair", "ev"), with = FALSE], by = key, all.x = TRUE, suffixes = c("", "_next"))
  x[, status := fifelse(is.na(ev_next), "gone", fifelse(ev_next > 0, "still positive", "no longer positive"))]
  x[status == "no longer positive", moved := fifelse(abs(log(cost_next / cost)) >= abs(log(fair_next / fair)), "the venue's price", "Pinnacle's price")]
  x[, `:=`(from = stamp_of(files[k]), to = stamp_of(files[k + 1L]))][]
}))
persist <- trans[, .(sides_positive = .N, still_positive = mean(status == "still positive"), no_longer_positive = mean(status == "no longer positive"),
                     gone = mean(status == "gone"), venue_moved = sum(moved == "the venue's price", na.rm = TRUE), pinnacle_moved = sum(moved == "Pinnacle's price", na.rm = TRUE),
                     median_ev_pct = 100 * stats::median(ev)), by = .(from, to)]
by_venue <- trans[, .(sides_positive = .N, still_positive = mean(status == "still positive"), venue_moved = sum(moved == "the venue's price", na.rm = TRUE),
                      pinnacle_moved = sum(moved == "Pinnacle's price", na.rm = TRUE)), by = venue][order(-sides_positive)]
# a side that stayed positive through every later snapshot in which it was quoted
streak <- rbindlist(evs)[, .(snapshots = .N, positive = sum(ev > 0), first = min(stamp)), by = key][positive >= 2]
summ_files <- sort(list.files(out, pattern = "^snapshot_summary__.*\\.csv$", full.names = TRUE))
snaps <- rbindlist(lapply(summ_files, fread), fill = TRUE)
fwrite(persist[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 4) else v)], file.path(out, "persistence.csv"))
fwrite(by_venue[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 4) else v)], file.path(out, "persistence_by_venue.csv"))
fwrite(snaps, file.path(out, "snapshots.csv"))
options(width = 220)
print(snaps[, .(snapshot_utc, games, venues, quotes, two_sided_markets, arbitrages, closest_two_sided_cost, middles, middles_ev_positive, best_middle_ev_cents,
                sides_ev_positive_vs_pinnacle, sides_ev_over_2pct_vs_pinnacle)])
print(persist); print(by_venue)
cat(sprintf("\nsides positive in 2+ snapshots: %d (of them positive in every snapshot where quoted: %d)\n", nrow(streak), streak[positive == snapshots, .N]))

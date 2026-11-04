# How late did GitHub start the scheduled odds captures? Each scheduled run of odds-capture.yml (the output of
# `gh run list --workflow odds-capture.yml --json createdAt,startedAt,event,conclusion,databaseId`, saved as
# capture_runs.json) is matched to the cron slot it ran for. GitHub runs a slot at most once and in order, so slots and
# runs are paired in time order, one to one: each slot takes the first unpaired run that starts within 8 hours after it.
# A slot with no run is listed as skipped. It lists each delay and the games that kicked off between the slot and the
# run's start, whose pre-kickoff capture the run missed. Only slots after --since (when the schedule took effect) count.
# Run from the repository root:
#   Rscript reports/2026-10-28/feasibility/capture_delays.R <capture_runs.json> <out_csv> --since=<ISO time>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
since <- as.POSIXct(sub("^--since=", "", grep("^--since=", args, value = TRUE)), format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
args <- grep("^--", args, value = TRUE, invert = TRUE)
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
wf <- readLines(file.path(".github", "workflows", "odds-capture.yml"))
cr <- regmatches(wf, regexpr('cron: "[^"]+"', wf))
cr <- data.table(spec = sub('^cron: "([^"]+)"$', "\\1", cr))
cr[, c("min", "hour", "dom", "mon", "dow") := tstrsplit(spec, " ", fixed = TRUE)]
stopifnot(all(cr$dom == "*"), all(cr$mon == "*"), !anyNA(as.integer(cr$dow)))
runs <- as.data.table(jsonlite::fromJSON(args[1]))[event == "schedule"]
runs[, start := as.POSIXct(createdAt, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")]
runs <- runs[start >= since][order(start)]
days <- seq(as.Date(since, tz = "UTC"), as.Date(max(runs$start), tz = "UTC"), by = "day")
slots <- rbindlist(lapply(days, function(d) cr[as.integer(dow) == as.POSIXlt(d, tz = "UTC")$wday,
  .(cron = spec, slot = as.POSIXct(sprintf("%s %02d:%02d:00", d, as.integer(hour), as.integer(min)), tz = "UTC"))]))
slots <- slots[slot >= since & slot <= max(runs$start)][order(slot)]
used <- rep(FALSE, nrow(runs)); slots[, i_run := NA_integer_]
for (i in seq_len(nrow(slots))) {
  j <- which(!used & runs$start >= slots$slot[i] & runs$start < slots$slot[i] + 8 * 3600)
  if (length(j)) { used[j[1]] <- TRUE; slots$i_run[i] <- j[1] }
}
slots[, `:=`(run = runs$databaseId[i_run], start = runs$start[i_run], conclusion = runs$conclusion[i_run])]
sched <- props_schedule()
kicked <- function(i) if (is.na(slots$start[i])) character(0) else sched[kick > slots$slot[i] & kick <= slots$start[i], game_id]
slots[, `:=`(delay_min = round(as.numeric(difftime(start, slot, units = "mins"))),
             games_kicked_off_before_start = vapply(seq_len(.N), function(i) length(kicked(i)), integer(1)),
             games = vapply(seq_len(.N), function(i) paste(kicked(i), collapse = " "), character(1)),
             next_kickoff_min = vapply(seq_len(.N), function(i) { if (is.na(start[i])) return(NA_real_); k <- sched[kick > start[i], min(kick)]
                                                                  round(as.numeric(difftime(k, start[i], units = "mins"))) }, numeric(1)))]
iso <- function(t) format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
out <- slots[, .(cron, slot = iso(slot), run, start = iso(start), delay_min, games_kicked_off_before_start, next_kickoff_min,
                 conclusion = fifelse(is.na(run), "skipped", conclusion), games)]
fwrite(out, args[2])
print(out[, !"games"])
ran <- out[!is.na(run)]
missed <- unique(unlist(strsplit(ran$games, " ", fixed = TRUE)))
cat(sprintf("\nslots since %s: %d (%d with no run; %d runs unpaired); delay %d-%d min (median %d); distinct games that kicked off between a slot and its run: %d (%s)\n",
            iso(since), nrow(out), sum(is.na(out$run)), sum(!used), min(ran$delay_min), max(ran$delay_min), as.integer(stats::median(ran$delay_min)),
            length(missed), paste(missed, collapse = " ")))

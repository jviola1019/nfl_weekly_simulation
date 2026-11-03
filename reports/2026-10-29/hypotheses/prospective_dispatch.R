# The weekly testing program on a timer (HYPOTHESES.md §15, nfl_props_v1's weekly runs). Windows Task Scheduler starts
# this every 15 minutes, and it runs whatever step is due for the 2026 regular-season weeks it covers:
#   run    Tuesday 18:00Z and Friday 21:00Z before the week (the decision points): run_week.R, then a snapshot.
#          Tuesday's must finish before the week's first kickoff, Friday's before its last.
#   snap   Thursday 18:00Z, and 60 minutes before every distinct kickoff time (deadline: 5 minutes before it).
#   fetch  Kalshi's settlements and hourly candles for the week, then score_week.R: the first Tuesday 12:00Z after the
#          week's last game, and again on Wednesday 12:00Z for anything settled late.
#   preclose  nfl_preclose_v1.1's predictions for the week (backtest/preclose/run_2026.R predict, after build_history.R
#          refreshes the private 2025-2026 history), Tuesday 18:30Z, deadline the week's first kickoff. Scheduled only
#          when <store>/preclose_checkout.txt names a checkout of the registered code; outputs go to <store>/preclose/.
# Every step goes through weekly_prospective.sh, so a timed run and a hand run are the same thing. A step that exits 0
# leaves <store>/wWW/done/<step>.ok; a failure is retried at the next 3 starts, then an hour after its last failure, until
# its deadline and at most 12 tries in all; a step whose deadline passes, or that fails 12 times, is marked missed and
# logged. The schedule (nflverse, keyless) is cached in <store> and refreshed
# every 12 hours; 2026 only.
# Usage: Rscript prospective_dispatch.R --store=<dir> --prod=<checkout for run_week.R> --res=<research checkout>
#          [--first-week=9] [--last-week=18] [--now=<YYYY-mm-ddTHH:MM:SSZ>] [--only=<regex>] [--dry-run]
# --dry-run prints every step with its status at --now (default: the clock) and runs nothing. --only keeps the steps
# whose name matches (a hand run of one step: --only=^snap_thu$ with a --now inside its window).
suppressPackageStartupMessages(library(data.table))
BASH <- "C:/Program Files/Git/bin/bash.exe"   # Git for Windows' launcher, which puts the POSIX tools on PATH
RUNNER <- file.path("reports", "2026-10-29", "hypotheses", "weekly_prospective.sh")
TRIES <- 3L         # tries at successive starts after a failure
RETRY_GAP <- 3600   # then one try this many seconds after the last failure, until the deadline
MAX_TRIES <- 12L    # and no more than this many in all
utc <- function(x) format(x, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

load_schedule <- function(store, now, log) {
  f <- file.path(store, "schedule_2026.csv")
  if (!file.exists(f) || difftime(now, file.mtime(f), units = "hours") > 12) {
    s <- tryCatch(as.data.table(nflreadr::load_schedules(2026)), error = function(e) { log("schedule refresh failed:", conditionMessage(e)); NULL })
    if (!is.null(s) && nrow(s) > 0) fwrite(s[, .(game_id, season, game_type, week, gameday, gametime, home_team, away_team)], f)
  }
  if (!file.exists(f)) stop("no schedule: the refresh failed and there is no cached copy")
  s <- fread(f)[game_type == "REG"]
  stopifnot(nrow(s) > 0, all(s$season == 2026))
  s[, kick := as.POSIXct(paste(gameday, gametime), format = "%Y-%m-%d %H:%M", tz = "America/New_York")]
  attr(s$kick, "tzone") <- "UTC"
  s[]
}

# every step of every week, with when it is due and its deadline
week_steps <- function(sched, weeks, preclose = FALSE) {
  at <- function(d, hm) as.POSIXct(paste(format(d), hm), tz = "UTC")
  et_day <- function(t) as.Date(format(t, "%Y-%m-%d", tz = "America/New_York"))
  wday <- function(d) as.POSIXlt(d)$wday   # Sunday 0, Tuesday 2
  rbindlist(lapply(weeks, function(w) {
    g <- sched[week == w]
    if (!nrow(g)) return(NULL)
    k1 <- min(g$kick); kn <- max(g$kick); kicks <- sort(unique(g$kick))
    tue <- et_day(k1) - ((wday(et_day(k1)) - 2L) %% 7L)            # the Tuesday on or before the first game
    after <- et_day(kn) + ((1L - wday(et_day(kn))) %% 7L) + 1L      # the first Tuesday after the last game
    fetch_env <- sprintf("FROM=%s TO=%s", format(as.Date(k1) - 1L), format(as.Date(kn) + 3L))
    rbind(
      data.table(week = w, step = "run_tue", mode = "run", due = at(tue, "18:00:00"), deadline = k1, env = ""),
      data.table(week = w, step = "snap_thu", mode = "snap", due = at(tue + 2L, "18:00:00"), deadline = kn, env = ""),
      data.table(week = w, step = "run_fri", mode = "run", due = at(tue + 3L, "21:00:00"), deadline = kn, env = ""),
      data.table(week = w, step = sprintf("snap_%s", format(kicks, "%Y%m%dT%H%MZ", tz = "UTC")), mode = "snap",
                 due = kicks - 3600, deadline = kicks - 300, env = ""),
      data.table(week = w, step = c("fetch_tue", "fetch_wed"), mode = "fetch",
                 due = c(at(after, "12:00:00"), at(after + 1L, "12:00:00")), deadline = at(after + 6L, "12:00:00"), env = fetch_env),
      if (preclose) data.table(week = w, step = "preclose_predict", mode = "preclose", due = at(tue, "18:30:00"), deadline = k1, env = "")
    )
  }))[order(due)]
}

step_state <- function(store, s, now) {
  d <- file.path(store, sprintf("w%02d", s$week), "done")
  if (file.exists(file.path(d, paste0(s$step, ".ok")))) return("ok")
  if (file.exists(file.path(d, paste0(s$step, ".missed")))) return("missed")
  fails <- list.files(d, pattern = sprintf("^%s\\.fail[0-9]+$", s$step), full.names = TRUE)
  if (now < s$due) return("waiting")
  if (now >= s$deadline || length(fails) >= MAX_TRIES) return("expire")
  # an outage can outlast three starts (2026-11-03: a DNS failure took all three in 30 minutes)
  if (length(fails) >= TRIES && difftime(now, max(file.mtime(fails)), units = "secs") < RETRY_GAP) return("backoff")
  "due"
}

run_step <- function(store, prod, res, s, log) {
  w <- file.path(store, sprintf("w%02d", s$week)); d <- file.path(w, "done")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  for (kv in strsplit(strsplit(s$env, " ")[[1]], "=")) if (length(kv) == 2L) do.call(Sys.setenv, setNames(list(kv[2]), kv[1]))
  q <- function(x) shQuote(x, type = "cmd")
  log(sprintf("start week %d %s (%s, due %s)", s$week, s$step, s$mode, utc(s$due)))
  if (s$mode == "preclose") {
    pc <- trimws(readLines(file.path(store, "preclose_checkout.txt"), warn = FALSE)[1]); ps <- file.path(store, "preclose")
    dir.create(file.path(w, "logs"), recursive = TRUE, showWarnings = FALSE)
    lf <- file.path(w, "logs", sprintf("preclose_%s.log", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")))
    old <- setwd(pc); on.exit(setwd(old), add = TRUE)
    rc <- system2("Rscript", c(file.path("backtest", "preclose", "build_history.R"), q(file.path(ps, "raw")), q(file.path(ps, "history"))), stdout = lf, stderr = lf)
    if (rc == 0L) rc <- system2("Rscript", c(file.path("backtest", "preclose", "run_2026.R"), "predict", q(file.path(ps, "predictions")),
                                          paste0("--history=", file.path(ps, "history")), paste0("--week=", s$week)), stdout = lf, stderr = lf)
    setwd(old)
  } else rc <- system2(BASH, c(q(file.path(res, RUNNER)), s$mode, q(prod), q(res), q(w), s$week))
  if (rc == 0L && s$mode == "fetch") rc <- system2(BASH, c(q(file.path(res, RUNNER)), "score", q(prod), q(res), q(w), s$week))
  if (rc == 0L) file.create(file.path(d, paste0(s$step, ".ok"))) else
    file.create(file.path(d, sprintf("%s.fail%d", s$step, length(list.files(d, pattern = sprintf("^%s\\.fail", s$step))) + 1L)))
  log(sprintf("end week %d %s exit=%d", s$week, s$step, rc))
}

main <- function() {
  a <- commandArgs(trailingOnly = TRUE)
  opt <- function(k, d = NULL) { v <- sub(sprintf("^--%s=", k), "", grep(sprintf("^--%s=", k), a, value = TRUE)); if (length(v)) v[1] else d }
  store <- opt("store"); prod <- opt("prod"); res <- opt("res")
  if (is.null(store) || is.null(prod) || is.null(res)) stop("--store, --prod and --res are required")
  weeks <- as.integer(opt("first-week", "9")):as.integer(opt("last-week", "18"))
  dry <- "--dry-run" %in% a
  now <- if (is.null(opt("now"))) Sys.time() else as.POSIXct(opt("now"), format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  dir.create(file.path(store, "logs"), recursive = TRUE, showWarnings = FALSE)
  log <- function(...) if (!dry) cat(utc(Sys.time()), paste(...), "\n", file = file.path(store, "logs", "dispatch.log"), append = TRUE)
  # one dispatcher at a time, whoever started it (the loop, the scheduled task or a hand run): creating the lock
  # directory is atomic; a lock older than 8 hours is stale
  lock <- file.path(store, "dispatch.lock")
  if (!dry) {
    if (!dir.create(lock, showWarnings = FALSE)) {
      if (difftime(Sys.time(), file.mtime(lock), units = "hours") < 8) return(invisible())
      unlink(lock, recursive = TRUE)
      if (!dir.create(lock, showWarnings = FALSE)) return(invisible())
    }
    on.exit(unlink(lock, recursive = TRUE))
  }
  steps <- week_steps(load_schedule(store, now, log), weeks, preclose = file.exists(file.path(store, "preclose_checkout.txt")))
  if (!is.null(opt("only"))) steps <- steps[grepl(opt("only"), step)]
  steps[, state := vapply(seq_len(.N), function(i) step_state(store, steps[i], now), "")]
  if (dry) {
    options(width = 200)
    print(steps[, .(week, step, mode, due = utc(due), deadline = utc(deadline), state)], nrows = 500)
    return(invisible())
  }
  for (i in which(steps$state == "expire")) {
    d <- file.path(store, sprintf("w%02d", steps$week[i]), "done"); dir.create(d, recursive = TRUE, showWarnings = FALSE)
    file.create(file.path(d, paste0(steps$step[i], ".missed")))
    log(sprintf("missed week %d %s (due %s, deadline %s)", steps$week[i], steps$step[i], utc(steps$due[i]), utc(steps$deadline[i])))
  }
  # due steps in time order; the clock is re-read after each, because a step can outlast another's deadline
  for (i in which(steps$state == "due")) {
    if (Sys.time() >= steps$deadline[i] && is.null(opt("now"))) next
    run_step(store, prod, res, steps[i], log)
  }
}

main()

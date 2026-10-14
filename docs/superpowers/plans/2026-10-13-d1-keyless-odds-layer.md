# D1: The Keyless Odds Layer and the Decision-Time Archive — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One keyless odds layer in R (`R/odds/`) that every later phase reads: a single HTTP layer with the owner's rate rules, one provider interface with three providers (nflverse consensus close, ESPN core open/close and live prop lines, Kalshi game and prop candles), a normalized `odds_snapshots` table, the closing rule, a committed decision-time archive of ESPN game openers and closes for 2023–2024 (never 2025), and forward capture that runs through the same code.

**Architecture:**
- `R/odds/http.R` is the only code that touches the network. It takes the actual call as an injectable `fetch_fn(url, cfg)`. Tests pass a fake that serves recorded JSON from `tests/testthat/fixtures/odds/`, so the default suite makes no request and needs no new package.
- Providers are built by constructors (`provider_nflverse()`, `provider_espn_core()`, `provider_kalshi()`) and return `odds_result`s: normalized snapshots, a `source_status` row (the existing contract) and the fetch lineage (sha256 of every raw response).
- `R/odds/snapshots.R` defines the `odds_snapshots` shape from the Drizzle table; `R/odds/closing.R` implements the closing rule; `R/odds/archive.R` plus `backtest/build_odds_archive.R` build `backtest/data/odds_archive/` the way `backtest/build_inputs.R` builds `backtest/data/`.
- `scripts/capture_odds_raw.R` becomes a 60-line caller of `run_capture()` (`R/odds/capture.R`), and `.github/workflows/odds-capture.yml` is unchanged.

**Tech Stack:** R 4.5.1, httr2, jsonlite, digest (all in `renv.lock`), testthat 3. **No new dependency.** `httptest2` is not locked and is not used (owner checkpoint CP1).

**Spec:** `docs/superpowers/specs/2026-09-28-nfl-overhaul-design.md` Phase 2 (keyless odds layer), the HTTP policy in §2, and the data-sources addendum. **Roadmap:** `docs/superpowers/plans/2026-10-12-modeling-roadmap.md` §4 D1. **Audit IDs:** S2 and S4. **Base:** `main` at `210f791`.

**What this plan found in the real data** (so the executor knows the numbers are measured, not assumed): the dry run fetched all 570 ESPN game-odds responses for 2023–2024 and the coverage is in Task 9 and `docs/odds-sources.md`. A real response with a line but no price broke the first parser; Task 5's test `a line whose price is missing…` pins it.

---

## Global Constraints

Copied from the roadmap §2 and the planner brief, plus D1's own:

- **Keyless data only:** no API keys and no free trials. At most 1 request per second, a truthful user agent, and a 20 s timeout. Never work around an HTTP 403 or 429.
- **The 2025 game Holdout stays sealed** until `nfl_games_v2` is signed with C3 (or the owner decides to go without C3). It is scored once, for every candidate together (A2 decision 3). D1 never fetches, stores, reads or scores 2025 game rows. The G3 Holdout build appends them after the freeze.
- **Props may read 2025 Kalshi data only under a signed `nfl_props_v1` protocol** (owner, 2026-10-13); that is P3's job. D1 builds the Kalshi reader and fixtures from 2026 data only.
- **Stop and ask the owner before:** changing `config.R` defaults; editing `NFLsimulation.R`, `NFLmarket.R` or `injury_scalp.R` beyond an approved item; adding a dependency (`renv.lock` or `web/package.json`; `httptest2` is not locked); changing `R/data_validation.R` signatures; editing `backtest/eval_windows/*.json` or any frozen `PROTOCOL.md`; deleting any file; merging any PR.
- **Numbers in docs.** A number goes in a doc only if a script or CI produced it. No silent fallbacks: every data problem is logged and flagged, and the project rule outranks plan text.
- **Golden master.** D1 changes no prediction (it touches no engine file). CI's golden master must still read "no differences". Local R gates run with a fresh `HOME` (an empty scratch directory).
- **Linux.** CI is Linux. Any shell argument built in R is quoted with `shQuote`. Nothing relies on Windows-only behaviour.
- **Commits** end with a blank line, then exactly `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. PR bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. One branch per phase (`feat/d1-odds-layer`); fix and feat are never mixed.
- **Windows and Git Bash:** write and edit files with the file tools (heredocs collapse backslashes); pass `C:/` paths to R; list a directory before deleting anything. This plan deletes no file.
- **Frozen inputs:** `backtest/data/espn_open_close.csv` and the other four files hashed in `backtest/eval_windows/nfl_games_v1.json` are never touched. The new archive lives beside them in `backtest/data/odds_archive/`.
- **Model choice (SDD):** tasks marked *haiku* are complete code to transcribe; tasks marked *sonnet* need judgment (network runs, diffs against existing files, docs).

## Owner checkpoints (STOP and ask)

| # | Checkpoint | Where | What the plan does |
|---|---|---|---|
| CP1 | **Any dependency** | whole plan | Adds none. `httptest2` would give recorded-HTTP fixtures but is not in `renv.lock`; it is an alternative only if the owner approves adding it. The plan's default is the no-new-dependency fetch seam (Tasks 1, 5, 6). |
| CP2 | **Anything touching 2025** | Tasks 8, 9 | Game rows: `odds_archive_assert_seasons()` refuses 2025 before any schedule load or request, tested in-process and on the command line, and the committed data is tested to contain none. Kalshi: only 2026 markets are used for fixtures; 2025 props wait for P3's signed protocol. The G3 Holdout build, after the freeze, is the only code that may raise `ODDS_ARCHIVE_MAX_SEASON`. |
| CP3 | `config.R` defaults | Task 1, 7 | Not edited. `CAPTURE_MIN_INTERVAL_SEC` is `0.5` today, which is 2 requests per second and breaks the 1 req/s rule; `odds_http_config()` floors it at 1 s in code and `capture_odds_raw.R` prints a note. **The owner may want to set the constant to 1 so the file says what runs.** |
| CP4 | Committing new data | Task 9 | Adds `backtest/data/odds_archive/` (four files). It is additive; no protocol hashes it (a test checks `nfl_games_v1.json` does not list it). Review the coverage before merging. |
| CP5 | New workflow | Task 10 | Adds `.github/workflows/odds-live-smoke.yml` (manual only, read-only permissions). `odds-capture.yml` is unchanged. |
| CP6 | Terms-of-service sign-off (audit S4, spec A4) | Task 11 | `docs/odds-sources.md` records what was verified and marks the terms text of ESPN, Kalshi and nflverse **not reviewed by the owner**. Production use of the archive waits for the sign-off. |
| CP7 | Merge | end | The owner merges. |

Nothing in this plan edits `NFLsimulation.R`, `NFLmarket.R`, `injury_scalp.R`, `R/data_validation.R`, any `eval_windows` file or any `PROTOCOL.md`, and nothing deletes a file. `run_capture()` and `capture_http_get()` stay in the API (their code moves or delegates), so `scripts/spike/*` and `reports/…/clv_power.R` keep working.

## Review Focus

The five failure modes most likely to bite, each pinned by a test:

1. **A close that is not a close** (a snapshot after kickoff, or a stale one, reaches headline CLV). Pinned by Task 3: `a post-kickoff snapshot is never a close…`, `a gap over 60 minutes is stale…`, and Task 6's end-to-end `game_snapshots … feeds the closing rule`.
2. **A close at the wrong line.** A pick at spread −3 must not be compared with a later −3.5 close, and a missing close stays missing (the M11 rule). Pinned by Task 3: `the close is taken per line…` (`no_close_at_line`, no nearest-line substitute).
3. **2025 rows entering the archive.** Pinned by Task 8: `odds_archive_build refuses 2025 before any request or file` (zero requests, no directory), `the build script refuses 2025 on the command line…`, and by Task 9's `test-odds-archive-data.R` on the committed files.
4. **Rate and block rules broken** (more than 1 request/second to a domain, a retry after a 403, hammering after a 429). Pinned by Task 1: the throttle test, `a 403 is never retried and blocks the domain`, `a 429 that survives every retry blocks the domain`; and by Task 7: the configured 0.5 s is raised to the floor.
5. **A silent substitute for a data problem, or a live call in the default suite.** A provider item without open and close blocks, an unmapped prop type or Kalshi strike, a failed game, a game with no kickoff: each is named in `source_status`/attributes and produces no row. The fake fetch errors on an unknown URL, `odds_http_get` refuses while `NFL_ODDS_FORBID_LIVE=1`, and Task 10's `test-odds-no-live.R` scans the odds tests. Pinned by Tasks 1, 4, 5, 6, 10.

## File map

| File | Task | Responsibility |
|---|---|---|
| `tests/testthat/setup.R` (edit) | 1 | also load `R/odds/*.R` (the loader is not recursive) |
| `tests/testthat/helper-odds.R` | 1 | live guard on, `odds_fake_fetch()`, `odds_fake_clock()`, fixture readers |
| `R/odds/http.R`, `tests/testthat/test-odds-http.R` | 1 | throttle, backoff, block breaker, sha256, fetch log, seam |
| `R/odds/snapshots.R`, `tests/testthat/test-odds-snapshots.R` | 2 | `odds_snapshots` shape, market and venue catalogs, validation |
| `R/odds/closing.R`, `tests/testthat/test-odds-closing.R` | 3 | closing rule, stale flag, same-line match |
| `R/odds/provider.R`, `R/odds/provider_nflverse.R`, `tests/testthat/test-odds-provider.R` | 4 | interface, `odds_result`, nflverse consensus close |
| `R/odds/provider_espn_core.R`, `tests/testthat/test-odds-espn-core.R`, `fixtures/odds/espn_game_odds_*.json` | 5 | ESPN open/close, DraftKings prop lines, capture pass |
| `R/odds/provider_kalshi.R`, `tests/testthat/test-odds-kalshi.R`, `fixtures/odds/kalshi_*.json` | 6 | Kalshi markets and candles, both endpoint forms, capture pass |
| `R/odds/capture.R`, `R/capture_raw.R` (edit), `scripts/capture_odds_raw.R`, `tests/testthat/test-odds-capture.R` | 7 | forward capture through the providers |
| `R/odds/archive.R`, `backtest/build_odds_archive.R`, `tests/testthat/test-odds-archive.R` | 8 | archive builder, coverage, verifier, 2025 seal |
| `backtest/data/odds_archive/*`, `tests/testthat/test-odds-archive-data.R` | 9 | the committed 2023–2024 archive and its guard |
| `tests/live/test-odds-live.R`, `scripts/odds_live_smoke.R`, `.github/workflows/odds-live-smoke.yml`, `tests/testthat/test-odds-no-live.R`, two test edits | 10 | live smoke outside the suite; no-live guard; recursive R/ scans |
| `docs/odds-sources.md`, `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `HANDOFF.md` | 11 | sources, terms matrix, coverage, inventory |

## Setup (once, before Task 1)

- [ ] **S1: Worktree.** `git -C C:/Users/jviol/Downloads/nfl worktree add C:/Users/jviol/Downloads/nfl-worktrees/d1 -b feat/d1-odds-layer origin/main`, then `cd` into it. If `C:/Users/jviol/Downloads/nfl/.Rprofile` exists and the worktree has none, copy it (it is gitignored). `ls C:/Users/jviol/Downloads/nfl-worktrees/` first: the name `d1` must not exist.
- [ ] **S2: R library.** `Rscript -e "library(testthat); library(httr2); library(jsonlite); library(digest); library(withr); library(yaml); cat('ok\n')"` prints `ok`. If a package is missing, `Rscript -e "renv::restore(prompt = FALSE)"`, then `git diff --exit-code renv.lock` (it must stay unchanged).
- [ ] **S3: Fresh HOME.** Create an empty scratch directory (call it `<fresh>`) and prefix every `Rscript` below with `HOME=<fresh>`.
- [ ] **S4: Baseline.** `HOME=<fresh> Rscript scripts/run_tests.R` and `HOME=<fresh> Rscript scripts/verify_repo_integrity.R`. Record the final lines; both exit 0 on the untouched branch (the `run_tests` baseline at the `210f791` merge was `450 tests, 1722 passed, 0 failed, 0 errors, 1 allowlisted skip (KNOWN-DEFECT P13)`; integrity 63/63 — see CHANGELOG A8).

In every test command below, `<T>` stands for `HOME=<fresh> Rscript -e` and each test run is written `testthat::test_file("tests/testthat/<file>", reporter = "summary", stop_on_failure = TRUE)`. GREEN means: no `══ Failed` section in the output and exit status 0. RED means the failure shown in the step.

---

## Task 1: the HTTP layer and the test seam (*haiku*)

**Files:** create `R/odds/http.R`, `tests/testthat/helper-odds.R`, `tests/testthat/test-odds-http.R`; edit `tests/testthat/setup.R`.

**Interface:** `odds_http_config(env, overrides)`; `odds_fetch(url, cfg, fetch_fn, log_path, source, now_fn, sleep_fn)` returns `list(url, source, status, body, error, sha256, bytes, fetched_at, tries, blocked)`; `odds_http_get(url, cfg)` is the only real network call and refuses under `NFL_ODDS_FORBID_LIVE=1`; `odds_json(rec)`; `odds_http_reset()`; test helpers `odds_fake_fetch(routes)`, `odds_fake_clock()`.

- [ ] **Step 1: loader and helpers.** Apply this edit to `tests/testthat/setup.R` (save it as a file and run `git apply --whitespace=nowarn <file>`, or make the same edit with the file tools):

````diff
diff --git a/tests/testthat/setup.R b/tests/testthat/setup.R
index dafdc79..aac6a34 100644
--- a/tests/testthat/setup.R
+++ b/tests/testthat/setup.R
@@ -73,6 +73,10 @@ LOAD_FIRST <- c("logging", "utils", "capture_raw", "data_validation", "playoffs"
 all_modules <- sub("\\.R$", "", list.files(file.path(PROJECT_ROOT, "R"), pattern = "\\.R$"))
 for (m in c(LOAD_FIRST, setdiff(sort(all_modules), LOAD_FIRST))) source_module(m)
 
+# R/odds/*.R, the keyless odds layer (roadmap D1): list.files() above is not recursive
+odds_modules <- sub("\\.R$", "", list.files(file.path(PROJECT_ROOT, "R", "odds"), pattern = "\\.R$"))
+for (m in file.path("odds", sort(odds_modules))) source_module(m)
+
 # Load player props configuration (v2.9.0)
 props_config_path <- file.path(PROJECT_ROOT, "sports", "nfl", "props", "props_config.R")
 if (!file.exists(props_config_path)) {
````

  Create `tests/testthat/helper-odds.R`:

````r
# =============================================================================
# Odds-layer test helpers (roadmap D1)
# =============================================================================
# The default suite never touches the network for odds: this sets the guard that
# makes odds_http_get() refuse to run, and offers a fake fetch function that
# serves recorded JSON fixtures from tests/testthat/fixtures/odds/. Live checks
# live in tests/live/ and run only through scripts/odds_live_smoke.R.
# =============================================================================

Sys.setenv(NFL_ODDS_FORBID_LIVE = "1")

odds_fixture_path <- function(...) testthat::test_path("fixtures", "odds", ...)

odds_fixture_raw <- function(name) {
  path <- odds_fixture_path(name)
  readBin(path, "raw", n = file.size(path))
}

odds_fixture_json <- function(name) {
  jsonlite::fromJSON(rawToChar(odds_fixture_raw(name)), simplifyVector = FALSE)
}

#' A fetch function for odds_fetch()/the providers that serves fixtures by URL.
#' `routes` maps a full URL to a fixture file name, or to list(status =, file =,
#' text =, retry_after =); `text` serves an inline body. An unknown URL is an error,
#' so a test can never reach out by accident.
#' @return list(fn = fetch function, state = environment with `urls`, the URLs requested)
odds_fake_fetch <- function(routes) {
  state <- new.env()
  state$urls <- character()
  fn <- function(url, cfg) {
    state$urls <- c(state$urls, url)
    hit <- routes[[url]]
    if (is.null(hit)) stop("odds_fake_fetch: no fixture route for ", url, call. = FALSE)
    if (is.character(hit)) hit <- list(status = 200L, file = hit)
    body <- if (!is.null(hit$file)) odds_fixture_raw(hit$file) else if (!is.null(hit$text)) charToRaw(hit$text) else NULL
    list(status = as.integer(hit$status %||% 200L), body = body,
         error = if ((hit$status %||% 200L) >= 400) sprintf("HTTP %d", hit$status) else NA_character_,
         retry_after = hit$retry_after %||% NA_real_)
  }
  list(fn = fn, state = state)
}

#' A deterministic clock: now() and a sleep() that advances it and records each wait
odds_fake_clock <- function(start = 1e9) {
  state <- new.env()
  state$t <- start
  state$sleeps <- numeric()
  list(
    now = function() as.POSIXct(state$t, origin = "1970-01-01", tz = "UTC"),
    sleep = function(s) {
      state$sleeps <- c(state$sleeps, s)
      state$t <- state$t + s
    },
    state = state
  )
}
````

- [ ] **Step 2: write the test.** Create `tests/testthat/test-odds-http.R`:

````r
# =============================================================================
# Tests: keyless odds HTTP layer (R/odds/http.R)
# No test here touches the network: every fetch goes through a fake fetch function.
# =============================================================================

local_odds_state <- function(env = parent.frame()) {
  odds_http_reset()
  withr::defer(odds_http_reset(), envir = env)
}

# A fetch function that returns the queued responses in order and counts calls
queued_fetch <- function(...) {
  queue <- list(...)
  state <- new.env()
  state$calls <- 0L
  fn <- function(url, cfg) {
    state$calls <- state$calls + 1L
    r <- queue[[min(state$calls, length(queue))]]
    list(status = r$status, body = r$body, error = r$error %||% NA_character_,
         retry_after = r$retry_after %||% NA_real_)
  }
  list(fn = fn, state = state)
}
ok_body <- function(txt = '{"ok":true}') list(status = 200L, body = charToRaw(txt))

test_that("the request settings enforce the owner rules", {
  cfg <- odds_http_config(overrides = list(min_interval_sec = 0.25))
  expect_equal(cfg$min_interval_sec, 1)                   # a faster config is raised to 1 request/second
  expect_equal(cfg$timeout_sec, 20)
  expect_match(cfg$user_agent, "nfl", ignore.case = TRUE)  # truthful: names this project
  expect_match(cfg$user_agent, "research")
  expect_gte(odds_http_config(overrides = list(max_tries = 0))$max_tries, 1L)
})

test_that("requests to one domain are spaced at least one second apart; other domains are independent", {
  local_odds_state()
  clock <- odds_fake_clock()
  f <- queued_fetch(ok_body())
  cfg <- odds_http_config()
  for (u in c("https://sports.core.api.espn.com/a", "https://site.api.espn.com/b", "https://sports.core.api.espn.com/c")) {
    odds_fetch(u, cfg, fetch_fn = f$fn, now_fn = clock$now, sleep_fn = clock$sleep)
  }
  expect_equal(clock$state$sleeps, c(1, 1))                # espn.com hosts share one budget
  odds_fetch("https://api.elections.kalshi.com/x", cfg, fetch_fn = f$fn, now_fn = clock$now, sleep_fn = clock$sleep)
  expect_equal(clock$state$sleeps, c(1, 1))                # kalshi.com has its own
})

test_that("a 429 is retried with backoff and then succeeds", {
  local_odds_state()
  clock <- odds_fake_clock()
  f <- queued_fetch(list(status = 429L), list(status = 503L), ok_body())
  rec <- odds_fetch("https://example.test/x", odds_http_config(), fetch_fn = f$fn,
                    now_fn = clock$now, sleep_fn = clock$sleep)
  expect_equal(rec$status, 200L)
  expect_equal(rec$tries, 3L)
  expect_equal(f$state$calls, 3L)
  expect_false(rec$blocked)
  expect_true(all(clock$state$sleeps >= 1))
  expect_true(2 %in% clock$state$sleeps && 4 %in% clock$state$sleeps)   # exponential backoff 2 s, 4 s
})

test_that("Retry-After is honoured and capped", {
  expect_equal(odds_backoff_sec(1, retry_after = 7), 7)
  expect_equal(odds_backoff_sec(1, retry_after = 9999), ODDS_BACKOFF_CAP_SEC)
  expect_equal(odds_backoff_sec(3), 8)
  expect_equal(odds_backoff_sec(20), ODDS_BACKOFF_CAP_SEC)
})

test_that("a network error (no status) is retried, then reported, never guessed", {
  local_odds_state()
  clock <- odds_fake_clock()
  f <- queued_fetch(list(status = NA_integer_, error = "timeout"))
  rec <- odds_fetch("https://example.test/x", odds_http_config(), fetch_fn = f$fn,
                    now_fn = clock$now, sleep_fn = clock$sleep)
  expect_true(is.na(rec$status))
  expect_equal(f$state$calls, 3L)
  expect_equal(rec$error, "timeout")
  expect_null(rec$body)
})

test_that("a 403 is never retried and blocks the domain for the session", {
  local_odds_state()
  clock <- odds_fake_clock()
  f <- queued_fetch(list(status = 403L))
  cfg <- odds_http_config()
  rec <- odds_fetch("https://sports.core.api.espn.com/a", cfg, fetch_fn = f$fn, now_fn = clock$now, sleep_fn = clock$sleep)
  expect_equal(rec$status, 403L)
  expect_true(rec$blocked)
  expect_equal(f$state$calls, 1L)                          # no retry, no workaround
  again <- odds_fetch("https://site.api.espn.com/b", cfg, fetch_fn = f$fn, now_fn = clock$now, sleep_fn = clock$sleep)
  expect_equal(f$state$calls, 1L)                          # the breaker: no second request to espn.com
  expect_true(again$blocked)
  expect_match(again$error, "blocked")
  expect_equal(again$tries, 0L)
})

test_that("a 429 that survives every retry blocks the domain", {
  local_odds_state()
  clock <- odds_fake_clock()
  f <- queued_fetch(list(status = 429L, retry_after = 3))
  cfg <- odds_http_config()
  rec <- odds_fetch("https://example.test/x", cfg, fetch_fn = f$fn, now_fn = clock$now, sleep_fn = clock$sleep)
  expect_equal(f$state$calls, cfg$max_tries)
  expect_true(rec$blocked)
  expect_true(3 %in% clock$state$sleeps)                   # waited the server's Retry-After
  odds_fetch("https://example.test/y", cfg, fetch_fn = f$fn, now_fn = clock$now, sleep_fn = clock$sleep)
  expect_equal(f$state$calls, cfg$max_tries)               # nothing more was sent
})

test_that("the raw sha256 is returned and appended to the fetch log, with credentials redacted", {
  local_odds_state()
  clock <- odds_fake_clock()
  log_path <- file.path(withr::local_tempdir(), "logs", "fetch_log.ndjson")
  body <- charToRaw('{"hello":"world"}')
  f <- queued_fetch(list(status = 200L, body = body))
  rec <- odds_fetch("https://example.test/x?apikey=SECRET&page=2", odds_http_config(), fetch_fn = f$fn,
                    log_path = log_path, source = "unit", now_fn = clock$now, sleep_fn = clock$sleep)
  expect_equal(rec$sha256, digest::digest(body, algo = "sha256", serialize = FALSE))
  expect_equal(rec$bytes, length(body))
  line <- jsonlite::fromJSON(readLines(log_path))
  expect_equal(line$raw_sha256, rec$sha256)
  expect_equal(line$http_status, 200L)
  expect_equal(line$source, "unit")
  expect_equal(line$endpoint_redacted, "https://example.test/x?apikey=REDACTED&page=2")
  expect_false(grepl("SECRET", readLines(log_path)))
  # a failed fetch is logged too, with a null hash
  f2 <- queued_fetch(list(status = 404L))
  odds_fetch("https://example.test/gone", odds_http_config(), fetch_fn = f2$fn, log_path = log_path,
             source = "unit", now_fn = clock$now, sleep_fn = clock$sleep)
  lines <- readLines(log_path)
  expect_length(lines, 2)
  expect_true(is.null(jsonlite::fromJSON(lines[[2]])$raw_sha256))
})

test_that("odds_json returns NULL for a missing or malformed body", {
  expect_null(odds_json(list(body = NULL)))
  expect_null(odds_json(list(body = charToRaw("<html>not json"))))
  expect_equal(odds_json(list(body = charToRaw('{"a":1}')))$a, 1)
})

test_that("the real network call refuses to run inside the default suite", {
  expect_identical(Sys.getenv("NFL_ODDS_FORBID_LIVE"), "1")
  expect_error(odds_http_get("https://example.test/", odds_http_config()), "forbidden")
})

test_that("the realm of a URL is its registrable domain", {
  expect_equal(odds_url_realm("https://sports.core.api.espn.com/v2/x?y=1"), "espn.com")
  expect_equal(odds_url_realm("https://api.elections.kalshi.com/trade-api/v2"), "kalshi.com")
  expect_equal(odds_url_realm("https://example.test/x"), "example.test")
})
````

- [ ] **Step 3: RED.** `<T> 'testthat::test_file("tests/testthat/test-odds-http.R", reporter = "summary")'`. Expected (measured in the dry run with `R/odds/http.R` absent):

```
── 1. Error ('test-odds-http.R:27:3'): the request settings enforce the owner ru
Error in `odds_http_config(overrides = list(min_interval_sec = 0.25))`: could not find function "odds_http_config"
── 2. Error ('test-odds-http.R:36:3'): requests to one domain are spaced at leas
Error in `odds_http_reset()`: could not find function "odds_http_reset"
```

- [ ] **Step 4: implement.** Create `R/odds/http.R`:

````r
# =============================================================================
# Keyless odds HTTP layer (roadmap D1)
# =============================================================================
# The one place the odds providers touch the network. Policy (owner rules):
#   - a truthful user agent, a 20 s timeout, at most 1 request per second per
#     registrable domain (a hard floor: a config value below 1 s is raised to 1 s)
#   - bounded retry with backoff on HTTP 429/5xx and on network errors
#   - a 401/403, or a 429 that survives the retries, is never worked around: the
#     result is flagged `blocked`, and later calls to that domain make no request
#   - every response's raw sha256 is returned, and appended to a fetch log when
#     `log_path` is given (the columns follow the source_fetches table)
#
# The network call itself is `fetch_fn(url, cfg)`, an injectable seam. Tests pass
# a fake that reads recorded JSON fixtures, so the default suite makes no request.
# `odds_http_get` is the only real implementation; it refuses to run when
# NFL_ODDS_FORBID_LIVE=1, which tests/testthat/helper-odds.R sets.
# =============================================================================

ODDS_MIN_INTERVAL_SEC <- 1       # hard floor between requests to one domain
ODDS_DEFAULT_TIMEOUT_SEC <- 20
ODDS_DEFAULT_MAX_TRIES <- 3L
ODDS_RETRY_STATUS <- c(429L, 500L, 502L, 503L, 504L)
ODDS_BLOCKED_STATUS <- c(401L, 403L, 429L)
ODDS_BACKOFF_CAP_SEC <- 60
ODDS_DEFAULT_USER_AGENT <- "nfl-weekly-simulation (research; https://github.com/jviola1019/nfl_weekly_simulation)"

# Per-process state: the last request time and the blocked flag, by domain
.odds_http_state <- new.env(parent = emptyenv())

#' Forget throttle times and blocked domains (tests, and long-lived sessions)
odds_http_reset <- function() {
  rm(list = ls(.odds_http_state, all.names = TRUE), envir = .odds_http_state)
  invisible(NULL)
}

#' Request settings. Reads the CAPTURE_* constants from `env` (config.R), applies
#' `overrides`, and enforces the 1 request/second floor.
odds_http_config <- function(env = globalenv(), overrides = list()) {
  pick <- function(name, default) {
    if (exists(name, envir = env, inherits = FALSE)) get(name, envir = env, inherits = FALSE) else default
  }
  cfg <- list(
    user_agent = pick("CAPTURE_USER_AGENT", ODDS_DEFAULT_USER_AGENT),
    timeout_sec = pick("CAPTURE_TIMEOUT_SEC", ODDS_DEFAULT_TIMEOUT_SEC),
    max_tries = pick("CAPTURE_MAX_TRIES", ODDS_DEFAULT_MAX_TRIES),
    min_interval_sec = pick("CAPTURE_MIN_INTERVAL_SEC", ODDS_MIN_INTERVAL_SEC)
  )
  cfg[names(overrides)] <- overrides
  cfg$min_interval_sec <- max(cfg$min_interval_sec, ODDS_MIN_INTERVAL_SEC)
  cfg$max_tries <- max(1L, as.integer(cfg$max_tries))
  cfg
}

#' Registrable domain of a URL ("sports.core.api.espn.com" -> "espn.com"), the
#' throttle key, so two ESPN hosts share one budget
odds_url_realm <- function(url) {
  host <- sub("^[a-z]+://([^/:?#]+).*$", "\\1", tolower(url))
  parts <- strsplit(host, ".", fixed = TRUE)[[1]]
  if (length(parts) <= 2) host else paste(utils::tail(parts, 2), collapse = ".")
}

#' Blank the value of any credential-looking query parameter before a URL is logged
odds_redact_url <- function(url) {
  gsub("([?&](?:key|apikey|api_key|token|auth|access_token)=)[^&]*", "\\1REDACTED", url,
       ignore.case = TRUE, perl = TRUE)
}

odds_iso <- function(x) format(as.POSIXct(x, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

#' Wait until `min_interval_sec` has passed since the last request to this domain
odds_throttle <- function(url, min_interval_sec, now_fn = Sys.time, sleep_fn = Sys.sleep) {
  realm <- odds_url_realm(url)
  key <- paste0("last:", realm)
  now <- as.numeric(now_fn())
  last <- if (exists(key, envir = .odds_http_state, inherits = FALSE)) get(key, envir = .odds_http_state) else NULL
  if (!is.null(last)) {
    wait <- last + min_interval_sec - now
    if (wait > 0) {
      sleep_fn(wait)
      now <- now + wait
    }
  }
  assign(key, now, envir = .odds_http_state)
  invisible(now)
}

#' Seconds to wait after attempt `attempt` failed: the server's Retry-After when
#' it sent one, otherwise 2, 4, 8 ... seconds, never more than ODDS_BACKOFF_CAP_SEC
odds_backoff_sec <- function(attempt, retry_after = NA_real_) {
  if (!is.null(retry_after) && !is.na(retry_after) && retry_after >= 0) {
    return(min(retry_after, ODDS_BACKOFF_CAP_SEC))
  }
  min(2^attempt, ODDS_BACKOFF_CAP_SEC)
}

#' The real network call: one GET, no retry, no throttle (odds_fetch adds both).
#' @return list(status, body [raw or NULL], error, retry_after)
odds_http_get <- function(url, cfg) {
  if (identical(Sys.getenv("NFL_ODDS_FORBID_LIVE"), "1")) {
    stop("odds_http_get: live HTTP is forbidden while NFL_ODDS_FORBID_LIVE=1 (url: ", url, ")", call. = FALSE)
  }
  req <- httr2::request(url) |>
    httr2::req_user_agent(cfg$user_agent) |>
    httr2::req_timeout(cfg$timeout_sec) |>
    httr2::req_error(is_error = function(resp) FALSE)
  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  if (inherits(resp, "error")) {
    return(list(status = NA_integer_, body = NULL, error = conditionMessage(resp), retry_after = NA_real_))
  }
  status <- httr2::resp_status(resp)
  retry_after <- suppressWarnings(as.numeric(httr2::resp_header(resp, "Retry-After", default = NA_character_)))
  list(
    status = status,
    body = if (status < 400) httr2::resp_body_raw(resp) else NULL,
    error = if (status >= 400) sprintf("HTTP %d", status) else NA_character_,
    retry_after = retry_after
  )
}

#' Append one fetch-log line (NDJSON; the columns follow the source_fetches table)
odds_log_fetch <- function(path, rec) {
  entry <- list(
    source = rec$source, endpoint_redacted = odds_redact_url(rec$url),
    http_status = rec$status, fetched_at = odds_iso(rec$fetched_at),
    raw_sha256 = rec$sha256, bytes = rec$bytes, tries = rec$tries,
    blocked = rec$blocked, error = rec$error
  )
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  cat(jsonlite::toJSON(entry, auto_unbox = TRUE, na = "null"), "\n", file = path, append = TRUE, sep = "")
  invisible(path)
}

#' GET with throttle, bounded retry and backoff, a blocked-domain breaker, the raw
#' sha256 and an optional fetch log.
#' @param fetch_fn function(url, cfg) -> list(status, body, error, retry_after)
#' @return list(url, source, status, body, error, sha256, bytes, fetched_at, tries, blocked)
odds_fetch <- function(url, cfg = odds_http_config(), fetch_fn = odds_http_get, log_path = NULL,
                       source = NA_character_, now_fn = Sys.time, sleep_fn = Sys.sleep) {
  stopifnot(is.character(url), length(url) == 1L, !is.na(url))
  min_interval <- max(cfg$min_interval_sec %||% ODDS_MIN_INTERVAL_SEC, ODDS_MIN_INTERVAL_SEC)
  max_tries <- max(1L, as.integer(cfg$max_tries %||% ODDS_DEFAULT_MAX_TRIES))
  realm <- odds_url_realm(url)
  blocked_key <- paste0("blocked:", realm)

  if (exists(blocked_key, envir = .odds_http_state, inherits = FALSE)) {
    res <- list(status = get(blocked_key, envir = .odds_http_state), body = NULL,
                error = sprintf("blocked: %s refused an earlier request (HTTP %s); no further requests this session",
                                realm, get(blocked_key, envir = .odds_http_state)),
                retry_after = NA_real_)
    attempts <- 0L
  } else {
    res <- NULL
    attempts <- 0L
    for (attempt in seq_len(max_tries)) {
      attempts <- attempt
      odds_throttle(url, min_interval, now_fn, sleep_fn)
      res <- fetch_fn(url, cfg)
      status <- res$status %||% NA_integer_
      transient <- is.na(status) || status %in% ODDS_RETRY_STATUS
      if (!transient || attempt == max_tries) break
      sleep_fn(odds_backoff_sec(attempt, res$retry_after %||% NA_real_))
    }
    final <- res$status %||% NA_integer_
    if (!is.na(final) && final %in% ODDS_BLOCKED_STATUS) {
      assign(blocked_key, as.integer(final), envir = .odds_http_state)
    }
  }

  body <- res$body
  status <- res$status %||% NA_integer_
  rec <- list(
    url = url, source = source, status = as.integer(status), body = body,
    error = res$error %||% NA_character_,
    sha256 = if (is.null(body)) NA_character_ else digest::digest(body, algo = "sha256", serialize = FALSE),
    bytes = if (is.null(body)) 0L else length(body),
    fetched_at = as.POSIXct(now_fn(), tz = "UTC"), tries = attempts,
    blocked = !is.na(status) && status %in% ODDS_BLOCKED_STATUS
  )
  if (!is.null(log_path)) odds_log_fetch(log_path, rec)
  rec
}

#' Parse a fetch result's body as JSON. Returns NULL (and the caller records why)
#' when there is no body or it is not JSON; it never returns a guess.
odds_json <- function(rec) {
  if (is.null(rec$body)) return(NULL)
  tryCatch(jsonlite::fromJSON(rawToChar(rec$body), simplifyVector = FALSE), error = function(e) NULL)
}
````

- [ ] **Step 5: GREEN.** Same command with `stop_on_failure = TRUE`: no failures, exit 0.
- [ ] **Step 6: commit.**

```bash
git add R/odds/http.R tests/testthat/helper-odds.R tests/testthat/test-odds-http.R tests/testthat/setup.R
git commit -m "feat(odds): keyless HTTP layer with 1 req/s floor, backoff, block breaker and raw sha256 (D1)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 2: the `odds_snapshots` shape and vocabulary (*haiku*)

**Files:** create `R/odds/snapshots.R`, `tests/testthat/test-odds-snapshots.R`.

**Interface:** `ODDS_SNAPSHOT_COLUMNS`, `odds_markets_catalog()`, `odds_venues_catalog()`, `american_to_int()`, `odds_snapshots_empty()`, `complete_odds_snapshots()`, `validate_odds_snapshots()`, `new_odds_snapshots()`, `bind_odds_snapshots()`. The shape is the Drizzle `odds_snapshots` table; the catalogs satisfy `contracts/schema/markets.schema.json` and `venues.schema.json` (the test runs `bw_validate_rows` on them).

- [ ] **Step 1: write the test.** Create `tests/testthat/test-odds-snapshots.R`:

````r
# =============================================================================
# Tests: the odds_snapshots shape (R/odds/snapshots.R)
# =============================================================================

snap_row <- function(...) {
  base <- data.frame(
    game_id = "2024_01_ARI_BUF", market_id = "moneyline", venue_id = "espn_bet", side = "home",
    price_american = -275L, snapshot_kind = "open", source = "espn_core", raw_sha256 = "abc",
    player_key = NA_character_, captured_at = as.POSIXct(NA, tz = "UTC"), bid = NA_real_, ask = NA_real_,
    stringsAsFactors = FALSE
  )
  over <- list(...)
  for (nm in names(over)) base[[nm]] <- over[[nm]]
  base
}

test_that("the shape is the Drizzle odds_snapshots table plus lineage columns", {
  # web/src/db/schema.ts oddsSnapshots: game_id, market_id, venue_id, player_id, side, line,
  # price_american, bid, ask, last, volume, captured_at (fetch_id is assigned at ingest).
  # player_id is carried as the unresolved player_key until the alias tables exist.
  schema_ts <- readLines(file.path(PROJECT_ROOT, "web", "src", "db", "schema.ts"), warn = FALSE)
  start <- grep('export const oddsSnapshots', schema_ts)
  end <- start + which(grepl("^  \\},?$", schema_ts[-seq_len(start)]))[1]
  block <- paste(schema_ts[start:end], collapse = "\n")
  db_cols <- regmatches(block, gregexpr('"[a-z_]+"\\)', block))[[1]]
  db_cols <- gsub('[")]', "", db_cols)
  expect_true(all(setdiff(db_cols, c("snapshot_id", "fetch_id", "player_id")) %in% ODDS_SNAPSHOT_COLUMNS))
  expect_true(all(c("player_key", "snapshot_kind", "source", "raw_sha256") %in% ODDS_SNAPSHOT_COLUMNS))
})

test_that("the market and venue catalogs satisfy the contract schemas", {
  contracts <- file.path(PROJECT_ROOT, "contracts", "schema")
  expect_equal(bw_validate_rows(odds_markets_catalog(), bw_read_schema("markets", contracts), "markets"), character())
  expect_equal(bw_validate_rows(odds_venues_catalog(), bw_read_schema("venues", contracts), "venues"), character())
  expect_true(all(c("moneyline", "spread", "total", "anytime_td", "first_td", "td_2plus",
                    "passing_yards", "rushing_yards", "receiving_yards", "receptions") %in% odds_markets_catalog()$market_id))
  expect_true(all(c("nflverse_consensus", "espn_bet", "draftkings", "kalshi") %in% odds_venues_catalog()$venue_id))
})

test_that("american_to_int parses signed strings and rejects non-prices without warning", {
  expect_warning(out <- american_to_int(c("+225", "-275", "EVEN", "", NA, "OFF", "-110.0", 150)), NA)
  expect_identical(out, c(225L, -275L, 100L, NA, NA, NA, -110L, 150L))
  expect_identical(american_to_int(-0.5), NA_integer_)   # between -100 and +100 is not an American price
})

test_that("new_odds_snapshots completes missing columns with typed NAs and orders them", {
  s <- new_odds_snapshots(snap_row())
  expect_identical(names(s), ODDS_SNAPSHOT_COLUMNS)
  expect_true(is.integer(s$price_american))
  expect_true(is.numeric(s$line) && is.na(s$line))
  expect_s3_class(s$captured_at, "POSIXct")
  expect_equal(attr(s$captured_at, "tzone"), "UTC")
  expect_equal(nrow(odds_snapshots_empty()), 0)
  expect_identical(names(odds_snapshots_empty()), ODDS_SNAPSHOT_COLUMNS)
})

test_that("validation names every problem, and the constructor refuses invalid rows", {
  bad <- rbind(
    snap_row(market_id = "made_up"),
    snap_row(venue_id = "nowhere"),
    snap_row(side = "sideways"),
    snap_row(snapshot_kind = "observed"),                       # timed kinds need captured_at
    snap_row(price_american = -50L),                            # |price| must be >= 100
    snap_row(market_id = "anytime_td", venue_id = "kalshi", side = "yes", snapshot_kind = "candle",
             captured_at = as.POSIXct("2026-10-01 12:00", tz = "UTC"), bid = 0.6, ask = 0.5),   # crossed, and no player_key
    snap_row(market_id = "moneyline", player_key = "kalshi:x")  # game markets carry no player
  )
  problems <- validate_odds_snapshots(complete_odds_snapshots(bad))
  expect_true(any(grepl("market_id", problems)))
  expect_true(any(grepl("venue_id", problems)))
  expect_true(any(grepl("side", problems)))
  expect_true(any(grepl("captured_at", problems)))
  expect_true(any(grepl("price_american", problems)))
  expect_true(any(grepl("bid > ask", problems)))
  expect_true(any(grepl("player_key", problems)))
  expect_error(new_odds_snapshots(bad), "invalid odds_snapshots")
  expect_error(new_odds_snapshots(snap_row(surprise = 1)), "unknown column")
  expect_equal(validate_odds_snapshots(new_odds_snapshots(snap_row())), character())
})

test_that("bind_odds_snapshots stacks results and skips empty ones", {
  a <- new_odds_snapshots(snap_row())
  b <- new_odds_snapshots(snap_row(side = "away", price_american = 225L))
  all <- bind_odds_snapshots(list(a, odds_snapshots_empty(), b, NULL))
  expect_equal(nrow(all), 2)
  expect_equal(nrow(bind_odds_snapshots(list())), 0)
})
````

- [ ] **Step 2: RED.** Expected failures with `R/odds/snapshots.R` absent:

```
── 1. Error ('test-odds-snapshots.R:27:3'): the shape is the Drizzle odds_snapsh
Error in `eval(code, test_env)`: object 'ODDS_SNAPSHOT_COLUMNS' not found
── 2. Error ('test-odds-snapshots.R:33:3'): the market and venue catalogs satisf
Error in `odds_markets_catalog()`: could not find function "odds_markets_catalog"
```

- [ ] **Step 3: implement.** Create `R/odds/snapshots.R`:

````r
# =============================================================================
# The odds_snapshots shape, and the market / venue vocabulary (roadmap D1)
# =============================================================================
# Every provider returns rows in this shape. It is the Drizzle `odds_snapshots`
# table (web/src/db/schema.ts) with three differences, all resolved at ingest:
#   - `fetch_id` is replaced by `source` + `raw_sha256` (the fetch lineage; the
#     ingest maps them to a source_fetches row)
#   - `player_id` is carried as `player_key`, an unresolved external key such as
#     "kalshi:<uuid>" or "espn:<athleteId>" (alias tables are P1/P3 work)
#   - `snapshot_kind` says how to read `captured_at`:
#       open     the venue's labelled opening line; its time is unknown, so captured_at is NA
#       close    the venue's labelled closing line; captured_at is NA
#       observed a line seen at captured_at (forward capture)
#       candle   the end of a Kalshi candle
#     Only observed and candle rows have a time, so only they can be tested for
#     "before kickoff" (R/odds/closing.R).
# `side` is home/away (moneyline, spread), over/under (total), yes/no (binary
# prop and exchange contracts), or `line` for a line-only observation with no
# price. For the spread, `line` is the side's own handicap (home -6.5, away +6.5).
# Kalshi bid, ask and last are dollars in [0, 1]; American prices are integers.
# =============================================================================

ODDS_SNAPSHOT_COLUMNS <- c(
  "game_id", "market_id", "venue_id", "player_key", "side", "line", "price_american",
  "bid", "ask", "last", "volume", "captured_at", "snapshot_kind", "source", "raw_sha256"
)
ODDS_SIDES <- c("home", "away", "over", "under", "yes", "no", "line")
ODDS_SNAPSHOT_KINDS <- c("open", "close", "observed", "candle")
ODDS_TIMED_KINDS <- c("observed", "candle")

#' The markets D1 knows, in the shape of contracts/schema/markets.schema.json
odds_markets_catalog <- function() {
  data.frame(
    market_id = c("moneyline", "spread", "total", "anytime_td", "first_td", "td_2plus",
                  "passing_yards", "rushing_yards", "receiving_yards", "receptions"),
    scope = c(rep("game", 3), rep("player", 7)),
    outcome_kind = c("yes_no", "line", "line", "yes_no", "yes_no", "yes_no", "line", "line", "line", "line"),
    grading_rule = c(
      "team scores more points than its opponent, overtime included; a tie voids",
      "side score plus handicap beats the opponent score; a push voids",
      "total points over or under the line; a push voids",
      "player scores at least 1 rushing or receiving touchdown",
      "player scores the first touchdown of the game",
      "player scores at least 2 rushing or receiving touchdowns",
      "player passing yards over or under the line, overtime included",
      "player rushing yards over or under the line, overtime included",
      "player receiving yards over or under the line, overtime included",
      "player receptions over or under the line, overtime included"
    ),
    stringsAsFactors = FALSE
  )
}

#' The venues D1 knows, in the shape of contracts/schema/venues.schema.json
odds_venues_catalog <- function() {
  data.frame(
    venue_id = c("nflverse_consensus", "espn_bet", "draftkings", "kalshi"),
    display_name = c("nflverse consensus close", "ESPN BET", "DraftKings", "Kalshi"),
    kind = c("consensus", "sportsbook", "sportsbook", "exchange"),
    stringsAsFactors = FALSE
  )
}

#' Parse American prices ("+225", "-275", "EVEN", 150) to integers. Anything that
#' is not a price (empty, OFF, between -100 and +100, fractional) is NA.
american_to_int <- function(x) {
  txt <- toupper(trimws(as.character(x)))
  txt[!is.na(txt) & txt %in% c("EVEN", "EV", "PK")] <- "100"
  num <- suppressWarnings(as.numeric(sub("^\\+", "", txt)))
  ok <- !is.na(num) & abs(num) >= 100 & abs(num - round(num)) < 1e-9
  out <- rep(NA_integer_, length(num))
  out[ok] <- as.integer(round(num[ok]))
  out
}

odds_snapshots_empty <- function() {
  data.frame(
    game_id = character(), market_id = character(), venue_id = character(), player_key = character(),
    side = character(), line = numeric(), price_american = integer(), bid = numeric(), ask = numeric(),
    last = numeric(), volume = numeric(), captured_at = as.POSIXct(character(), tz = "UTC"),
    snapshot_kind = character(), source = character(), raw_sha256 = character(),
    stringsAsFactors = FALSE
  )
}

#' Problems with a snapshot table, as character strings; empty means valid
validate_odds_snapshots <- function(df) {
  fails <- character()
  missing_cols <- setdiff(ODDS_SNAPSHOT_COLUMNS, names(df))
  if (length(missing_cols)) {
    return(sprintf("odds_snapshots: missing column(s) %s", paste(missing_cols, collapse = ", ")))
  }
  flag <- function(what, bad) {
    if (any(bad, na.rm = TRUE)) {
      fails <<- c(fails, sprintf("%s (rows %s)", what, paste(utils::head(which(bad), 10), collapse = ", ")))
    }
  }
  markets <- odds_markets_catalog()
  venues <- odds_venues_catalog()
  for (col in c("game_id", "market_id", "venue_id", "side", "snapshot_kind", "source")) {
    flag(sprintf("%s: required, found NA or empty", col), is.na(df[[col]]) | !nzchar(df[[col]]))
  }
  flag("market_id: not in odds_markets_catalog()", !is.na(df$market_id) & !df$market_id %in% markets$market_id)
  flag("venue_id: not in odds_venues_catalog()", !is.na(df$venue_id) & !df$venue_id %in% venues$venue_id)
  flag("side: not one of home/away/over/under/yes/no/line", !is.na(df$side) & !df$side %in% ODDS_SIDES)
  flag("snapshot_kind: not one of open/close/observed/candle", !is.na(df$snapshot_kind) & !df$snapshot_kind %in% ODDS_SNAPSHOT_KINDS)
  flag("captured_at: timed kinds (observed, candle) need a time",
       df$snapshot_kind %in% ODDS_TIMED_KINDS & is.na(df$captured_at))
  flag("price_american: must be an integer with |price| >= 100",
       !is.na(df$price_american) & abs(df$price_american) < 100)
  flag("bid > ask", !is.na(df$bid) & !is.na(df$ask) & df$bid > df$ask)
  exchange <- df$venue_id %in% venues$venue_id[venues$kind == "exchange"]
  flag("bid/ask/last: exchange quotes are dollars in [0, 1]",
       exchange & (((!is.na(df$bid)) & (df$bid < 0 | df$bid > 1)) | ((!is.na(df$ask)) & (df$ask < 0 | df$ask > 1)) |
                     ((!is.na(df$last)) & (df$last < 0 | df$last > 1))))
  scope <- markets$scope[match(df$market_id, markets$market_id)]
  flag("player_key: player markets need one", scope %in% "player" & (is.na(df$player_key) | !nzchar(df$player_key)))
  flag("player_key: game markets must not carry one", scope %in% "game" & !is.na(df$player_key))
  fails
}

#' Complete a snapshot table without validating it: missing columns become typed
#' NAs, the types are coerced and the column order is fixed. Unknown columns stop.
complete_odds_snapshots <- function(df) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  extra <- setdiff(names(df), ODDS_SNAPSHOT_COLUMNS)
  if (length(extra)) stop("new_odds_snapshots: unknown column(s) ", paste(extra, collapse = ", "), call. = FALSE)
  template <- odds_snapshots_empty()
  n <- nrow(df)
  out <- template[rep(NA_integer_, n), , drop = FALSE]
  rownames(out) <- NULL
  for (col in ODDS_SNAPSHOT_COLUMNS) {
    if (col %in% names(df)) {
      out[[col]] <- switch(
        col,
        price_american = as.integer(df[[col]]),
        captured_at = as.POSIXct(df[[col]], tz = "UTC"),
        line = , bid = , ask = , last = , volume = as.numeric(df[[col]]),
        as.character(df[[col]])
      )
    }
  }
  attr(out$captured_at, "tzone") <- "UTC"
  out
}

#' Build a validated snapshot table from the columns a provider has; an invalid
#' table stops, it is never repaired.
new_odds_snapshots <- function(df) {
  out <- complete_odds_snapshots(df)
  problems <- validate_odds_snapshots(out)
  if (length(problems)) {
    stop("new_odds_snapshots: invalid odds_snapshots:\n  ", paste(problems, collapse = "\n  "), call. = FALSE)
  }
  out
}

#' Stack snapshot tables; NULL and zero-row entries are skipped
bind_odds_snapshots <- function(parts) {
  parts <- Filter(function(p) !is.null(p) && nrow(p) > 0, parts)
  if (length(parts) == 0) return(odds_snapshots_empty())
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out
}
````

- [ ] **Step 4: GREEN.** Run the test file: no failures, exit 0.
- [ ] **Step 5: commit.**

```bash
git add R/odds/snapshots.R tests/testthat/test-odds-snapshots.R
git commit -m "feat(odds): odds_snapshots shape, market and venue catalogs, validation (D1)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 3: the closing rule (*haiku*)

**Files:** create `R/odds/closing.R`, `tests/testthat/test-odds-closing.R`.

**Interface:** `select_closing_snapshots(snaps, kickoffs, stale_after_min = 60)` returns one row per (game, market, venue, player, side, **line**) with `close_gap_min`, `stale`, `headline_eligible`, `timing`, `rule_version = "close-v1"` and `attr(, "audit")`; `match_close_at_line(closes, game_id, market_id, venue_id, side, line, player_key)` returns the close at exactly that line plus `reason` (`ok`, `no_close_at_line`, `no_close`).

- [ ] **Step 1: write the test.** Create `tests/testthat/test-odds-closing.R`:

````r
# =============================================================================
# Tests: the closing rule (R/odds/closing.R)
# The close is the last snapshot at or before kickoff at the SAME line. A gap of
# more than 60 minutes is flagged stale and kept out of headline CLV. Nothing
# after kickoff is ever a close, and a missing close is never filled in.
# =============================================================================

KICK <- as.POSIXct("2026-10-12 20:15:00", tz = "UTC")
kickoffs <- data.frame(game_id = c("g1", "g2"), kickoff_utc = rep(KICK, 2))

candle <- function(minutes_before_kickoff, bid, ask, line = NA_real_, game_id = "g1", side = "home",
                   market_id = "moneyline", venue_id = "kalshi", kind = "candle") {
  data.frame(
    game_id = game_id, market_id = market_id, venue_id = venue_id, player_key = NA_character_, side = side,
    line = line, price_american = NA_integer_, bid = bid, ask = ask, last = NA_real_, volume = NA_real_,
    captured_at = KICK - minutes_before_kickoff * 60, snapshot_kind = kind, source = "kalshi_live",
    raw_sha256 = "x", stringsAsFactors = FALSE
  )
}
rows <- function(...) new_odds_snapshots(do.call(rbind, list(...)))

test_that("the close is the last snapshot at or before kickoff", {
  s <- rows(candle(180, .40, .42), candle(120, .44, .46), candle(50, .48, .50), candle(0, .49, .51), candle(-30, .90, .92))
  close <- select_closing_snapshots(s, kickoffs)
  expect_equal(nrow(close), 1)
  expect_equal(close$bid, .49)              # the candle ending exactly at kickoff counts
  expect_equal(close$close_gap_min, 0)
  expect_false(close$stale)
  expect_true(close$headline_eligible)
  expect_equal(close$rule_version, ODDS_CLOSE_RULE_VERSION)
  expect_equal(attr(close, "audit")$n_post_kickoff_dropped, 1)
})

test_that("a post-kickoff snapshot is never a close, even when it is the only one", {
  s <- rows(candle(-5, .90, .92))
  close <- select_closing_snapshots(s, kickoffs)
  expect_equal(nrow(close), 0)
  expect_equal(attr(close, "audit")$n_post_kickoff_dropped, 1)
})

test_that("a gap over 60 minutes is stale and not headline eligible; exactly 60 is not stale", {
  at_61 <- select_closing_snapshots(rows(candle(61, .40, .42)), kickoffs)
  expect_equal(at_61$close_gap_min, 61)
  expect_true(at_61$stale)
  expect_false(at_61$headline_eligible)
  at_60 <- select_closing_snapshots(rows(candle(60, .40, .42)), kickoffs)
  expect_false(at_60$stale)
  expect_true(at_60$headline_eligible)
  expect_equal(attr(at_61, "audit")$n_stale, 1)
})

test_that("the close is taken per line: a later snapshot at another line never replaces it", {
  s <- rows(
    candle(90, .50, .52, line = -3, market_id = "spread", venue_id = "kalshi", side = "home"),
    candle(10, .55, .57, line = -3.5, market_id = "spread", venue_id = "kalshi", side = "home")
  )
  close <- select_closing_snapshots(s, kickoffs)
  expect_equal(sort(close$line), c(-3.5, -3))
  hit <- match_close_at_line(close, "g1", "spread", "kalshi", "home", line = -3)
  expect_equal(hit$reason, "ok")
  expect_equal(hit$bid, .50)
  expect_equal(hit$close_gap_min, 90)
  expect_true(hit$stale)                                   # found, but too old for the headline
  miss <- match_close_at_line(close, "g1", "spread", "kalshi", "home", line = -2.5)
  expect_equal(miss$reason, "no_close_at_line")            # no nearest-line substitute
  expect_true(is.na(miss$bid))
  none <- match_close_at_line(close, "g1", "total", "kalshi", "over", line = 45.5)
  expect_equal(none$reason, "no_close")
})

test_that("venues, sides and games close independently", {
  s <- rows(
    candle(30, .40, .42, side = "home"), candle(20, .58, .60, side = "away"),
    candle(45, .10, .12, venue_id = "kalshi", game_id = "g2")
  )
  close <- select_closing_snapshots(s, kickoffs)
  expect_equal(nrow(close), 3)
})

test_that("a labelled close is used only when no timed snapshot exists, and has no gap", {
  labelled <- rows(candle(0, NA, NA, kind = "close", venue_id = "espn_bet"))
  labelled$captured_at <- as.POSIXct(NA, tz = "UTC")
  labelled$price_american <- -150L
  close <- select_closing_snapshots(labelled, kickoffs)
  expect_equal(nrow(close), 1)
  expect_equal(close$timing, "labelled")
  expect_true(is.na(close$close_gap_min))
  expect_false(close$stale)
  expect_true(close$headline_eligible)

  both <- rbind(labelled, rows(candle(25, .40, .42, venue_id = "espn_bet")))
  expect_equal(select_closing_snapshots(both, kickoffs)$timing, "timed")
})

test_that("opening lines are ignored, and games without a kickoff are counted, not guessed", {
  open_row <- rows(candle(0, NA, NA, kind = "open", venue_id = "espn_bet"))
  open_row$captured_at <- as.POSIXct(NA, tz = "UTC")
  open_row$price_american <- -110L
  expect_equal(nrow(select_closing_snapshots(open_row, kickoffs)), 0)
  orphan <- rows(candle(30, .40, .42, game_id = "unknown_game"))
  close <- select_closing_snapshots(orphan, kickoffs)
  expect_equal(nrow(close), 0)
  expect_equal(attr(close, "audit")$n_no_kickoff, 1)
})
````

- [ ] **Step 2: RED.** Expected with `R/odds/closing.R` absent:

```
── 1. Error ('test-odds-closing.R:24:3'): the close is the last snapshot at or b
Error in `select_closing_snapshots(s, kickoffs)`: could not find function "select_closing_snapshots"
── 2. Error ('test-odds-closing.R:36:3'): a post-kickoff snapshot is never a clo
Error in `select_closing_snapshots(s, kickoffs)`: could not find function "select_closing_snapshots"
```

- [ ] **Step 3: implement.** Create `R/odds/closing.R`:

````r
# =============================================================================
# The closing rule (roadmap D1; spec Phase 2)
# =============================================================================
# The close of a (game, market, venue, player, side) at one line is the last
# snapshot at or before kickoff at that same line:
#   - a snapshot after kickoff is never a close (it is counted in the audit)
#   - the line is part of the key, so a later snapshot at another line does not
#     replace the close, and a pick with no close at its line gets none
#     (match_close_at_line says so; it never takes the nearest line)
#   - a gap of more than 60 minutes between the close and kickoff is `stale` and
#     is not eligible for headline CLV
#   - a venue's labelled close (snapshot_kind "close", no timestamp) is used only
#     when no timed snapshot exists; it has no gap, so it is never stale, and its
#     timing is reported as "labelled"
# Opening lines are ignored here. The rule is price-agnostic: Kalshi's close is
# the mid of the returned bid and ask, a sportsbook's is price_american.
# =============================================================================

ODDS_CLOSE_RULE_VERSION <- "close-v1"
ODDS_CLOSE_STALE_MIN <- 60

odds_line_key <- function(line) ifelse(is.na(line), "NA", formatC(line, format = "f", digits = 3))

odds_snapshot_key <- function(df) {
  paste(df$game_id, df$market_id, df$venue_id, ifelse(is.na(df$player_key), "", df$player_key),
        df$side, odds_line_key(df$line), sep = "|")
}

#' Select the close of every (game, market, venue, player, side, line).
#' @param snaps odds_snapshots table
#' @param kickoffs data.frame(game_id, kickoff_utc [POSIXct UTC])
#' @return data.frame, one row per close, with attr "audit" (counts of what was set aside)
select_closing_snapshots <- function(snaps, kickoffs, stale_after_min = ODDS_CLOSE_STALE_MIN) {
  stopifnot(all(c("game_id", "kickoff_utc") %in% names(kickoffs)))
  n_input <- nrow(snaps)
  s <- snaps
  s$.idx <- seq_len(n_input)
  s$kickoff_utc <- kickoffs$kickoff_utc[match(s$game_id, kickoffs$game_id)]
  no_kickoff <- is.na(s$kickoff_utc)
  timed <- s$snapshot_kind %in% ODDS_TIMED_KINDS
  post_kickoff <- timed & !no_kickoff & s$captured_at > s$kickoff_utc
  is_open <- s$snapshot_kind == "open"
  keep <- !no_kickoff & !is_open & !post_kickoff
  e <- s[keep, , drop = FALSE]

  if (nrow(e) > 0) {
    e$timing <- ifelse(e$snapshot_kind %in% ODDS_TIMED_KINDS, "timed", "labelled")
    e$.key <- odds_snapshot_key(e)
    when <- ifelse(is.na(e$captured_at), -Inf, as.numeric(e$captured_at))
    ord <- order(e$.key, e$timing != "timed", -when, -e$.idx)
    e <- e[ord, , drop = FALSE]
    e <- e[!duplicated(e$.key), , drop = FALSE]
    e$close_gap_min <- ifelse(e$timing == "timed",
                              as.numeric(difftime(e$kickoff_utc, e$captured_at, units = "mins")), NA_real_)
    e$stale <- e$timing == "timed" & e$close_gap_min > stale_after_min
    e$headline_eligible <- !e$stale
    e$rule_version <- ODDS_CLOSE_RULE_VERSION
    cols <- c(setdiff(ODDS_SNAPSHOT_COLUMNS, c("source", "raw_sha256")), "timing", "close_gap_min", "stale",
              "headline_eligible", "rule_version", "source", "raw_sha256")
    e <- e[order(e$.key), cols, drop = FALSE]
  } else {
    e <- data.frame(
      odds_snapshots_empty()[, setdiff(ODDS_SNAPSHOT_COLUMNS, c("source", "raw_sha256"))],
      timing = character(), close_gap_min = numeric(), stale = logical(), headline_eligible = logical(),
      rule_version = character(), source = character(), raw_sha256 = character(), stringsAsFactors = FALSE
    )
  }
  rownames(e) <- NULL
  attr(e, "audit") <- data.frame(
    n_input = n_input, n_no_kickoff = sum(no_kickoff), n_post_kickoff_dropped = sum(post_kickoff),
    n_open_ignored = sum(is_open & !no_kickoff), n_closes = nrow(e), n_stale = sum(e$stale)
  )
  e
}

#' The close for one pick, at exactly its line.
#' @return one row of `closes` plus `reason`: "ok"; "no_close_at_line" when the key has
#'   closes only at other lines; "no_close" when it has none. Non-ok rows are NA-filled.
match_close_at_line <- function(closes, game_id, market_id, venue_id, side, line, player_key = NA_character_) {
  same_key <- closes$game_id == game_id & closes$market_id == market_id & closes$venue_id == venue_id &
    closes$side == side &
    ifelse(is.na(closes$player_key), "", closes$player_key) == ifelse(is.na(player_key), "", player_key)
  same_line <- if (is.na(line)) is.na(closes$line) else (!is.na(closes$line) & abs(closes$line - line) < 1e-9)
  hit <- closes[same_key & same_line, , drop = FALSE]
  if (nrow(hit) > 0) {
    hit <- hit[1, , drop = FALSE]
    hit$reason <- "ok"
    return(hit)
  }
  blank <- closes[NA_integer_, , drop = FALSE][1, , drop = FALSE]
  rownames(blank) <- NULL
  blank$game_id <- game_id
  blank$market_id <- market_id
  blank$venue_id <- venue_id
  blank$side <- side
  blank$line <- line
  blank$reason <- if (any(same_key)) "no_close_at_line" else "no_close"
  blank
}
````

- [ ] **Step 4: GREEN.** Run the test file: no failures, exit 0.
- [ ] **Step 5: commit.**

```bash
git add R/odds/closing.R tests/testthat/test-odds-closing.R
git commit -m "feat(odds): closing rule at the same line, 60-minute stale flag, no nearest-line fill (D1)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 4: the provider interface and the nflverse provider (*haiku*)

**Files:** create `R/odds/provider.R`, `R/odds/provider_nflverse.R`, `tests/testthat/test-odds-provider.R`.

**Interface:** `new_odds_provider(id, venue_ids, game_snapshots, prop_snapshots, capture)`, `validate_odds_provider()`, `odds_result(snapshots, source, status, detail, fetches)`, `bind_odds_results()`, `odds_fetch_row()`, `odds_games_from_schedule(schedule)` (the `games` table: `game_id, season, week, game_type, gameday, kickoff_utc, home_team, away_team, espn`), `provider_nflverse(load_schedules_fn)`.

- [ ] **Step 1: write the test.** Create `tests/testthat/test-odds-provider.R`:

````r
# =============================================================================
# Tests: the provider interface (R/odds/provider.R) and the nflverse provider
# (R/odds/provider_nflverse.R). No network: the schedule comes from a fixture.
# =============================================================================

sched_fixture <- function() utils::read.csv(testthat::test_path("fixtures", "schedules_2024_lines.csv"), stringsAsFactors = FALSE)

test_that("a provider declares its id, venues and capabilities, and the interface rejects a bad one", {
  p <- new_odds_provider("demo", "kalshi", game_snapshots = function(games, ...) odds_result(source = "demo"))
  expect_s3_class(p, "odds_provider")
  expect_equal(validate_odds_provider(p), character())
  expect_true(is.null(p$prop_snapshots))
  expect_error(new_odds_provider("demo", "nowhere"), "venue")
  expect_error(new_odds_provider("", "kalshi"), "id")
  expect_error(new_odds_provider("demo", "kalshi", game_snapshots = "not a function"), "function")
})

test_that("odds_result carries snapshots, a source_status row and the fetch lineage", {
  r <- odds_result(source = "demo", status = "ok", detail = "fine")
  expect_equal(names(r$source_status), c("source", "status", "last_success_utc", "detail"))
  expect_equal(nrow(r$snapshots), 0)
  contracts <- file.path(PROJECT_ROOT, "contracts", "schema")
  expect_equal(bw_validate_rows(r$source_status, bw_read_schema("source_status", contracts), "source_status"), character())
  expect_error(odds_result(source = "demo", status = "fine"), "status")
  both <- bind_odds_results(list(r, odds_result(source = "other", status = "failed", detail = "HTTP 500")))
  expect_equal(both$source_status$source, c("demo", "other"))
})

test_that("odds_games_from_schedule converts the Eastern kickoff to UTC and never guesses a missing time", {
  sched <- data.frame(
    game_id = c("a", "b"), season = 2024L, week = 1L, game_type = "REG",
    gameday = c("2024-09-08", "2024-09-08"), gametime = c("13:00", NA),
    home_team = "KC", away_team = "BAL", espn = c("1", "2"), stringsAsFactors = FALSE
  )
  g <- odds_games_from_schedule(sched)
  expect_equal(format(g$kickoff_utc[1], "%Y-%m-%d %H:%M", tz = "UTC"), "2024-09-08 17:00")   # EDT is UTC-4
  expect_true(is.na(g$kickoff_utc[2]))
})

test_that("the nflverse provider turns the consensus close into snapshots", {
  p <- provider_nflverse(load_schedules_fn = function(seasons) sched_fixture())
  expect_equal(validate_odds_provider(p), character())
  games <- data.frame(game_id = c("2024_01_BAL_KC", "2024_01_GB_PHI"), season = 2024L, stringsAsFactors = FALSE)
  res <- p$game_snapshots(games)
  s <- res$snapshots
  expect_equal(unique(s$venue_id), "nflverse_consensus")
  expect_equal(unique(s$snapshot_kind), "close")
  expect_true(all(is.na(s$captured_at)))
  expect_equal(nrow(s), 8)                                   # 2 games x (2 moneyline + 2 spread); no total_line column
  ml <- s[s$game_id == "2024_01_BAL_KC" & s$market_id == "moneyline", ]
  expect_equal(ml$price_american[ml$side == "home"], -148L)
  expect_equal(ml$price_american[ml$side == "away"], 124L)
  sp <- s[s$game_id == "2024_01_BAL_KC" & s$market_id == "spread", ]
  expect_equal(sp$line[sp$side == "home"], -3)               # spread_line > 0 means the home team is favoured
  expect_equal(sp$line[sp$side == "away"], 3)
  expect_equal(res$source_status$status, "ok")
  expect_match(res$source_status$detail, "total_line")       # the missing column is reported, not hidden
  expect_equal(length(unique(s$raw_sha256)), 1)
  expect_match(s$raw_sha256[1], "^[0-9a-f]{64}$")
})

test_that("games the schedule does not have are reported as a failure, never filled", {
  p <- provider_nflverse(load_schedules_fn = function(seasons) sched_fixture())
  games <- data.frame(game_id = c("2024_01_BAL_KC", "2024_99_AAA_BBB"), season = 2024L, stringsAsFactors = FALSE)
  res <- p$game_snapshots(games)
  expect_equal(res$source_status$status, "failed")
  expect_match(res$source_status$detail, "2024_99_AAA_BBB")
  expect_false("2024_99_AAA_BBB" %in% res$snapshots$game_id)
  none <- p$game_snapshots(data.frame(game_id = "2024_99_AAA_BBB", season = 2024L, stringsAsFactors = FALSE))
  expect_equal(none$source_status$status, "unavailable")
})

test_that("a game with no moneyline gets no moneyline rows (M11: a missing market stays missing)", {
  s <- sched_fixture()
  s$home_moneyline[1] <- NA
  s$away_moneyline[1] <- NA
  p <- provider_nflverse(load_schedules_fn = function(seasons) s)
  res <- p$game_snapshots(data.frame(game_id = s$game_id[1], season = 2024L, stringsAsFactors = FALSE))
  expect_false("moneyline" %in% res$snapshots$market_id)
  expect_true("spread" %in% res$snapshots$market_id)
  expect_match(res$source_status$detail, "1 without a moneyline")
})
````

- [ ] **Step 2: RED.** Expected with both implementation files absent:

```
── 1. Error ('test-odds-provider.R:9:3'): a provider declares its id, venues and
Error in `new_odds_provider("demo", "kalshi", game_snapshots = function(games, ...) odds_result(source = "demo"))`: could not find function "new_odds_provider"
── 2. Error ('test-odds-provider.R:19:3'): odds_result carries snapshots, a sour
Error in `odds_result(source = "demo", status = "ok", detail = "fine")`: could not find function "odds_result"
```

- [ ] **Step 3: implement.** Create `R/odds/provider.R`:

````r
# =============================================================================
# The odds provider interface (roadmap D1; spec Phase 2)
# =============================================================================
# One interface for every source. A provider is built by a constructor
# (provider_nflverse(), provider_espn_core(), provider_kalshi()) that takes its
# network seam (`fetch_fn`) as an argument, and is a list with:
#   id               short source id
#   venue_ids        the odds_venues_catalog() venues it can emit
#   game_snapshots   function(games, ...) -> odds_result, or NULL
#   prop_snapshots   function(games, ...) -> odds_result, or NULL
#   capture          function(fetch, now, cfg), the forward-capture pass that stores
#                    raw responses (the games it needs come from the source itself), or NULL
# `games` is the table odds_games_from_schedule() builds. Every method returns an
# odds_result: normalized snapshots, a source_status row (the contract in
# contracts/schema/source_status.schema.json) and the fetch lineage. A source that
# fails says so in source_status; it never returns made-up rows.
# =============================================================================

ODDS_RESULT_STATUSES <- c("ok", "complete", "stale", "failed", "unavailable")

#' Build and check a provider
new_odds_provider <- function(id, venue_ids, game_snapshots = NULL, prop_snapshots = NULL, capture = NULL) {
  p <- structure(
    list(id = id, venue_ids = venue_ids, game_snapshots = game_snapshots,
         prop_snapshots = prop_snapshots, capture = capture),
    class = "odds_provider"
  )
  problems <- validate_odds_provider(p)
  if (length(problems)) stop("new_odds_provider: ", paste(problems, collapse = "; "), call. = FALSE)
  p
}

validate_odds_provider <- function(p) {
  fails <- character()
  if (!is.character(p$id) || length(p$id) != 1L || is.na(p$id) || !nzchar(p$id)) fails <- c(fails, "id must be a non-empty string")
  if (!is.character(p$venue_ids) || length(p$venue_ids) == 0 || !all(p$venue_ids %in% odds_venues_catalog()$venue_id)) {
    fails <- c(fails, "every venue id must be in odds_venues_catalog()")
  }
  for (m in c("game_snapshots", "prop_snapshots", "capture")) {
    if (!is.null(p[[m]]) && !is.function(p[[m]])) fails <- c(fails, sprintf("%s must be a function or NULL", m))
  }
  fails
}

#' One row of fetch lineage from an odds_fetch() record
odds_fetch_row <- function(rec, key) {
  data.frame(
    source = rec$source %||% NA_character_, key = key, url = rec$url, http_status = rec$status,
    raw_sha256 = rec$sha256, bytes = rec$bytes, tries = rec$tries, blocked = rec$blocked,
    fetched_at = rec$fetched_at, stringsAsFactors = FALSE
  )
}

odds_fetches_empty <- function() {
  data.frame(
    source = character(), key = character(), url = character(), http_status = integer(),
    raw_sha256 = character(), bytes = integer(), tries = integer(), blocked = logical(),
    fetched_at = as.POSIXct(character(), tz = "UTC"), stringsAsFactors = FALSE
  )
}

#' What a provider method returns
odds_result <- function(snapshots = odds_snapshots_empty(), source, status = "ok", detail = NA_character_,
                        fetches = odds_fetches_empty(), now = Sys.time()) {
  if (!status %in% ODDS_RESULT_STATUSES) {
    stop("odds_result: status must be one of ", paste(ODDS_RESULT_STATUSES, collapse = ", "), call. = FALSE)
  }
  list(
    snapshots = snapshots,
    source_status = data.frame(
      source = source, status = status,
      last_success_utc = if (status %in% c("ok", "complete")) odds_iso(now) else NA_character_,
      detail = detail, stringsAsFactors = FALSE
    ),
    fetches = fetches
  )
}

bind_odds_results <- function(results) {
  results <- Filter(Negate(is.null), results)
  list(
    snapshots = bind_odds_snapshots(lapply(results, `[[`, "snapshots")),
    source_status = do.call(rbind, c(list(odds_result(source = "none")$source_status[0, ]),
                                     lapply(results, `[[`, "source_status"))),
    fetches = do.call(rbind, c(list(odds_fetches_empty()), lapply(results, `[[`, "fetches")))
  )
}

#' The `games` table the providers take, from an nflreadr::load_schedules() frame.
#' A game whose time is unknown keeps a NA kickoff; it is never given a default.
odds_games_from_schedule <- function(schedule) {
  sched <- as.data.frame(schedule, stringsAsFactors = FALSE)
  kick <- as.POSIXct(paste(sched$gameday, sched$gametime), format = "%Y-%m-%d %H:%M", tz = "America/New_York")
  attr(kick, "tzone") <- "UTC"
  data.frame(
    game_id = sched$game_id, season = as.integer(sched$season), week = as.integer(sched$week),
    game_type = sched$game_type, gameday = sched$gameday, kickoff_utc = kick,
    home_team = sched$home_team, away_team = sched$away_team, espn = as.character(sched$espn),
    stringsAsFactors = FALSE
  )
}
````

  Create `R/odds/provider_nflverse.R`:

````r
# =============================================================================
# nflverse provider: the consensus closing line (roadmap D1)
# =============================================================================
# nflreadr::load_schedules() carries one closing moneyline, spread and total per
# game since 1999. It is a consensus close, with no open and no timestamp, so
# every row is snapshot_kind "close" with captured_at NA. Sign convention: nflverse
# `spread_line` is positive when the HOME team is favoured, so the home handicap is
# -spread_line and the away handicap is +spread_line.
# `load_schedules_fn(seasons)` is the seam: tests pass a fixture reader.
# =============================================================================

NFLVERSE_PRICE_COLUMNS <- c("home_moneyline", "away_moneyline", "spread_line", "home_spread_odds",
                            "away_spread_odds", "total_line", "over_odds", "under_odds")

provider_nflverse <- function(load_schedules_fn = NULL) {
  load_fn <- load_schedules_fn %||% function(seasons) nflreadr::load_schedules(seasons)

  game_snapshots <- function(games, ...) {
    source <- "nflverse_schedules"
    sched <- as.data.frame(load_fn(sort(unique(games$season))), stringsAsFactors = FALSE)
    absent <- setdiff(NFLVERSE_PRICE_COLUMNS, names(sched))
    for (nm in absent) sched[[nm]] <- NA
    requested <- unique(games$game_id)
    sched <- sched[sched$game_id %in% requested, , drop = FALSE]
    sched <- sched[order(sched$game_id), , drop = FALSE]
    not_found <- setdiff(requested, sched$game_id)

    raw_cols <- c("game_id", setdiff(NFLVERSE_PRICE_COLUMNS, absent))
    raw_text <- paste(utils::capture.output(utils::write.csv(sched[, raw_cols, drop = FALSE], row.names = FALSE)),
                      collapse = "\n")
    sha <- digest::digest(raw_text, algo = "sha256", serialize = FALSE)

    make <- function(idx, market_id, side, line, price) {
      keep <- !is.na(price) | !is.na(line)
      if (!any(keep)) return(NULL)
      data.frame(
        game_id = sched$game_id[idx][keep], market_id = market_id, venue_id = "nflverse_consensus",
        side = side, line = line[keep], price_american = american_to_int(price[keep]),
        snapshot_kind = "close", source = source, raw_sha256 = sha, stringsAsFactors = FALSE
      )
    }
    all_idx <- seq_len(nrow(sched))
    has_ml <- !is.na(sched$home_moneyline) & !is.na(sched$away_moneyline)
    ml_idx <- which(has_ml)
    parts <- list(
      make(ml_idx, "moneyline", "home", rep(NA_real_, length(ml_idx)), sched$home_moneyline[ml_idx]),
      make(ml_idx, "moneyline", "away", rep(NA_real_, length(ml_idx)), sched$away_moneyline[ml_idx]),
      make(all_idx, "spread", "home", -as.numeric(sched$spread_line), sched$home_spread_odds),
      make(all_idx, "spread", "away", as.numeric(sched$spread_line), sched$away_spread_odds),
      make(all_idx, "total", "over", as.numeric(sched$total_line), sched$over_odds),
      make(all_idx, "total", "under", as.numeric(sched$total_line), sched$under_odds)
    )
    snaps <- new_odds_snapshots(do.call(rbind, Filter(Negate(is.null), parts)) %||% odds_snapshots_empty())

    detail <- sprintf("%d of %d games in the schedule; %d without a moneyline",
                      nrow(sched), length(requested), sum(!has_ml))
    if (length(not_found)) detail <- paste0(detail, "; not in the schedule: ", paste(utils::head(not_found, 5), collapse = ", "))
    if (length(absent)) detail <- paste0(detail, "; column(s) absent: ", paste(absent, collapse = ", "))
    status <- if (nrow(sched) == 0) "unavailable" else if (length(not_found)) "failed" else "ok"
    odds_result(snaps, source = source, status = status, detail = detail)
  }

  new_odds_provider("nflverse", "nflverse_consensus", game_snapshots = game_snapshots)
}
````

- [ ] **Step 4: GREEN.** Run the test file: no failures, exit 0.
- [ ] **Step 5: commit.**

```bash
git add R/odds/provider.R R/odds/provider_nflverse.R tests/testthat/test-odds-provider.R
git commit -m "feat(odds): provider interface and the nflverse consensus-close provider (D1)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 5: the ESPN core provider (*haiku* to transcribe, *sonnet* to review the fixtures)

**Files:** create `tests/testthat/fixtures/odds/espn_game_odds_2024_01_ARI_BUF.json`, `tests/testthat/fixtures/odds/espn_game_odds_2026_01_NE_SEA.json`, `tests/testthat/test-odds-espn-core.R`, `R/odds/provider_espn_core.R`.

The two JSON fixtures are trimmed REAL responses from `https://sports.core.api.espn.com/v2/sports/football/leagues/nfl/events/{401671617,401872656}/competitions/{same}/odds`, fetched 2026-10-13 (links, betslip URLs and display fields removed; every value kept is the response's). The first holds Bet 365 (no open/close blocks), ESPN BET (58, with open, close and current) and "ESPN Bet - Live Odds" (59, no close). The second is DraftKings (100). The prop and scoreboard fixtures are the existing `tests/testthat/fixtures/capture/*.json`.

- [ ] **Step 1: fixtures.** Create `tests/testthat/fixtures/odds/espn_game_odds_2024_01_ARI_BUF.json`:

````json
{
 "count": 3,
 "pageIndex": 1,
 "pageSize": 25,
 "pageCount": 1,
 "items": [
  {
   "provider": {
    "id": "2000",
    "name": "Bet 365"
   }
  },
  {
   "provider": {
    "id": "58",
    "name": "ESPN BET"
   },
   "details": "BUF -6.5",
   "overUnder": 45.5,
   "spread": -6.5,
   "overOdds": -110.0,
   "underOdds": -110.0,
   "awayTeamOdds": {
    "moneyLine": 260,
    "spreadOdds": 100.0,
    "open": {
     "pointSpread": {
      "american": "+7"
     },
     "spread": {
      "american": "-110"
     },
     "moneyLine": {
      "american": "+225"
     }
    },
    "close": {
     "pointSpread": {
      "american": "+6.5"
     },
     "spread": {
      "american": "+100"
     },
     "moneyLine": {
      "american": "+260"
     }
    },
    "current": {
     "pointSpread": {
      "american": "+6.5"
     },
     "spread": {
      "american": "+100"
     },
     "moneyLine": {
      "american": "+260"
     }
    }
   },
   "homeTeamOdds": {
    "moneyLine": -320,
    "spreadOdds": -120.0,
    "open": {
     "pointSpread": {
      "american": "-7"
     },
     "spread": {
      "american": "-110"
     },
     "moneyLine": {
      "american": "-275"
     }
    },
    "close": {
     "pointSpread": {
      "american": "-6.5"
     },
     "spread": {
      "american": "-120"
     },
     "moneyLine": {
      "american": "-320"
     }
    },
    "current": {
     "pointSpread": {
      "american": "-6.5"
     },
     "spread": {
      "american": "-120"
     },
     "moneyLine": {
      "american": "-320"
     }
    }
   },
   "open": {
    "over": {
     "american": "-105"
    },
    "under": {
     "american": "-115"
    },
    "total": {
     "american": "48"
    }
   },
   "close": {
    "over": {
     "american": "-110"
    },
    "under": {
     "american": "-110"
    },
    "total": {
     "american": "45.5"
    }
   },
   "current": {
    "over": {
     "american": "-110"
    },
    "under": {
     "american": "-110"
    },
    "total": {
     "american": "45.5"
    }
   }
  },
  {
   "provider": {
    "id": "59",
    "name": "ESPN Bet - Live Odds"
   },
   "details": "BUF -8.5",
   "overUnder": 65.5,
   "spread": -8.5,
   "overOdds": -130.0,
   "underOdds": 100.0,
   "awayTeamOdds": {
    "moneyLine": 550,
    "spreadOdds": -5000.0,
    "open": {
     "pointSpread": {
      "american": "+7"
     },
     "spread": {
      "american": "-110"
     },
     "moneyLine": {
      "american": "+225"
     }
    },
    "current": {
     "pointSpread": {
      "american": "+8.5"
     },
     "spread": {
      "american": "-5000"
     },
     "moneyLine": {
      "american": "+550"
     }
    }
   },
   "homeTeamOdds": {
    "moneyLine": -1000,
    "spreadOdds": 1400.0,
    "open": {
     "pointSpread": {
      "american": "-7"
     },
     "spread": {
      "american": "-110"
     },
     "moneyLine": {
      "american": "-275"
     }
    },
    "current": {
     "pointSpread": {
      "american": "-8.5"
     },
     "spread": {
      "american": "+1400"
     },
     "moneyLine": {
      "american": "-1000"
     }
    }
   },
   "open": {
    "over": {
     "american": "-105"
    },
    "under": {
     "american": "-115"
    },
    "total": {
     "american": "48"
    }
   },
   "current": {
    "over": {
     "american": "-130"
    },
    "under": {
     "american": "+100"
    },
    "total": {
     "american": "65.5"
    }
   }
  }
 ]
}
````

  Create `tests/testthat/fixtures/odds/espn_game_odds_2026_01_NE_SEA.json`:

````json
{
 "count": 1,
 "pageIndex": 1,
 "pageSize": 25,
 "pageCount": 1,
 "items": [
  {
   "provider": {
    "id": "100",
    "name": "DraftKings"
   },
   "details": "SEA -3",
   "overUnder": 44.5,
   "spread": -3.0,
   "overOdds": -108.0,
   "underOdds": -112.0,
   "awayTeamOdds": {
    "moneyLine": 142,
    "spreadOdds": 100.0,
    "open": {
     "pointSpread": {
      "american": "+3.5"
     },
     "spread": {
      "american": "-110"
     },
     "moneyLine": {
      "american": "+160"
     }
    },
    "close": {
     "pointSpread": {
      "american": "+3"
     },
     "spread": {
      "american": "+100"
     },
     "moneyLine": {
      "american": "+142"
     }
    },
    "current": {
     "pointSpread": {
      "american": "+3"
     },
     "spread": {
      "american": "+100"
     },
     "moneyLine": {
      "american": "+142"
     }
    }
   },
   "homeTeamOdds": {
    "moneyLine": -170,
    "spreadOdds": -120.0,
    "open": {
     "pointSpread": {
      "american": "-3.5"
     },
     "spread": {
      "american": "-110"
     },
     "moneyLine": {
      "american": "-192"
     }
    },
    "close": {
     "pointSpread": {
      "american": "-3"
     },
     "spread": {
      "american": "-120"
     },
     "moneyLine": {
      "american": "-170"
     }
    },
    "current": {
     "pointSpread": {
      "american": "-3"
     },
     "spread": {
      "american": "-120"
     },
     "moneyLine": {
      "american": "-170"
     }
    }
   },
   "open": {
    "over": {
     "american": "-110"
    },
    "under": {
     "american": "-110"
    },
    "total": {
     "american": "44.5"
    }
   },
   "close": {
    "over": {
     "american": "-108"
    },
    "under": {
     "american": "-112"
    },
    "total": {
     "american": "44.5"
    }
   },
   "current": {
    "over": {
     "american": "-108"
    },
    "under": {
     "american": "-112"
    },
    "total": {
     "american": "44.5"
    }
   }
  }
 ]
}
````

- [ ] **Step 2: write the test.** Create `tests/testthat/test-odds-espn-core.R`:

````r
# =============================================================================
# Tests: the ESPN core provider (R/odds/provider_espn_core.R)
# Fixtures in fixtures/odds/ are trimmed REAL responses (2024_01_ARI_BUF from the
# 2024 season, NE at SEA from 2026 week 1); the prop and scoreboard fixtures are in
# fixtures/capture/. Every fetch goes through odds_fake_fetch(): no network.
# =============================================================================

GAME_2024 <- data.frame(game_id = "2024_01_ARI_BUF", season = 2024L, espn = "401671617", stringsAsFactors = FALSE)
GAME_2026 <- data.frame(game_id = "2026_01_NE_SEA", season = 2026L, espn = "401872656", stringsAsFactors = FALSE)
odds_url <- function(event) espn_game_odds_url(event)

espn_provider <- function(routes, clock = odds_fake_clock(), log_path = NULL) {
  odds_http_reset()
  fake <- odds_fake_fetch(routes)
  list(provider = provider_espn_core(cfg = odds_http_config(), fetch_fn = fake$fn, log_path = log_path,
                                     now_fn = clock$now, sleep_fn = clock$sleep),
       fake = fake, clock = clock)
}

test_that("ESPN BET open and close lines become snapshots for the moneyline, spread and total", {
  parsed <- odds_fixture_json("espn_game_odds_2024_01_ARI_BUF.json")
  s <- parse_espn_game_odds(parsed, "2024_01_ARI_BUF", sha256 = strrep("a", 64))
  expect_equal(validate_odds_snapshots(s), character())
  expect_equal(unique(s$venue_id), "espn_bet")
  expect_equal(nrow(s), 12)                                         # 3 markets x 2 sides x open/close
  expect_true(all(is.na(s$captured_at)))
  pick <- function(market, side, kind) s[s$market_id == market & s$side == side & s$snapshot_kind == kind, ]
  expect_equal(pick("moneyline", "home", "open")$price_american, -275L)
  expect_equal(pick("moneyline", "home", "close")$price_american, -320L)
  expect_equal(pick("moneyline", "away", "open")$price_american, 225L)
  expect_equal(pick("moneyline", "away", "close")$price_american, 260L)
  expect_equal(pick("spread", "home", "open")$line, -7)
  expect_equal(pick("spread", "home", "close")$line, -6.5)
  expect_equal(pick("spread", "home", "close")$price_american, -120L)
  expect_equal(pick("spread", "away", "close")$line, 6.5)
  expect_equal(pick("spread", "away", "close")$price_american, 100L)
  expect_equal(pick("total", "over", "open")$line, 48)
  expect_equal(pick("total", "under", "open")$price_american, -115L)
  expect_equal(pick("total", "over", "close")$line, 45.5)
  expect_equal(unique(s$raw_sha256), strrep("a", 64))
  # providers without an open and a close block are skipped and named, not guessed
  expect_setequal(attr(s, "skipped_providers"), c("2000 Bet 365", "59 ESPN Bet - Live Odds"))
})

test_that("DraftKings (provider 100) maps to its own venue", {
  s <- parse_espn_game_odds(odds_fixture_json("espn_game_odds_2026_01_NE_SEA.json"), "2026_01_NE_SEA", sha256 = "b")
  expect_equal(unique(s$venue_id), "draftkings")
  expect_equal(s$price_american[s$market_id == "moneyline" & s$side == "home" & s$snapshot_kind == "open"], -192L)
  expect_equal(s$line[s$market_id == "total" & s$side == "over" & s$snapshot_kind == "close"], 44.5)
})

test_that("a pick'em spread parses as a handicap of 0, and a missing side drops that market only", {
  parsed <- odds_fixture_json("espn_game_odds_2026_01_NE_SEA.json")
  parsed$items[[1]]$homeTeamOdds$open$pointSpread$american <- "PK"
  parsed$items[[1]]$awayTeamOdds$open$pointSpread$american <- "PK"
  parsed$items[[1]]$awayTeamOdds$close$moneyLine <- NULL
  s <- parse_espn_game_odds(parsed, "g", sha256 = "c")
  expect_equal(s$line[s$market_id == "spread" & s$snapshot_kind == "open" & s$side == "home"], 0)
  expect_false(any(s$market_id == "moneyline" & s$snapshot_kind == "close"))     # one side missing: no half market
  expect_true(any(s$market_id == "moneyline" & s$snapshot_kind == "open"))
})

test_that("a game with a close but no open keeps its close (80 of the 285 games of 2023)", {
  parsed <- odds_fixture_json("espn_game_odds_2024_01_ARI_BUF.json")
  espn_bet <- which(vapply(parsed$items, function(i) identical(i$provider$id, "58"), logical(1)))
  for (side in c("homeTeamOdds", "awayTeamOdds")) parsed$items[[espn_bet]][[side]]$open <- NULL
  parsed$items[[espn_bet]]$open <- NULL
  s <- parse_espn_game_odds(parsed, "g", sha256 = "c")
  expect_equal(unique(s$snapshot_kind), "close")
  expect_equal(nrow(s), 6)
})

test_that("a line whose price is missing keeps the line with an NA price (found in the real 2023-2024 responses)", {
  parsed <- odds_fixture_json("espn_game_odds_2026_01_NE_SEA.json")
  parsed$items[[1]]$homeTeamOdds$open$spread <- NULL
  parsed$items[[1]]$open$over <- NULL
  s <- parse_espn_game_odds(parsed, "g", sha256 = "c")
  sp <- s[s$market_id == "spread" & s$side == "home" & s$snapshot_kind == "open", ]
  expect_equal(c(sp$line, sp$price_american), c(-3.5, NA))
  tot <- s[s$market_id == "total" & s$side == "over" & s$snapshot_kind == "open", ]
  expect_equal(c(tot$line, tot$price_american), c(44.5, NA))
})

test_that("game_snapshots fetches each event once, records the raw hash and hands the raw body to on_raw", {
  e <- espn_provider(setNames(list("espn_game_odds_2024_01_ARI_BUF.json", "espn_game_odds_2026_01_NE_SEA.json"),
                              c(odds_url("401671617"), odds_url("401872656"))))
  seen <- list()
  res <- e$provider$game_snapshots(rbind(GAME_2024, GAME_2026), on_raw = function(key, body, rec) seen[[key]] <<- rec$sha256)
  expect_equal(res$source_status$status, "ok")
  expect_setequal(unique(res$snapshots$venue_id), c("espn_bet", "draftkings"))
  expect_equal(nrow(res$fetches), 2)
  expect_equal(res$fetches$raw_sha256[res$fetches$key == "401671617"],
               digest::digest(odds_fixture_raw("espn_game_odds_2024_01_ARI_BUF.json"), algo = "sha256", serialize = FALSE))
  expect_equal(seen[["401671617"]], res$fetches$raw_sha256[res$fetches$key == "401671617"])
  expect_equal(e$fake$state$urls, c(odds_url("401671617"), odds_url("401872656")))
  expect_equal(e$clock$state$sleeps, 1)                              # the second request waited out the 1 s budget
})

test_that("a failed game is reported by name; the others are kept; nothing is substituted", {
  e <- espn_provider(setNames(list("espn_game_odds_2024_01_ARI_BUF.json", list(status = 404L)),
                              c(odds_url("401671617"), odds_url("401872656"))))
  res <- e$provider$game_snapshots(rbind(GAME_2024, GAME_2026))
  expect_equal(res$source_status$status, "failed")
  expect_match(res$source_status$detail, "2026_01_NE_SEA")
  expect_equal(unique(res$snapshots$game_id), "2024_01_ARI_BUF")
  all_bad <- espn_provider(setNames(list(list(status = 404L)), odds_url("401671617")))$provider$game_snapshots(GAME_2024)
  expect_equal(all_bad$source_status$status, "unavailable")
  expect_equal(nrow(all_bad$snapshots), 0)
})

test_that("a game with no ESPN event id is counted, and a 403 stops the run", {
  no_id <- transform(GAME_2024, game_id = "2024_01_NOID", espn = NA_character_)
  e <- espn_provider(setNames(list(list(status = 403L)), odds_url("401671617")))
  res <- e$provider$game_snapshots(rbind(no_id, GAME_2024, GAME_2026))
  expect_match(res$source_status$detail, "1 game without an ESPN event id")
  expect_match(res$source_status$detail, "blocked")
  expect_equal(length(e$fake$state$urls), 1)                         # no request after the 403, and none for the third game
  expect_equal(res$source_status$status, "unavailable")
})

test_that("live prop lines are normalized as line-only snapshots with the fetch time", {
  page <- odds_fixture_json(file.path("..", "capture", "espn_propbets_page1.json"))
  at <- as.POSIXct("2026-09-28 20:53:02", tz = "UTC")
  s <- parse_espn_prop_bets(page, "2026_03_PHI_CHI", fetched_at = at, sha256 = "d")
  expect_equal(validate_odds_snapshots(s), character())
  expect_equal(nrow(s), 6)                                           # 3 rows x (current + open)
  expect_equal(unique(s$venue_id), "draftkings")
  expect_equal(unique(s$market_id), "passing_yards")
  expect_equal(unique(s$side), "line")
  expect_true(all(is.na(s$price_american)))                          # ESPN prop rows carry lines, not prices
  cur <- s[s$snapshot_kind == "observed", ]
  expect_equal(cur$captured_at, rep(at, 3))
  expect_true(172.5 %in% cur$line)
  expect_true(165.5 %in% s$line[s$snapshot_kind == "open"])
  expect_true(all(is.na(s$captured_at[s$snapshot_kind == "open"])))
  expect_true("espn:15168" %in% s$player_key)
  # an unknown prop type is counted, not mapped by guess
  page$items[[1]]$type$name <- "Longest Reception"
  s2 <- parse_espn_prop_bets(page, "g", fetched_at = at, sha256 = "d")
  expect_equal(nrow(s2), 4)
  expect_equal(attr(s2, "unmapped_types"), "Longest Reception")
})

test_that("prop_snapshots reads every page and reports a post-game 404 as unavailable", {
  p1 <- paste(readLines(testthat::test_path("fixtures", "capture", "espn_propbets_page1.json"), warn = FALSE), collapse = "\n")
  one_page <- sub('"pageCount": 2', '"pageCount": 1', p1, fixed = TRUE)
  url <- espn_prop_bets_url("401872656", 100, 1)
  e <- espn_provider(setNames(list(list(text = one_page)), url))
  res <- e$provider$prop_snapshots(GAME_2026)
  expect_equal(res$source_status$status, "ok")
  expect_equal(nrow(res$snapshots), 6)
  expect_equal(unique(res$snapshots$game_id), "2026_01_NE_SEA")
  gone <- espn_provider(setNames(list(list(status = 404L)), url))$provider$prop_snapshots(GAME_2026)
  expect_equal(gone$source_status$status, "unavailable")
  expect_match(gone$source_status$detail, "live only")
})

test_that("the forward-capture pass fetches odds and props for games inside the horizon only", {
  odds_http_reset()
  fetched <- list()
  fetch <- function(source, key, url) {
    fetched[[length(fetched) + 1]] <<- c(source = source, key = key)
    if (source == "espn_scoreboard") return(paste(readLines(testthat::test_path("fixtures", "capture", "espn_scoreboard.json"), warn = FALSE), collapse = "\n"))
    if (source == "espn_propbets") return('{"pageCount": 1, "items": []}')
    "{}"
  }
  p <- provider_espn_core()
  cfg <- list(horizon_hours = 36, espn_prop_providers = 100L)
  p$capture(fetch, now = as.POSIXct("2026-09-28 20:53:00", tz = "UTC"), cfg = cfg)
  got <- vapply(fetched, paste, "", collapse = ":")
  expect_equal(got, c("espn_scoreboard:scoreboard", "espn_game_odds:401872963", "espn_propbets:401872963_100_p1"))
})

test_that("the ESPN provider satisfies the provider interface", {
  p <- provider_espn_core()
  expect_equal(validate_odds_provider(p), character())
  expect_setequal(p$venue_ids, c("espn_bet", "draftkings"))
  expect_true(is.function(p$game_snapshots) && is.function(p$prop_snapshots) && is.function(p$capture))
})
````

- [ ] **Step 3: RED.** Expected with `R/odds/provider_espn_core.R` absent:

```
── 1. Error ('test-odds-espn-core.R:22:3'): ESPN BET open and close lines become
Error in `parse_espn_game_odds(parsed, "2024_01_ARI_BUF", sha256 = strrep("a", 64))`: could not find function "parse_espn_game_odds"
── 2. Error ('test-odds-espn-core.R:46:3'): DraftKings (provider 100) maps to it
Error in `parse_espn_game_odds(odds_fixture_json("espn_game_odds_2026_01_NE_SEA.json"), "2026_01_NE_SEA", sha256 = "b")`: could not find function "parse_espn_game_odds"
```

- [ ] **Step 4: implement.** Create `R/odds/provider_espn_core.R`:

````r
# =============================================================================
# ESPN core provider: game open/close lines and live DraftKings prop lines
# =============================================================================
# Keyless endpoints (see docs/odds-sources.md):
#   .../events/{id}/competitions/{id}/odds           game odds per provider. ESPN BET (58)
#       carries an open and a close block for every game from 2023; DraftKings (100)
#       replaces it late in 2025. The blocks have NO timestamp, so these rows are
#       snapshot_kind "open" / "close" with captured_at NA.
#   .../odds/100/propBets                            DraftKings prop LINES, live only
#       (404 after the game), no prices. Rows are line-only observations at fetch time.
# A provider item that is not in ESPN_GAME_VENUES or has neither an open nor a close
# moneyline block (Bet 365) is skipped and named in attr(, "skipped_providers"); a phase
# whose block is absent produces no rows for that phase; a prop type that
# is not mapped is named in attr(, "unmapped_types"). Nothing is guessed.
# URL builders and the scoreboard parser come from R/capture_raw.R.
# =============================================================================

ESPN_GAME_VENUES <- c("58" = "espn_bet", "100" = "draftkings")
ESPN_PROP_PROVIDER_ID <- 100L
ESPN_PROP_MARKETS <- c(
  "Total Passing Yards (incl. overtime)" = "passing_yards",
  "Total Rushing Yards (incl. overtime)" = "rushing_yards",
  "Total Receiving Yards (incl. overtime)" = "receiving_yards",
  "Total Receptions (incl. overtime)" = "receptions"
)

# "-6.5", "+7", "o48", "PK" -> number (a pick'em is a handicap of 0); NA when unreadable
espn_number <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_real_)
  txt <- toupper(trimws(as.character(x)))
  if (txt %in% c("PK", "PICK", "EVEN")) return(0)
  suppressWarnings(as.numeric(gsub("[^0-9.+-]", "", txt)))
}

#' Normalize one ESPN game-odds response (parsed JSON) into snapshots
parse_espn_game_odds <- function(parsed, game_id, sha256) {
  rows <- list()
  skipped <- character()
  add <- function(venue, market, side, kind, line, price) {
    rows[[length(rows) + 1]] <<- data.frame(
      game_id = game_id, market_id = market, venue_id = venue, side = side, line = line,
      price_american = american_to_int(price %||% NA_character_), snapshot_kind = kind, source = "espn_core",
      raw_sha256 = sha256, stringsAsFactors = FALSE
    )
  }
  for (it in parsed$items %||% list()) {
    pid <- as.character(it$provider$id %||% NA)
    label <- paste(pid, it$provider$name %||% "")
    venue <- unname(ESPN_GAME_VENUES[pid])
    h <- it$homeTeamOdds
    a <- it$awayTeamOdds
    # a block that is absent yields no rows for that phase (ESPN BET has a close but no open
    # for 80 of the 285 games of 2023); only an item with neither is skipped
    has_blocks <- !is.null(h$open$moneyLine$american) || !is.null(h$close$moneyLine$american)
    if (is.na(venue) || !has_blocks) {
      skipped <- c(skipped, trimws(label))
      next
    }
    for (phase in c("open", "close")) {
      hp <- h[[phase]]
      ap <- a[[phase]]
      if (!is.null(hp$moneyLine$american) && !is.null(ap$moneyLine$american)) {
        add(venue, "moneyline", "home", phase, NA_real_, hp$moneyLine$american)
        add(venue, "moneyline", "away", phase, NA_real_, ap$moneyLine$american)
      }
      if (!is.na(espn_number(hp$pointSpread$american)) && !is.na(espn_number(ap$pointSpread$american))) {
        add(venue, "spread", "home", phase, espn_number(hp$pointSpread$american), hp$spread$american)
        add(venue, "spread", "away", phase, espn_number(ap$pointSpread$american), ap$spread$american)
      }
      tb <- it[[phase]]
      if (!is.na(espn_number(tb$total$american))) {
        add(venue, "total", "over", phase, espn_number(tb$total$american), tb$over$american)
        add(venue, "total", "under", phase, espn_number(tb$total$american), tb$under$american)
      }
    }
  }
  out <- if (length(rows)) new_odds_snapshots(do.call(rbind, rows)) else odds_snapshots_empty()
  attr(out, "skipped_providers") <- skipped
  out
}

#' Normalize one page of ESPN propBets (parsed JSON): current and open lines
parse_espn_prop_bets <- function(parsed, game_id, fetched_at, sha256) {
  rows <- list()
  unmapped <- character()
  for (it in parsed$items %||% list()) {
    type_name <- it$type$name %||% NA_character_
    market <- unname(ESPN_PROP_MARKETS[type_name])
    casino <- sub("^.*/casinos/([0-9]+).*$", "\\1", it$provider$`$ref` %||% "")
    venue <- unname(ESPN_GAME_VENUES[casino])
    if (is.na(market) || is.na(venue)) {
      if (is.na(market)) unmapped <- c(unmapped, type_name)
      next
    }
    athlete <- sub("^.*/athletes/([0-9]+).*$", "\\1", it$athlete$`$ref` %||% "")
    if (!grepl("^[0-9]+$", athlete)) next
    for (phase in c("current", "open")) {
      value <- it[[phase]]$target$value
      if (is.null(value)) next
      rows[[length(rows) + 1]] <- data.frame(
        game_id = game_id, market_id = market, venue_id = venue, player_key = paste0("espn:", athlete),
        side = "line", line = as.numeric(value),
        captured_at = if (phase == "current") fetched_at else as.POSIXct(NA, tz = "UTC"),
        snapshot_kind = if (phase == "current") "observed" else "open",
        source = "espn_core", raw_sha256 = sha256, stringsAsFactors = FALSE
      )
    }
  }
  out <- if (length(rows)) new_odds_snapshots(do.call(rbind, rows)) else odds_snapshots_empty()
  attr(out, "unmapped_types") <- unique(unmapped)
  out
}

provider_espn_core <- function(cfg = odds_http_config(), fetch_fn = odds_http_get, log_path = NULL,
                               now_fn = Sys.time, sleep_fn = Sys.sleep) {
  get <- function(url, source) {
    odds_fetch(url, cfg, fetch_fn = fetch_fn, log_path = log_path, source = source, now_fn = now_fn, sleep_fn = sleep_fn)
  }

  game_snapshots <- function(games, on_raw = NULL, ...) {
    parts <- list()
    fetches <- list()
    failed <- character()
    no_event <- character()
    blocked <- FALSE
    for (i in seq_len(nrow(games))) {
      g <- games[i, , drop = FALSE]
      if (i %% 50L == 0L) message(sprintf("ESPN game odds: %d/%d games", i, nrow(games)))
      if (is.na(g$espn) || !nzchar(g$espn)) {
        no_event <- c(no_event, g$game_id)
        next
      }
      rec <- get(espn_game_odds_url(g$espn), "espn_game_odds")
      fetches[[length(fetches) + 1]] <- odds_fetch_row(rec, g$espn)
      parsed <- odds_json(rec)
      if (is.null(parsed)) {
        failed <- c(failed, sprintf("%s (%s)", g$game_id, rec$error %||% "not JSON"))
        if (rec$blocked) {
          blocked <- TRUE
          break
        }
        next
      }
      if (!is.null(on_raw)) on_raw(g$espn, rec$body, rec)
      parts[[length(parts) + 1]] <- parse_espn_game_odds(parsed, g$game_id, rec$sha256)
    }
    snaps <- bind_odds_snapshots(parts)
    n_ok <- length(parts)
    detail <- sprintf("%d of %d games fetched", n_ok, nrow(games))
    if (length(no_event)) detail <- paste0(detail, sprintf("; %d game%s without an ESPN event id", length(no_event), if (length(no_event) == 1) "" else "s"))
    if (length(failed)) detail <- paste0(detail, "; failed: ", paste(utils::head(failed, 5), collapse = ", "))
    if (blocked) detail <- paste0(detail, "; blocked by the server, run stopped")
    status <- if (n_ok == 0) "unavailable" else if (length(failed) || blocked) "failed" else "ok"
    odds_result(snaps, source = "espn_core_game_odds", status = status, detail = detail,
                fetches = do.call(rbind, c(list(odds_fetches_empty()), fetches)))
  }

  prop_snapshots <- function(games, provider_id = ESPN_PROP_PROVIDER_ID, ...) {
    parts <- list()
    fetches <- list()
    gone <- character()
    for (i in seq_len(nrow(games))) {
      g <- games[i, , drop = FALSE]
      if (is.na(g$espn) || !nzchar(g$espn)) next
      page <- 1L
      n_pages <- 1L
      while (page <= n_pages) {
        rec <- get(espn_prop_bets_url(g$espn, provider_id, page), "espn_propbets")
        fetches[[length(fetches) + 1]] <- odds_fetch_row(rec, sprintf("%s_%s_p%d", g$espn, provider_id, page))
        parsed <- odds_json(rec)
        if (is.null(parsed)) {
          gone <- c(gone, sprintf("%s (%s)", g$game_id, rec$error %||% "not JSON"))
          break
        }
        if (page == 1L) n_pages <- max(1L, as.integer(parsed$pageCount %||% 1L))
        parts[[length(parts) + 1]] <- parse_espn_prop_bets(parsed, g$game_id, rec$fetched_at, rec$sha256)
        page <- page + 1L
      }
    }
    snaps <- bind_odds_snapshots(parts)
    detail <- sprintf("%d prop line rows", nrow(snaps))
    if (length(gone)) detail <- paste0(detail, "; no propBets for: ", paste(utils::head(gone, 5), collapse = ", "),
                                       " (DraftKings propBets are live only; they return 404 after the game)")
    status <- if (nrow(snaps) == 0 && length(gone)) "unavailable" else if (length(gone)) "failed" else "ok"
    odds_result(snaps, source = "espn_core_prop_lines", status = status, detail = detail,
                fetches = do.call(rbind, c(list(odds_fetches_empty()), fetches)))
  }

  #' Forward capture: scoreboard, then odds and propBets for each game inside the horizon.
  #' `fetch(source, key, url)` stores the raw response and returns its text, or NULL.
  capture <- function(fetch, now, cfg) {
    sb_text <- fetch("espn_scoreboard", "scoreboard", espn_scoreboard_url())
    if (is.null(sb_text)) return(invisible(FALSE))
    targets <- select_capture_events(parse_espn_scoreboard(sb_text), now, cfg$horizon_hours)
    message(sprintf("ESPN: %d game(s) kick off within %dh", nrow(targets), cfg$horizon_hours))
    for (event_id in targets$event_id) {
      fetch("espn_game_odds", event_id, espn_game_odds_url(event_id))
      for (provider_id in cfg$espn_prop_providers) {
        first <- fetch("espn_propbets", sprintf("%s_%s_p1", event_id, provider_id),
                       espn_prop_bets_url(event_id, provider_id, 1))
        if (is.null(first)) next
        for (page in seq_len(espn_page_count(first))[-1]) {
          fetch("espn_propbets", sprintf("%s_%s_p%d", event_id, provider_id, page),
                espn_prop_bets_url(event_id, provider_id, page))
        }
      }
    }
    invisible(TRUE)
  }

  new_odds_provider("espn_core", unname(ESPN_GAME_VENUES), game_snapshots = game_snapshots,
                    prop_snapshots = prop_snapshots, capture = capture)
}
````

- [ ] **Step 5: GREEN.** Run the test file: no failures, exit 0.
- [ ] **Step 6: commit.**

```bash
git add R/odds/provider_espn_core.R tests/testthat/test-odds-espn-core.R tests/testthat/fixtures/odds/espn_game_odds_2024_01_ARI_BUF.json tests/testthat/fixtures/odds/espn_game_odds_2026_01_NE_SEA.json
git commit -m "feat(odds): ESPN core provider, game open/close and DraftKings prop lines (D1)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 6: the Kalshi provider (*haiku* to transcribe, *sonnet* to review the fixtures)

**Files:** create the eight `tests/testthat/fixtures/odds/kalshi_*.json` fixtures, `tests/testthat/test-odds-kalshi.R`, `R/odds/provider_kalshi.R`.

The fixtures are trimmed REAL responses from the public Kalshi API fetched 2026-10-13 (no key): `/historical/cutoff`; the markets of the 2026-10-12 BUF at LA game (`KXNFLGAME`), its touchdown (`KXNFLTD`) and receiving-yards (`KXNFLRECYDS`) props; the live candles of two of them (the last four and three candles; the receiving-yards market opened after kickoff, so its pre-kickoff list is empty, which is real); and, for the historical endpoint form (`price.close`, not `price.close_dollars`), an August 2026 preseason market (CAR at ARI). No 2025 market is used.

- [ ] **Step 1: fixtures.** Create each file with exactly this content.

`tests/testthat/fixtures/odds/kalshi_cutoff.json`:

````json
{
 "market_positions_last_updated_ts": "2026-08-14T00:00:00Z",
 "market_settled_ts": "2026-08-14T00:00:00Z",
 "orders_updated_ts": "2026-09-29T00:00:00Z",
 "trades_created_ts": "2026-08-14T00:00:00Z"
}
````

`tests/testthat/fixtures/odds/kalshi_markets_game_live.json`:

````json
{
 "cursor": "",
 "markets": [
  {
   "ticker": "KXNFLGAME-26OCT12BUFLAR-LAR",
   "event_ticker": "KXNFLGAME-26OCT12BUFLAR",
   "title": "Los Angeles R wins",
   "yes_sub_title": "Los Angeles R",
   "status": "finalized",
   "result": "no",
   "open_time": "2026-09-29T04:06:00Z",
   "close_time": "2026-10-13T03:48:50Z",
   "expected_expiration_time": "2026-10-13T03:15:00Z",
   "last_price_dollars": "0.0100",
   "volume_fp": "46872394.60",
   "custom_strike": {
    "football_team": "422d5fd7-ad18-4c96-902d-6f7c50e4660f"
   },
   "strike_type": "structured",
   "market_type": "binary"
  },
  {
   "ticker": "KXNFLGAME-26OCT12BUFLAR-BUF",
   "event_ticker": "KXNFLGAME-26OCT12BUFLAR",
   "title": "Buffalo wins",
   "yes_sub_title": "Buffalo",
   "status": "finalized",
   "result": "yes",
   "open_time": "2026-09-29T04:06:00Z",
   "close_time": "2026-10-13T03:48:50Z",
   "expected_expiration_time": "2026-10-13T03:15:00Z",
   "last_price_dollars": "0.9900",
   "volume_fp": "57487787.45",
   "custom_strike": {
    "football_team": "f9acd396-ba35-4cae-a431-a44b2af707b0"
   },
   "strike_type": "structured",
   "market_type": "binary"
  }
 ]
}
````

`tests/testthat/fixtures/odds/kalshi_markets_td_live.json`:

````json
{
 "cursor": "",
 "markets": [
  {
   "ticker": "KXNFLTD-26OCT12BUFLAR-BUFJCOOK4-2",
   "event_ticker": "KXNFLTD-26OCT12BUFLAR",
   "title": "James Cook III: 2+ touchdowns",
   "yes_sub_title": "James Cook III: 2+",
   "status": "finalized",
   "result": "yes",
   "open_time": "2026-10-08T01:16:00Z",
   "close_time": "2026-10-13T03:20:08Z",
   "expected_expiration_time": "2026-10-13T03:15:00Z",
   "last_price_dollars": "0.9900",
   "volume_fp": "873371.17",
   "custom_strike": {
    "football_player": "28cbef9d-f049-419b-89d0-5dbf89d38eef",
    "football_team": "f9acd396-ba35-4cae-a431-a44b2af707b0"
   },
   "floor_strike": 1.5,
   "strike_type": "greater",
   "market_type": "binary"
  },
  {
   "ticker": "KXNFLTD-26OCT12BUFLAR-BUFJCOOK4-1",
   "event_ticker": "KXNFLTD-26OCT12BUFLAR",
   "title": "James Cook III: 1+ touchdowns",
   "yes_sub_title": "James Cook III: 1+",
   "status": "finalized",
   "result": "yes",
   "open_time": "2026-10-08T01:16:00Z",
   "close_time": "2026-10-13T01:15:30Z",
   "expected_expiration_time": "2026-10-13T03:15:00Z",
   "last_price_dollars": "0.9900",
   "volume_fp": "405927.72",
   "custom_strike": {
    "football_player": "28cbef9d-f049-419b-89d0-5dbf89d38eef",
    "football_team": "f9acd396-ba35-4cae-a431-a44b2af707b0"
   },
   "floor_strike": 0.5,
   "strike_type": "greater",
   "market_type": "binary"
  },
  {
   "ticker": "KXNFLTD-26OCT12BUFLAR-BUFJCOOK4-4",
   "event_ticker": "KXNFLTD-26OCT12BUFLAR",
   "title": "James Cook III: 4+ touchdowns",
   "yes_sub_title": "James Cook III: 4+",
   "status": "finalized",
   "result": "no",
   "open_time": "2026-10-13T03:29:00Z",
   "close_time": "2026-10-13T03:57:18Z",
   "expected_expiration_time": "2026-10-13T06:15:00Z",
   "last_price_dollars": "0.0100",
   "volume_fp": "733.82",
   "custom_strike": {
    "football_player": "28cbef9d-f049-419b-89d0-5dbf89d38eef",
    "football_team": "f9acd396-ba35-4cae-a431-a44b2af707b0"
   },
   "floor_strike": 3.5,
   "strike_type": "greater",
   "market_type": "binary"
  }
 ]
}
````

`tests/testthat/fixtures/odds/kalshi_markets_recyds_live.json`:

````json
{
 "cursor": "",
 "markets": [
  {
   "ticker": "KXNFLRECYDS-26OCT12BUFLAR-BUFTJOHNSON26-75",
   "event_ticker": "KXNFLRECYDS-26OCT12BUFLAR",
   "title": "Ty Johnson: 75+ receiving yards",
   "yes_sub_title": "Ty Johnson: 75+",
   "status": "finalized",
   "result": "no",
   "open_time": "2026-10-13T03:32:00Z",
   "close_time": "2026-10-13T03:57:24Z",
   "expected_expiration_time": "2026-10-13T06:15:00Z",
   "last_price_dollars": "0.0200",
   "volume_fp": "52.00",
   "custom_strike": {
    "football_player": "a2f1b838-3ddb-43f5-b1ff-aca7c57d9c5d",
    "football_team": "f9acd396-ba35-4cae-a431-a44b2af707b0"
   },
   "floor_strike": 74.5,
   "strike_type": "greater",
   "market_type": "binary"
  }
 ]
}
````

`tests/testthat/fixtures/odds/kalshi_markets_game_historical.json`:

````json
{
 "cursor": "",
 "markets": [
  {
   "ticker": "KXNFLGAME-26AUG06CARARI-CAR",
   "event_ticker": "KXNFLGAME-26AUG06CARARI",
   "title": "Will Carolina win the Carolina vs Arizona Pro Football game?",
   "yes_sub_title": "Carolina",
   "status": "finalized",
   "result": "yes",
   "open_time": "2026-06-29T18:01:00Z",
   "close_time": "2026-08-07T03:05:24Z",
   "expected_expiration_time": "2026-08-07T06:00:00Z",
   "last_price_dollars": "0.9900",
   "volume_fp": "6891841.66",
   "custom_strike": {
    "football_team": "e37050ce-354f-4dd0-b2d8-0bd1e9650eb7"
   },
   "strike_type": "structured",
   "market_type": "binary"
  },
  {
   "ticker": "KXNFLGAME-26AUG06CARARI-ARI",
   "event_ticker": "KXNFLGAME-26AUG06CARARI",
   "title": "Will Arizona win the Carolina vs Arizona Pro Football game?",
   "yes_sub_title": "Arizona",
   "status": "finalized",
   "result": "no",
   "open_time": "2026-06-29T18:01:00Z",
   "close_time": "2026-08-07T03:05:24Z",
   "expected_expiration_time": "2026-08-07T06:00:00Z",
   "last_price_dollars": "0.0100",
   "volume_fp": "6077734.63",
   "custom_strike": {
    "football_team": "d73dae4f-1f08-4b5e-bf23-4e25e9b6a69c"
   },
   "strike_type": "structured",
   "market_type": "binary"
  }
 ]
}
````

`tests/testthat/fixtures/odds/kalshi_candles_game_live.json`:

````json
{
 "candlesticks": [
  {
   "end_period_ts": 1791838800,
   "open_interest_fp": "5378697.59",
   "price": {
    "close_dollars": "0.3900",
    "high_dollars": "0.3900",
    "low_dollars": "0.3800",
    "mean_dollars": "0.3898",
    "open_dollars": "0.3900",
    "previous_dollars": "0.3900"
   },
   "volume_fp": "641348.43",
   "yes_ask": {
    "close_dollars": "0.3900",
    "high_dollars": "0.3900",
    "low_dollars": "0.3900",
    "open_dollars": "0.3900"
   },
   "yes_bid": {
    "close_dollars": "0.3800",
    "high_dollars": "0.3800",
    "low_dollars": "0.3800",
    "open_dollars": "0.3800"
   }
  },
  {
   "end_period_ts": 1791842400,
   "open_interest_fp": "5969864.16",
   "price": {
    "close_dollars": "0.3900",
    "high_dollars": "0.3900",
    "low_dollars": "0.3800",
    "mean_dollars": "0.3896",
    "open_dollars": "0.3900",
    "previous_dollars": "0.3900"
   },
   "volume_fp": "642764.09",
   "yes_ask": {
    "close_dollars": "0.3900",
    "high_dollars": "0.3900",
    "low_dollars": "0.3900",
    "open_dollars": "0.3900"
   },
   "yes_bid": {
    "close_dollars": "0.3800",
    "high_dollars": "0.3800",
    "low_dollars": "0.3800",
    "open_dollars": "0.3800"
   }
  },
  {
   "end_period_ts": 1791846000,
   "open_interest_fp": "6967457.37",
   "price": {
    "close_dollars": "0.3900",
    "high_dollars": "0.3900",
    "low_dollars": "0.3800",
    "mean_dollars": "0.3899",
    "open_dollars": "0.3900",
    "previous_dollars": "0.3900"
   },
   "volume_fp": "1025324.66",
   "yes_ask": {
    "close_dollars": "0.3900",
    "high_dollars": "0.3900",
    "low_dollars": "0.3900",
    "open_dollars": "0.3900"
   },
   "yes_bid": {
    "close_dollars": "0.3800",
    "high_dollars": "0.3800",
    "low_dollars": "0.3800",
    "open_dollars": "0.3800"
   }
  },
  {
   "end_period_ts": 1791849600,
   "open_interest_fp": "9100560.64",
   "price": {
    "close_dollars": "0.3900",
    "high_dollars": "0.3900",
    "low_dollars": "0.3800",
    "mean_dollars": "0.3898",
    "open_dollars": "0.3900",
    "previous_dollars": "0.3900"
   },
   "volume_fp": "2210163.70",
   "yes_ask": {
    "close_dollars": "0.3900",
    "high_dollars": "0.3900",
    "low_dollars": "0.3900",
    "open_dollars": "0.3900"
   },
   "yes_bid": {
    "close_dollars": "0.3800",
    "high_dollars": "0.3800",
    "low_dollars": "0.3800",
    "open_dollars": "0.3800"
   }
  }
 ],
 "ticker": "KXNFLGAME-26OCT12BUFLAR-BUF"
}
````

`tests/testthat/fixtures/odds/kalshi_candles_td_live.json`:

````json
{
 "candlesticks": [
  {
   "end_period_ts": 1791842400,
   "open_interest_fp": "65408.51",
   "price": {
    "close_dollars": "0.5000",
    "high_dollars": "0.5000",
    "low_dollars": "0.4900",
    "mean_dollars": "0.4997",
    "open_dollars": "0.5000",
    "previous_dollars": "0.5000"
   },
   "volume_fp": "17087.00",
   "yes_ask": {
    "close_dollars": "0.5000",
    "high_dollars": "0.5000",
    "low_dollars": "0.5000",
    "open_dollars": "0.5000"
   },
   "yes_bid": {
    "close_dollars": "0.4900",
    "high_dollars": "0.4900",
    "low_dollars": "0.4900",
    "open_dollars": "0.4900"
   }
  },
  {
   "end_period_ts": 1791846000,
   "open_interest_fp": "86935.59",
   "price": {
    "close_dollars": "0.5000",
    "high_dollars": "0.5000",
    "low_dollars": "0.4900",
    "mean_dollars": "0.4990",
    "open_dollars": "0.5000",
    "previous_dollars": "0.5000"
   },
   "volume_fp": "22843.78",
   "yes_ask": {
    "close_dollars": "0.5000",
    "high_dollars": "0.5000",
    "low_dollars": "0.5000",
    "open_dollars": "0.5000"
   },
   "yes_bid": {
    "close_dollars": "0.4900",
    "high_dollars": "0.4900",
    "low_dollars": "0.4900",
    "open_dollars": "0.4900"
   }
  },
  {
   "end_period_ts": 1791849600,
   "open_interest_fp": "124892.99",
   "price": {
    "close_dollars": "0.5000",
    "high_dollars": "0.5000",
    "low_dollars": "0.4900",
    "mean_dollars": "0.4999",
    "open_dollars": "0.5000",
    "previous_dollars": "0.5000"
   },
   "volume_fp": "38249.16",
   "yes_ask": {
    "close_dollars": "0.5000",
    "high_dollars": "0.5000",
    "low_dollars": "0.5000",
    "open_dollars": "0.5000"
   },
   "yes_bid": {
    "close_dollars": "0.4900",
    "high_dollars": "0.4900",
    "low_dollars": "0.4900",
    "open_dollars": "0.4900"
   }
  }
 ],
 "ticker": "KXNFLTD-26OCT12BUFLAR-BUFJCOOK4-1"
}
````

`tests/testthat/fixtures/odds/kalshi_candles_recyds_live.json`:

````json
{
 "candlesticks": [],
 "ticker": "KXNFLRECYDS-26OCT12BUFLAR-BUFTJOHNSON26-75"
}
````

`tests/testthat/fixtures/odds/kalshi_candles_game_historical.json`:

````json
{
 "candlesticks": [
  {
   "end_period_ts": 1786053600,
   "open_interest": "570458.31",
   "price": {
    "close": "0.5300",
    "high": "0.5300",
    "low": "0.5200",
    "mean": "0.5298",
    "open": "0.5300",
    "previous": "0.5300"
   },
   "volume": "106363.30",
   "yes_ask": {
    "close": "0.5300",
    "high": "0.5300",
    "low": "0.5300",
    "open": "0.5300"
   },
   "yes_bid": {
    "close": "0.5200",
    "high": "0.5200",
    "low": "0.5200",
    "open": "0.5200"
   }
  },
  {
   "end_period_ts": 1786057200,
   "open_interest": "734985.17",
   "price": {
    "close": "0.5300",
    "high": "0.5300",
    "low": "0.5200",
    "mean": "0.5298",
    "open": "0.5300",
    "previous": "0.5300"
   },
   "volume": "170999.15",
   "yes_ask": {
    "close": "0.5300",
    "high": "0.5300",
    "low": "0.5300",
    "open": "0.5300"
   },
   "yes_bid": {
    "close": "0.5200",
    "high": "0.5200",
    "low": "0.5200",
    "open": "0.5200"
   }
  },
  {
   "end_period_ts": 1786060800,
   "open_interest": "1329788.90",
   "price": {
    "close": "0.5300",
    "high": "0.5300",
    "low": "0.5200",
    "mean": "0.5299",
    "open": "0.5300",
    "previous": "0.5300"
   },
   "volume": "602880.19",
   "yes_ask": {
    "close": "0.5300",
    "high": "0.5300",
    "low": "0.5300",
    "open": "0.5300"
   },
   "yes_bid": {
    "close": "0.5200",
    "high": "0.5200",
    "low": "0.5200",
    "open": "0.5200"
   }
  }
 ],
 "ticker": "KXNFLGAME-26AUG06CARARI-CAR"
}
````

- [ ] **Step 2: write the test.** Create `tests/testthat/test-odds-kalshi.R`:

````r
# =============================================================================
# Tests: the Kalshi provider (R/odds/provider_kalshi.R)
# Fixtures in fixtures/odds/ are trimmed REAL responses from the public Kalshi API
# (fetched 2026-10-13): the 2026-10-12 BUF at LA game, its touchdown and receiving
# yards props, an August 2026 preseason market for the historical endpoint form, and
# /historical/cutoff. Every fetch goes through odds_fake_fetch(): no network.
# =============================================================================

KO <- as.POSIXct("2026-10-13 00:15:00", tz = "UTC")      # BUF at LA, Monday night
GAME_K <- data.frame(game_id = "2026_05_BUF_LA", season = 2026L, week = 5L, gameday = "2026-10-12",
                     kickoff_utc = KO, home_team = "LA", away_team = "BUF", espn = "401872994",
                     stringsAsFactors = FALSE)
PRE_KO <- as.POSIXct("2026-08-07 00:00:00", tz = "UTC")  # CAR at ARI, preseason (not an nflverse game)
GAME_PRE <- data.frame(game_id = "pre_2026_08_06_CAR_ARI", season = 2026L, week = 0L, gameday = "2026-08-06",
                       kickoff_utc = PRE_KO, home_team = "ARI", away_team = "CAR", espn = NA_character_,
                       stringsAsFactors = FALSE)
TS <- function(t) as.integer(as.numeric(t))
EV_GAME <- "KXNFLGAME-26OCT12BUFLAR"
empty_markets <- list(text = '{"markets": [], "cursor": ""}')
empty_candles <- list(text = '{"candlesticks": []}')

kalshi_provider <- function(routes, clock = odds_fake_clock()) {
  odds_http_reset()
  fake <- odds_fake_fetch(routes)
  list(provider = provider_kalshi(cfg = odds_http_config(), fetch_fn = fake$fn, now_fn = clock$now, sleep_fn = clock$sleep),
       fake = fake, clock = clock)
}

test_that("Kalshi URLs are built exactly", {
  b <- "https://api.elections.kalshi.com/trade-api/v2"
  expect_equal(kalshi_cutoff_url(), paste0(b, "/historical/cutoff"))
  expect_equal(kalshi_event_markets_url(EV_GAME, historical = FALSE),
               paste0(b, "/markets?event_ticker=", EV_GAME, "&limit=1000"))
  expect_equal(kalshi_event_markets_url(EV_GAME, historical = TRUE, cursor = "a b"),
               paste0(b, "/historical/markets?event_ticker=", EV_GAME, "&limit=1000&cursor=a%20b"))
  expect_equal(kalshi_candles_url("KXNFLGAME", "KXNFLGAME-X-BUF", 10L, 20L, historical = FALSE),
               paste0(b, "/series/KXNFLGAME/markets/KXNFLGAME-X-BUF/candlesticks?start_ts=10&end_ts=20&period_interval=60"))
  expect_equal(kalshi_candles_url("KXNFLGAME", "KXNFLGAME-X-BUF", 10L, 20L, historical = TRUE),
               paste0(b, "/historical/markets/KXNFLGAME-X-BUF/candlesticks?start_ts=10&end_ts=20&period_interval=60"))
})

test_that("event tickers are built from the game, trying each spelling of JAX and LA", {
  expect_equal(kalshi_candidate_events("KXNFLGAME", GAME_K), c("KXNFLGAME-26OCT12BUFLA", "KXNFLGAME-26OCT12BUFLAR"))
  jax <- transform(GAME_K, home_team = "JAX", away_team = "KC", gameday = "2026-09-13")
  expect_equal(kalshi_candidate_events("KXNFLTD", jax), c("KXNFLTD-26SEP13KCJAX", "KXNFLTD-26SEP13KCJAC"))
  expect_equal(kalshi_candidate_events("KXNFLGAME", GAME_K, date_offsets = c(0L, 1L))[3], "KXNFLGAME-26OCT13BUFLA")
  expect_equal(kalshi_parse_event_ticker("KXNFLTD-26SEP28PHICHI")$date, as.Date("2026-09-28"))
  expect_true(is.na(kalshi_parse_event_ticker("KXNFLWINS-NO")$date))
})

test_that("a market maps to a moneyline side, a prop market and a strike, or is named as unsupported", {
  game_markets <- odds_fixture_json("kalshi_markets_game_live.json")$markets
  by_ticker <- setNames(game_markets, vapply(game_markets, `[[`, "", "ticker"))
  away <- kalshi_market_meta(by_ticker[["KXNFLGAME-26OCT12BUFLAR-BUF"]], GAME_K, "KXNFLGAME")
  home <- kalshi_market_meta(by_ticker[["KXNFLGAME-26OCT12BUFLAR-LAR"]], GAME_K, "KXNFLGAME")
  expect_equal(c(away$market_id, away$side), c("moneyline", "away"))
  expect_equal(home$side, "home")                                   # Kalshi spells the Rams LAR; nflverse says LA

  td <- odds_fixture_json("kalshi_markets_td_live.json")$markets
  metas <- lapply(td, kalshi_market_meta, game = GAME_K, series = "KXNFLTD")
  ok <- Filter(function(m) m$ok, metas)
  expect_setequal(vapply(ok, `[[`, "", "market_id"), c("anytime_td", "td_2plus"))
  expect_equal(unique(vapply(ok, `[[`, "", "side")), "yes")
  expect_equal(unique(vapply(ok, `[[`, "", "player_key")), "kalshi:28cbef9d-f049-419b-89d0-5dbf89d38eef")
  bad <- Filter(function(m) !m$ok, metas)
  expect_length(bad, 1)
  expect_match(bad[[1]]$reason, "strike 3.5")

  rec <- kalshi_market_meta(odds_fixture_json("kalshi_markets_recyds_live.json")$markets[[1]], GAME_K, "KXNFLRECYDS")
  expect_equal(c(rec$market_id, rec$line), c("receiving_yards", "74.5"))
  expect_false(kalshi_market_meta(list(ticker = "KXNFLSPREAD-X-BUF"), GAME_K, "KXNFLSPREAD")$ok)
  expect_false(kalshi_market_meta(list(ticker = "KXNFLGAME-X-ZZZ"), GAME_K, "KXNFLGAME")$ok)   # team code matches neither side
})

test_that("candles from both endpoint forms normalize to bid, ask, last and volume", {
  meta <- list(ok = TRUE, market_id = "moneyline", side = "away", line = NA_real_, player_key = NA_character_)
  live <- parse_kalshi_candles(odds_fixture_json("kalshi_candles_game_live.json"), meta, "2026_05_BUF_LA", "e", "kalshi_live")
  expect_equal(nrow(live), 4)
  expect_equal(validate_odds_snapshots(live), character())
  expect_equal(unique(live$snapshot_kind), "candle")
  expect_equal(unique(live$venue_id), "kalshi")
  expect_true(all(live$bid <= live$ask))
  expect_equal(max(live$captured_at), as.POSIXct("2026-10-13 00:00:00", tz = "UTC"))
  hist <- parse_kalshi_candles(odds_fixture_json("kalshi_candles_game_historical.json"), meta, "g", "h", "kalshi_historical")
  expect_equal(nrow(hist), 3)                                        # the historical form says price.close, not price.close_dollars
  expect_false(anyNA(hist$bid) || anyNA(hist$ask) || anyNA(hist$last))
  expect_equal(unique(hist$source), "kalshi_historical")
  # a candle with no trade has no last price, and that stays NA
  untraded <- odds_fixture_json("kalshi_candles_game_live.json")
  untraded$candlesticks[[1]]$price <- NULL
  expect_true(is.na(parse_kalshi_candles(untraded, meta, "g", "e", "kalshi_live")$last[1]))
  expect_equal(nrow(parse_kalshi_candles(list(candlesticks = list()), meta, "g", "e", "kalshi_live")), 0)
})

test_that("kalshi_mid needs a genuine two-sided quote", {
  expect_equal(kalshi_mid(c(.48, 0, .40, .55), c(.50, .5, 1, .50)), c(.49, NA, NA, NA))
})

test_that("game_snapshots tries each spelling, reads live candles and feeds the closing rule", {
  b <- list()
  b[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  b[[kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLA", FALSE)]] <- empty_markets
  b[[kalshi_event_markets_url(EV_GAME, FALSE)]] <- "kalshi_markets_game_live.json"
  b[[kalshi_candles_url("KXNFLGAME", "KXNFLGAME-26OCT12BUFLAR-BUF", TS(KO) - 48L * 3600L, TS(KO), FALSE)]] <- "kalshi_candles_game_live.json"
  b[[kalshi_candles_url("KXNFLGAME", "KXNFLGAME-26OCT12BUFLAR-LAR", TS(KO) - 48L * 3600L, TS(KO), FALSE)]] <- empty_candles
  k <- kalshi_provider(b)
  res <- k$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "ok")
  s <- res$snapshots
  expect_equal(nrow(s), 4)
  expect_equal(unique(s$side), "away")                               # BUF is the away team
  expect_equal(unique(s$source), "kalshi_live")
  expect_match(res$source_status$detail, "1 market without candles")
  expect_equal(res$fetches$source[1], "kalshi_cutoff")
  expect_true(all(grepl("^[0-9a-f]{64}$", res$fetches$raw_sha256)))
  close <- select_closing_snapshots(s, data.frame(game_id = "2026_05_BUF_LA", kickoff_utc = KO))
  expect_equal(nrow(close), 1)
  expect_equal(close$close_gap_min, 15)
  expect_true(close$headline_eligible)
})

test_that("a game that kicked off before Kalshi's historical cutoff reads the historical endpoints only", {
  b <- list()
  b[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  b[[kalshi_event_markets_url("KXNFLGAME-26AUG06CARARI", TRUE)]] <- "kalshi_markets_game_historical.json"
  b[[kalshi_candles_url("KXNFLGAME", "KXNFLGAME-26AUG06CARARI-CAR", TS(PRE_KO) - 48L * 3600L, TS(PRE_KO), TRUE)]] <- "kalshi_candles_game_historical.json"
  b[[kalshi_candles_url("KXNFLGAME", "KXNFLGAME-26AUG06CARARI-ARI", TS(PRE_KO) - 48L * 3600L, TS(PRE_KO), TRUE)]] <- list(status = 404L)
  b[[kalshi_candles_url("KXNFLGAME", "KXNFLGAME-26AUG06CARARI-ARI", TS(PRE_KO) - 48L * 3600L, TS(PRE_KO), FALSE)]] <- list(status = 404L)
  k <- kalshi_provider(b)
  res <- k$provider$game_snapshots(GAME_PRE)
  expect_equal(res$source_status$status, "ok")
  expect_equal(unique(res$snapshots$source), "kalshi_historical")
  expect_equal(unique(res$snapshots$side), "away")                   # CAR is the away team
  expect_match(res$source_status$detail, "1 market without candles")
  expect_equal(sum(grepl("/series/", k$fake$state$urls)), 1)        # a live candle request only as the fallback for the 404
})

test_that("props: unsupported strikes are named, markets opened after kickoff have no candles, nothing is invented", {
  b <- list()
  b[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  b[[kalshi_event_markets_url("KXNFLTD-26OCT12BUFLA", FALSE)]] <- empty_markets
  b[[kalshi_event_markets_url("KXNFLTD-26OCT12BUFLAR", FALSE)]] <- "kalshi_markets_td_live.json"
  b[[kalshi_event_markets_url("KXNFLRECYDS-26OCT12BUFLA", FALSE)]] <- empty_markets
  b[[kalshi_event_markets_url("KXNFLRECYDS-26OCT12BUFLAR", FALSE)]] <- "kalshi_markets_recyds_live.json"
  win <- function(series, ticker) kalshi_candles_url(series, ticker, TS(KO) - 48L * 3600L, TS(KO), FALSE)
  b[[win("KXNFLTD", "KXNFLTD-26OCT12BUFLAR-BUFJCOOK4-1")]] <- "kalshi_candles_td_live.json"
  b[[win("KXNFLTD", "KXNFLTD-26OCT12BUFLAR-BUFJCOOK4-2")]] <- empty_candles
  b[[win("KXNFLRECYDS", "KXNFLRECYDS-26OCT12BUFLAR-BUFTJOHNSON26-75")]] <- "kalshi_candles_recyds_live.json"
  k <- kalshi_provider(b)
  res <- k$provider$prop_snapshots(GAME_K, series = c("KXNFLTD", "KXNFLRECYDS"))
  s <- res$snapshots
  expect_equal(res$source_status$status, "ok")
  expect_equal(nrow(s), 3)                                           # Cook 1+ only: three candles
  expect_equal(unique(s$market_id), "anytime_td")
  expect_equal(unique(s$line), 0.5)
  expect_equal(unique(s$player_key), "kalshi:28cbef9d-f049-419b-89d0-5dbf89d38eef")
  expect_equal(unique(s$side), "yes")
  expect_match(res$source_status$detail, "1 unsupported")
  expect_match(res$source_status$detail, "2 markets without candles")
  expect_false(any(grepl("JCOOK4-4", k$fake$state$urls)))           # no candle request for an unsupported strike
})

test_that("a server error is reported as a failure and does not stop the other games", {
  b <- list()
  b[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  b[[kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLA", FALSE)]] <- list(status = 500L)
  b[[kalshi_event_markets_url(EV_GAME, FALSE)]] <- "kalshi_markets_game_live.json"
  b[[kalshi_candles_url("KXNFLGAME", "KXNFLGAME-26OCT12BUFLAR-BUF", TS(KO) - 48L * 3600L, TS(KO), FALSE)]] <- "kalshi_candles_game_live.json"
  b[[kalshi_candles_url("KXNFLGAME", "KXNFLGAME-26OCT12BUFLAR-LAR", TS(KO) - 48L * 3600L, TS(KO), FALSE)]] <- "kalshi_candles_game_live.json"
  res <- kalshi_provider(b)$provider$game_snapshots(GAME_K)
  expect_equal(res$source_status$status, "failed")
  expect_match(res$source_status$detail, "HTTP 500")
  expect_equal(nrow(res$snapshots), 8)
})

test_that("a game with no kickoff is skipped and counted", {
  g <- transform(GAME_K, kickoff_utc = as.POSIXct(NA, tz = "UTC"))
  b <- list()
  b[[kalshi_cutoff_url()]] <- "kalshi_cutoff.json"
  res <- kalshi_provider(b)$provider$game_snapshots(g)
  expect_equal(res$source_status$status, "unavailable")
  expect_match(res$source_status$detail, "1 game without a kickoff")
})

test_that("the forward-capture pass stores per-game NFL series only", {
  odds_http_reset()
  fetched <- character()
  fetch <- function(source, key, url) {
    fetched <<- c(fetched, paste(source, key, sep = ":"))
    if (source == "kalshi_series") {
      return('{"series": [{"ticker": "KXNFLTD"}, {"ticker": "KXNFLGAME"}, {"ticker": "KXNFLWINS-NO"}, {"ticker": "KXNBAGAME"}]}')
    }
    '{"markets": [], "cursor": ""}'
  }
  provider_kalshi()$capture(fetch, now = Sys.time(), cfg = list())
  expect_equal(fetched, c("kalshi_series:sports", "kalshi_markets:KXNFLGAME_p1", "kalshi_markets:KXNFLTD_p1"))
})

test_that("the Kalshi provider satisfies the provider interface", {
  p <- provider_kalshi()
  expect_equal(validate_odds_provider(p), character())
  expect_equal(p$venue_ids, "kalshi")
})
````

- [ ] **Step 3: RED.** Expected with `R/odds/provider_kalshi.R` absent:

```
── 1. Error ('test-odds-kalshi.R:31:3'): Kalshi URLs are built exactly ─────────
Error in `kalshi_cutoff_url()`: could not find function "kalshi_cutoff_url"
── 2. Error ('test-odds-kalshi.R:43:3'): event tickers are built from the game,
Error in `kalshi_candidate_events("KXNFLGAME", GAME_K)`: could not find function "kalshi_candidate_events"
```

- [ ] **Step 4: implement.** Create `R/odds/provider_kalshi.R`:

````r
# =============================================================================
# Kalshi provider: game and player-prop contracts, hourly candles (roadmap D1)
# =============================================================================
# Public market data, no key (see docs/odds-sources.md):
#   /historical/cutoff                                         the date after which settled markets leave /historical
#   /markets?event_ticker=E                                    live markets of an event
#   /historical/markets?event_ticker=E                         markets settled before the cutoff
#   /series/S/markets/T/candlesticks?...&period_interval=60    live candles
#   /historical/markets/T/candlesticks?...                     historical candles
# The cutoff moves (2026-07-31 on 2026-09-29, 2026-08-14 on 2026-10-13), so it is read at
# run time. Each event tries the side of the cutoff it falls on first and falls back to
# the other side on a 404 or an empty list. The two candle forms differ in field names
# (price.close vs price.close_dollars), and both are parsed.
# One row per candle: captured_at is the candle's end, bid/ask/last are the yes-side
# close in dollars, volume is the candle volume. The Kalshi close is the mid of the last
# pre-kickoff candle (kalshi_mid), chosen by select_closing_snapshots().
# Supported contracts: KXNFLGAME (moneyline) and the player series below. Spread and total
# series are not mapped yet; a market that cannot be mapped is counted, never guessed.
# =============================================================================

KALSHI_GAME_SERIES <- "KXNFLGAME"
KALSHI_SERIES_MARKETS <- c(
  KXNFLGAME = "moneyline", KXNFLANYTD = "anytime_td", KXNFL2TD = "td_2plus", KXNFLFIRSTTD = "first_td",
  KXNFLRECYDS = "receiving_yards", KXNFLRSHYDS = "rushing_yards", KXNFLPASSYDS = "passing_yards",
  KXNFLREC = "receptions"
)
# KXNFLTD holds 1+/2+/3+/4+ touchdown strikes as separate markets; only 1+ and 2+ map to a market
KALSHI_TD_LADDER <- c("0.5" = "anytime_td", "1.5" = "td_2plus")
KALSHI_PROP_SERIES <- c("KXNFLANYTD", "KXNFLTD", "KXNFL2TD", "KXNFLFIRSTTD", "KXNFLRECYDS", "KXNFLRSHYDS",
                        "KXNFLPASSYDS", "KXNFLREC")
KALSHI_PAGE_LIMIT <- 1000L
KALSHI_MAX_PAGES <- 20L
KALSHI_MONTHS <- c("JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC")

kalshi_cutoff_url <- function() paste0(KALSHI_BASE, "/historical/cutoff")

kalshi_event_markets_url <- function(event_ticker, historical, cursor = NULL) {
  url <- sprintf("%s/%smarkets?event_ticker=%s&limit=%d", KALSHI_BASE, if (historical) "historical/" else "",
                 utils::URLencode(event_ticker, reserved = TRUE), KALSHI_PAGE_LIMIT)
  if (!is.null(cursor) && nzchar(cursor)) url <- paste0(url, "&cursor=", utils::URLencode(cursor, reserved = TRUE))
  url
}

kalshi_candles_url <- function(series, ticker, start_ts, end_ts, historical, period_minutes = 60L) {
  path <- if (historical) sprintf("historical/markets/%s", ticker) else sprintf("series/%s/markets/%s", series, ticker)
  sprintf("%s/%s/candlesticks?start_ts=%d&end_ts=%d&period_interval=%d", KALSHI_BASE, path,
          as.integer(start_ts), as.integer(end_ts), as.integer(period_minutes))
}

# Kalshi writes Jacksonville as JAC, and the Rams as LA (2025 tickers) or LAR (2026 tickers)
kalshi_spellings <- function(team) {
  switch(team, JAX = c("JAX", "JAC"), JAC = c("JAX", "JAC"), LA = c("LA", "LAR"), LAR = c("LA", "LAR"), team)
}

kalshi_date_code <- function(date) {
  sprintf("%s%s%02d", format(date, "%y"), KALSHI_MONTHS[as.integer(format(date, "%m"))], as.integer(format(date, "%d")))
}

#' Candidate event tickers for a game: SERIES-YYMONDD + AWAY + HOME, over every spelling
#' of the two teams and every date offset (days from the ET game day)
kalshi_candidate_events <- function(series, game, date_offsets = 0L) {
  base_date <- as.Date(game$gameday)
  away <- kalshi_spellings(game$away_team)
  home <- kalshi_spellings(game$home_team)
  suffixes <- as.vector(outer(away, home, paste0))
  unlist(lapply(date_offsets, function(d) paste0(series, "-", kalshi_date_code(base_date + d), suffixes)))
}

kalshi_parse_event_ticker <- function(event_ticker) {
  m <- regmatches(event_ticker, regexpr("-[0-9]{2}[A-Z]{3}[0-9]{2}", event_ticker))
  if (length(m) == 0) return(list(date = as.Date(NA), suffix = NA_character_))
  code <- sub("^-", "", m)
  month <- match(substr(code, 3, 5), KALSHI_MONTHS)
  list(date = as.Date(sprintf("20%s-%02d-%s", substr(code, 1, 2), month, substr(code, 6, 7))),
       suffix = sub("^.*-[0-9]{2}[A-Z]{3}[0-9]{2}", "", event_ticker))
}

kalshi_num <- function(x) if (is.null(x) || length(x) == 0) NA_real_ else suppressWarnings(as.numeric(x))

#' How one Kalshi market maps to (market_id, side, line, player_key).
#' @return list(ok = TRUE, market_id, side, line, player_key) or list(ok = FALSE, reason)
kalshi_market_meta <- function(market, game, series) {
  no <- function(reason) list(ok = FALSE, reason = reason)
  ticker <- market$ticker %||% ""
  if (series == KALSHI_GAME_SERIES) {
    code <- sub("^.*-", "", ticker)
    side <- if (code %in% kalshi_spellings(game$home_team)) "home" else if (code %in% kalshi_spellings(game$away_team)) "away" else NA_character_
    if (is.na(side)) return(no(sprintf("team code %s matches neither side of %s", code, game$game_id)))
    return(list(ok = TRUE, market_id = "moneyline", side = side, line = NA_real_, player_key = NA_character_))
  }
  player <- market$custom_strike$football_player
  if (is.null(player)) return(no(sprintf("%s has no player in custom_strike", ticker)))
  strike <- kalshi_num(market$floor_strike)
  if (series == "KXNFLTD") {
    market_id <- unname(KALSHI_TD_LADDER[format(strike, nsmall = 1)])
    if (is.na(market_id)) return(no(sprintf("strike %s is not mapped for KXNFLTD", strike)))
  } else {
    market_id <- unname(KALSHI_SERIES_MARKETS[series])
    if (is.na(market_id)) return(no(sprintf("series %s is not supported", series)))
  }
  # a touchdown market's strike is its definition: anytime = more than 0.5, 2+ = more than 1.5
  if (is.na(strike)) strike <- switch(market_id, anytime_td = 0.5, td_2plus = 1.5, NA_real_)
  list(ok = TRUE, market_id = market_id, side = "yes", line = strike, player_key = paste0("kalshi:", player))
}

#' Mid price from a genuine two-sided quote (0 < bid <= ask < 1); otherwise NA
kalshi_mid <- function(bid, ask) {
  ok <- !is.na(bid) & !is.na(ask) & bid > 0 & ask < 1 & bid <= ask
  ifelse(ok, (bid + ask) / 2, NA_real_)
}

#' Normalize a candlesticks response (either endpoint form) into snapshots
parse_kalshi_candles <- function(parsed, meta, game_id, sha256, source) {
  candles <- parsed$candlesticks %||% list()
  if (length(candles) == 0) return(odds_snapshots_empty())
  field <- function(obj, name) kalshi_num(obj[[name]] %||% obj[[paste0(name, "_dollars")]])
  rows <- lapply(candles, function(cd) {
    data.frame(
      game_id = game_id, market_id = meta$market_id, venue_id = "kalshi", player_key = meta$player_key,
      side = meta$side, line = meta$line, bid = field(cd$yes_bid, "close"), ask = field(cd$yes_ask, "close"),
      last = field(cd$price, "close"), volume = kalshi_num(cd$volume_fp %||% cd$volume),
      captured_at = as.POSIXct(kalshi_num(cd$end_period_ts), origin = "1970-01-01", tz = "UTC"),
      snapshot_kind = "candle", source = source, raw_sha256 = sha256, stringsAsFactors = FALSE
    )
  })
  new_odds_snapshots(do.call(rbind, rows))
}

provider_kalshi <- function(cfg = odds_http_config(), fetch_fn = odds_http_get, log_path = NULL,
                            now_fn = Sys.time, sleep_fn = Sys.sleep) {
  get <- function(url, source) {
    odds_fetch(url, cfg, fetch_fn = fetch_fn, log_path = log_path, source = source, now_fn = now_fn, sleep_fn = sleep_fn)
  }

  # snapshots_for() builds these as it goes; they are per call
  snapshots_for <- function(games, series_vec, hours_before, max_markets_per_event, date_offsets, on_raw, source_name) {
    parts <- list()
    fetches <- list()
    failures <- character()
    n_no_kickoff <- 0L
    n_not_found <- 0L
    n_unsupported <- 0L
    unsupported <- character()
    n_no_candles <- 0L
    cutoff <- NULL
    log_fetch <- function(rec, key) fetches[[length(fetches) + 1]] <<- odds_fetch_row(rec, key)
    note_failure <- function(rec, what) {
      if (!is.na(rec$status) && rec$status == 404L) return(invisible(NULL))
      failures <<- c(failures, sprintf("%s (%s)", what, rec$error %||% "unreadable response"))
    }

    # All markets of one event on one endpoint (paged); empty when there are none
    list_markets <- function(event_ticker, historical) {
      markets <- list()
      cursor <- NULL
      for (page in seq_len(KALSHI_MAX_PAGES)) {
        rec <- get(kalshi_event_markets_url(event_ticker, historical, cursor), "kalshi_markets")
        log_fetch(rec, sprintf("%s_%s_p%d", event_ticker, if (historical) "hist" else "live", page))
        parsed <- odds_json(rec)
        if (is.null(parsed)) {
          note_failure(rec, event_ticker)
          break
        }
        markets <- c(markets, parsed$markets %||% list())
        cursor <- parsed$cursor
        if (is.null(cursor) || !nzchar(cursor)) break
      }
      markets
    }

    # The event of a game: every spelling on the endpoint on the cutoff side of the kickoff
    # first, and only if none exists there, every spelling on the other endpoint
    find_event <- function(series, g, historical_first) {
      for (historical in c(historical_first, !historical_first)) {
        for (event_ticker in kalshi_candidate_events(series, g, date_offsets)) {
          markets <- list_markets(event_ticker, historical)
          if (length(markets)) return(list(markets = markets, historical = historical))
        }
      }
      NULL
    }

    for (i in seq_len(nrow(games))) {
      g <- games[i, , drop = FALSE]
      if (is.na(g$kickoff_utc)) {
        n_no_kickoff <- n_no_kickoff + 1L
        next
      }
      if (is.null(cutoff)) {
        rec <- get(kalshi_cutoff_url(), "kalshi_cutoff")
        log_fetch(rec, "cutoff")
        parsed <- odds_json(rec)
        cutoff <- if (is.null(parsed)) as.POSIXct(NA, tz = "UTC") else
          as.POSIXct(parsed$market_settled_ts, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
        if (is.na(cutoff)) note_failure(rec, "historical cutoff unreadable; trying live first")
      }
      historical_first <- !is.na(cutoff) && g$kickoff_utc < cutoff
      ko <- as.integer(as.numeric(g$kickoff_utc))
      for (series in series_vec) {
        found <- find_event(series, g, historical_first)
        if (is.null(found)) {
          n_not_found <- n_not_found + 1L
          next
        }
        markets <- found$markets
        markets <- markets[order(vapply(markets, function(m) m$ticker %||% "", ""))]
        if (is.finite(max_markets_per_event)) markets <- utils::head(markets, max_markets_per_event)
        for (m in markets) {
          meta <- kalshi_market_meta(m, g, series)
          if (!meta$ok) {
            n_unsupported <- n_unsupported + 1L
            unsupported <- c(unsupported, meta$reason)
            next
          }
          got <- NULL
          for (historical in c(found$historical, !found$historical)) {
            rec <- get(kalshi_candles_url(series, m$ticker, ko - hours_before * 3600L, ko, historical), "kalshi_candles")
            log_fetch(rec, sprintf("%s_%s", m$ticker, if (historical) "hist" else "live"))
            parsed <- odds_json(rec)
            if (is.null(parsed)) {
              note_failure(rec, m$ticker)
              if (!is.na(rec$status) && rec$status == 404L) next
              break
            }
            if (length(parsed$candlesticks %||% list()) == 0) break   # an empty 200 is an answer: no pre-kickoff candles
            if (!is.null(on_raw)) on_raw(m$ticker, rec$body, rec)
            got <- parse_kalshi_candles(parsed, meta, g$game_id, rec$sha256,
                                        if (historical) "kalshi_historical" else "kalshi_live")
            break
          }
          if (is.null(got)) n_no_candles <- n_no_candles + 1L else parts[[length(parts) + 1]] <- got
        }
      }
    }

    snaps <- bind_odds_snapshots(parts)
    detail <- sprintf("%d snapshot rows", nrow(snaps))
    if (n_no_kickoff) detail <- paste0(detail, sprintf("; %d game%s without a kickoff", n_no_kickoff, if (n_no_kickoff == 1) "" else "s"))
    if (n_not_found) detail <- paste0(detail, sprintf("; %d game-series with no Kalshi event", n_not_found))
    if (n_unsupported) detail <- paste0(detail, sprintf("; %d unsupported market%s (%s)", n_unsupported,
                                                        if (n_unsupported == 1) "" else "s",
                                                        paste(utils::head(unique(unsupported), 3), collapse = " | ")))
    if (n_no_candles) detail <- paste0(detail, sprintf("; %d market%s without candles", n_no_candles, if (n_no_candles == 1) "" else "s"))
    if (length(failures)) detail <- paste0(detail, "; failed: ", paste(utils::head(failures, 5), collapse = ", "))
    status <- if (length(failures)) "failed" else if (nrow(snaps) == 0) "unavailable" else "ok"
    odds_result(snaps, source = source_name, status = status, detail = detail,
                fetches = do.call(rbind, c(list(odds_fetches_empty()), fetches)))
  }

  game_snapshots <- function(games, hours_before = 48L, date_offsets = 0L, on_raw = NULL, ...) {
    snapshots_for(games, KALSHI_GAME_SERIES, hours_before, Inf, date_offsets, on_raw, "kalshi_games")
  }

  # One candle request per market: an event has hundreds, so cap them with max_markets_per_event
  prop_snapshots <- function(games, series = KALSHI_PROP_SERIES, hours_before = 48L, date_offsets = 0L,
                             max_markets_per_event = Inf, on_raw = NULL, ...) {
    snapshots_for(games, series, hours_before, max_markets_per_event, date_offsets, on_raw, "kalshi_props")
  }

  #' Forward capture: the open markets of every per-game NFL series.
  capture <- function(fetch, now, cfg) {
    series_text <- fetch("kalshi_series", "sports", kalshi_series_url())
    if (is.null(series_text)) return(invisible(FALSE))
    series <- jsonlite::fromJSON(series_text, simplifyVector = FALSE)$series %||% list()
    tickers <- vapply(series, function(s) s$ticker, character(1))
    tickers <- sort(tickers[is_nfl_game_series(tickers)])
    message(sprintf("Kalshi: %d per-game NFL series", length(tickers)))
    for (ticker in tickers) {
      cursor <- NULL
      page <- 1L
      repeat {
        text <- fetch("kalshi_markets", sprintf("%s_p%d", ticker, page), kalshi_open_markets_url(ticker, cursor))
        if (is.null(text)) break
        cursor <- jsonlite::fromJSON(text, simplifyVector = FALSE)$cursor
        if (is.null(cursor) || !nzchar(cursor) || page >= 20L) break
        page <- page + 1L
      }
    }
    invisible(TRUE)
  }

  new_odds_provider("kalshi", "kalshi", game_snapshots = game_snapshots, prop_snapshots = prop_snapshots,
                    capture = capture)
}
````

- [ ] **Step 5: GREEN.** Run the test file: no failures, exit 0.
- [ ] **Step 6: commit.**

```bash
git add R/odds/provider_kalshi.R tests/testthat/test-odds-kalshi.R tests/testthat/fixtures/odds/kalshi_*.json
git commit -m "feat(odds): Kalshi provider, game and prop candles from both endpoint forms (D1)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 7: forward capture through the providers (*sonnet*)

**Files:** create `R/odds/capture.R`, `tests/testthat/test-odds-capture.R`; edit `R/capture_raw.R`; replace `scripts/capture_odds_raw.R`. `.github/workflows/odds-capture.yml` is not edited.

`run_capture()` moves out of `R/capture_raw.R` into `R/odds/capture.R` with the same name and result columns, and gains `fetch_fn`, `providers`, `now_fn`, `sleep_fn`. `capture_http_get()` stays (the spike scripts and `clv_power.R` call it) but now delegates to `odds_fetch()`, so the 1 req/s floor and the block breaker apply to them too. The on-disk layout and `manifest.ndjson` are unchanged, so `odds-capture.yml` keeps uploading `data/raw_capture/`.

- [ ] **Step 1: write the test.** Create `tests/testthat/test-odds-capture.R`:

````r
# =============================================================================
# Tests: forward capture through the provider layer (R/odds/capture.R,
# scripts/capture_odds_raw.R, .github/workflows/odds-capture.yml). No network.
# =============================================================================

capture_routes <- function() {
  r <- list()
  r[[espn_scoreboard_url()]] <- file.path("..", "capture", "espn_scoreboard.json")
  r[[espn_game_odds_url("401872963")]] <- "espn_game_odds_2026_01_NE_SEA.json"
  r[[espn_prop_bets_url("401872963", 100, 1)]] <- file.path("..", "capture", "espn_propbets_page1.json")
  r[[espn_prop_bets_url("401872963", 100, 2)]] <- list(text = '{"pageCount": 2, "items": []}')
  r[[kalshi_series_url()]] <- list(text = '{"series": [{"ticker": "KXNFLTD"}, {"ticker": "KXNFLGAME"}, {"ticker": "KXNFLWINS-NO"}]}')
  r[[kalshi_open_markets_url("KXNFLGAME")]] <- "kalshi_markets_game_live.json"
  r[[kalshi_open_markets_url("KXNFLTD")]] <- "kalshi_markets_td_live.json"
  r
}
capture_cfg <- list(user_agent = "nfl-weekly-simulation/test (research)", timeout_sec = 20, max_tries = 3,
                    min_interval_sec = 0.5, horizon_hours = 36, espn_prop_providers = 100L)
NOW <- as.POSIXct("2026-09-28 20:53:00", tz = "UTC")

test_that("a capture pass stores every raw body with its sha256 and keeps the on-disk layout", {
  odds_http_reset()
  root <- withr::local_tempdir()
  clock <- odds_fake_clock()
  fake <- odds_fake_fetch(capture_routes())
  summary <- run_capture(root, capture_cfg, now = NOW, fetch_fn = fake$fn, now_fn = clock$now, sleep_fn = clock$sleep)

  expect_equal(summary$source, c("espn_scoreboard", "espn_game_odds", "espn_propbets", "espn_propbets",
                                 "kalshi_series", "kalshi_markets", "kalshi_markets"))
  expect_true(all(summary$status == 200L))
  manifest <- jsonlite::stream_in(file(file.path(root, "manifest.ndjson")), verbose = FALSE)
  expect_equal(nrow(manifest), nrow(summary))
  expect_true(all(file.exists(manifest$path)))
  expect_true(all(grepl("/espn_scoreboard/|/espn_game_odds/|/espn_propbets/|/kalshi_series/|/kalshi_markets/", manifest$path)))
  sb <- manifest[manifest$source == "espn_scoreboard", ]
  expect_equal(sb$sha256, digest::digest(readBin(testthat::test_path("fixtures", "capture", "espn_scoreboard.json"), "raw", 1e6),
                                         algo = "sha256", serialize = FALSE))
  expect_equal(fake$state$urls[1], espn_scoreboard_url())
  expect_equal(sum(clock$state$sleeps >= 1), length(fake$state$urls) - 2)    # one request per second per domain; 2 domains, so 2 first requests
})

test_that("the configured 0.5 s interval is raised to the 1 request/second floor", {
  odds_http_reset()
  clock <- odds_fake_clock()
  fake <- odds_fake_fetch(capture_routes())
  run_capture(withr::local_tempdir(), capture_cfg, now = NOW, sources = "espn", fetch_fn = fake$fn,
              now_fn = clock$now, sleep_fn = clock$sleep)
  expect_true(all(clock$state$sleeps >= 1))
  expect_false(any(clock$state$sleeps == 0.5))
})

test_that("a failed request is recorded in the summary and the manifest; nothing is dropped", {
  odds_http_reset()
  routes <- capture_routes()
  routes[[espn_game_odds_url("401872963")]] <- list(status = 404L)
  root <- withr::local_tempdir()
  clock <- odds_fake_clock()
  summary <- run_capture(root, capture_cfg, now = NOW, sources = "espn", fetch_fn = odds_fake_fetch(routes)$fn,
                         now_fn = clock$now, sleep_fn = clock$sleep)
  bad <- summary[summary$source == "espn_game_odds", ]
  expect_equal(bad$status, 404L)
  expect_equal(bad$error, "HTTP 404")
  manifest <- jsonlite::stream_in(file(file.path(root, "manifest.ndjson")), verbose = FALSE)
  expect_equal(manifest$http_status[manifest$source == "espn_game_odds"], 404L)
  expect_true(is.na(manifest$sha256[manifest$source == "espn_game_odds"]))
})

test_that("a 403 stops further requests to that domain", {
  odds_http_reset()
  routes <- capture_routes()
  routes[[espn_scoreboard_url()]] <- list(status = 403L)
  clock <- odds_fake_clock()
  fake <- odds_fake_fetch(routes)
  summary <- run_capture(withr::local_tempdir(), capture_cfg, now = NOW, sources = "espn", fetch_fn = fake$fn,
                         now_fn = clock$now, sleep_fn = clock$sleep)
  expect_equal(nrow(summary), 1)
  expect_equal(length(fake$state$urls), 1)
})

test_that("the legacy capture_http_get now runs through the same layer", {
  expect_error(capture_http_get("https://example.test/", "ua", 20, 1, 0.1), "forbidden")
})

test_that("scripts/capture_odds_raw.R is a thin caller and the workflow still runs it", {
  script <- readLines(file.path(PROJECT_ROOT, "scripts", "capture_odds_raw.R"), warn = FALSE)
  expect_silent(parse(file.path(PROJECT_ROOT, "scripts", "capture_odds_raw.R")))
  expect_true(any(grepl("run_capture(", script, fixed = TRUE)))
  expect_false(any(grepl("httr2|capture_http_get|req_perform", script)))
  expect_lt(length(script), 80)
  wf <- yaml::read_yaml(file.path(PROJECT_ROOT, ".github", "workflows", "odds-capture.yml"))
  runs <- vapply(wf$jobs$capture$steps, function(s) if (is.null(s$run)) "" else s$run, "")
  expect_true(any(runs == "Rscript scripts/capture_odds_raw.R"))
  installs <- paste(runs, collapse = " ")
  expect_match(installs, "httr2")
  expect_match(installs, "jsonlite")
  expect_match(installs, "digest")
  expect_identical(wf$permissions, list(contents = "read"))
  # everything the script sources exists (the runner has no renv: base R plus the installed packages)
  src <- regmatches(script, gregexpr('"[^"]+\\.R"', script))
  files <- gsub('"', "", unlist(src))
  files <- files[!grepl("^scripts/", files)]
  expect_true(all(file.exists(file.path(PROJECT_ROOT, files))))
})
````

- [ ] **Step 2: RED.** Expected with the original `R/capture_raw.R` and script, and no `R/odds/capture.R`:

```
── 1. Error ('test-odds-capture.R:26:3'): a capture pass stores every raw body w
Error in `run_capture(root, capture_cfg, now = NOW, fetch_fn = fake$fn, now_fn = clock$now, sleep_fn = clock$sleep)`: unused arguments (fetch_fn = fake$fn, now_fn = clock$now, sleep_fn = clock$sleep)
── 2. Error ('test-odds-capture.R:46:3'): the configured 0.5 s interval is raise
Error in `run_capture(withr::local_tempdir(), capture_cfg, now = NOW, sources = "espn", fetch_fn = fake$fn, now_fn = clock$now, sleep_fn = clock$sleep)`: unused arguments (fetch_fn = fake$fn, now_fn = clock$now, sleep_fn = clock$sleep)
```

- [ ] **Step 3: implement.** Create `R/odds/capture.R`:

````r
# =============================================================================
# Forward capture, as a caller of the provider layer (roadmap D1)
# =============================================================================
# One pass over the providers' capture() methods. Every request goes through
# odds_fetch() (truthful user agent, 20 s timeout, at most 1 request/second per
# domain, backoff on 429/5xx, no workaround for a 403), and every raw response is
# stored byte-for-byte (gzipped) with its sha256 in the append-only manifest
# (write_capture() in R/capture_raw.R). The on-disk layout is unchanged:
#   root/YYYY-MM-DD/<source>/<key>__<timestamp>.json.gz   and   root/manifest.ndjson
# =============================================================================

#' One capture pass over ESPN and Kalshi. Returns a summary data.frame
#' (source, key, status, bytes, error), one row per request.
#' @param cfg list(user_agent, timeout_sec, max_tries, min_interval_sec, horizon_hours,
#'   espn_prop_providers)
#' @param fetch_fn the network seam (odds_http_get in production)
run_capture <- function(root, cfg, now = Sys.time(), sources = c("espn", "kalshi"),
                        fetch_fn = odds_http_get, providers = NULL,
                        now_fn = Sys.time, sleep_fn = Sys.sleep) {
  now <- as.POSIXct(format(now, tz = "UTC"), tz = "UTC")
  http_cfg <- odds_http_config(overrides = cfg[intersect(names(cfg), c("user_agent", "timeout_sec", "max_tries", "min_interval_sec"))])
  providers <- providers %||% list(espn = provider_espn_core(), kalshi = provider_kalshi())
  log <- list()

  fetch <- function(source, key, url) {
    rec <- odds_fetch(url, http_cfg, fetch_fn = fetch_fn, source = source, now_fn = now_fn, sleep_fn = sleep_fn)
    write_capture(root, source, key, rec$fetched_at, url, rec$status, body = rec$body, error = rec$error)
    if (rec$blocked) message(sprintf("  %s refused the request (HTTP %s); no further requests to that domain", url, rec$status))
    log[[length(log) + 1]] <<- data.frame(
      source = source, key = key, status = rec$status, bytes = rec$bytes,
      error = rec$error %||% NA_character_, stringsAsFactors = FALSE
    )
    if (is.null(rec$body)) NULL else rawToChar(rec$body)
  }

  for (name in intersect(sources, names(providers))) {
    providers[[name]]$capture(fetch, now, cfg)
  }
  unknown <- setdiff(sources, names(providers))
  if (length(unknown)) warning("run_capture: no provider for source(s): ", paste(unknown, collapse = ", "), call. = FALSE)

  if (length(log) == 0) return(data.frame())
  do.call(rbind, log)
}
````

  Apply this change to `R/capture_raw.R` (the header note, `capture_http_get` as a delegating wrapper, and `run_capture` removed). Save it to a file and run `git apply --whitespace=nowarn <file>`; `git apply --check` first:

````diff
diff --git a/R/capture_raw.R b/R/capture_raw.R
index 61cd145..e86b6ec 100644
--- a/R/capture_raw.R
+++ b/R/capture_raw.R
@@ -10,8 +10,8 @@
 #   - ESPN core API: scoreboard, per-game odds (open/close), DraftKings propBets
 #   - Kalshi public market data: open markets for per-game NFL series
 #
-# Pure helpers (parse/select/URL/path) are unit-tested with fixtures; only
-# capture_http_get() touches the network.
+# Pure helpers (parse/select/URL/path) are unit-tested with fixtures. The network
+# calls and the capture pass live in R/odds/ (http.R, provider_*.R, capture.R).
 # =============================================================================
 
 ESPN_CORE_BASE <- "https://sports.core.api.espn.com/v2/sports/football/leagues/nfl"
@@ -139,90 +139,13 @@ write_capture <- function(root, source, key, captured_at, url, http_status,
   list(path = path, sha256 = sha, bytes = bytes)
 }
 
-#' GET with a truthful user agent, timeout, polite throttle and bounded retry
+#' GET through the odds HTTP layer (R/odds/http.R): truthful user agent, timeout, at most
+#' 1 request per second per domain, bounded retry with backoff, no workaround for a 403.
+#' Kept for the spike scripts; new code calls odds_fetch() directly.
 #' @return list(status, body [raw or NULL], error)
 capture_http_get <- function(url, user_agent, timeout_sec, max_tries, min_interval_sec) {
-  req <- httr2::request(url) |>
-    httr2::req_user_agent(user_agent) |>
-    httr2::req_timeout(timeout_sec) |>
-    httr2::req_throttle(capacity = 1, fill_time_s = min_interval_sec) |>
-    httr2::req_retry(
-      max_tries = max_tries,
-      is_transient = function(resp) httr2::resp_status(resp) %in% c(429, 500, 502, 503, 504)
-    ) |>
-    httr2::req_error(is_error = function(resp) FALSE)
-  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
-  if (inherits(resp, "error")) {
-    return(list(status = NA_integer_, body = NULL, error = conditionMessage(resp)))
-  }
-  status <- httr2::resp_status(resp)
-  if (status >= 400) {
-    return(list(status = status, body = NULL, error = sprintf("HTTP %d", status)))
-  }
-  list(status = status, body = httr2::resp_body_raw(resp), error = NA_character_)
-}
-
-#' One capture pass over ESPN and Kalshi. Returns a summary data.frame.
-#' @param cfg list with user_agent, timeout_sec, max_tries, min_interval_sec,
-#'   horizon_hours, espn_prop_providers (integer vector)
-run_capture <- function(root, cfg, now = Sys.time(), sources = c("espn", "kalshi")) {
-  now <- as.POSIXct(format(now, tz = "UTC"), tz = "UTC")
-  log <- list()
-  fetch <- function(source, key, url) {
-    res <- capture_http_get(url, cfg$user_agent, cfg$timeout_sec,
-                            cfg$max_tries, cfg$min_interval_sec)
-    rec <- write_capture(root, source, key, Sys.time(), url, res$status,
-                         body = res$body, error = res$error)
-    log[[length(log) + 1]] <<- data.frame(
-      source = source, key = key, status = res$status %||% NA_integer_,
-      bytes = rec$bytes, error = res$error %||% NA_character_, stringsAsFactors = FALSE
-    )
-    if (is.null(res$body)) NULL else rawToChar(res$body)
-  }
-
-  if ("espn" %in% sources) {
-    sb_text <- fetch("espn_scoreboard", "scoreboard", espn_scoreboard_url())
-    if (!is.null(sb_text)) {
-      targets <- select_capture_events(parse_espn_scoreboard(sb_text), now, cfg$horizon_hours)
-      message(sprintf("ESPN: %d game(s) kick off within %dh", nrow(targets), cfg$horizon_hours))
-      for (event_id in targets$event_id) {
-        fetch("espn_game_odds", event_id, espn_game_odds_url(event_id))
-        for (provider_id in cfg$espn_prop_providers) {
-          first <- fetch("espn_propbets", sprintf("%s_%s_p1", event_id, provider_id),
-                         espn_prop_bets_url(event_id, provider_id, 1))
-          if (is.null(first)) next
-          n_pages <- espn_page_count(first)
-          for (page in seq_len(n_pages)[-1]) {
-            fetch("espn_propbets", sprintf("%s_%s_p%d", event_id, provider_id, page),
-                  espn_prop_bets_url(event_id, provider_id, page))
-          }
-        }
-      }
-    }
-  }
-
-  if ("kalshi" %in% sources) {
-    series_text <- fetch("kalshi_series", "sports", kalshi_series_url())
-    if (!is.null(series_text)) {
-      series <- jsonlite::fromJSON(series_text, simplifyVector = FALSE)$series %||% list()
-      tickers <- vapply(series, function(s) s$ticker, character(1))
-      tickers <- sort(tickers[is_nfl_game_series(tickers)])
-      message(sprintf("Kalshi: %d per-game NFL series", length(tickers)))
-      for (ticker in tickers) {
-        cursor <- NULL
-        page <- 1L
-        repeat {
-          text <- fetch("kalshi_markets", sprintf("%s_p%d", ticker, page),
-                        kalshi_open_markets_url(ticker, cursor))
-          if (is.null(text)) break
-          cursor <- jsonlite::fromJSON(text, simplifyVector = FALSE)$cursor
-          if (is.null(cursor) || !nzchar(cursor) || page >= 20L) break
-          page <- page + 1L
-        }
-      }
-    }
-  }
-
-  if (length(log) == 0) return(data.frame())
-  do.call(rbind, log)
+  if (!exists("odds_fetch", mode = "function")) source("R/odds/http.R")
+  rec <- odds_fetch(url, list(user_agent = user_agent, timeout_sec = timeout_sec,
+                              max_tries = max_tries, min_interval_sec = min_interval_sec))
+  list(status = rec$status, body = rec$body, error = rec$error)
 }
````

  Replace `scripts/capture_odds_raw.R` with:

````r
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
# second per domain, backoff on 429/5xx, no workaround for a 403.
# Exit status 1 if every request failed (so schedulers notice).
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
  espn_prop_providers = cfg_env$CAPTURE_ESPN_PROP_PROVIDERS
)
if (cfg$min_interval_sec < ODDS_MIN_INTERVAL_SEC) {
  message(sprintf("Note: CAPTURE_MIN_INTERVAL_SEC = %s is below the 1 request/second floor; using %s",
                  cfg$min_interval_sec, ODDS_MIN_INTERVAL_SEC))
}
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

ok <- !is.na(summary$status) & summary$status < 400
by_source <- aggregate(
  cbind(requests = 1, ok = ok, bytes = summary$bytes) ~ source,
  data = transform(summary, ok = ok), FUN = sum
)
print(by_source, row.names = FALSE)
message(sprintf("Done in %.0fs: %d/%d requests ok, %.1f MB raw",
                as.numeric(difftime(Sys.time(), started, units = "secs")),
                sum(ok), nrow(summary), sum(summary$bytes) / 1e6))
if (!any(ok)) quit(status = 1)
````

- [ ] **Step 4: GREEN.** Run `test-odds-capture.R` and also `test-capture-raw.R`: no failures, exit 0 (the existing pure-helper tests still pass).
- [ ] **Step 5: commit.**

```bash
git add R/odds/capture.R R/capture_raw.R scripts/capture_odds_raw.R tests/testthat/test-odds-capture.R
git commit -m "feat(odds): forward capture is a caller of the provider layer; capture_http_get delegates to it (D1)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 8: the archive builder, coverage and the 2025 seal (*haiku*)

**Files:** create `R/odds/archive.R`, `backtest/build_odds_archive.R`, `tests/testthat/test-odds-archive.R`.

**Interface:** `ODDS_ARCHIVE_MIN_SEASON = 2023L`, `ODDS_ARCHIVE_MAX_SEASON = 2024L` (a seal, not a setting), `odds_archive_assert_seasons()`, `odds_archive_games(schedule, seasons)`, `odds_archive_build(games, provider, out_dir, raw_dir)`, `odds_archive_verify(out_dir, raw_dir)` (`raw_dir = NULL` checks the committed derived files only), `odds_coverage(snaps, games)`, `odds_replay_fetch(raw_dir)` (offline rebuild), `odds_archive_read_event_map()`.

- [ ] **Step 1: write the test.** Create `tests/testthat/test-odds-archive.R`:

````r
# =============================================================================
# Tests: the decision-time archive builder (R/odds/archive.R, backtest/build_odds_archive.R)
# The 2025 Holdout is sealed: the builder must refuse 2025 before it makes a request.
# The fixture is a trimmed REAL ESPN response; no test here touches the network.
# =============================================================================

schedule_rows <- function() {
  data.frame(
    game_id = c("2024_01_ARI_BUF", "2023_01_XXX_YYY", "2025_01_AAA_BBB"),
    season = c(2024L, 2023L, 2025L), week = 1L, game_type = "REG",
    gameday = c("2024-09-08", "2023-09-10", "2025-09-07"), gametime = "13:00",
    home_team = c("BUF", "YYY", "BBB"), away_team = c("ARI", "XXX", "AAA"),
    espn = c("401671617", "999", "888"), stringsAsFactors = FALSE
  )
}
archive_provider <- function(routes, clock = odds_fake_clock()) {
  odds_http_reset()
  fake <- odds_fake_fetch(routes)
  list(provider = provider_espn_core(cfg = odds_http_config(), fetch_fn = fake$fn,
                                     now_fn = clock$now, sleep_fn = clock$sleep), fake = fake)
}
archive_routes <- function() {
  setNames(list("espn_game_odds_2024_01_ARI_BUF.json", list(status = 404L)),
           c(espn_game_odds_url("401671617"), espn_game_odds_url("999")))
}
file_sha <- function(path) digest::digest(file = path, algo = "sha256")

test_that("the archive window is 2023 to 2024, and 2025 is refused with the reason", {
  expect_equal(ODDS_ARCHIVE_MAX_SEASON, 2024L)
  expect_equal(odds_archive_assert_seasons(c(2024L, 2023L)), c(2023L, 2024L))
  expect_error(odds_archive_assert_seasons(2025L), "2025 Holdout is sealed")
  expect_error(odds_archive_assert_seasons(c(2023L, 2024L, 2025L)), "refusing season\\(s\\) 2025")
  expect_error(odds_archive_assert_seasons(2026L), "sealed")
  expect_error(odds_archive_assert_seasons(2022L), "before 2023")
  expect_error(odds_archive_assert_seasons(integer()), "integers")
})

test_that("the game list never carries a sealed season, even from a wider schedule", {
  games <- odds_archive_games(schedule_rows(), c(2023L, 2024L))
  expect_equal(games$game_id, c("2023_01_XXX_YYY", "2024_01_ARI_BUF"))      # kickoff order
  expect_false(2025L %in% games$season)
  expect_error(odds_archive_games(schedule_rows(), 2025L), "sealed")
  expect_equal(format(games$kickoff_utc[2], "%Y-%m-%d %H:%M", tz = "UTC"), "2024-09-08 17:00")
})

test_that("odds_archive_build refuses 2025 before any request or file", {
  a <- archive_provider(archive_routes())
  out <- file.path(withr::local_tempdir(), "archive")
  raw <- file.path(withr::local_tempdir(), "raw")
  games_2025 <- odds_games_from_schedule(schedule_rows()[3, ])
  expect_error(odds_archive_build(games_2025, a$provider, out, raw), "2025 Holdout is sealed")
  expect_length(a$fake$state$urls, 0)                                         # no request was made
  expect_false(dir.exists(out))
  mixed <- odds_games_from_schedule(schedule_rows()[c(1, 3), ])
  expect_error(odds_archive_build(mixed, a$provider, out, raw), "sealed")
  expect_length(a$fake$state$urls, 0)
})

test_that("the build script refuses 2025 on the command line without loading a schedule", {
  withr::local_dir(PROJECT_ROOT)
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
                                  c(shQuote("backtest/build_odds_archive.R"), shQuote(withr::local_tempdir()), "--seasons=2023,2025"),
                                  stdout = TRUE, stderr = TRUE))
  expect_gt(attr(out, "status") %||% 0L, 0L)
  expect_match(paste(out, collapse = "\n"), "2025 Holdout is sealed")
})

test_that("coverage counts a market as covered only when both sides of the line are present", {
  s <- new_odds_snapshots(data.frame(
    game_id = c("g1", "g1", "g1", "g2", "g2"), market_id = "moneyline", venue_id = "espn_bet",
    side = c("home", "away", "home", "home", "away"), price_american = c(-110L, 100L, -120L, -110L, 100L),
    snapshot_kind = c("open", "open", "close", "open", "open"), source = "espn_core", raw_sha256 = "x",
    stringsAsFactors = FALSE))
  games <- data.frame(game_id = c("g1", "g2", "g3"), season = 2024L, stringsAsFactors = FALSE)
  cov <- odds_coverage(s, games)
  row <- cov[cov$venue_id == "espn_bet" & cov$market_id == "moneyline", ]
  expect_equal(c(row$games_expected, row$games_with_open, row$games_with_close, row$games_with_open_and_close), c(3, 2, 0, 0))
  expect_equal(cov$games_with_open[cov$venue_id == "any" & cov$market_id == "moneyline"], 2)
  expect_equal(nrow(cov[cov$market_id == "total", ]), 1)                       # the "any" row still reports 0 of 3
})

test_that("a build writes hash-recorded derived files, keeps the raw bodies, and verifies", {
  a <- archive_provider(archive_routes())
  out <- file.path(withr::local_tempdir(), "archive")
  raw <- file.path(withr::local_tempdir(), "raw")
  games <- odds_archive_games(schedule_rows(), c(2023L, 2024L))
  res <- odds_archive_build(games, a$provider, out, raw, built_utc = as.POSIXct("2026-10-13 12:00:00", tz = "UTC"))

  expect_setequal(list.files(out), c("COVERAGE.csv", "SOURCES.json", "event_map.csv", "espn_game_odds.csv"))
  arch <- utils::read.csv(file.path(out, "espn_game_odds.csv"), stringsAsFactors = FALSE)
  expect_equal(names(arch), ODDS_ARCHIVE_COLUMNS)
  expect_equal(nrow(arch), 12)
  expect_equal(unique(arch$season), 2024L)
  expect_false(2025L %in% arch$season)
  src <- jsonlite::read_json(file.path(out, "SOURCES.json"))
  expect_length(src$raw, 1)
  expect_equal(src$raw[[1]]$sha256, digest::digest(odds_fixture_raw("espn_game_odds_2024_01_ARI_BUF.json"), algo = "sha256", serialize = FALSE))
  expect_equal(src$raw[[1]]$file, "espn_game_odds__401671617.json.gz")
  expect_true(file.exists(file.path(raw, src$raw[[1]]$file)))
  expect_length(src$fetch_failures, 1)                                         # the 2023 game's 404 is recorded, not dropped
  expect_equal(src$fetch_failures[[1]]$http_status, 404L)
  expect_equal(src$max_season, 2024L)
  expect_equal(src$built_utc, "2026-10-13T12:00:00Z")
  for (d in src$derived) expect_equal(d$sha256, file_sha(file.path(out, d$file)))
  expect_false(any(grepl("\r", readLines(file.path(out, "espn_game_odds.csv"), warn = FALSE), fixed = TRUE)))
  expect_equal(odds_archive_verify(out, raw), character())
  expect_equal(odds_archive_verify(out, NULL), character())                    # derived files only, as in the committed data test

  cov <- utils::read.csv(file.path(out, "COVERAGE.csv"), stringsAsFactors = FALSE)
  expect_equal(cov$games_with_open_and_close[cov$season == 2024 & cov$venue_id == "espn_bet" & cov$market_id == "moneyline"], 1)
  expect_equal(cov$games_with_open_and_close[cov$season == 2023 & cov$venue_id == "any" & cov$market_id == "moneyline"], 0)

  # tampering is caught
  oa_write_gz(file.path(raw, "espn_game_odds__401671617.json.gz"), charToRaw("{}"))
  expect_match(odds_archive_verify(out, raw), "raw hash differs", all = FALSE)
})

test_that("the archive rebuilds byte for byte from its stored raw responses, offline", {
  a <- archive_provider(archive_routes())
  out1 <- file.path(withr::local_tempdir(), "a")
  out2 <- file.path(withr::local_tempdir(), "b")
  raw <- file.path(withr::local_tempdir(), "raw")
  games <- odds_archive_games(schedule_rows(), c(2023L, 2024L))
  odds_archive_build(games, a$provider, out1, raw)
  odds_http_reset()
  replay <- provider_espn_core(cfg = odds_http_config(), fetch_fn = odds_replay_fetch(raw),
                               now_fn = odds_fake_clock()$now, sleep_fn = function(s) NULL)
  odds_archive_build(games, replay, out2, raw)
  for (f in c("espn_game_odds.csv", "event_map.csv", "COVERAGE.csv")) {
    expect_identical(file_sha(file.path(out1, f)), file_sha(file.path(out2, f)), info = f)
  }
})

test_that("the event map round-trips into the games table", {
  a <- archive_provider(archive_routes())
  out <- file.path(withr::local_tempdir(), "archive")
  games <- odds_archive_games(schedule_rows(), c(2023L, 2024L))
  odds_archive_build(games, a$provider, out, file.path(withr::local_tempdir(), "raw"))
  back <- odds_archive_read_event_map(file.path(out, "event_map.csv"))
  expect_equal(back$game_id, games$game_id)
  expect_equal(back$kickoff_utc, games$kickoff_utc)
  expect_equal(back$espn, games$espn)
})
````

- [ ] **Step 2: RED.** Expected with `R/odds/archive.R` and the script absent:

```
── 1. Error ('test-odds-archive.R:29:3'): the archive window is 2023 to 2024, an
Error in `eval(code, test_env)`: object 'ODDS_ARCHIVE_MAX_SEASON' not found
── 2. Error ('test-odds-archive.R:39:3'): the game list never carries a sealed s
Error in `odds_archive_games(schedule_rows(), c(2023L, 2024L))`: could not find function "odds_archive_games"
```

- [ ] **Step 3: implement.** Create `R/odds/archive.R`:

````r
# =============================================================================
# The decision-time archive: ESPN game openers and closes, 2023-2024 (roadmap D1)
# =============================================================================
# backtest/build_odds_archive.R builds backtest/data/odds_archive/ from the ESPN core
# game-odds responses, the way backtest/build_inputs.R builds backtest/data/: derived
# CSVs are committed, and SOURCES.json records the sha256 of every raw response and
# every derived file. The raw responses are stored gzipped under a raw directory that
# is NOT committed (16.4 MB measured); odds_archive_verify() re-checks them against SOURCES.json.
#
# THE 2025 HOLDOUT IS SEALED. This builder refuses any season after
# ODDS_ARCHIVE_MAX_SEASON before it loads a schedule or makes one request. The 2025 rows
# are appended only by the G3 Holdout build, after the freeze. The constant is not a
# config value on purpose: raising it is a protocol decision, not a setting.
# ESPN has no open line before 2023 (2022 has a close only), so 2023 is the first season.
# =============================================================================

ODDS_ARCHIVE_MIN_SEASON <- 2023L
ODDS_ARCHIVE_MAX_SEASON <- 2024L
ODDS_ARCHIVE_DIR <- file.path("backtest", "data", "odds_archive")
ODDS_ARCHIVE_COLUMNS <- c("game_id", "season", "week", "game_type", "market_id", "venue_id", "side", "line",
                          "price_american", "snapshot_kind", "raw_sha256")

#' Stop unless every season is inside the archive window
odds_archive_assert_seasons <- function(seasons) {
  seasons <- as.integer(seasons)
  if (length(seasons) == 0 || anyNA(seasons)) stop("odds archive: seasons must be integers", call. = FALSE)
  sealed <- seasons[seasons > ODDS_ARCHIVE_MAX_SEASON]
  if (length(sealed)) {
    stop(sprintf(paste0("odds archive: refusing season(s) %s. The 2025 Holdout is sealed; only the G3 Holdout build, ",
                        "after the freeze, may add 2025 game rows (archive window %d-%d)."),
                 paste(sort(unique(sealed)), collapse = ", "), ODDS_ARCHIVE_MIN_SEASON, ODDS_ARCHIVE_MAX_SEASON),
         call. = FALSE)
  }
  early <- seasons[seasons < ODDS_ARCHIVE_MIN_SEASON]
  if (length(early)) {
    stop(sprintf("odds archive: no ESPN opening line before %d (season(s) %s)", ODDS_ARCHIVE_MIN_SEASON,
                 paste(sort(unique(early)), collapse = ", ")), call. = FALSE)
  }
  invisible(sort(unique(seasons)))
}

#' The games of the archive window from a schedule table, in kickoff order. Re-checks
#' the seasons of the result, so a wide schedule can never leak a sealed season through.
odds_archive_games <- function(schedule, seasons) {
  seasons <- odds_archive_assert_seasons(seasons)
  sched <- as.data.frame(schedule, stringsAsFactors = FALSE)
  games <- odds_games_from_schedule(sched[as.integer(sched$season) %in% seasons, , drop = FALSE])
  games <- games[order(games$kickoff_utc, games$game_id), , drop = FALSE]
  if (nrow(games) && max(games$season) > ODDS_ARCHIVE_MAX_SEASON) stop("odds archive: sealed season in the game list", call. = FALSE)
  rownames(games) <- NULL
  games
}

oa_raw_path <- function(raw_dir, key) file.path(raw_dir, sprintf("espn_game_odds__%s.json.gz", key))

oa_write_gz <- function(path, body) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- gzfile(path, "wb")
  on.exit(close(con))
  writeBin(body, con)
  invisible(path)
}

oa_read_gz <- function(path) {
  con <- gzfile(path, "rb")
  on.exit(close(con))
  out <- raw()
  repeat {
    chunk <- readBin(con, "raw", 65536L)
    if (length(chunk) == 0) break
    out <- c(out, chunk)
  }
  out
}

#' A fetch function that serves stored raw responses, so the archive can be rebuilt
#' offline from a raw directory (the `--from-raw` mode). A missing file is a 404.
odds_replay_fetch <- function(raw_dir) {
  function(url, cfg) {
    key <- sub("^.*/events/([0-9]+)/competitions/.*$", "\\1", url)
    path <- oa_raw_path(raw_dir, key)
    if (!grepl("^[0-9]+$", key) || !file.exists(path)) {
      return(list(status = 404L, body = NULL, error = "HTTP 404 (no stored raw response)", retry_after = NA_real_))
    }
    list(status = 200L, body = oa_read_gz(path), error = NA_character_, retry_after = NA_real_)
  }
}

# LF line endings on every platform: the files are hash-locked evidence (.gitattributes)
oa_write_text <- function(text, path) {
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeBin(charToRaw(enc2utf8(paste0(paste(text, collapse = "\n"), "\n"))), con)
  invisible(path)
}

oa_write_csv <- function(x, path) {
  oa_write_text(utils::capture.output(utils::write.csv(x, row.names = FALSE, na = "")), path)
}

oa_sha256_file <- function(path) digest::digest(file = path, algo = "sha256")

#' Games per season, market and venue that have a complete open, a complete close, or both.
#' A line is complete when both its sides are present (home and away, over and under).
#' The venue "any" counts a game once if any venue has it.
odds_coverage <- function(snaps, games) {
  markets <- c("moneyline", "spread", "total")
  out <- list()
  complete <- function(d) {
    # (game, venue, market, kind) groups with 2 distinct sides
    if (nrow(d) == 0) return(d[0, c("game_id", "venue_id", "market_id", "snapshot_kind")])
    key <- paste(d$game_id, d$venue_id, d$market_id, d$snapshot_kind, sep = "|")
    n_sides <- tapply(d$side, key, function(x) length(unique(x)))
    keep <- !duplicated(key) & n_sides[key] >= 2
    d[keep, c("game_id", "venue_id", "market_id", "snapshot_kind")]
  }
  cmp <- complete(snaps)
  venues <- c(sort(unique(snaps$venue_id)), "any")
  for (season in sort(unique(games$season))) {
    ids <- games$game_id[games$season == season]
    for (venue in venues) {
      for (market in markets) {
        d <- cmp[cmp$game_id %in% ids & cmp$market_id == market & (venue == "any" | cmp$venue_id == venue), ]
        open <- unique(d$game_id[d$snapshot_kind == "open"])
        close <- unique(d$game_id[d$snapshot_kind == "close"])
        both <- intersect(open, close)
        if (venue != "any" && length(open) + length(close) == 0) next
        out[[length(out) + 1]] <- data.frame(
          season = season, venue_id = venue, market_id = market, games_expected = length(ids),
          games_with_open = length(open), games_with_close = length(close), games_with_open_and_close = length(both),
          pct_open_and_close = round(100 * length(both) / length(ids), 1), stringsAsFactors = FALSE
        )
      }
    }
  }
  if (length(out) == 0) {
    return(data.frame(season = integer(), venue_id = character(), market_id = character(), games_expected = integer(),
                      games_with_open = integer(), games_with_close = integer(), games_with_open_and_close = integer(),
                      pct_open_and_close = numeric(), stringsAsFactors = FALSE))
  }
  do.call(rbind, out)
}

#' Games read back from a committed event_map.csv (the offline `--from-raw` input)
odds_archive_read_event_map <- function(path) {
  em <- utils::read.csv(path, colClasses = "character", na.strings = "")
  games <- data.frame(
    game_id = em$game_id, season = as.integer(em$season), week = as.integer(em$week), game_type = em$game_type,
    gameday = em$gameday, kickoff_utc = as.POSIXct(em$kickoff_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    home_team = em$home_team, away_team = em$away_team, espn = em$espn_event_id, stringsAsFactors = FALSE
  )
  odds_archive_assert_seasons(unique(games$season))
  games
}

#' Build the archive: fetch (or replay) the ESPN game odds of `games`, store each raw body,
#' and write the derived CSVs plus SOURCES.json to `out_dir`.
#' @param provider provider_espn_core() with the network (or replay) seam of the caller
#' @return list(snapshots, coverage, sources, status)
odds_archive_build <- function(games, provider, out_dir, raw_dir, built_utc = Sys.time()) {
  odds_archive_assert_seasons(unique(games$season))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  res <- provider$game_snapshots(games, on_raw = function(key, body, rec) oa_write_gz(oa_raw_path(raw_dir, key), body))

  s <- res$snapshots
  meta <- games[match(s$game_id, games$game_id), c("season", "week", "game_type")]
  arch <- cbind(s["game_id"], meta, s[c("market_id", "venue_id", "side", "line", "price_american", "snapshot_kind", "raw_sha256")])
  arch <- arch[order(arch$game_id, arch$venue_id, arch$market_id, arch$side, arch$snapshot_kind), ODDS_ARCHIVE_COLUMNS, drop = FALSE]
  rownames(arch) <- NULL
  event_map <- data.frame(
    game_id = games$game_id, season = games$season, week = games$week, game_type = games$game_type,
    gameday = games$gameday, kickoff_utc = odds_iso(games$kickoff_utc), home_team = games$home_team,
    away_team = games$away_team, espn_event_id = games$espn, stringsAsFactors = FALSE
  )
  coverage <- odds_coverage(s, games)

  paths <- list(odds_archive = file.path(out_dir, "espn_game_odds.csv"),
                event_map = file.path(out_dir, "event_map.csv"),
                coverage = file.path(out_dir, "COVERAGE.csv"))
  oa_write_csv(arch, paths$odds_archive)
  oa_write_csv(event_map, paths$event_map)
  oa_write_csv(coverage, paths$coverage)

  f <- res$fetches
  ok <- !is.na(f$http_status) & f$http_status == 200L & !is.na(f$raw_sha256)
  raw <- lapply(which(ok), function(i) list(file = basename(oa_raw_path(raw_dir, f$key[i])), url = f$url[i],
                                            sha256 = f$raw_sha256[i], bytes = f$bytes[i]))
  failures <- lapply(which(!ok), function(i) list(key = f$key[i], url = f$url[i], http_status = f$http_status[i]))
  derived <- lapply(paths, function(p) list(file = basename(p), rows = nrow(utils::read.csv(p)), sha256 = oa_sha256_file(p)))
  sources <- list(
    built_utc = odds_iso(built_utc), seasons = sort(unique(games$season)), max_season = ODDS_ARCHIVE_MAX_SEASON,
    script = "backtest/build_odds_archive.R", games = nrow(games), source_status = res$source_status$status,
    source_detail = res$source_status$detail, raw = unname(raw), fetch_failures = unname(failures), derived = derived,
    r_version = R.version.string
  )
  oa_write_text(jsonlite::toJSON(sources, auto_unbox = TRUE, pretty = TRUE, na = "null"), file.path(out_dir, "SOURCES.json"))
  invisible(list(snapshots = arch, coverage = coverage, sources = sources, status = res$source_status))
}

#' Re-hash the stored raw responses and the derived files against SOURCES.json.
#' With `raw_dir = NULL` only the committed derived files are checked (the raw
#' responses are not committed).
#' @return character vector of mismatches (empty when everything verifies)
odds_archive_verify <- function(out_dir, raw_dir) {
  src <- jsonlite::read_json(file.path(out_dir, "SOURCES.json"), simplifyVector = FALSE)
  bad <- character()
  for (r in if (is.null(raw_dir)) list() else src$raw) {
    path <- file.path(raw_dir, r$file)
    if (!file.exists(path)) {
      bad <- c(bad, paste("missing raw file", r$file))
    } else if (!identical(digest::digest(oa_read_gz(path), algo = "sha256", serialize = FALSE), r$sha256)) {
      bad <- c(bad, paste("raw hash differs", r$file))
    }
  }
  for (d in src$derived) {
    path <- file.path(out_dir, d$file)
    if (!file.exists(path)) {
      bad <- c(bad, paste("missing derived file", d$file))
    } else if (!identical(oa_sha256_file(path), d$sha256)) {
      bad <- c(bad, paste("derived hash differs", d$file))
    }
  }
  if (max(unlist(src$seasons)) > ODDS_ARCHIVE_MAX_SEASON) bad <- c(bad, "SOURCES.json lists a sealed season")
  bad
}
````

  Create `backtest/build_odds_archive.R`:

````r
#!/usr/bin/env Rscript
# =============================================================================
# Decision-time archive: ESPN game openers and closes, 2023-2024 (roadmap D1)
# =============================================================================
#   Rscript backtest/build_odds_archive.R <raw_dir>                  # fetch ~570 games at 1 request/second
#   Rscript backtest/build_odds_archive.R <raw_dir> --from-raw       # rebuild offline from <raw_dir>
#   options: --seasons=2023,2024   --out=backtest/data/odds_archive
#
# <raw_dir> receives one gzipped ESPN response per game (not committed) and a fetch log
# (fetch_log.ndjson). The derived CSVs and SOURCES.json (the sha256 of every raw response
# and every derived file) go to the output directory and are committed, as
# backtest/build_inputs.R does for backtest/data/.
#
# THE 2025 HOLDOUT IS SEALED: any season after 2024 stops the script before it loads a
# schedule or makes a request (R/odds/archive.R). Exit status 1 when any game could not be
# fetched; the files are still written, with the failures listed in SOURCES.json.
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(name, default) {
  hit <- grep(sprintf("^--%s=", name), args, value = TRUE)
  if (length(hit) == 0) default else sub(sprintf("^--%s=", name), "", hit[[1]])
}
positional <- args[!startsWith(args, "--")]
if (length(positional) != 1L) {
  stop("usage: Rscript backtest/build_odds_archive.R <raw_dir> [--seasons=2023,2024] [--from-raw] [--out=DIR]")
}
raw_dir <- positional[[1]]
from_raw <- "--from-raw" %in% args

if (!file.exists("config.R") || !dir.exists("R/odds")) {
  stop("Run from the repository root (config.R and R/odds not found)")
}
cfg_env <- new.env()
sys.source("config.R", envir = cfg_env)
source("R/capture_raw.R")
for (f in sort(list.files("R/odds", pattern = "\\.R$", full.names = TRUE))) source(f)

seasons <- as.integer(strsplit(arg_value("seasons", "2023,2024"), ",", fixed = TRUE)[[1]])
odds_archive_assert_seasons(seasons)   # before any schedule is loaded or any request is made
out_dir <- arg_value("out", ODDS_ARCHIVE_DIR)

if (from_raw) {
  games <- odds_archive_read_event_map(file.path(out_dir, "event_map.csv"))
  games <- games[games$season %in% seasons, , drop = FALSE]
  fetch_fn <- odds_replay_fetch(raw_dir)
} else {
  games <- odds_archive_games(nflreadr::load_schedules(seasons), seasons)
  fetch_fn <- odds_http_get
}
message(sprintf("Odds archive: %d games, seasons %s, %s", nrow(games), paste(seasons, collapse = ", "),
                if (from_raw) "replaying stored raw responses" else "fetching at 1 request/second"))

provider <- provider_espn_core(cfg = odds_http_config(env = cfg_env), fetch_fn = fetch_fn,
                               log_path = file.path(raw_dir, "fetch_log.ndjson"))
res <- odds_archive_build(games, provider, out_dir, raw_dir)

cat("\nCoverage (games with a complete open and close):\n")
print(res$coverage[res$coverage$venue_id == "any", ], row.names = FALSE)
cat("\n", res$status$source, ": ", res$status$status, " - ", res$status$detail, "\n", sep = "")
verify <- odds_archive_verify(out_dir, raw_dir)
if (length(verify)) stop("odds archive: verification failed: ", paste(verify, collapse = "; "))
if (!identical(res$status$status, "ok")) {
  message("INCOMPLETE: some games could not be fetched; see fetch_failures in SOURCES.json")
  quit(status = 1)
}
````

- [ ] **Step 4: GREEN.** Run the test file: no failures, exit 0. (It includes a subprocess run of the script with `--seasons=2023,2025`; it must stop on the seal before any network access.)
- [ ] **Step 5: commit.**

```bash
git add R/odds/archive.R backtest/build_odds_archive.R tests/testthat/test-odds-archive.R
git commit -m "feat(odds): decision-time archive builder, coverage report and verifier; refuses 2025 (D1)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 9: build and commit the 2023–2024 archive (*sonnet*; needs the network, about 10 minutes)

**Files:** create `tests/testthat/test-odds-archive-data.R`; create (by running the builder) `backtest/data/odds_archive/{espn_game_odds.csv,event_map.csv,COVERAGE.csv,SOURCES.json}`.

This is the only task that fetches the ESPN archive: 570 requests at 1 request/second. Do not run another odds job at the same time (the 1 request/second budget is per domain, per process). The 2025 seal is already enforced by Task 8, and the next command is the one that would stop on `--seasons=2025`.

- [ ] **Step 1: write the data guard.** Create `tests/testthat/test-odds-archive-data.R`:

````r
# =============================================================================
# Guard on the COMMITTED decision-time archive (backtest/data/odds_archive/, built by
# backtest/build_odds_archive.R). The 2025 Holdout is sealed: no 2025 row may be in it.
# The raw ESPN responses are not committed, so only the derived files are re-hashed here.
# =============================================================================

arch_dir <- file.path(PROJECT_ROOT, "backtest", "data", "odds_archive")
arch_read <- function(name) utils::read.csv(file.path(arch_dir, name), stringsAsFactors = FALSE, na.strings = "")

test_that("the committed archive holds 2023 and 2024 only, with no 2025 row anywhere", {
  src <- jsonlite::read_json(file.path(arch_dir, "SOURCES.json"))
  expect_equal(src$max_season, 2024L)
  expect_setequal(unlist(src$seasons), c(2023L, 2024L))
  arch <- arch_read("espn_game_odds.csv")
  em <- arch_read("event_map.csv")
  expect_true(all(arch$season %in% c(2023L, 2024L)))
  expect_true(all(em$season %in% c(2023L, 2024L)))
  expect_false(any(grepl("^2025_", c(arch$game_id, em$game_id))))
})

test_that("every derived file matches its recorded sha256 and uses LF line endings", {
  expect_equal(odds_archive_verify(arch_dir, NULL), character())
  for (f in c("espn_game_odds.csv", "event_map.csv", "COVERAGE.csv", "SOURCES.json")) {
    bytes <- readBin(file.path(arch_dir, f), "raw", file.size(file.path(arch_dir, f)))
    expect_false(as.raw(13) %in% bytes, info = f)
  }
})

test_that("the archive covers the 570 games of 2023-2024 and every game is a known schedule game", {
  em <- arch_read("event_map.csv")
  expect_equal(nrow(em), 570L)
  expect_equal(as.vector(table(em$season)), c(285L, 285L))
  games <- utils::read.csv(file.path(PROJECT_ROOT, "backtest", "data", "games.csv"), stringsAsFactors = FALSE)
  expect_true(all(em$game_id %in% games$game_id))               # backtest/data/games.csv is hash-locked and stops at 2024
  arch <- arch_read("espn_game_odds.csv")
  expect_true(all(arch$game_id %in% em$game_id))
  expect_equal(sort(unique(arch$venue_id)), "espn_bet")
})

test_that("COVERAGE.csv is exactly what the archive rows imply, and its numbers are the measured ones", {
  arch <- arch_read("espn_game_odds.csv")
  em <- arch_read("event_map.csv")
  snaps <- new_odds_snapshots(data.frame(
    game_id = arch$game_id, market_id = arch$market_id, venue_id = arch$venue_id, side = arch$side,
    line = arch$line, price_american = arch$price_american, snapshot_kind = arch$snapshot_kind,
    source = "espn_core", raw_sha256 = arch$raw_sha256, stringsAsFactors = FALSE))
  games <- data.frame(game_id = em$game_id, season = em$season, stringsAsFactors = FALSE)
  recomputed <- odds_coverage(snaps, games)
  committed <- arch_read("COVERAGE.csv")
  expect_equal(recomputed, committed, ignore_attr = TRUE)
  any_ml <- committed[committed$venue_id == "any" & committed$market_id == "moneyline", ]
  # Measured 2026-10-13: ESPN BET has a close for almost every game but no opener for 2023 weeks 1-5
  expect_equal(any_ml$games_with_open_and_close[any_ml$season == 2023], 205L)
  expect_equal(any_ml$games_with_open_and_close[any_ml$season == 2024], 284L)
})

test_that("the frozen v1 protocol does not hash the archive, and its ESPN input is untouched", {
  win <- jsonlite::read_json(file.path(PROJECT_ROOT, "backtest", "eval_windows", "nfl_games_v1.json"), simplifyVector = TRUE)
  expect_false("odds_archive" %in% names(win$data_sha256))
  expect_identical(digest::digest(file = file.path(PROJECT_ROOT, "backtest", "data", "espn_open_close.csv"), algo = "sha256"),
                   win$data_sha256[["espn_open_close"]])
})
````

- [ ] **Step 2: RED.** With `backtest/data/odds_archive/` absent:

```
── 1. Error ('test-odds-archive-data.R:11:3'): the committed archive holds 2023
Error in `open.connection(con, "rb")`: cannot open the connection
── 2. Error ('test-odds-archive-data.R:22:3'): every derived file matches its re
Error in `open.connection(con, "rb")`: cannot open the connection
```

- [ ] **Step 3: the seal, on the real script.** `Rscript backtest/build_odds_archive.R <raw_dir> --seasons=2024,2025`. Expected: it stops immediately, before any request:

```
Error: odds archive: refusing season(s) 2025. The 2025 Holdout is sealed; only the G3 Holdout build, after the freeze, may add 2025 game rows (archive window 2023-2024).
Execution halted
```

- [ ] **Step 4: build.** `<raw_dir>` is an empty scratch directory outside the repository (about 16 MB; do not commit it). `Rscript backtest/build_odds_archive.R <raw_dir>` (run it in the background with the log in the scratchpad). Expected final output (measured in the dry run on 2026-10-13; 9.5 minutes):

```
Coverage (games with a complete open and close):
 season venue_id market_id games_expected games_with_open games_with_close games_with_open_and_close pct_open_and_close
   2023      any moneyline            285             207              282                       205               71.9
   2023      any    spread            285             192              281                       192               67.4
   2023      any     total            285             192              285                       192               67.4
   2024      any moneyline            285             284              284                       284               99.6
   2024      any    spread            285             284              284                       284               99.6
   2024      any     total            285             284              284                       284               99.6

espn_core_game_odds: ok - 570 of 570 games fetched
```

  The coverage is the answer to the roadmap's "open and close from 2023": **it holds for 2024 (284 of 285 games; the missing one is `2024_02_PIT_DEN`) but not for all of 2023.** ESPN BET has a close for 282 to 285 games of 2023 but an opener for only 207 (moneyline): the openers are missing for 80 regular-season games, 16 in each of weeks 1 to 4, 14 in week 5 and one each in weeks 6 and 8. Playoff games are complete. **G3's CLV sample can therefore draw picks from at most 205 games of 2023 with both lines (71.9%) and 284 of 2024: 489 games. The A2 gate needs 400 picks, and the 2024-only look drew 199 to 214 picks from 284 games (`RESULT.md` of backtest-games-v1), so the gate remains uncertain.** If the numbers differ by more than a handful of games, stop: ESPN may have changed what it serves; diagnose before committing (superpowers:systematic-debugging).
- [ ] **Step 5: offline rebuild proves determinism.** `Rscript backtest/build_odds_archive.R <raw_dir> --from-raw` rebuilds from the stored raw responses with no network. Then `git status --short backtest/data/odds_archive` must show the three CSVs unchanged (only `SOURCES.json`'s `built_utc` may differ): `git diff --stat backtest/data/odds_archive/espn_game_odds.csv backtest/data/odds_archive/event_map.csv backtest/data/odds_archive/COVERAGE.csv` prints nothing after you `git add` the first build, or compare `sha256sum` before and after.
- [ ] **Step 6: GREEN.** Run `test-odds-archive-data.R`: no failures, exit 0. (The numbers in its last assertions are the measured ones above: if a re-run of the build gives different numbers, change them only after Step 4's diagnosis.)
- [ ] **Step 7: commit** (owner checkpoint CP4: additive data, reviewed before merge).

```bash
git add backtest/data/odds_archive tests/testthat/test-odds-archive-data.R
git commit -m "data(odds): ESPN game openers and closes for 2023-2024 with raw sha256 (570 games, no 2025) (D1)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 10: the live smoke test outside the suite, the no-live guard, and recursive R/ scans (*haiku*)

**Files:** create `tests/testthat/test-odds-no-live.R`, `tests/live/test-odds-live.R`, `scripts/odds_live_smoke.R`, `.github/workflows/odds-live-smoke.yml`; edit `tests/testthat/test-module-duplicates.R` and `tests/testthat/test-source-targets.R` (the R/ scans become recursive, so `R/odds/*.R` is covered by the duplicate-definition and `source()` target checks).

The live tests are the only place a real odds request is made. They live in `tests/live/`, which `scripts/run_tests.R` (it runs `tests/testthat` only) never reaches; they run through `scripts/odds_live_smoke.R` or the manual workflow, and each skips as `LIVE:` only after `skip_live()`'s real connectivity check fails (`helper-live.R`).

- [ ] **Step 1: write the guard test.** Create `tests/testthat/test-odds-no-live.R`:

````r
# =============================================================================
# The default suite makes no odds request. Live checks live in tests/live/ and run
# only through scripts/odds_live_smoke.R (roadmap D1 gate).
# =============================================================================

odds_test_files <- function() {
  files <- list.files(file.path(PROJECT_ROOT, "tests", "testthat"), pattern = "^test-odds-.*\\.R$", full.names = TRUE)
  files[!basename(files) %in% "test-odds-no-live.R"]
}

test_that("the odds tests use the fake fetch seam, never a live helper or the real network call", {
  expect_gt(length(odds_test_files()), 5)
  for (f in odds_test_files()) {
    txt <- readLines(f, warn = FALSE, encoding = "UTF-8")
    expect_false(any(grepl("skip_live\\(|with_live\\(|live_host_reachable\\(", txt)), info = basename(f))
    expect_false(any(grepl("Sys.setenv\\(\\s*NFL_ODDS_FORBID_LIVE", txt)), info = basename(f))
    if (basename(f) != "test-odds-http.R") {
      expect_false(any(grepl("odds_http_get", txt)), info = basename(f))   # only the guard test names it
    }
  }
})

test_that("the live guard is on for the whole suite, and the live tests are outside tests/testthat", {
  expect_identical(Sys.getenv("NFL_ODDS_FORBID_LIVE"), "1")
  expect_true(file.exists(file.path(PROJECT_ROOT, "tests", "live", "test-odds-live.R")))
  expect_false(file.exists(file.path(PROJECT_ROOT, "tests", "testthat", "test-odds-live.R")))
  runner <- readLines(file.path(PROJECT_ROOT, "scripts", "run_tests.R"), warn = FALSE)
  expect_true(any(grepl('test_dir("tests/testthat"', runner, fixed = TRUE)))
  wf <- yaml::read_yaml(file.path(PROJECT_ROOT, ".github", "workflows", "odds-live-smoke.yml"))
  on <- if (!is.null(wf[["on"]])) wf[["on"]] else wf[["TRUE"]]
  expect_identical(names(on), "workflow_dispatch")        # manual only
})

test_that("no provider or HTTP code can reach a host outside the owner-approved keyless set", {
  code <- unlist(lapply(list.files(file.path(PROJECT_ROOT, "R", "odds"), pattern = "\\.R$", full.names = TRUE),
                        readLines, warn = FALSE, encoding = "UTF-8"))
  urls <- unique(unlist(regmatches(code, gregexpr("https?://[A-Za-z0-9.-]+", code))))
  hosts <- sub("^https?://", "", urls)
  expect_true(all(hosts %in% c("github.com", "example.test")), info = paste(hosts, collapse = ", "))   # hosts appear only in comments
})
````

- [ ] **Step 2: RED.** With `tests/live/`, the smoke script and the workflow absent:

```
── 1. Failure ('test-odds-no-live.R:25:3'): the live guard is on for the whole s
Expected `file.exists(file.path(PROJECT_ROOT, "tests", "live", "test-odds-live.R"))` to be TRUE.
── 2. Error ('test-odds-no-live.R:29:3'): the live guard is on for the whole sui
Error in `file(file, "rt", encoding = fileEncoding)`: cannot open the connection
```

- [ ] **Step 3: create the live files.** `tests/live/test-odds-live.R`:

````r
# =============================================================================
# LIVE smoke tests for the keyless odds layer. NOT part of the default suite:
# scripts/run_tests.R runs tests/testthat only. Run with
#   Rscript scripts/odds_live_smoke.R
# (or the manual "Odds live smoke" workflow). Each test skips as LIVE only after a real
# connectivity check to its host fails (helper-live.R). They make a handful of requests at
# 1 request/second and compare the live responses with the recorded fixtures, so API drift
# shows up here and not in the default suite.
# =============================================================================

test_that("LIVE: ESPN core still returns the 2024 week 1 open and close lines we recorded", {
  skip_live("sports.core.api.espn.com")
  odds_http_reset()
  game <- data.frame(game_id = "2024_01_ARI_BUF", season = 2024L, espn = "401671617", stringsAsFactors = FALSE)
  res <- with_live("sports.core.api.espn.com", provider_espn_core()$game_snapshots(game))
  expect_equal(res$source_status$status, "ok")
  recorded <- parse_espn_game_odds(odds_fixture_json("espn_game_odds_2024_01_ARI_BUF.json"), "2024_01_ARI_BUF", "x")
  key <- function(d) d[order(d$venue_id, d$market_id, d$side, d$snapshot_kind), c("venue_id", "market_id", "side", "snapshot_kind", "line", "price_american")]
  expect_equal(key(res$snapshots), key(recorded), ignore_attr = TRUE)
})

test_that("LIVE: Kalshi still serves the historical cutoff and a game-market listing", {
  skip_live("api.elections.kalshi.com")
  odds_http_reset()
  rec <- with_live("api.elections.kalshi.com", odds_fetch(kalshi_cutoff_url(), odds_http_config(), source = "kalshi_cutoff"))
  expect_equal(rec$status, 200L)
  expect_false(is.null(odds_json(rec)$market_settled_ts))
  rec2 <- with_live("api.elections.kalshi.com",
                    odds_fetch(kalshi_event_markets_url("KXNFLGAME-26OCT12BUFLAR", historical = FALSE), odds_http_config(), source = "kalshi_markets"))
  expect_equal(rec2$status, 200L)
  expect_gte(length(odds_json(rec2)$markets), 2L)
})
````

  `scripts/odds_live_smoke.R`:

````r
#!/usr/bin/env Rscript
# Live smoke test of the keyless odds layer (tests/live/). Makes a handful of real requests
# at 1 request/second; never part of scripts/run_tests.R. Exit status 1 on any failure.
#   Rscript scripts/odds_live_smoke.R
if (!file.exists("config.R") || !dir.exists("tests/live")) stop("Run from the repository root")
Sys.setenv(NFL_ODDS_FORBID_LIVE = "0")
env <- new.env(parent = globalenv())
sys.source("config.R", envir = env)
sys.source("R/capture_raw.R", envir = env)
for (f in sort(list.files("R/odds", pattern = "\\.R$", full.names = TRUE))) sys.source(f, envir = env)
sys.source("tests/testthat/helper-live.R", envir = env)
sys.source("tests/testthat/helper-odds.R", envir = env)
fixture_dir <- normalizePath(file.path("tests", "testthat", "fixtures", "odds"))
env$odds_fixture_path <- function(...) file.path(fixture_dir, ...)   # test_path() would resolve inside tests/live
Sys.setenv(NFL_ODDS_FORBID_LIVE = "0")   # helper-odds.R sets the guard for the default suite; undo it here
res <- testthat::test_dir("tests/live", env = env, reporter = "summary", stop_on_failure = FALSE)
df <- as.data.frame(res)
quit(status = if (sum(df$failed) + sum(df$error) > 0) 1 else 0)
````

  `.github/workflows/odds-live-smoke.yml`:

````yaml
name: Odds live smoke

# Manual only. Makes a handful of real requests (1 request/second) to ESPN and Kalshi and
# compares them with the recorded fixtures, to catch API drift. Not part of CI.

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  smoke:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up R
        uses: r-lib/actions/setup-r@v2
        with:
          r-version: "4.5.1"
          use-public-rspm: true

      - name: Install dependencies
        run: install.packages(c("httr2", "jsonlite", "digest", "testthat", "curl", "withr"))
        shell: Rscript {0}

      - name: Live smoke
        run: Rscript scripts/odds_live_smoke.R
````

- [ ] **Step 4: make the R/ scans recursive.** Apply (`git apply --check` first):

````diff
diff --git a/tests/testthat/test-module-duplicates.R b/tests/testthat/test-module-duplicates.R
index a94b0a4..a8959d3 100644
--- a/tests/testthat/test-module-duplicates.R
+++ b/tests/testthat/test-module-duplicates.R
@@ -61,14 +61,14 @@ test_that("the definition scan sees plain and conditional definitions", {
 })
 
 test_that("no new function is defined in more than one R/ module", {
-  files <- list.files(file.path(PROJECT_ROOT, "R"), pattern = "\\.R$", full.names = TRUE)
+  files <- list.files(file.path(PROJECT_ROOT, "R"), pattern = "\\.R$", full.names = TRUE, recursive = TRUE)
   all_defs <- strip_if(unlist(lapply(files, defined_functions)))
   dups <- sort(unique(all_defs[duplicated(all_defs)]))
   expect_equal(setdiff(dups, KNOWN_DUPLICATES), character())
 })
 
 test_that("NFLmarket.R and NFLbrier_logloss.R add no new copies of R/ functions", {
-  r_files <- list.files(file.path(PROJECT_ROOT, "R"), pattern = "\\.R$", full.names = TRUE)
+  r_files <- list.files(file.path(PROJECT_ROOT, "R"), pattern = "\\.R$", full.names = TRUE, recursive = TRUE)
   r_defs <- unique(strip_if(unlist(lapply(r_files, defined_functions))))
   overlaps <- unlist(lapply(ENGINE_FILES, function(f) {
     defs <- defined_functions(file.path(PROJECT_ROOT, f))
````

````diff
diff --git a/tests/testthat/test-source-targets.R b/tests/testthat/test-source-targets.R
index af5296d..8d4f00c 100644
--- a/tests/testthat/test-source-targets.R
+++ b/tests/testthat/test-source-targets.R
@@ -10,7 +10,7 @@ literal_source_targets <- function(path) {
 
 test_that("literal source() targets in entry points exist", {
   entry <- c("run_week.R", "NFLsimulation.R", "NFLmarket.R",
-             file.path("R", list.files(file.path(PROJECT_ROOT, "R"), pattern = "\\.R$")))
+             file.path("R", list.files(file.path(PROJECT_ROOT, "R"), pattern = "\\.R$", recursive = TRUE)))
   targets <- unique(unlist(lapply(file.path(PROJECT_ROOT, entry), literal_source_targets)))
   missing <- targets[!file.exists(file.path(PROJECT_ROOT, targets))]
   expect_equal(missing, character())
````

- [ ] **Step 5: GREEN.** Run `test-odds-no-live.R`, `test-module-duplicates.R`, `test-source-targets.R`, `test-workflows.R`, `test-skip-hygiene.R`: no failures, exit 0.
- [ ] **Step 6: live smoke (network; do not run while another odds job is running).** `Rscript scripts/odds_live_smoke.R` makes about 4 requests at 1 request/second. Expected: both tests pass (or skip as `LIVE:` when a host is unreachable); exit 0. Quote the output in the close-out.
- [ ] **Step 7: commit.**

```bash
git add tests/testthat/test-odds-no-live.R tests/live/test-odds-live.R scripts/odds_live_smoke.R .github/workflows/odds-live-smoke.yml tests/testthat/test-module-duplicates.R tests/testthat/test-source-targets.R
git commit -m "test(odds): live smoke outside the suite, no-live guard, recursive R/ scans (D1)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 11: documentation (*sonnet*)

**Files:** create `docs/odds-sources.md`; edit `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `HANDOFF.md`.

`docs/odds-sources.md` carries the endpoints, rate limits, per-season and per-market coverage (the Task 9 numbers) and the terms-of-service matrix (spec Phase 2). Every number in it was produced by a script run on 2026-10-13 or comes from `reports/2026-09-29/DATA_SOURCES_SPIKE.md`; if the Task 9 build gave different numbers, change the table to match `backtest/data/odds_archive/COVERAGE.csv`. It states plainly that the terms texts are **not reviewed** (CP6).

- [ ] **Step 1: create `docs/odds-sources.md`:**

````markdown
# Keyless odds sources

The odds layer (`R/odds/`) reads three public sources. None needs an API key or a trial. This file lists what each one serves, how fast we may call it, what it covers and what we have and have not verified about its terms. Every number below comes from a script run on the date shown, or from `reports/2026-09-29/DATA_SOURCES_SPIKE.md`, and is marked so.

## Rules every request follows (`R/odds/http.R`)

- A truthful user agent (`CAPTURE_USER_AGENT`: names this project and its repository).
- A 20 second timeout.
- At most **1 request per second per registrable domain** (`espn.com`, `kalshi.com`). This is a floor in code: a smaller `CAPTURE_MIN_INTERVAL_SEC` (the constant is 0.5 today) is raised to 1.
- Backoff on HTTP 429/5xx and on network errors: up to `CAPTURE_MAX_TRIES` attempts, waiting 2, 4, 8 ... seconds (the server's `Retry-After` when sent), capped at 60 s.
- A 401/403, or a 429 that survives the retries, is **never worked around**. The domain is marked blocked for the rest of the process and no further request is sent to it.
- The sha256 of every raw response is returned, written to the capture manifest (`data/raw_capture/manifest.ndjson`) or the archive fetch log, and recorded in `backtest/data/odds_archive/SOURCES.json`.

## Sources, endpoints and coverage

| Source | Endpoint (no key) | Gives | Coverage |
|---|---|---|---|
| **nflverse** (`nflreadr::load_schedules`) | GitHub release `nflverse-data/schedules` | Consensus closing moneyline, spread and total per game. No open, no timestamp. | Closing moneylines for 100% of games 2018–2025 (`HANDOFF.md`, confirmed facts). |
| **ESPN core** game odds | `https://sports.core.api.espn.com/v2/sports/football/leagues/nfl/events/{id}/competitions/{id}/odds` | Per provider: moneyline, spread and total with an `open` block and a `close` block. The blocks have **no timestamp**. | See the measured table below. ESPN BET (provider 58) is the book through 2025 week 11 at least; DraftKings (100) in weeks 15, 17 and 18 of 2025 and in 2026 (spike, section 3). 2022 has a close only; 2018–2021 have neither. |
| **ESPN core** prop lines | `.../odds/100/propBets` (DraftKings), `.../odds/58/propBets` (ESPN BET archive) | Prop **lines**, not prices. DraftKings propBets are live only (404 after the game). | ESPN BET archive: 2024 through about 2025 week 13; only a subset of rows keeps prices and `lastUpdated` is after kickoff for 93–99% of rows, so it is line movement only (spike, section 2). |
| **Kalshi** public market data | `https://api.elections.kalshi.com/trade-api/v2`: `/historical/cutoff`, `/markets?event_ticker=`, `/historical/markets?event_ticker=`, `/series/{S}/markets/{T}/candlesticks`, `/historical/markets/{T}/candlesticks` (`period_interval=60`) | Hourly yes bid/ask/last/volume candles for game (`KXNFLGAME`) and player contracts. | Anytime TD from 2025-09-04 (`KXNFLANYTD`; 2026 uses `KXNFLTD` strikes), receiving, rushing and passing yards from 2025-10-06, receptions from 2025-10-27, game series from 2025-07-31 (spike, section 1). 93.1% of a random sample of markets had a pre-kickoff price. The 2025 props are for P3 under its signed protocol; D1 uses 2026 markets only. |

Quirks the code handles: the Kalshi historical cutoff moves (2026-07-31 on 2026-09-29, 2026-08-14 on 2026-10-13), so it is read at run time and each event tries the cutoff side first and falls back on a 404; the two candle forms name fields differently (`price.close` and `price.close_dollars`); Jacksonville is `JAC` and the Rams `LA` or `LAR` in Kalshi tickers; some strikes open after kickoff and have no pre-kickoff candle (the receiving-yards fixture is such a market); `KXNFLTD` holds 1+/2+/3+/4+ strikes as separate markets and only 1+ and 2+ are mapped.

### ESPN game odds archive 2023–2024 (measured 2026-10-13)

Built by `Rscript backtest/build_odds_archive.R <raw_dir>`: 570 requests to `sports.core.api.espn.com`, 1 per second, 9.5 minutes, all 570 answered HTTP 200, 16.4 MB of raw JSON (not committed; its sha256 are in `backtest/data/odds_archive/SOURCES.json`). Source: `backtest/data/odds_archive/COVERAGE.csv`. "Games with both" counts games where both sides of the line exist in both the opener and the closer.

| Season | Market | Games | With opener | With closer | With both | Both |
|---|---|---|---|---|---|---|
| 2023 | moneyline | 285 | 207 | 282 | 205 | 71.9% |
| 2023 | spread | 285 | 192 | 281 | 192 | 67.4% |
| 2023 | total | 285 | 192 | 285 | 192 | 67.4% |
| 2024 | moneyline | 285 | 284 | 284 | 284 | 99.6% |
| 2024 | spread | 285 | 284 | 284 | 284 | 99.6% |
| 2024 | total | 285 | 284 | 284 | 284 | 99.6% |

Only ESPN BET (provider 58) appears in the archive: the other providers in the responses (Bet 365, "ESPN Bet - Live Odds" and others) have no usable open and close blocks. The 2023 openers are missing for 80 regular-season games (16 in each of weeks 1 to 4, 14 in week 5, one each in weeks 6 and 8); playoff games are complete. In 2024 the single game without a pair is `2024_02_PIT_DEN`. Each season has 285 games (272 regular season plus 13 playoff games). **2025 rows are not in the archive and the builder refuses them** (the Holdout is sealed; the G3 Holdout build appends them after the freeze).

The ESPN opener and closer have no timestamp, so their rows have `captured_at` empty and `snapshot_kind` `open`/`close`. The closing rule (`R/odds/closing.R`) treats such a labelled close as the venue's close with no gap, never stale, and reports its timing as `labelled`. Timestamped sources (Kalshi candles, forward capture) follow the full rule: the last snapshot at or before kickoff at the same line, stale when more than 60 minutes before kickoff.

### Forward capture

`odds-capture.yml` runs `scripts/capture_odds_raw.R` on 8 cron windows per week. A live run on 2026-10-13 (a Tuesday, no game inside the 36 hour horizon) made 192 requests, all HTTP 200, in 3 minutes 11 seconds, wrote 19.7 MB of raw responses and a manifest line per request with its sha256.

## Terms-of-service matrix (spec Phase 2, audit S4 / A4)

"Verified" means checked by a run or a page read on the date shown. **The terms texts of ESPN, Kalshi and nflverse have not been reviewed by the owner; production use of the archive and the capture waits for the owner's sign-off.**

| Source | Access verified | Documented rate limit | Our rate | Block behaviour | Terms text | Owner sign-off |
|---|---|---|---|---|---|---|
| nflverse | Downloads via `nflreadr` (GitHub release assets), no key | GitHub's release download limits apply; none documented by nflverse | one download per run | n/a | License not read by the agent: **to review** | pending |
| ESPN core API | HTTP 200 without credentials, 2,400+ requests in the 2026-09-29 spike plus 192 capture and 570 archive requests in 2026-10-13, no 401/403/429 | None published (the endpoints are undocumented) | 1 request/second | stop on 403/429 | ESPN/Disney terms of use: **to review**; the endpoints are not an offered public API | pending |
| Kalshi public market data | HTTP 200 without credentials on the market, event, candle and cutoff endpoints (2026-10-13) | Token buckets per tier, read bucket 200 tokens/second at the Basic tier, 429 on excess, exponential backoff recommended (`docs.kalshi.com/getting_started/rate_limits`, read 2026-10-13; the page describes authenticated requests and does not say whether public endpoints are metered) | 1 request/second | stop on 403/429 | Kalshi developer terms: **to review** | pending |

Retired and excluded (audit S1, owner rule keyless-only): the ScoresAndOdds private endpoint, OddsTrader, Covers, The Odds API (historical data needs a paid plan) and OddsPapi (needs a signup key).

## Live checks

`Rscript scripts/odds_live_smoke.R` (or the manual "Odds live smoke" workflow) makes about four requests and compares the live ESPN response for `2024_01_ARI_BUF` and the Kalshi cutoff and `KXNFLGAME-26OCT12BUFLAR` listing with the recorded fixtures. It is never part of `scripts/run_tests.R`.
````

- [ ] **Step 2: inventories.** Apply (`git apply --check` first):

````diff
diff --git a/README.md b/README.md
index 8bb2278..442d9ad 100644
--- a/README.md
+++ b/README.md
@@ -308,6 +308,19 @@ Rscript scripts/run_matrix.R  # Should show 11/11 passed (golden-master needs ne
 | `backtest/metrics.R`, `backtest/controls.R` | Paired block bootstrap, DM-HLN, BH, ECE, CLV; leak canary, shuffled labels, market copy |
 | `backtest/eval_windows/nfl_games_v1.json` | Hash-locked windows, data and protocol |
 | `backtest/prospective.R` | Weekly bundle of unplayed games from the v1 candidates (never predicts a played game) |
+| `backtest/build_odds_archive.R` | Builds `backtest/data/odds_archive/` (ESPN game openers and closes, 2023-2024 only; refuses 2025) with the sha256 of every raw response in `SOURCES.json` |
+
+### Keyless Odds Layer (`R/odds/`)
+| File | Purpose |
+|------|---------|
+| `R/odds/http.R` | The only HTTP layer: truthful user agent, 20 s timeout, at most 1 request/second per domain, backoff on 429/5xx, no workaround for a 403, raw sha256 per response |
+| `R/odds/snapshots.R` | The `odds_snapshots` shape, market and venue vocabulary, validation |
+| `R/odds/closing.R` | The closing rule: last snapshot at or before kickoff at the same line; over 60 minutes is stale |
+| `R/odds/provider.R`, `provider_nflverse.R`, `provider_espn_core.R`, `provider_kalshi.R` | One provider interface and the three keyless sources |
+| `R/odds/capture.R`, `scripts/capture_odds_raw.R` | Forward capture (`odds-capture.yml`) as a caller of the providers |
+| `R/odds/archive.R` | The decision-time archive builder, coverage report and verifier |
+| `scripts/odds_live_smoke.R`, `tests/live/` | Manual live smoke test (never part of `run_tests.R`) |
+| `docs/odds-sources.md` | Endpoints, rate limits, coverage and the terms-of-service matrix |
 
 ### Data Contract and Web App (`contracts/`, `web/`)
 | File | Purpose |
````

````diff
diff --git a/CLAUDE.md b/CLAUDE.md
index 6313e99..7d62b97 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -349,6 +349,7 @@ USE_SNAP_WEIGHTED_INJURIES <- FALSE  # Must be FALSE
 - `R/sim_bundle.R` - the simulator's weekly bundle, written by `run_week.R` (replaced the HTML report at A8)
 - `R/mu_terms.R` - explicit mean composition: the term table and `compose_mu()` (M22)
 - `R/schedule_context.R` - neutral sites, home-field points and rest days (M24, M23)
+- `R/odds/` - the keyless odds layer (D1): `http.R` is the only HTTP code (1 request/second per domain, no workaround for a 403/429); providers for nflverse, ESPN core and Kalshi; the `odds_snapshots` shape; the closing rule; the archive builder. Tests inject a fetch function and read `tests/testthat/fixtures/odds/`; live checks are in `tests/live/` only. Endpoints and the terms matrix: `docs/odds-sources.md`
 
 ### Props Data Sources
 - `sports/nfl/props/data_sources.R` - Player projections with fallback chain
@@ -364,6 +365,7 @@ USE_SNAP_WEIGHTED_INJURIES <- FALSE  # Must be FALSE
 ### Game Backtest
 - `backtest/walk_forward.R` - pre-registered walk-forward shootout; `--stage score` refuses to run unless `reports/<date>/backtest-games-v1/PROTOCOL.md` matches the hash in `backtest/eval_windows/nfl_games_v1.json` and is committed. Never edit a frozen PROTOCOL.md; register a new version instead.
 - `backtest/build_inputs.R` - derives the committed point-in-time inputs in `backtest/data/`
+- `backtest/build_odds_archive.R` - derives `backtest/data/odds_archive/` (ESPN game openers and closes, 2023-2024). It refuses 2025: the G3 Holdout build appends 2025 after the freeze
 
 ### Tests
 - `tests/testthat/setup.R` - Test infrastructure
````

- [ ] **Step 3: CHANGELOG and HANDOFF.** Apply:

````diff
diff --git a/CHANGELOG.md b/CHANGELOG.md
index b9ee306..56bdfdb 100644
--- a/CHANGELOG.md
+++ b/CHANGELOG.md
@@ -4,6 +4,13 @@ All notable changes to the NFL Prediction Model are documented in this file.
 
 ## [Unreleased]
 
+### D1: the keyless odds layer and the decision-time archive (roadmap D1; audit S2, S4)
+
+- **`R/odds/`:** one HTTP layer (`http.R`: truthful user agent, 20 s timeout, at most 1 request/second per domain as a floor in code, backoff on 429/5xx, a 401/403/429 that survives the retries blocks the domain, sha256 of every raw response, fetch log), the `odds_snapshots` shape and market/venue vocabulary (`snapshots.R`), the closing rule (`closing.R`: last snapshot at or before kickoff at the same line, more than 60 minutes is stale, a missing line stays missing), one provider interface with `provider_nflverse`, `provider_espn_core` and `provider_kalshi`, forward capture (`capture.R`) and the archive builder (`archive.R`). No new dependency; tests inject a fetch function and read recorded fixtures in `tests/testthat/fixtures/odds/`.
+- **Capture:** `scripts/capture_odds_raw.R` is a thin caller of `run_capture()`; `odds-capture.yml` is unchanged. `capture_http_get()` delegates to the new layer. `CAPTURE_MIN_INTERVAL_SEC` is 0.5 in `config.R` (2 requests/second); the layer raises it to 1 and the script says so. A live run: 192 requests, all HTTP 200, 3 min 11 s.
+- **Archive:** `backtest/build_odds_archive.R` wrote `backtest/data/odds_archive/` (ESPN BET game openers and closes, 570 games of 2023–2024, 9.5 min, 570/570 answered). It refuses 2025 before any schedule load or request. Measured coverage of games with a complete moneyline opener and closer: 2023 205 of 285 (71.9%), 2024 284 of 285 (99.6%). ESPN BET has no opener for 80 regular-season games of 2023 (weeks 1 to 5 mostly), so "open and close from 2023" holds from 2024 on. `backtest/data/espn_open_close.csv` and the v1 protocol hashes are untouched.
+- **Docs:** `docs/odds-sources.md` (endpoints, rate limits, coverage, terms matrix; the terms texts are not yet reviewed by the owner). Manual `odds-live-smoke.yml` and `scripts/odds_live_smoke.R`; the live tests are in `tests/live/`, outside the default suite.
+
 ### A8: the HTML report is retired; the Next.js app is the only UI, offline and online (owner decisions 2026-10-01, 2026-10-03, 2026-10-04)
 
 - **Offline:** `run_week.R` writes a weekly bundle (`R/sim_bundle.R`: C0 market and C3 simulator win probabilities, margin and total distributions over the central 99.9% of draws, source status; every problem is a QA failure, a game without a market keeps NA market fields). `cd web && npm run local` creates a private loopback PostgreSQL, ingests every bundle and serves the app on 127.0.0.1:3000 with no network; Archivo is committed (`next/font/local`), so a build needs no network either.
````

````diff
diff --git a/HANDOFF.md b/HANDOFF.md
index 08ac3f4..051d821 100644
--- a/HANDOFF.md
+++ b/HANDOFF.md
@@ -2,7 +2,11 @@
 
 Resume point for the NFL overhaul. Read this first, then the spec. To verify everything and finish the remaining work in a full local environment (VS Code), use `docs/handoff/2026-09-29-vscode-prompt.md`.
 
-## Current state — A8 (feat/a8-local-app)
+## D1 done - 2026-10-13 (feat/d1-odds-layer, draft PR, awaiting the owner)
+
+The keyless odds layer is in `R/odds/` (see CHANGELOG, "D1"). **Objective:** one HTTP layer, three providers, the `odds_snapshots` shape, the closing rule, the 2023–2024 ESPN opener/closer archive, forward capture on the same code. **Done:** all of it, tests with recorded fixtures only. **Not done:** player alias tables (snapshots carry `player_key`), Kalshi spread/total series, owner sign-off of the terms matrix, raw ESPN responses are not committed (16.4 MB; sha256 in `backtest/data/odds_archive/SOURCES.json`). **Confirmed facts:** the archive has 570 games, no 2025 row; ESPN BET openers cover 205 of 285 games of 2023 and 284 of 285 of 2024; `CAPTURE_MIN_INTERVAL_SEC` 0.5 was 2 requests/second, now floored at 1. **Open risks:** ESPN's endpoints are undocumented; the openers/closers carry no timestamp. **Next target:** G3 reads the archive and appends 2025 only in its Holdout build, after the freeze.
+
+## Previous state — A8 (feat/a8-local-app)
 
 2026-10-13. Branch `feat/a8-local-app` (base `4f9aad3`; `main` at `28e4ed7`, with #210, merged in on 2026-10-13), draft PR #212 against `main` (never merged by the agent). The final whole-branch review returned "with fixes"; the fix wave below applied them and the owner's four decisions, and every gate was re-run on the merged branch.
 
````

- [ ] **Step 4: docs checks.** `test-docs-truth.R` (withdrawn claims must not reappear), `test-repo-hygiene.R` and `scripts/verify_repo_integrity.R` pass.
- [ ] **Step 5: commit.**

```bash
git add docs/odds-sources.md README.md CLAUDE.md CHANGELOG.md HANDOFF.md
git commit -m "docs(odds): sources, rate limits, coverage and terms matrix; inventories and changelog (D1)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 12: gates, review and close-out (*sonnet*)

- [ ] **Step 1: gates, each with a fresh `HOME`.** (Write each command's final lines in the PR body.)

```bash
HOME=<fresh> Rscript scripts/run_tests.R              # exit 0; only allowlisted skips
HOME=<fresh> Rscript scripts/verify_repo_integrity.R  # exit 0
HOME=<fresh> Rscript scripts/run_matrix.R             # every artifact PASS (golden master up to 1800 s)
git diff --exit-code origin/main -- renv.lock DESCRIPTION config.R NFLsimulation.R NFLmarket.R injury_scalp.R R/data_validation.R backtest/eval_windows web/package.json   # no output: nothing owner-gated changed
git diff --name-status origin/main | grep -E '^D' ; test $? -eq 1                                                                  # no file deleted
```

  The golden master is unaffected (no engine file changed); CI's `golden-master` workflow must read "no differences".
- [ ] **Step 2: the default suite makes no odds request.** `grep -rn "odds_http_get" tests/testthat` lists only `test-odds-http.R` (the guard test) and `test-odds-no-live.R` (which scans for it); `tests/testthat/test-odds-no-live.R` passes.
- [ ] **Step 3: coverage report.** `Rscript -e 'print(read.csv("backtest/data/odds_archive/COVERAGE.csv"))'` matches the table in `docs/odds-sources.md`.
- [ ] **Step 4: review.** `superpowers:requesting-code-review`, then the `/code-review` skill at high effort, then the pr-review-toolkit agents: **silent-failure-hunter** (every provider data path), **pr-test-analyzer**, **comment-analyzer** (the roxygen and the docs), and the `/security-review` skill for `http.R`, the two workflows and the capture script. Fix findings in new commits.
- [ ] **Step 5: close-out.** Run `superpowers:finishing-a-development-branch`. Push `feat/d1-odds-layer`, open a draft PR (body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`), confirm CI is green (`gh run list --branch feat/d1-odds-layer`), and wait for the owner to merge (CP7). Then update the roadmap's D1 status and the HANDOFF context-reset packet (objective, done, not done, confirmed facts, open risks, contradictions, next target).
- [ ] **Step 6: hand-offs to later phases.** G3 reads `backtest/data/odds_archive/espn_game_odds.csv` (openers and closes, 2023–2024) and appends 2025 only in its own Holdout build, after the freeze, by raising `ODDS_ARCHIVE_MAX_SEASON` in that PR. P1 (P14) and P3 read `provider_kalshi()$prop_snapshots()` and `select_closing_snapshots()`; the player alias tables (Kalshi UUIDs and ESPN athlete IDs to canonical players) are not part of D1 — snapshots carry `player_key` (`kalshi:<uuid>`, `espn:<athleteId>`) until P1/P3 resolve it.

## Open questions for the owner

1. **Terms of service (CP6, audit S4).** Please read the ESPN, Kalshi and nflverse terms and sign off the matrix in `docs/odds-sources.md`. The plan could not verify them and says so.
2. **`config.R`.** Set `CAPTURE_MIN_INTERVAL_SEC` to `1` so the constant matches the enforced rate? (The code already floors it.)
3. **Untimed ESPN open/close.** ESPN's open and close blocks carry no timestamp, so those rows have `captured_at` NA and the closing rule treats a venue's labelled close as the close with no gap (never stale). Is that acceptable for the A2 CLV gate, or should G3 require a timed second source for the close (Kalshi from 2025, forward capture from 2026)?
4. **`httptest2`.** The plan uses the no-new-dependency fetch seam. Approve `httptest2` only if you prefer recorded-HTTP cassettes; the providers would not change.
5. **Kalshi spread and total series** are not mapped (counted as unsupported). Add them in P3 if the props protocol or G3 needs them?
6. **Player alias tables** (spec Phase 2) are deferred to P1/P3 as noted in Task 12 Step 6.
7. **Release hosting of the raw ESPN responses.** The archive records the sha256 of all 570 raw responses and commits only the derived CSVs, like `backtest/build_inputs.R`. Do you also want the raw gzips (16.4 MB measured) kept as a GitHub Release asset?

## Dry-run evidence (2026-10-13/14)

The plan was applied in `C:/Users/jviol/Downloads/nfl-worktrees/d1dry` (detached at `210f791`, nothing committed). **The plan and the tree agree byte for byte by construction and by check:** every code, fixture, test and doc block in this file was inserted from the dry-run tree by a script (`assemble.py`, which reads each file and each `git diff` of a tracked file); afterwards (a) each of the 8 diff blocks was extracted from this file and `git apply --check -R` accepted it against the tree, and (b) all 40 untracked files in the tree (excluding the four generated archive files) were found verbatim in this file. The four `backtest/data/odds_archive/*` files are produced by Task 9's build, not transcribed.

Two defects were found only by running the real data, and are fixed in the code above with a regression test each:
1. The first archive build stopped at game 50 with `arguments imply differing number of rows: 1, 0`: a real ESPN line with no price. Test `a line whose price is missing keeps the line with an NA price`.
2. The first complete build dropped every ESPN BET item that had a close but no opener, which is 80 games of 2023. Test `a game with a close but no open keeps its close`. The archive was rebuilt offline from the stored raw responses (`--from-raw`, the replay path).

**RED before GREEN.** For each task the implementation files were moved away and the test run; the failures are quoted in each task's RED step (measured, not typed).

**Gates, fresh `HOME` (an empty scratch directory), after the last code change:**

```
HOME=<fresh> Rscript scripts/run_tests.R
tests=526 passed=2126 failed=0 errors=0 skipped=1 unapproved_skips=0     (exit 0; the one skip is KNOWN-DEFECT P13)
HOME=<fresh> Rscript scripts/verify_repo_integrity.R
  Total:            63 passed, 0 failed     [VERIFICATION PASSED]          (exit 0)
Rscript scripts/odds_live_smoke.R            (live: ESPN 2024_01_ARI_BUF equals the fixture; Kalshi cutoff and listing)
odds-live: ......   exit 0
Rscript scripts/capture_odds_raw.R           (live, 2026-10-13: 192 requests, all HTTP 200, 3 min 11 s, 19.7 MB raw)
Rscript backtest/build_odds_archive.R <raw>  (live: 570 of 570 games fetched, 9.5 min)
```

`HOME=<fresh> Rscript scripts/run_matrix.R` gave `Total: 11 artifacts, Passed: 10, Failed: 1` (`[RUN MATRIX: 1 FAILURES]`): the golden-master artifact hit the matrix's 1800 s cap (`Status: FAIL (1800.2s)`) on a cold cache while the machine was also running other work; the other ten artifacts passed. No engine file changed, so the golden master was re-run uncapped with a fresh HOME: `HOME=<fresh> Rscript scripts/golden_master.R compare 15 2024 reports/2026-09-29/golden-master/2024-w15` printed `golden master: no differences` (exit 0, 15 min 46 s). **For the executor:** expect the matrix cap to be tight on a cold cache; if it times out, run the compare uncapped as above and CI's `golden-master` workflow is the reference.

`git diff origin/main` touches none of `renv.lock`, `DESCRIPTION`, `config.R`, `NFLsimulation.R`, `NFLmarket.R`, `injury_scalp.R`, `R/data_validation.R`, `backtest/eval_windows`, `web/package.json`, and deletes no file.

Not run in the dry run: the web gates (`web/` is untouched), CI on Linux (the plan quotes `shQuote` in the one subprocess test; Linux CI is the reference), and the reviews in Task 12 Step 4 (they run after execution).

## Self-review

- **Spec coverage (roadmap D1):** HTTP layer (Task 1); three providers on one interface (4, 5, 6); normalization into the Drizzle `odds_snapshots` shape (2); closing rule with the 60 minute stale flag (3); archive for 2023–2024 with hashes and a build script, 2025 refused and tested (8, 9); forward capture as a thin caller with `odds-capture.yml` unchanged (7); fixture seam instead of `httptest2` and live tests only behind `skip_live` outside the suite (1, 10); `docs/odds-sources.md` with the terms matrix, rate limits and coverage (11); gates (12).
- **Placeholders:** none; every code step holds complete code that was run. The only generated content is Task 9's data, with the commands and the expected output.
- **Type consistency:** `odds_fetch` records feed `odds_fetch_row`; `odds_result` is the return of every provider method; `games` tables come from `odds_games_from_schedule()`; `on_raw(key, body, rec)` is the same in Tasks 5 and 8.
- **Known limits, stated:** ESPN open/close rows are untimed; Kalshi spread/total are unsupported (counted); player aliases are deferred; the terms texts are not reviewed; the 2023 openers exist for 71.9% of games.

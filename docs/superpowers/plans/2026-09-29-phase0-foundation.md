# Phase 0 Foundation (remainder) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the repo honest, testable and CI-green before any model fix. This means retiring dead or misleading code, withdrawing unverifiable claims, making tests fail loudly instead of skipping, fixing CI, and measuring the keyless data sources.

**Architecture:** Five independent deliverables, landed as atomic commits on one branch `chore/phase0-foundation` (Tasks 1–4) plus one branch `spike/keyless-data` (Task 5). The last task runs the global gates and opens the PRs. No model math changes in this phase.

**Tech Stack:** R 4.5.1, testthat 3.3.2, httr2, jsonlite, digest, nflreadr, GitHub Actions (`r-lib/actions`).

**Spec:** `docs/superpowers/specs/2026-09-28-nfl-overhaul-design.md` (§5 Phase 0, §6 Verification). Audit IDs refer to `reports/2026-09-28/AUDIT.md`.

## Global Constraints

- R 4.5.1 everywhere (renv.lock `R.Version` is 4.5.1).
- Rules from CLAUDE.md:
  - No hardcoded values: new parameters go in `config.R`.
  - No silent fallbacks.
  - Run `Rscript scripts/verify_repo_integrity.R` after changes.
- Approved at A0 (2026-09-28): the deletion batch, untracking plus scoped settings, deps plus CI, and the honest default. Anything outside those needs a new approval.
- Never modify `NFLsimulation.R` or `NFLmarket.R` beyond what the approved spec lists for Phase 0:
  - `NFLsimulation.R`: the four `leakage_free` flags only.
  - `NFLmarket.R`: the banner/subtitle call-sites, sourcing `R/report_banner.R`, emptying the two three.js script blocks, and escaping fallback cells (spec §5 Phase 0 "Remove the three.js CDN script; escape the no-gt fallback").
- The keyless data policy holds: no API keys and no free trials.
- On Windows, run R through script files (`Rscript file.R`), not long `Rscript -e` strings.
- Scratch files go in the session scratchpad, not `/tmp`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Deviations from the spec (recorded, not silent)

1. **`core/calibration.R` is kept.** The A0 deletion batch listed all of `core/`, but `tests/testthat/test-calibration-harness.R:5` sources `core/calibration.R`, which the leakage-guarded calibration harness (`validation/calibration_harness.R`) depends on. Only `core/simulation_engine.R` (no references) is deleted. `core/calibration.R` moves into the backtest in Phase 3.
2. **The invalid calibrator moves to Phase 1** (`ensemble_calibration_implementation.R`, `ensemble_calibration_production.rds`). `NFLsimulation.R:5614,5680` and `config.R:96` still load it, so deleting it changes model output. That is the M4 fix under checkpoint A1a.
3. **The golden master moves to Phase 1, Task 2** (after the M1 fix). Until M1 is fixed, the only runnable week is 2025 week 22 (one game), which makes a useless golden master.
4. **`httptest2` is added in Phase 2**, where it's first used (YAGNI). The approval from A0 carries over.
5. **The ScoresAndOdds scraper stays until Phase 2 (A4)** replaces it. "Dead scraper code" here means OddsTrader and Covers only.

## Review Focus

1. **A deleted file is still sourced at runtime.** `run_week.R` must still source cleanly. → Task 1 adds `test-source-targets.R`: every literal `source("…")` path in `run_week.R`, `NFLsimulation.R`, `NFLmarket.R` and `R/*.R` must exist.
2. **Loading every `R/` module in `setup.R` lets duplicate definitions shadow each other** (H1: `american_to_probability` in 4 places), so results depend on load order. → Task 3 adds `test-module-duplicates.R`: the set of functions defined in more than one `R/` file must equal a documented allowlist, so no new duplicates can appear.
3. **The claims test misses a reworded claim** (e.g. ".211" or "2282 games"). → Task 2's ledger stores regex patterns, and `test-docs-truth.R` covers variant spellings.
4. **A test "passes" by returning early**, which testthat reports as an "empty test" skip. → Task 3's skip policy treats `empty test` as not allowed.
5. **The banner shows "NA%" or a stale 60%** when a config value is missing. → Task 2's `render_model_status_banner()` stops on missing or non-numeric inputs and derives every number from its arguments.

---

### Task 1: Hygiene: deletions, scraper retirement, untracking, settings

**Files:**
- Delete: `core/simulation_engine.R`, `sports/nfl/config.R`, `sports/nfl/props/props_pipeline.R`, `professional_model_benchmarking.R`, `simplified_baseline_comparison.R`, `rolling_validation_system.R`, `scripts/grid_search_results_copula.rds`, `artifacts/oddstrader_playerprops.js`, `artifacts/tmp_check.R`; untracked on disk: `nul`, `.playwright-mcp/`
- Move: `AUDIT.md`, `IMPROVEMENT_PLAN.md`, `docs/AUDIT_REPORT.md` → `reports/history/`
- Modify: `R/prop_odds_api.R` (remove the OddsTrader/Covers block starting at the `# ODDSTRADER + COVERS HTML SCRAPERS` header, ~401-505, and the two resolver branches ~871-882), `config.R:863-864`, `sports/nfl/props/props_config.R:131`, `.gitignore`, `README.md`, `GETTING_STARTED.md`, `CLAUDE.md` (file inventory lines only), `.claude/settings.json` (untracked, local)
- Test: `tests/testthat/test-repo-hygiene.R`, `tests/testthat/test-source-targets.R`

**Interfaces:**
- Consumes: `PROJECT_ROOT` (defined in `tests/testthat/setup.R`), `PROP_ODDS_SOURCE_ORDER` (config.R)
- Produces: `PROP_ODDS_SOURCE_ORDER == c("scoresandodds", "odds_api", "csv", "model")`; functions `load_prop_odds_oddstrader`, `load_prop_odds_covers` and `parse_oddstrader_html` no longer exist.

- [ ] **Step 1: Create the branch**

```bash
cd C:/Users/jviol/Downloads/nfl && git fetch -q origin && git checkout -b chore/phase0-foundation origin/main
```

- [ ] **Step 2: Write the failing tests**

`tests/testthat/test-repo-hygiene.R`:
```r
# Repo hygiene invariants from the 2026-09-28 audit (H1, H2, SEC2, S1)

test_that("dead and misleading files are gone", {
  removed <- c(
    "core/simulation_engine.R", "sports/nfl/config.R", "sports/nfl/props/props_pipeline.R",
    "professional_model_benchmarking.R", "simplified_baseline_comparison.R",
    "rolling_validation_system.R", "scripts/grid_search_results_copula.rds",
    "artifacts/oddstrader_playerprops.js", "artifacts/tmp_check.R",
    "AUDIT.md", "IMPROVEMENT_PLAN.md", "docs/AUDIT_REPORT.md"
  )
  still_there <- removed[file.exists(file.path(PROJECT_ROOT, removed))]
  expect_equal(still_there, character())
})

test_that("superseded audit documents are preserved under reports/history", {
  kept <- file.path(PROJECT_ROOT, "reports", "history",
                    c("AUDIT.md", "IMPROVEMENT_PLAN.md", "AUDIT_REPORT.md"))
  expect_true(all(file.exists(kept)))
})

test_that(".gitignore covers secrets, local settings and generated data", {
  gi <- trimws(readLines(file.path(PROJECT_ROOT, ".gitignore"), warn = FALSE))
  required <- c(".Renviron", ".env*", ".claude/settings*.json", ".playwright-mcp/",
                "data/raw_capture/", "run_logs/")
  expect_equal(setdiff(required, gi), character())
  expect_false("reports/" %in% gi)
})

test_that("OddsTrader and Covers scrapers are retired", {
  env <- new.env()
  sys.source(file.path(PROJECT_ROOT, "R", "prop_odds_api.R"), envir = env)
  retired <- c("load_prop_odds_oddstrader", "load_prop_odds_covers", "parse_oddstrader_html")
  expect_false(any(vapply(retired, exists, logical(1), envir = env, inherits = FALSE)))
  expect_false(any(c("oddstrader", "covers") %in% PROP_ODDS_SOURCE_ORDER))
})
```

`tests/testthat/test-source-targets.R`:
```r
# Every literal source("...") target in the runtime entry points must exist,
# so deleting a file can never silently break run_week.R.

literal_source_targets <- function(path) {
  txt <- readLines(path, warn = FALSE)
  txt <- txt[!grepl("^\\s*#", txt)]
  hits <- regmatches(txt, gregexpr('source\\(\\s*"[^"]+\\.R"', txt))
  unique(sub('source\\(\\s*"', "", sub('"$', "", unlist(hits))))
}

test_that("literal source() targets in entry points exist", {
  entry <- c("run_week.R", "NFLsimulation.R", "NFLmarket.R",
             file.path("R", list.files(file.path(PROJECT_ROOT, "R"), pattern = "\\.R$")))
  targets <- unique(unlist(lapply(file.path(PROJECT_ROOT, entry), literal_source_targets)))
  missing <- targets[!file.exists(file.path(PROJECT_ROOT, targets))]
  expect_equal(missing, character())
})
```

- [ ] **Step 3: Run them to verify they fail**

Create `<scratchpad>/run_one.R`:
```r
args <- commandArgs(trailingOnly = TRUE)
setwd("C:/Users/jviol/Downloads/nfl")
res <- as.data.frame(testthat::test_file(file.path("tests/testthat", args[[1]]), reporter = "summary"))
cat(sprintf("\nRESULT %s: tests=%d passed=%d failed=%d errors=%d skipped=%d\n", args[[1]],
            nrow(res), sum(res$passed), sum(res$failed), sum(res$error), sum(res$skipped)))
```
Run: `Rscript <scratchpad>/run_one.R test-repo-hygiene.R`
Expected: FAIL. The removed files still exist, the history files don't, the `.gitignore` patterns are missing, and the retired functions still exist.
Run: `Rscript <scratchpad>/run_one.R test-source-targets.R`
Expected: PASS (a guard test; it must still pass after the deletions).

- [ ] **Step 4: Delete, move, untrack**

```bash
cd C:/Users/jviol/Downloads/nfl
git rm -q core/simulation_engine.R sports/nfl/config.R sports/nfl/props/props_pipeline.R \
  professional_model_benchmarking.R simplified_baseline_comparison.R rolling_validation_system.R \
  scripts/grid_search_results_copula.rds artifacts/oddstrader_playerprops.js artifacts/tmp_check.R
mkdir -p reports/history
git mv AUDIT.md reports/history/AUDIT.md
git mv IMPROVEMENT_PLAN.md reports/history/IMPROVEMENT_PLAN.md
git mv docs/AUDIT_REPORT.md reports/history/AUDIT_REPORT.md
git rm -r -q --cached run_logs .claude/settings.local.json
rm -f ./nul && rm -rf .playwright-mcp
```

- [ ] **Step 5: Update `.gitignore`**

Replace the line `reports/` with the comment line `# reports/ holds committed, dated evidence (see reports/README.md) — do not ignore` (the same text as on `docs/overhaul-spec`, so the two branches merge cleanly). Then append:
```
# Secrets and local tool state
.Renviron
.env*
.claude/settings*.json
.playwright-mcp/
```

- [ ] **Step 6: Retire OddsTrader/Covers in `R/prop_odds_api.R`**

Delete the whole block that starts at the comment `# ODDSTRADER + COVERS HTML SCRAPERS (best-effort)` and ends after the closing `}` of `load_prop_odds_covers`. That block contains `oddstrader_default_url`, `covers_default_url`, `parse_oddstrader_html`, `load_prop_odds_oddstrader` and `load_prop_odds_covers`.

In `resolve_prop_odds_cache`, delete these two branches:
```r
    if (src %in% c("oddstrader", "odds_trader", "ot")) {
      ...
    }
    if (src %in% c("covers", "cover")) {
      ...
    }
```
Also change its default `source_order <- c("scoresandodds", "oddstrader", "covers", "odds_api", "csv", "model")` to `c("scoresandodds", "odds_api", "csv", "model")`.

In `config.R:863-864` and `sports/nfl/props/props_config.R:131`, set:
```r
#' @default c("scoresandodds","odds_api","csv","model")
PROP_ODDS_SOURCE_ORDER <- c("scoresandodds", "odds_api", "csv", "model")
```
Then check nothing else references the removed names:
Run: `grep -rn -iE "oddstrader|load_prop_odds_covers|covers_default_url" --include=*.R . | grep -v archive/`
Expected: no output.

- [ ] **Step 7: Remove doc references to deleted scripts**

Run: `grep -n -E "professional_model_benchmarking|simplified_baseline_comparison|rolling_validation_system|IMPROVEMENT_PLAN|AUDIT_REPORT|AUDIT\.md" README.md GETTING_STARTED.md CLAUDE.md DOCUMENTATION.md docs/*.md`
- In README.md and GETTING_STARTED.md, delete each command block or inventory line that runs or lists a deleted script.
- In CLAUDE.md §6, change `` `AUDIT.md` - Repository audit report `` to `` `reports/history/AUDIT.md` - superseded audit (current: `reports/2026-09-28/AUDIT.md`) ``.
- DOCUMENTATION.md is rewritten in Phase 8. Only add at its top: `> Sections describing professional_model_benchmarking.R, simplified_baseline_comparison.R and rolling_validation_system.R refer to scripts removed on 2026-09-29 (audit M7).`

- [ ] **Step 8: Scope local Claude permissions**

Invoke the `update-config` skill to replace the blanket `"Bash"`, `"Edit"`, `"Write"` allow in `.claude/settings.json` (untracked, now gitignored) with:
```json
{
  "permissions": {
    "allow": [
      "Edit", "Write",
      "Bash(Rscript:*)",
      "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git branch:*)",
      "Bash(gh pr view:*)", "Bash(gh pr checks:*)", "Bash(gh run view:*)", "Bash(gh run list:*)"
    ]
  }
}
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `Rscript <scratchpad>/run_one.R test-repo-hygiene.R` → Expected: PASS (4 tests)
Run: `Rscript <scratchpad>/run_one.R test-source-targets.R` → Expected: PASS
Run: `Rscript <scratchpad>/run_one.R test-prop-odds-fallback.R` → Expected: no new failures relative to `main`.

- [ ] **Step 10: Commit**

```bash
git add -A tests/testthat/test-repo-hygiene.R tests/testthat/test-source-targets.R R/prop_odds_api.R config.R \
  sports/nfl/props/props_config.R .gitignore README.md GETTING_STARTED.md CLAUDE.md DOCUMENTATION.md reports/history
git commit -m "Retire dead code and scrapers, untrack run logs, harden .gitignore (A0)"
```

---

### Task 2: Honest default: evidence ledger, withdrawn claims, paper staking, banner, T1

**Files:**
- Create: `docs/EVIDENCE_LEDGER.md`, `R/report_banner.R`, `tests/testthat/test-docs-truth.R`, `tests/testthat/test-report-banner.R`
- Modify:
  - docs: `README.md`, `CLAUDE.md`, `GETTING_STARTED.md`
  - `config.R`: add `STAKING_MODE`; remove `MODEL_BRIER_SCORE`/`MARKET_BRIER_SCORE` (only used by the summary print and `list2env`, `config.R:554-555,1141-1142`); rewrite the printed summary lines `config.R:1043-1051`; fix the correlation docstrings near `config.R:815-830`
  - `NFLmarket.R`:
    - source `R/report_banner.R` next to the `R/utils.R` sourcing (`:38-43`)
    - replace the hardcoded block at `:2993-2999` and the subtitle at `:3561`
    - empty `colorbends_script` (`:3867`) and `colorbends_script_fallback` (`:4545`)
    - escape fallback cells (`:4779`)
  - `NFLsimulation.R`: `leakage_free = TRUE` → `FALSE` at `:5675, 5733, 5743, 5907`
  - `tests/testthat/setup.R`: add `source_module("report_banner")`. Task 3 later loads all modules anyway.
  - `scripts/verify_repo_integrity.R:293-298` (T1)

**Interfaces:**
- Produces: `STAKING_MODE` (character, `"paper"` or `"live"`) in config.R.
- Produces: `render_model_status_banner(shrinkage, kelly_fraction, max_stake, staking_mode)` → a character HTML fragment. It stops on invalid input.
- Produces: `html_escape_cell(x)` → character, HTML-escaped; `NA` → `""`.
- Both live in `R/report_banner.R`, so tests never need to source the 5,000-line `NFLmarket.R`. That file sources `NFLbrier_logloss.R` by a working-directory-relative path and fails from `tests/testthat`.
- Produces: `docs/EVIDENCE_LEDGER.md`, a pipe table with columns `claim_id | claim | pattern | status | reason | evidence`. `pattern` is a regex that must not match README.md, CLAUDE.md or GETTING_STARTED.md while `status == withdrawn`.

- [ ] **Step 1: Write the ledger**

`docs/EVIDENCE_LEDGER.md`:
```markdown
# Evidence ledger

Every quantitative or "validated" claim about this model is listed here with its status.
A claim becomes **validated** only through a backtest run that passed the promotion gates
(spec §5 Phase 3/5). Statuses: validated · reproducible · unvalidated · withdrawn.

| claim_id | claim | pattern | status | reason | evidence |
|---|---|---|---|---|---|
| C-BRIER | Brier 0.211/0.214 on 2022–2024 | `0?\.21[14]\b` | withdrawn | No script with saved output reproduces it; 0.2115 hardcoded | reports/2026-09-28/AUDIT.md (M7) |
| C-GAMES | 2,282 games 2022–2024 | `2,?282` | withdrawn | 2022–2024 has ≈855 games | reports/2026-09-28/AUDIT.md (M7) |
| C-ACC | 67.1% accuracy | `67\.1\s*%` | withdrawn | Hardcoded, cites nonexistent RESULTS.md | reports/2026-09-28/AUDIT.md (M7) |
| C-SPLINE | Spline calibration −6.9% Brier | `(?<![0-9])6\.9\s*%` | withdrawn | Calibrator trained on outcome-leaked probabilities | reports/2026-09-28/AUDIT.md (M4) |
| C-RANK | "#2 vs professional models", 538 0.215 / FPI 0.218 | `Rank\s*#?2\|#2 vs professional\|FiveThirtyEight \(0\.215\)\|FPI \(0\.218\)` | withdrawn | Mock benchmark data | reports/2026-09-28/AUDIT.md (M7) |
| C-CORR | Prop correlations r=0.75/0.60/0.50/0.40 "empirically validated" with CIs | `r = 0\.75\|0\.75 \[0\.72\|empirically validated` | withdrawn | Config uses 0.40/0.09/0.30/0.17; no saved analysis | reports/2026-09-28/AUDIT.md (D1) |
| C-POSW | Position injury weights "validated p < 0.001" | `p < 0\.001` | unvalidated | No saved test output found; re-test in Phase 3 | reports/2026-09-28/AUDIT.md (M7) |
| C-SHRINK | "60%" / "70%" market shrinkage | – | unvalidated | Effective weight ≈65.5% via two stages plus anti-shrink (M2, M3); fixed in Phase 1 | reports/2026-09-28/AUDIT.md (M2, M3) |
| PROP_GAME_CORR_PASSING | 0.40 | – | unvalidated | Config value; to be estimated point-in-time in Phase 4 | config.R |
| PROP_GAME_CORR_RUSHING | 0.09 | – | unvalidated | as above | config.R |
| PROP_GAME_CORR_RECEIVING | 0.30 | – | unvalidated | as above | config.R |
| PROP_GAME_CORR_TD | 0.17 | – | unvalidated | as above | config.R |
```

- [ ] **Step 2: Write the failing docs-truth test**

`tests/testthat/test-docs-truth.R`:
```r
# Withdrawn claims (docs/EVIDENCE_LEDGER.md) must not reappear in the
# most-read docs. Phase 8 extends the scope to DOCUMENTATION.md and docs/.

read_ledger <- function() {
  lines <- readLines(file.path(PROJECT_ROOT, "docs", "EVIDENCE_LEDGER.md"), warn = FALSE, encoding = "UTF-8")
  rows <- grep("^\\|\\s*[A-Z]", lines, value = TRUE)
  rows <- rows[!grepl("^\\|\\s*claim_id", rows)]
  # Split on unescaped pipes only; "\|" inside a cell is a literal pipe
  # (regex alternation in the pattern column).
  cells <- lapply(strsplit(rows, "(?<!\\\\)\\|", perl = TRUE),
                  function(x) trimws(gsub("\\|", "|", x[-1], fixed = TRUE)))
  data.frame(
    claim_id = vapply(cells, `[`, "", 1),
    pattern = gsub("^`|`$", "", vapply(cells, `[`, "", 3)),
    status = vapply(cells, `[`, "", 4),
    stringsAsFactors = FALSE
  )
}

test_that("ledger parses and every row has a known status", {
  ledger <- read_ledger()
  expect_gt(nrow(ledger), 5)
  expect_true(all(ledger$status %in% c("validated", "reproducible", "unvalidated", "withdrawn")))
})

test_that("withdrawn claims do not appear in README, CLAUDE.md or GETTING_STARTED", {
  ledger <- read_ledger()
  withdrawn <- ledger[ledger$status == "withdrawn" & ledger$pattern != "–", ]
  docs <- c("README.md", "CLAUDE.md", "GETTING_STARTED.md")
  hits <- character()
  for (doc in docs) {
    txt <- readLines(file.path(PROJECT_ROOT, doc), warn = FALSE, encoding = "UTF-8")
    for (i in seq_len(nrow(withdrawn))) {
      ln <- grep(withdrawn$pattern[i], txt, perl = TRUE)
      if (length(ln)) hits <- c(hits, sprintf("%s:%s %s", doc, paste(ln, collapse = ","), withdrawn$claim_id[i]))
    }
  }
  expect_equal(hits, character())
})
```

- [ ] **Step 3: Write the failing banner/escaping test**

`tests/testthat/test-report-banner.R`:
```r
test_that("banner derives every number from its arguments", {
  html <- render_model_status_banner(0.70, 0.125, 0.02, "paper")
  expect_match(html, "70% market weight", fixed = TRUE)
  expect_match(html, "1/8 Kelly", fixed = TRUE)
  expect_match(html, "2% max stake", fixed = TRUE)
  expect_false(grepl("60%", html, fixed = TRUE))
})

test_that("banner states the model is unvalidated and stakes are paper", {
  html <- render_model_status_banner(0.70, 0.125, 0.02, "paper")
  expect_match(html, "Unvalidated model", fixed = TRUE)
  expect_match(html, "Paper stakes", fixed = TRUE)
  expect_match(html, "docs/EVIDENCE_LEDGER.md", fixed = TRUE)
})

test_that("banner refuses missing or invalid inputs instead of printing NA", {
  expect_error(render_model_status_banner(NA, 0.125, 0.02, "paper"), "shrinkage")
  expect_error(render_model_status_banner(0.7, 0.125, 0.02, "yolo"), "staking_mode")
  expect_error(render_model_status_banner(1.2, 0.125, 0.02, "paper"), "shrinkage")
})

test_that("config declares paper staking by default", {
  expect_identical(STAKING_MODE, "paper")
})

test_that("html_escape_cell escapes markup and blanks NA", {
  expect_identical(html_escape_cell("<script>alert(1)</script>"), "&lt;script&gt;alert(1)&lt;/script&gt;")
  expect_identical(html_escape_cell("A&B <b>"), "A&amp;B &lt;b&gt;")   # text content: quotes need no escaping
  expect_identical(html_escape_cell(NA), "")
  expect_identical(html_escape_cell(3.5), "3.5")
})

# Source guards (static): the report must not load remote scripts, and the
# no-gt fallback must escape cell values (audit SEC3, SEC4, U5).
test_that("NFLmarket.R loads no CDN scripts and escapes fallback cells", {
  src <- readLines(file.path(PROJECT_ROOT, "NFLmarket.R"), warn = FALSE, encoding = "UTF-8")
  expect_false(any(grepl("cdnjs|three\\.min\\.js", src)))
  expect_true(any(grepl("display_value <- html_escape_cell(cell_value)", src, fixed = TRUE)))
})
```

- [ ] **Step 4: Run both to verify they fail**

Run: `Rscript <scratchpad>/run_one.R test-docs-truth.R` → Expected: FAIL, listing hits such as `README.md:112 C-BRIER`
Run: `Rscript <scratchpad>/run_one.R test-report-banner.R` → Expected: FAIL, `could not find function "render_model_status_banner"`

- [ ] **Step 5: Implement the banner, escaping, paper staking, CDN removal**

In `config.R`, after the `MAX_STAKE` definition (~line 789):
```r
#' @description Staking mode. "paper" labels every stake as a paper/tracking unit
#'   until a backtest passes the promotion gates (docs/EVIDENCE_LEDGER.md).
#' @default "paper"
STAKING_MODE <- "paper"
```
Add `STAKING_MODE = STAKING_MODE,` to the `list2env(list(...))` block next to `MAX_STAKE`. Delete `MODEL_BRIER_SCORE`, `MARKET_BRIER_SCORE` (`config.R:554-555`) and their two `list2env` entries.

Create `R/report_banner.R`, and add `source_module("report_banner")` to `tests/testthat/setup.R` after `source_module("utils")`:
```r
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
```
Replace the literal HTML strings at `NFLmarket.R:2996-2999` (the `<h3>Risk Management Applied</h3>` list) with a call:
```r
    render_model_status_banner(SHRINKAGE, KELLY_FRACTION, MAX_STAKE, STAKING_MODE),
```
Keep the surrounding container markup the block sat in. Before editing, read `:2985-3010` to see the exact container.
Replace the subtitle at `:3561` with:
```r
      subtitle = sprintf("Unvalidated model • %.0f%% market weight • %s stakes", SHRINKAGE * 100, STAKING_MODE)
```
Make `NFLmarket.R` load the helper. In the `local({ ... })` block that sources `R/utils.R` (`:38-43`), add after it:
```r
    banner_path <- if (file.exists("R/report_banner.R")) "R/report_banner.R" else file.path(getwd(), "R/report_banner.R")
    if (!file.exists(banner_path)) stop("NFLmarket.R: R/report_banner.R not found (run from repo root)")
    source(banner_path)
```
Remove the remote script:
- Replace the whole `colorbends_script <- paste0( ... )` expression (starting `:3867`) with `colorbends_script <- ""  # decorative three.js background removed (audit U5/SEC3)`.
- Replace the `colorbends_script_fallback <- paste0( ... )` expression (starting `:4545`) with `colorbends_script_fallback <- ""`.

Escape the fallback cells: at `:4779` change `display_value <- cell_value` to `display_value <- html_escape_cell(cell_value)`. Then run `grep -n "cdnjs\|three.min.js" NFLmarket.R` → Expected: no output.

- [ ] **Step 6: Withdraw the claims in the docs**

- **README.md:**
  - Delete or replace lines 47, 54, 111–118 and 212 (Brier 0.211, −6.9%, "Performance (2022-2024, 2,282 games)", accuracy 67.1%, the model-vs-Vegas line, "10-fold cross-validation (2,282 games…)").
  - Insert directly under the title:
```markdown
> **Status (2026-09-29): unvalidated research model.** Earlier accuracy and calibration figures were withdrawn after an audit found no reproducible evidence for them. See `docs/EVIDENCE_LEDGER.md` and `reports/2026-09-28/AUDIT.md`. Validated numbers will appear here only after the pre-registered backtest passes its gates.
```
- **CLAUDE.md:**
  - Line 13: replace with `- Spline calibration (calibrator currently invalid, audit M4; disabled in Phase 1)`.
  - Line 39: replace with `**Correlation Model** (current config values, unvalidated, see docs/EVIDENCE_LEDGER.md):`.
  - Correlation tables at lines 44–53 and 84–93: replace the values with 0.40/0.09/0.30/0.17, set the source column to `config.R (unvalidated)`, and drop the CI column.
  - "Model Accuracy Benchmarks" table at lines 95–102: replace with `Withdrawn 2026-09-28; see docs/EVIDENCE_LEDGER.md.`
  - Line 318: replace "(validated p < 0.001)" with "(unvalidated, see ledger C-POSW)".
  - §1 "What Correct Looks Like": replace "50+/50+ checks pass" and "~625+ tests" with `verify_repo_integrity.R exits 0; scripts/run_tests.R exits 0 (skip policy enforced)`.
- **GETTING_STARTED.md:** replace lines 96–99 with the same status blockquote as README.

- [ ] **Step 7: Fix the config summary print and docstrings**

In `config.R`:
- Replace the header `cat("  Validated Parameters:\n")` (line 1043) with `cat("  Parameters (unvalidated, see docs/EVIDENCE_LEDGER.md):\n")`.
- Remove the three `(p=0.00x)` suffixes on lines 1044–1046.
- Replace lines 1048–1051 (the "Model Performance (Validation)" block, RMSE, Brier, Rank) with:
```r
  cat("  Model status:     UNVALIDATED (see docs/EVIDENCE_LEDGER.md)\n")
  cat(sprintf("  Staking mode:     %s\n", STAKING_MODE))
```
- In the `PROP_GAME_CORR_*` docstrings near lines 815–830, replace any "0.75 / 0.60 / 0.50 / 0.40 empirically validated" text with `@note Unvalidated config value (docs/EVIDENCE_LEDGER.md)`.

- [ ] **Step 8: Set the calibration quality flags to `leakage_free = FALSE`**

In `NFLsimulation.R`, change exactly these four calls (lines 5675, 5733, 5743 and 5907-5908), `leakage_free = TRUE` → `leakage_free = FALSE`. This is the only NFLsimulation.R edit in Phase 0. Then run `grep -n "leakage_free = TRUE" NFLsimulation.R` → Expected: no output.

- [ ] **Step 9: Fix T1 in `scripts/verify_repo_integrity.R:293-298`**

Replace the `[0.70, 0.80]` range check with a ledger check:
```r
  # Correlation values must be documented in the evidence ledger (audit T1)
  ledger_path <- "docs/EVIDENCE_LEDGER.md"
  ledger_txt <- if (file.exists(ledger_path)) readLines(ledger_path, warn = FALSE, encoding = "UTF-8") else character()
  for (param in c("PROP_GAME_CORR_PASSING", "PROP_GAME_CORR_RUSHING",
                  "PROP_GAME_CORR_RECEIVING", "PROP_GAME_CORR_TD")) {
    val <- if (exists(param)) get(param) else NA_real_
    row <- grep(sprintf("^\\|\\s*%s\\s*\\|", param), ledger_txt, value = TRUE)
    documented <- if (length(row) == 1) {
      suppressWarnings(as.numeric(trimws(strsplit(row, "|", fixed = TRUE)[[1]][3])))
    } else NA_real_
    if (is.finite(val) && val > -1 && val < 1 && isTRUE(all.equal(val, documented))) {
      pass("invariant", sprintf("%s = %s documented in evidence ledger", param, format(val)))
    } else {
      fail("invariant", sprintf("%s missing, out of (-1,1), or not matching docs/EVIDENCE_LEDGER.md", param))
    }
  }
```

- [ ] **Step 10: Run the tests and the integrity check**

Run: `Rscript <scratchpad>/run_one.R test-docs-truth.R` → Expected: PASS
Run: `Rscript <scratchpad>/run_one.R test-report-banner.R` → Expected: PASS (6 tests)
Run: `Rscript scripts/verify_repo_integrity.R` → Expected: exit 0 with `[VERIFICATION PASSED]`; the total now includes 4 ledger checks instead of 1 range check.
Smoke-check that `NFLmarket.R` still sources from the repo root. Create `<scratchpad>/smoke_market.R` with `setwd("C:/Users/jviol/Downloads/nfl"); source("config.R"); source("NFLmarket.R"); stopifnot(exists("render_model_status_banner")); cat("OK\n")`, run it, and expect `OK`.

- [ ] **Step 11: Commit**

```bash
git add docs/EVIDENCE_LEDGER.md R/report_banner.R tests/testthat/test-docs-truth.R tests/testthat/test-report-banner.R \
  tests/testthat/setup.R README.md CLAUDE.md GETTING_STARTED.md config.R NFLmarket.R NFLsimulation.R \
  scripts/verify_repo_integrity.R
git commit -m "Honest default: withdraw claims, paper staking, config-driven banner, drop CDN script, escape fallback, T1 (A0)"
```

---

### Task 3: Test harness that fails loudly

**Files:**
- Create: `R/test_policy.R`, `scripts/run_tests.R`, `tests/skip_allowlist.txt`, `tests/testthat/test-test-policy.R`, `tests/testthat/test-module-duplicates.R`
- Modify:
  - `tests/testthat/setup.R`: `source_module` stops on a missing module; load every `R/*.R`
  - Replace `getwd()` with `.test_project_root` in the path setup of `test-player-props.R:25`, `test-correlated-props.R:24-38`, and every other test found by the grep in Step 5
  - Tests that fail once they run: add a `KNOWN-DEFECT` skip that cites the audit ID

**Interfaces:**
- Produces: `classify_skips(reasons, allow_patterns)` → logical vector (TRUE = allowed).
- Produces: `summarize_test_run(df, skips, allowed)` → list with `ok` (logical) and `lines` (character).
- Produces: `scripts/run_tests.R`, which exits 0 only when there are 0 failures, 0 errors, and every skip reason matches `tests/skip_allowlist.txt`.
- Consumed by: Task 4 (CI calls `scripts/run_tests.R`).

- [ ] **Step 1: Write the failing policy tests**

`tests/testthat/test-test-policy.R`:
```r
test_that("classify_skips accepts only allowlisted reasons", {
  allow <- c("^On CRAN$", "^LIVE: ", "^KNOWN-DEFECT (M|P|S|U|T|H|D|SEC)[0-9]+: ")
  reasons <- c("On CRAN", "LIVE: needs nflreadr network", "KNOWN-DEFECT P1: edge label is column-wide",
               "correlated_props.R not found", "empty test", "KNOWN-DEFECT X9: bogus id")
  expect_equal(classify_skips(reasons, allow), c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE))
})

test_that("classify_skips handles no skips", {
  expect_equal(classify_skips(character(), "^On CRAN$"), logical())
})

test_that("summarize_test_run fails on failures, errors or unapproved skips", {
  df <- data.frame(failed = c(0L, 0L), error = c(FALSE, FALSE), skipped = c(FALSE, TRUE), passed = c(3L, 0L))
  skips <- data.frame(file = "test-a.R", test = "t", reason = "empty test")
  expect_false(summarize_test_run(df, skips, allowed = FALSE)$ok)
  expect_true(summarize_test_run(df, skips, allowed = TRUE)$ok)
  df$failed[1] <- 1L
  expect_false(summarize_test_run(df, skips, allowed = TRUE)$ok)
})
```

`tests/testthat/test-module-duplicates.R`:
```r
# Functions defined in more than one R/ module shadow each other depending on
# load order (audit H1). The allowlist may only shrink.
KNOWN_DUPLICATES <- character()   # filled in Step 7 from the actual scan, then only shrinks

defined_functions <- function(path) {
  exprs <- parse(path, keep.source = FALSE)
  nm <- vapply(exprs, function(e) {
    if (is.call(e) && (identical(e[[1]], as.name("<-")) || identical(e[[1]], as.name("="))) &&
        is.name(e[[2]]) && is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function")))
      as.character(e[[2]]) else NA_character_
  }, character(1))
  nm[!is.na(nm)]
}

test_that("no new function is defined in more than one R/ module", {
  files <- list.files(file.path(PROJECT_ROOT, "R"), pattern = "\\.R$", full.names = TRUE)
  all_defs <- unlist(lapply(files, defined_functions))
  dups <- sort(unique(all_defs[duplicated(all_defs)]))
  expect_equal(setdiff(dups, KNOWN_DUPLICATES), character())
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `Rscript <scratchpad>/run_one.R test-test-policy.R` → Expected: FAIL, `could not find function "classify_skips"`.
Run: `Rscript <scratchpad>/run_one.R test-module-duplicates.R` → Expected: PASS or FAIL depending on current duplicates (recorded in Step 7).

- [ ] **Step 3: Implement `R/test_policy.R`**

```r
# =============================================================================
# Test-run policy: failures, errors and unapproved skips all fail the run.
# Used by scripts/run_tests.R (CI) and unit-tested in test-test-policy.R.
# =============================================================================

#' TRUE for each skip reason matching at least one allowlist regex
classify_skips <- function(reasons, allow_patterns) {
  vapply(reasons, function(r) any(vapply(allow_patterns, grepl, logical(1), x = r, perl = TRUE)),
         logical(1), USE.NAMES = FALSE)
}

#' Decide pass/fail for a testthat run and build a printable summary
summarize_test_run <- function(df, skips, allowed) {
  n_fail <- sum(df$failed)
  n_err <- sum(df$error)
  bad_skips <- skips[!allowed, , drop = FALSE]
  lines <- sprintf("tests=%d passed=%d failed=%d errors=%d skipped=%d unapproved_skips=%d",
                   nrow(df), sum(df$passed), n_fail, n_err, nrow(skips), nrow(bad_skips))
  if (nrow(bad_skips)) {
    lines <- c(lines, "Unapproved skips:",
               sprintf("  %s :: %s :: %s", bad_skips$file, bad_skips$test, bad_skips$reason))
  }
  list(ok = n_fail == 0 && n_err == 0 && nrow(bad_skips) == 0, lines = lines)
}
```

- [ ] **Step 4: Write `scripts/run_tests.R` and `tests/skip_allowlist.txt`**

`tests/skip_allowlist.txt`:
```
# One regex per line. A skip whose reason matches none of these fails the run.
# KNOWN-DEFECT skips must cite an audit ID from reports/2026-09-28/AUDIT.md and
# are removed by the phase that fixes that ID.
^On CRAN$
^LIVE: 
^KNOWN-DEFECT (M|P|S|U|T|H|D|SEC)[0-9]+: 
```

`scripts/run_tests.R`:
```r
#!/usr/bin/env Rscript
# Run the testthat suite and enforce the skip policy (R/test_policy.R).
# Exit 0 only with 0 failures, 0 errors and every skip allowlisted.
if (!file.exists("tests/skip_allowlist.txt")) stop("Run from the repository root")
source("R/test_policy.R")
res <- testthat::test_dir("tests/testthat", reporter = "summary", stop_on_failure = FALSE)
df <- as.data.frame(res)
rows <- list()
for (r in res) for (x in r$results) if (inherits(x, "expectation_skip")) {
  rows[[length(rows) + 1]] <- data.frame(file = r$file, test = r$test,
                                         reason = sub("^Reason: ", "", conditionMessage(x)))
}
skips <- if (length(rows)) do.call(rbind, rows) else data.frame(file = character(), test = character(), reason = character())
allow <- trimws(readLines("tests/skip_allowlist.txt", warn = FALSE))
allow <- allow[nzchar(allow) & !startsWith(allow, "#")]
out <- summarize_test_run(df, skips, classify_skips(skips$reason, allow))
cat("\n", paste(out$lines, collapse = "\n"), "\n", sep = "")
if (nrow(skips)) { cat("All skips:\n"); print(as.data.frame(table(reason = skips$reason)), row.names = FALSE) }
quit(status = if (out$ok) 0 else 1)
```

- [ ] **Step 5: Make setup load every module and fail loudly; fix the `getwd()` paths**

In `tests/testthat/setup.R`, replace the body of `source_module`:
```r
source_module <- function(module_name) {
  path <- file.path(PROJECT_ROOT, "R", paste0(module_name, ".R"))
  if (!file.exists(path)) {
    stop(sprintf("Test setup: required module missing: R/%s.R", module_name), call. = FALSE)
  }
  source(path, local = FALSE)
  message(sprintf("  Loaded: R/%s.R", module_name))
}
```
Replace the module-loading section (from `source_module("logging")` through the `sleeper_api` tryCatch) with:
```r
LOAD_FIRST <- c("logging", "utils", "capture_raw", "data_validation", "playoffs", "date_resolver", "test_policy")
all_modules <- sub("\\.R$", "", list.files(file.path(PROJECT_ROOT, "R"), pattern = "\\.R$"))
for (m in c(LOAD_FIRST, setdiff(sort(all_modules), LOAD_FIRST))) source_module(m)
```
Then find every test resolving repo paths from `getwd()`:
Run: `grep -n "getwd()" tests/testthat/test-*.R`
Replace `getwd()` with `.test_project_root` on each of those lines. Known lines: `test-player-props.R:25` and `test-correlated-props.R:24,27,33`. Remove the `if (dir.exists(...))` / `if (file.exists(...))` wrappers around those `source()` calls, so a missing file errors instead of skipping.

- [ ] **Step 6: Run the policy tests and the whole suite through the runner**

Run: `Rscript <scratchpad>/run_one.R test-test-policy.R` → Expected: PASS (3 tests)
Run: `Rscript scripts/run_tests.R` → Expected: exit 1. The printout lists the newly running tests' failures and every unapproved skip. Save the output to `<scratchpad>/triage.txt`.

- [ ] **Step 7: Triage until the runner exits 0**

For every failure or unapproved skip in `triage.txt`, apply exactly one of these:
- **(a) Test bug** (wrong path, stale expectation of documented behavior): fix the test.
- **(b) Real defect already in the audit:** keep the test body, and put `skip("KNOWN-DEFECT <ID>: <one-line symptom>")` as the test's first line. Example: `skip("KNOWN-DEFECT P1: classify_prop_edge_quality is column-wide")`.
- **(c) Needs network or live data:** start the test with `skip_if_offline()` followed by `skip("LIVE: <what it needs>")` only when a network check fails. Never skip unconditionally.
- **(d) Empty test** (no expectations): add the missing expectation or delete the test.
- **(e) Real defect NOT in the audit:** stop. Append it to `reports/2026-09-28/AUDIT.md` as a new ID in a separate commit, report it to the user, then apply (b).

Fill `KNOWN_DUPLICATES` in `test-module-duplicates.R` with the exact names the scan reports. They're the documented H1 duplicates; Phase 1 shrinks the list.
Re-run `Rscript scripts/run_tests.R` until it exits 0. Record the final summary line and the skip table in the commit message.

- [ ] **Step 8: Commit**

```bash
git add R/test_policy.R scripts/run_tests.R tests/skip_allowlist.txt tests/testthat
git commit -m "Test harness fails loudly: load all modules, fix getwd() paths, enforce skip policy (T2)"
```

---

### Task 4: CI on R 4.5.1 with renv, ripgrep and the new gates

**Files:**
- Modify: `.github/workflows/ci.yml`, `scripts/audit_verify.sh`, `renv.lock`
- Test: the PR's CI run itself (Step 5)

**Interfaces:**
- Consumes: `scripts/run_tests.R` (Task 3) and `scripts/verify_repo_integrity.R` exiting 0 (Task 2).

- [ ] **Step 1: Record testthat and its missing dependencies in renv.lock**

Create `<scratchpad>/record_testthat.R`:
```r
setwd("C:/Users/jviol/Downloads/nfl")
if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv", repos = "https://cloud.r-project.org")
lock <- jsonlite::fromJSON("renv.lock", simplifyVector = FALSE)
ip <- installed.packages()
deps <- tools::package_dependencies("testthat", db = ip, which = c("Depends", "Imports", "LinkingTo"), recursive = TRUE)[[1]]
need <- setdiff(c("testthat", deps), c(rownames(installed.packages(priority = "base")), "R"))
missing <- setdiff(need, names(lock$Packages))
cat("recording:", paste(missing, collapse = ", "), "\n")
for (p in missing) renv::record(sprintf("%s@%s", p, as.character(packageVersion(p))), lockfile = "renv.lock")
```
Run: `Rscript <scratchpad>/record_testthat.R`
Then: `git diff --stat renv.lock` → Expected: additions only. Check that `"testthat"` now appears as a top-level key.

- [ ] **Step 2: Rewrite `.github/workflows/ci.yml`**

Keep the four `lint-and-check` validation steps exactly as they are ("Check R syntax", "Parse NFL props modules", "Source main files (smoke test)", "Run basic validation"). Replace the setup steps in both jobs, and add workflow permissions:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  audit-verify:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up R
        uses: r-lib/actions/setup-r@v2
        with:
          r-version: "4.5.1"
          use-public-rspm: true

      - name: Install system dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y libcurl4-openssl-dev libssl-dev libxml2-dev gfortran ripgrep

      - name: Restore renv library
        uses: r-lib/actions/setup-renv@v2

      - name: Run audit verification
        run: ./scripts/audit_verify.sh

  lint-and-check:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up R
        uses: r-lib/actions/setup-r@v2
        with:
          r-version: "4.5.1"
          use-public-rspm: true

      - name: Install system dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y libcurl4-openssl-dev libssl-dev libxml2-dev gfortran

      - name: Restore renv library
        uses: r-lib/actions/setup-renv@v2

      # (existing steps "Check R syntax", "Parse NFL props modules",
      #  "Source main files (smoke test)", "Run basic validation" follow unchanged)
```
Before writing it, fetch the current `setup-renv` usage through Context7 (`/r-lib/actions`) to confirm the v2 inputs. Don't answer from memory.

- [ ] **Step 3: Update `scripts/audit_verify.sh`**

Replace:
```bash
  Rscript -e "testthat::test_dir('tests/testthat', reporter='summary')"
  Rscript scripts/audit_verify.R
```
with:
```bash
  Rscript scripts/run_tests.R
  Rscript scripts/verify_repo_integrity.R
  Rscript scripts/audit_verify.R
```
Keep `set -euo pipefail`, so any non-zero exit fails CI.

- [ ] **Step 4: Run the verification script locally (Git Bash has no `rg`, so check that first)**

Run: `command -v rg || echo "no rg locally"`. If rg is missing, run the three R commands from Step 3 directly and expect each to exit 0.

- [ ] **Step 5: Commit, push, confirm CI**

```bash
git add .github/workflows/ci.yml scripts/audit_verify.sh renv.lock
git commit -m "CI: R 4.5.1 via setup-renv, ripgrep, run_tests.R skip policy and integrity gate (T4)"
git push -u origin chore/phase0-foundation
gh pr create --base main --head chore/phase0-foundation --title "Phase 0: foundation (hygiene, honest default, loud tests, CI)" --body-file <scratchpad>/pr_phase0.md
gh pr checks --watch
```
Expected: `audit-verify` and `lint-and-check` both pass. If one fails, read the log with `gh run view <id> --log-failed` and fix it in a new commit on the branch. Don't merge; merging needs the user's approval.

---

### Task 5: Keyless data spike (measurement, not production code)

**Files:**
- Create: `scripts/spike/README.md`, `scripts/spike/spike_helpers.R`, `scripts/spike/kalshi_coverage.R`, `scripts/spike/espn_bet_bias.R`, `scripts/spike/espn_game_odds_coverage.R`, `tests/testthat/test-spike-helpers.R`, `tests/testthat/fixtures/spike/kalshi_markets_settled.json`, `reports/<run-date>/DATA_SOURCES_SPIKE.md`
- Branch: `spike/keyless-data` from `origin/main`

**Interfaces:**
- Consumes: `capture_http_get()` and `espn_prop_bets_url()` from `R/capture_raw.R`
- Produces: `kalshi_event_date(event_ticker)` → Date; `espn_row_is_priced(item)` → logical; `bias_test(priced_hits, priced_n, unpriced_hits, unpriced_n)` → `list(diff, p_value)`. The GO/NO-GO table feeds Phases 2 and 5.

- [ ] **Step 1: Write the failing helper tests**

`tests/testthat/test-spike-helpers.R`:
```r
source(file.path(.test_project_root, "scripts", "spike", "spike_helpers.R"))

test_that("kalshi_event_date parses YYMONDD tickers", {
  expect_equal(kalshi_event_date("KXNFLANYTD-26JAN25LASEA"), as.Date("2026-01-25"))
  expect_equal(kalshi_event_date("KXNFLTD-26SEP28PHICHI"), as.Date("2026-09-28"))
  expect_true(is.na(kalshi_event_date("KXNFLWINS-NO")))
})

test_that("espn_row_is_priced needs an American price on over or under", {
  priced <- list(open = list(over = list(american = "-110"), target = list(value = 45.5)))
  line_only <- list(open = list(target = list(value = 45.5)), current = list(target = list(value = 44.5)))
  expect_true(espn_row_is_priced(priced))
  expect_false(espn_row_is_priced(line_only))
})

test_that("bias_test reports the hit-rate difference and a two-sided p-value", {
  same <- bias_test(50, 100, 500, 1000)
  expect_equal(same$diff, 0)
  expect_gt(same$p_value, 0.9)
  skewed <- bias_test(80, 100, 300, 1000)
  expect_equal(skewed$diff, 0.5)
  expect_lt(skewed$p_value, 1e-6)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript <scratchpad>/run_one.R test-spike-helpers.R` → Expected: FAIL (`cannot open file .../spike_helpers.R`).

- [ ] **Step 3: Implement `scripts/spike/spike_helpers.R`**

```r
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
```

- [ ] **Step 4: Run it to verify it passes**

Run: `Rscript <scratchpad>/run_one.R test-spike-helpers.R` → Expected: PASS (3 tests).

- [ ] **Step 5: Write and run the three measurement scripts**

Each script:
- sources `R/capture_raw.R`, `config.R` (into an environment) and `scripts/spike/spike_helpers.R`;
- uses `capture_http_get()` with the `CAPTURE_*` settings;
- writes its table as CSV to `reports/<run-date>/spike/` (committed);
- **records every failed request as a row with its status. Never drop a failure.**

- **`kalshi_coverage.R`**
  - For each of `KXNFLANYTD`, `KXNFLTD`, `KXNFL2TD`, `KXNFLFIRSTTD`, `KXNFLRECYDS`, `KXNFLRSHYDS`, `KXNFLPASSYDS`, `KXNFLREC`, `KXNFLGAME`, `KXNFLSPREAD`, `KXNFLTOTAL`: page through `/events?series_ticker=S&status=settled&limit=200` via `cursor`.
  - Output per series: event count and earliest/latest `kalshi_event_date()`.
  - Then take 3 events per season-month and call `/historical/markets?event_ticker=E`. Count markets, and for the highest-volume market call `/historical/markets/{t}/candlesticks?start_ts=kickoff-48h&end_ts=kickoff&period_interval=60`. Record whether a candle exists at or before kickoff. Kickoff comes from nflreadr `load_schedules()`, joined on date plus team codes parsed from the ticker suffix.
- **`espn_bet_bias.R`**
  - For every 2024 regular-season and 2025 week 1–13 game (nflreadr schedules, `espn` id column): fetch `…/odds/58/propBets` for all pages.
  - For the markets "Anytime Touchdown Scorer", "Total Receiving Yards (incl. overtime)", "Total Receptions (incl. overtime)" and "Total Rushing Yards (incl. overtime)": classify rows priced/unpriced with `espn_row_is_priced()`.
  - Join athletes via `nflreadr::load_ff_playerids()` (`espn_id` → `gsis_id`) to `load_player_stats()`. Outcome: TD ≥ 1 for anytime TD; stat > `open$target$value` for over/unders.
  - Run `bias_test()` per market.
  - Rate limit: `CAPTURE_MIN_INTERVAL_SEC`. The expected runtime is long; run it in the background and log progress.
- **`espn_game_odds_coverage.R`**
  - For 5 sampled games per season 2018–2025: fetch `…/competitions/{id}/odds`.
  - Record per provider whether `open`/`close` exist and whether a moneyline is present.

- [ ] **Step 6: Write `reports/<run-date>/DATA_SOURCES_SPIKE.md`**

The report contains:
1. **Kalshi coverage per series.** First/last date, events and settled markets. Pre-kickoff candle availability as a percentage.
2. **ESPN BET priced share per market and season.**
   - Bias test: difference, p-value, and the verdict. It's **USABLE** when p ≥ 0.05 and |diff| < 0.03; otherwise **LINE-MOVEMENT ONLY**.
3. **ESPN game open/close coverage by season.**
4. **GO/NO-GO per market** (spec rule: anytime TD plus at least 3 yardage markets, each with ≥300 settled player-games that have a pre-kickoff price).
   - **GO** markets are backtested historically in Phase 5.
   - **NO-GO** markets are prospective-only, labeled that way.
5. **Deviations and failures,** each with its count of failed requests.

- [ ] **Step 7: Commit, push, PR**

```bash
git add scripts/spike tests/testthat/test-spike-helpers.R reports/<run-date>
git commit -m "Spike: measure keyless Kalshi/ESPN coverage and ESPN BET selection bias"
git push -u origin spike/keyless-data
gh pr create --base main --head spike/keyless-data --title "Spike: keyless data coverage and bias" --body-file <scratchpad>/pr_spike.md
```

---

### Task 6: Phase 0 close-out

- [ ] **Step 1: Global gate on `chore/phase0-foundation`.** Quote the actual output.
  - `Rscript scripts/run_tests.R` → exit 0; record the summary line.
  - `Rscript scripts/verify_repo_integrity.R` → exit 0.
  - `Rscript scripts/run_matrix.R` → 9/9.
  - Both CI checks green on the PR.
- [ ] **Step 2: Reconcile against the spec.** Walk spec §5 Phase 0 line by line. Mark each item done, deferred (with the Deviations entry) or not done. Put the table in the PR description.
- [ ] **Step 3: Update docs.** Add CHANGELOG `[Unreleased]` entries for Tasks 1–5. Update `HANDOFF.md` with branch states, the gate output, open KNOWN-DEFECT skips by ID, and the next target, Phase 1 Task 1 (M1).
- [ ] **Step 4: Ask the user to approve merging** #191 (spec), the Phase 0 PR and the spike PR. Then start Phase 1 with its own writing-plans run.

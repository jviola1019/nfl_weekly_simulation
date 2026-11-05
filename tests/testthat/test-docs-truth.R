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

# The current docs, as the owner asked on 2026-11-05 ("Architectures, ERDs, documentation should be
# verified"). Not here: docs/EVIDENCE_LEDGER.md (it defines the claims), docs/VARIABLE_LEDGER.md
# (generated; its disclosure rows describe defects), CHANGELOG.md and HANDOFF.md (history).
MAIN_DOCS <- c("README.md", "CLAUDE.md", "GETTING_STARTED.md", "DOCUMENTATION.md", "docs/ARCHITECTURE.md",
               "docs/API.md", "docs/modeling.md", "docs/odds-sources.md", "docs/ERD.md")

test_that("withdrawn claims do not appear in the current docs", {
  ledger <- read_ledger()
  withdrawn <- ledger[ledger$status == "withdrawn" & ledger$pattern != "–", ]
  hits <- character()
  for (doc in MAIN_DOCS) {
    txt <- readLines(file.path(PROJECT_ROOT, doc), warn = FALSE, encoding = "UTF-8")
    for (i in seq_len(nrow(withdrawn))) {
      ln <- grep(withdrawn$pattern[i], txt, perl = TRUE)
      if (length(ln)) hits <- c(hits, sprintf("%s:%s %s", doc, paste(ln, collapse = ","), withdrawn$claim_id[i]))
    }
  }
  expect_equal(hits, character())
})

# Backticked repo paths in the main docs (a token with a slash whose first segment is a tracked
# source directory); placeholders such as <date> or test-*.R are not paths and are skipped
DOC_PATH_ROOTS <- c("R", "backtest", "contracts", "docs", "reports", "scripts", "sports", "tests", "web", ".github")
doc_missing_paths <- function(txt, root = PROJECT_ROOT, roots = DOC_PATH_ROOTS) {
  m <- unlist(regmatches(txt, gregexpr("`[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]*`", txt)))
  p <- unique(gsub("`", "", m, fixed = TRUE))
  p <- p[sub("/.*", "", p) %in% roots]
  p[!file.exists(file.path(root, sub("/$", "", p)))]
}

test_that("every repo path the main docs cite exists", {
  expect_identical(doc_missing_paths(c("see `backtest/vvf/no_such_file.R` and `R/utils.R`", "`bundles/` `reports/<date>/x.md`")),
                   "backtest/vvf/no_such_file.R")
  missing <- character()
  for (doc in MAIN_DOCS) {
    gone <- doc_missing_paths(readLines(file.path(PROJECT_ROOT, doc), warn = FALSE, encoding = "UTF-8"))
    if (length(gone)) missing <- c(missing, paste0(doc, ": ", gone))
  }
  expect_identical(missing, character())
})

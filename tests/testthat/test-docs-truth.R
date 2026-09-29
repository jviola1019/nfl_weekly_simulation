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

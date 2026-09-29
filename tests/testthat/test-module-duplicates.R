# Functions defined in more than one R/ module shadow each other depending on
# load order (audit H1). The allowlist may only shrink.
# Scan of R/*.R on 2026-09-29 (15 files, 166 top-level functions) found no
# duplicates. H1's other standardize_join_keys copies are outside R/
# (NFLmarket.R, NFLbrier_logloss.R), so this scan does not see them.
KNOWN_DUPLICATES <- character()

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

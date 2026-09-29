# Functions defined in more than one place shadow each other depending on load
# order (audit H1). Both allowlists may only shrink.
# Scan of R/*.R on 2026-09-29 (15 files): the only duplicate is `%||%`, as
# conditional `if (!exists("%||%"))` copies in R/prop_odds_api.R and
# R/sleeper_api.R. Base R >= 4.4 defines `%||%`, so neither copy is used there.
KNOWN_DUPLICATES <- c("%||%")

# Engine files that are sourced alongside R/ and redefine R/ functions, as
# "file::function" (scan of 2026-09-29). "[if]" marks a conditional
# `if (!exists("f")) f <- function` copy. Phase 1b removes these; delete an
# entry when its copy is removed.
KNOWN_H1_DUPLICATES <- c(
  "NFLmarket.R::coerce_numeric_safely",
  "NFLmarket.R::collapse_by_keys_relaxed",
  "NFLmarket.R::ensure_columns_with_defaults",
  "NFLmarket.R::ensure_unique_join_keys",
  "NFLmarket.R::probability_to_american",
  "NFLmarket.R::select_first_column",
  "NFLmarket.R::standardize_join_keys",
  "NFLbrier_logloss.R::american_to_decimal[if]",
  "NFLbrier_logloss.R::american_to_probability[if]",
  "NFLbrier_logloss.R::clamp_probability[if]",
  "NFLbrier_logloss.R::classify_edge_magnitude",
  "NFLbrier_logloss.R::conservative_kelly_stake",
  "NFLbrier_logloss.R::expected_value_units",
  "NFLbrier_logloss.R::first_non_missing_typed[if]",
  "NFLbrier_logloss.R::shrink_probability_toward_market",
  "NFLbrier_logloss.R::standardize_join_keys[if]"
)
ENGINE_FILES <- c("NFLmarket.R", "NFLbrier_logloss.R")

is_function_assignment <- function(e) {
  is.call(e) && (identical(e[[1]], as.name("<-")) || identical(e[[1]], as.name("="))) &&
    is.name(e[[2]]) && is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function"))
}

# Top-level function definitions of one file, including those inside a
# top-level `if` (the `if (!exists("f")) f <- function` fallback pattern).
# Returns names; conditional ones carry an "[if]" suffix.
defined_functions <- function(path) {
  collect <- function(e, conditional) {
    if (is_function_assignment(e)) return(paste0(as.character(e[[2]]), if (conditional) "[if]" else ""))
    if (is.call(e) && identical(e[[1]], as.name("if"))) {
      return(unlist(lapply(as.list(e)[-(1:2)], collect, conditional = TRUE)))
    }
    if (is.call(e) && identical(e[[1]], as.name("{"))) {
      return(unlist(lapply(as.list(e)[-1], collect, conditional = conditional)))
    }
    character()
  }
  as.character(unlist(lapply(parse(path, keep.source = FALSE), collect, conditional = FALSE)))
}

strip_if <- function(x) sub("\\[if\\]$", "", x)

test_that("the definition scan sees plain and conditional definitions", {
  f <- tempfile(fileext = ".R")
  writeLines(c("a <- function() 1", "if (!exists(\"b\")) b <- function() 2",
               "if (!exists(\"c\")) {", "  c <- function() 3", "}", "d <- 4"), f)
  expect_equal(defined_functions(f), c("a", "b[if]", "c[if]"))
})

test_that("no new function is defined in more than one R/ module", {
  files <- list.files(file.path(PROJECT_ROOT, "R"), pattern = "\\.R$", full.names = TRUE)
  all_defs <- strip_if(unlist(lapply(files, defined_functions)))
  dups <- sort(unique(all_defs[duplicated(all_defs)]))
  expect_equal(setdiff(dups, KNOWN_DUPLICATES), character())
})

test_that("NFLmarket.R and NFLbrier_logloss.R add no new copies of R/ functions", {
  r_files <- list.files(file.path(PROJECT_ROOT, "R"), pattern = "\\.R$", full.names = TRUE)
  r_defs <- unique(strip_if(unlist(lapply(r_files, defined_functions))))
  overlaps <- unlist(lapply(ENGINE_FILES, function(f) {
    defs <- defined_functions(file.path(PROJECT_ROOT, f))
    paste0(f, "::", defs[strip_if(defs) %in% r_defs])
  }))
  expect_gt(length(r_defs), 100)
  # New overlap: define it once, in R/, instead
  expect_equal(setdiff(overlaps, KNOWN_H1_DUPLICATES), character())
  # Removed overlap: delete its entry so the allowlist keeps shrinking
  expect_equal(setdiff(KNOWN_H1_DUPLICATES, overlaps), character())
})

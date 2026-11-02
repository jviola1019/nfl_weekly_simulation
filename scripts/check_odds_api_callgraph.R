#!/usr/bin/env Rscript
# =============================================================================
# FILE: scripts/check_odds_api_callgraph.R
# PURPOSE: P4/P5, the keyed Odds API path. Lists every reference to its symbols in the
#   repository's R files, so a deletion can be shown to leave no caller behind.
#   Usage: Rscript scripts/check_odds_api_callgraph.R   (prints references; exit 0 when none)
# =============================================================================

ODDS_API_SYMBOLS <- c("load_prop_odds", "ODDS_API_KEY", "odds_api", "oddsapi")

#' R files of the repository worth scanning (no vendored or generated trees; this script and
#' its test name the symbols on purpose)
repo_r_files <- function(root = ".") {
  files <- list.files(root, pattern = "[.]R$", recursive = TRUE, full.names = FALSE)
  skip <- grepl("^(renv|web/node_modules|reports|run_logs|data|\\.git)/", files) |
    files %in% c("scripts/check_odds_api_callgraph.R", "tests/testthat/test-odds-api-callgraph.R")
  sort(files[!skip])
}

#' References to symbols in R files
#'
#' A reference is a code symbol or call (`load_prop_odds(...)`, `ODDS_API_KEY`), a string equal to the
#' name (`exists("load_prop_odds")`, `Sys.getenv("ODDS_API_KEY")`, `"odds_api"`), or a comment that
#' contains the name as a whole word. `prop_odds_api.R` (the file name) is not a reference.
#'
#' @param files Paths relative to `root`
#' @param symbols Names to look for
#' @param root Directory the paths are relative to
#' @return data.frame(file, line, symbol, kind), one row per reference
refs_to_symbols <- function(files, symbols = ODDS_API_SYMBOLS, root = ".") {
  rows <- list()
  for (f in files) {
    pd <- utils::getParseData(parse(file.path(root, f), keep.source = TRUE))
    if (is.null(pd)) next
    for (s in symbols) {
      code <- pd$token %in% c("SYMBOL", "SYMBOL_FUNCTION_CALL", "SYMBOL_SUB", "SYMBOL_FORMALS") & pd$text == s
      str_const <- pd$token == "STR_CONST" & gsub("^[\"']|[\"']$", "", pd$text) == s
      comment <- pd$token == "COMMENT" & grepl(sprintf("\\b%s\\b", s), pd$text)
      for (kind in c("code", "string", "comment")) {
        hit <- switch(kind, code = code, string = str_const, comment = comment)
        if (any(hit)) {
          rows[[length(rows) + 1]] <- data.frame(file = f, line = pd$line1[hit], symbol = s, kind = kind,
                                                 stringsAsFactors = FALSE)
        }
      }
    }
  }
  if (!length(rows)) {
    return(data.frame(file = character(), line = integer(), symbol = character(), kind = character(),
                      stringsAsFactors = FALSE))
  }
  out <- do.call(rbind, rows)
  out[order(out$file, out$line, out$symbol), , drop = FALSE]
}

if (sys.nframe() == 0L) {
  if (!file.exists("DESCRIPTION")) stop("Run from the repository root")
  refs <- refs_to_symbols(repo_r_files("."))
  if (nrow(refs) == 0) {
    cat("No reference to the keyed Odds API path remains.\n")
    quit(status = 0)
  }
  print(refs, row.names = FALSE)
  cat(sprintf("\n%d reference(s) in %d file(s).\n", nrow(refs), length(unique(refs$file))))
  quit(status = 1)
}

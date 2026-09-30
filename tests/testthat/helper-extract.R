#' Evaluate selected top-level function definitions from a script (without running it).
#' Safety: only `name <- function(...)`-style assignments from this repository's own
#' tracked scripts are evaluated; nothing else in the script runs.
load_script_functions <- function(path, names, envir = new.env(parent = globalenv())) {
  exprs <- parse(path, keep.source = FALSE)
  found <- character()
  for (e in exprs) {
    if (is.call(e) && (identical(e[[1]], as.name("<-")) || identical(e[[1]], as.name("="))) &&
        is.name(e[[2]]) && as.character(e[[2]]) %in% names) {
      eval(e, envir)
      found <- c(found, as.character(e[[2]]))
    }
  }
  missing <- setdiff(names, found)
  if (length(missing)) stop("load_script_functions: not found in ", basename(path), ": ", paste(missing, collapse = ", "))
  envir
}

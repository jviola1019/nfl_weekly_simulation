# =============================================================================
# Load NFLmarket.R without shadowing R/ modules in the global environment
# =============================================================================
# Sourcing NFLmarket.R globally replaced R/utils.R functions with NFLmarket's
# own copies (collapse_by_keys_relaxed, ensure_unique_join_keys, ...) for every
# later test file (audit H1). Here NFLmarket.R's definitions go into a private
# environment. Its nested source() calls (NFLbrier_logloss.R and others) still
# write to the global environment, so any global binding they add or change is
# moved into the private environment and the global binding is restored.
# Tests take the functions they need from nflmarket_env().
# =============================================================================

nflmarket_env <- local({
  cache <- NULL
  function() {
    if (!is.null(cache)) return(cache)
    g <- globalenv()
    before <- mget(ls(g), envir = g)
    e <- new.env(parent = g)
    withr::with_dir(.test_project_root,
                    sys.source(file.path(.test_project_root, "NFLmarket.R"), envir = e))
    for (nm in ls(g)) {
      now <- get(nm, envir = g)
      changed <- !nm %in% names(before) || !identical(now, before[[nm]])
      # Moved functions resolve their siblings in `e` first, as they would
      # have in the global environment
      if (changed && is.function(now) && identical(environment(now), g)) environment(now) <- e
      if (!nm %in% names(before)) {
        assign(nm, now, envir = e)
        rm(list = nm, envir = g)
      } else if (changed) {
        assign(nm, now, envir = e)
        assign(nm, before[[nm]], envir = g)
      }
    }
    cache <<- e
    e
  }
})

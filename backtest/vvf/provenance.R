# =============================================================================
# VVF stage S0, provenance (design 2026-10-20 §2, §4): a feature may enter a
# decision only if the registry says it was known at that decision. This is the
# class-level counterpart of bt_assert_asof() (backtest/common.R), which stays
# the row-level timestamp check for sources with end times.
# =============================================================================

#' Stop unless every feature has a registry row whose known_at class is in the
#' decision's information set and which is not post-hoc
vvf_assert_known_at <- function(features, decision, registry = vvf_registry()) {
  if (!is.character(decision) || length(decision) != 1L || !decision %in% names(VVF_DECISIONS)) {
    stop(sprintf("known-at violation: unknown decision point '%s' (one of %s)", paste(decision, collapse = ","),
                 paste(names(VVF_DECISIONS), collapse = ", ")), call. = FALSE)
  }
  idx <- match(features, registry$name)
  if (anyNA(idx)) {
    stop(sprintf("known-at violation: no registry entry for %s", paste(features[is.na(idx)], collapse = ", ")), call. = FALSE)
  }
  reg <- registry[idx]
  bad <- reg$posthoc | !reg$known_at %in% VVF_DECISIONS[[decision]]
  if (any(bad)) {
    why <- sprintf("%s (%s%s)", reg$name[bad], reg$known_at[bad], ifelse(reg$posthoc[bad], ", post-hoc", ""))
    stop(sprintf("known-at violation at %s: %d feature(s) known after the decision: %s", decision, sum(bad),
                 paste(why, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}

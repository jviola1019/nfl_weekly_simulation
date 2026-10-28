# Why the hand-written logit sandwich and sandwich::vcovCL differ by about 1e-5: vcovCL builds the bread from
# glm's stored IRLS working weights (from the last iteration); the hand version uses the converged probabilities.
# For each moneyline feature of the v2 reproduction: the relative gap to the committed se_robust, at the optimum
# and with glm's IRLS weights, and glm's iteration count. Run from the repository root:
#   Rscript reports/2026-10-28/verification/sandwich_convergence.R > reports/2026-10-28/verification/sandwich_convergence.txt
suppressPackageStartupMessages(library(data.table))
e <- environment()
for (f in c("common.R", "candidates/market.R", "candidates/elo.R", "candidates/epa_glm.R", "blends.R", "calibrators.R",
            "metrics.R", "controls.R")) sys.source(file.path("backtest", f), envir = e)
for (f in c("common.R", "features.R", "registry.R", "provenance.R", "s1_screen.R", "s2_structure.R", "reproduce_v2.R",
            "input_schema.R")) sys.source(file.path("backtest", "vvf", f), envir = e)
v2t <- vvf_v2_table()$d
s1c <- fread(file.path("reports", "2026-10-22", "vvf-v2-repro", "s1_features.csv"))
cr <- function(X, u, w, g) { b <- solve(crossprod(X, X * w)); U <- rowsum(X * u, g); b %*% crossprod(U) %*% b * nrow(U) / (nrow(U) - 1) }
res <- rbindlist(lapply(VVF_V2_FEATURES, function(f) {
  x <- v2t[!is.na(y) & is.finite(lp_anchor) & is.finite(get(f))]
  if (uniqueN(x[[f]]) < 2L) return(NULL)
  X <- cbind(1, x[[f]])
  m1 <- stats::glm(x$y ~ X[, 2], offset = x$lp_anchor, family = stats::binomial())
  p1 <- stats::fitted(m1)
  ref <- s1c[family == "outcome" & feature == f, se_robust]
  data.table(feature = f, iterations = m1$iter,
             rel_gap_at_optimum = abs(sqrt(cr(X, x$y - p1, p1 * (1 - p1), x$wk)[2, 2]) / ref - 1),
             rel_gap_irls_weights = abs(sqrt(cr(X, stats::residuals(m1, "working") * m1$weights, m1$weights, x$wk)[2, 2]) / ref - 1))
}))
print(res[order(-rel_gap_at_optimum)], digits = 3)
cat(sprintf("\nlargest relative gap: %.2e at the optimum, %.2e with glm's IRLS weights (the CSV's 6-digit rounding is up to 5e-6); iterations %d-%d\n",
            max(res$rel_gap_at_optimum), max(res$rel_gap_irls_weights), min(res$iterations), max(res$iterations)))

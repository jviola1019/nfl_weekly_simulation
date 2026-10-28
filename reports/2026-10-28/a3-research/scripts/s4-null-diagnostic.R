# Why the A3b close run's shuffled-labels control voided (S4), on the real Tune table.
# (a) the spec's null: y permuted within week, the anchor offset kept;
# (b) the proposed null: each feature permuted within week, y and the anchor kept together.
# Exploratory, Tune 2018-2022 only (the loaders refuse 2025). Run from the a3dry root:
#   Rscript <this file> <out_csv> [B]
args <- commandArgs(trailingOnly = TRUE)
out_csv <- args[1]
B <- if (length(args) > 1) as.integer(args[2]) else 2000L
e <- environment()
for (f in c("common.R", "candidates/market.R", "candidates/elo.R", "candidates/epa_glm.R", "blends.R",
            "calibrators.R", "metrics.R", "controls.R")) sys.source(file.path("backtest", f), envir = e)
for (f in c("common.R", "features.R", "registry.R", "provenance.R", "s1_screen.R", "s3_skill.R", "s4_controls.R",
            "s5_curves.R", "s5_scores.R", "s5_anova.R", "reproduce_v2.R")) sys.source(file.path("backtest", "vvf", f), envir = e)
source(file.path("backtest", "vvf", "run_a3b_close.R"), local = e)   # defines vvf_a3b_table(); its main block does not run

tab <- vvf_a3b_table()
full <- tab$full
feats <- VVF_V2_FEATURES
tune <- full[season %in% VVF_V2_TUNE]
cor_anchor <- vapply(feats, function(f) {
  ok <- is.finite(tune[[f]]) & is.finite(tune$lp_anchor)
  if (sum(ok) < 3 || stats::sd(tune[[f]][ok]) == 0) NA_real_ else stats::cor(tune[[f]][ok], tune$lp_anchor[ok])
}, numeric(1))

# Each feature permuted within week into its own column perm_<f>, so the lp_anchor offset (itself one of
# v2's 36 features) is never touched; S3 is then run on those columns with the screen's own pieces.
perm_table <- function(d, features, seed = VVF_SHUFFLE_SEED) {
  x <- data.table::copy(d)
  vvf_seeded(seed, function() {
    for (f in features) {
      v <- x[[f]]
      for (w in unique(x$wk)) {
        j <- which(x$wk == w)
        if (length(j) > 1) v[j] <- v[j][sample.int(length(j))]
      }
      data.table::set(x, j = paste0("perm_", f), value = v)
    }
  })
  x
}
x_null_skill <- function(d, features, B) {
  weeks <- bt_week_schedule(d, VVF_V2_TUNE)
  x <- d[season %in% VVF_V2_TUNE, .(game_id, kickoff, season, week, wk, y, p_anchor)]
  dp <- perm_table(d, features)
  for (f in features) {
    p <- vvf_s3_refit(dp, paste0("perm_", f), weeks)
    x <- merge(x, p[, .(game_id, p_new = p)], by = "game_id", all.x = TRUE)
    data.table::setnames(x, "p_new", paste0("p_", f))
  }
  cols <- paste0("p_", features)
  vvf_s3_skill(x, cols, order = cols, ref = "p_anchor", B = B, seed = VVF_S3_SEED)
}

t0 <- Sys.time()
a <- vvf_s3_screen(vvf_shuffle_y(full), feats, "close", VVF_V2_TUNE, B = B)$skill
b <- x_null_skill(full, feats, B)
res <- data.table::data.table(
  feature = feats, cor_with_anchor = round(cor_anchor, 3),
  y_shuffle_skill = signif(a$skill, 4), y_shuffle_lo = signif(a$skill_lo, 4), y_shuffle_hi = signif(a$skill_hi, 4),
  x_shuffle_skill = signif(b$skill, 4), x_shuffle_lo = signif(b$skill_lo, 4), x_shuffle_hi = signif(b$skill_hi, 4))
res[, `:=`(y_excludes_0 = y_shuffle_lo > 0 | y_shuffle_hi < 0, x_excludes_0 = x_shuffle_lo > 0 | x_shuffle_hi < 0)]
data.table::fwrite(res, out_csv)
cat(sprintf("B = %d, %.1f min\n", B, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
cat(sprintf("y within week (spec): %d of %d intervals exclude 0; skill range %.5f to %.5f\n",
            sum(res$y_excludes_0, na.rm = TRUE), nrow(res), min(res$y_shuffle_skill, na.rm = TRUE), max(res$y_shuffle_skill, na.rm = TRUE)))
cat(sprintf("x within week (proposed): %d of %d intervals exclude 0; skill range %.5f to %.5f\n",
            sum(res$x_excludes_0, na.rm = TRUE), nrow(res), min(res$x_shuffle_skill, na.rm = TRUE), max(res$x_shuffle_skill, na.rm = TRUE)))
cat(sprintf("correlation of y-shuffle skill with |cor(x, anchor)|: %.3f\n",
            stats::cor(res$y_shuffle_skill, abs(res$cor_with_anchor), use = "complete.obs")))
print(res[order(-y_shuffle_skill)][1:10, .(feature, cor_with_anchor, y_shuffle_skill, y_shuffle_lo, x_shuffle_skill, x_shuffle_lo, x_shuffle_hi)])

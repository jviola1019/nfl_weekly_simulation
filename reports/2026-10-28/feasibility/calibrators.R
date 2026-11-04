# Do calibrators help? #205 fit three calibration maps (Platt, spline, isotonic) walk-forward on top of seven base
# models and committed every Tune prediction (tracking/moneyline_tune.csv). For each calibrated variant: its paired
# Brier and log-loss change against its own uncalibrated model (two-sided paired t-test, BH over all 21), against
# the close, and its calibration slope before and after. The engine's own calibrator is separate: it is invalid
# (audit M4) and disabled, so the engine shrinks toward the market instead (SHRINKAGE 0.7). Run from the repository root:
#   Rscript reports/2026-10-28/feasibility/calibrators.R <out_dir> <ref #205>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE); out <- args[1]; ref205 <- args[2]
git_csv <- function(ref, path) fread(text = system2("git", c("show", shQuote(sprintf("%s:%s", ref, path))), stdout = TRUE))
trk <- git_csv(ref205, "reports/2026-09-30/validation-sprint/tracking/moneyline_tune.csv")
trk[, `:=`(base = sub("__.*$", "", candidate), calibration = fifelse(grepl("__", candidate), sub("^.*__", "", candidate), "none"))]
ll <- function(p, y) -(y * log(p) + (1 - y) * log(1 - p))
slope <- function(p, y) { lp <- stats::qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6)); m <- stats::glm(y ~ lp, family = stats::binomial())
  c(slope = unname(stats::coef(m)[2]), lo = stats::confint.default(m)[2, 1], hi = stats::confint.default(m)[2, 2]) }
raw <- trk[calibration == "none", .(game_id, base, p0 = p_model)]
cal <- merge(trk[calibration != "none"], raw, by = c("game_id", "base"))
res <- cal[, {
  br <- (p_model - outcome)^2; br0 <- (p0 - outcome)^2; brm <- (p_market - outcome)^2
  s1 <- slope(p_model, outcome); s0 <- slope(p0, outcome)
  .(n = .N, brier_change = mean(br - br0), brier_p = stats::t.test(br, br0, paired = TRUE)$p.value,
    logloss_change = mean(ll(p_model, outcome) - ll(p0, outcome)), logloss_p = stats::t.test(ll(p_model, outcome), ll(p0, outcome), paired = TRUE)$p.value,
    skill_vs_close = 1 - mean(br) / mean(brm), skill_vs_close_raw = 1 - mean(br0) / mean(brm),
    slope_raw = s0[["slope"]], slope_cal = s1[["slope"]], slope_cal_lo = s1[["lo"]], slope_cal_hi = s1[["hi"]])
}, by = .(base, calibration)]
res[, `:=`(brier_q = stats::p.adjust(brier_p, method = "BH"), logloss_q = stats::p.adjust(logloss_p, method = "BH"))]
setorder(res, base, calibration)
fwrite(res[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 5) else v)], file.path(out, "calibrators.csv"))
print(res[, .(base, calibration, brier_change = signif(brier_change, 3), brier_q = signif(brier_q, 3), logloss_change = signif(logloss_change, 3),
              logloss_q = signif(logloss_q, 3), skill_vs_close = signif(skill_vs_close, 3), slope_raw = signif(slope_raw, 3), slope_cal = signif(slope_cal, 3))])
cat(sprintf("\ncalibrated variants: %d; Brier better than their own model: %d (BH q < 0.05: %d); worse with q < 0.05: %d\n", nrow(res),
            sum(res$brier_change < 0), sum(res$brier_change < 0 & res$brier_q < 0.05), sum(res$brier_change > 0 & res$brier_q < 0.05)))
cat(sprintf("log loss better: %d (q < 0.05: %d); worse with q < 0.05: %d; any calibrated variant with positive Brier skill against the close: %d\n",
            sum(res$logloss_change < 0), sum(res$logloss_change < 0 & res$logloss_q < 0.05), sum(res$logloss_change > 0 & res$logloss_q < 0.05),
            sum(res$skill_vs_close > 0)))
cat(sprintf("raw slopes %.2f-%.2f; calibrated %.2f-%.2f\n", min(res$slope_raw), max(res$slope_raw), min(res$slope_cal), max(res$slope_cal)))

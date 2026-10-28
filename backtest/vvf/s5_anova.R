# =============================================================================
# VVF stage S5, ANOVA additions (amendment 2026-10-21, item 1):
#   - does a candidate's paired loss difference against a reference vary by
#     season or by part of the season? lm(d ~ factor(group)) against lm(d ~ 1);
#   - team-level residual effects against the anchor: home-team and away-team
#     factors with sum-to-zero contrasts, an LR test for the outcome (anchor
#     offset) or an F test for a linear family.
# Feature x season interactions are S2's (s2_structure.R).
# =============================================================================

suppressPackageStartupMessages(library(data.table))

vvf_season_part <- function(week, phase) {
  fcase(phase == "POST", "playoffs", week <= 6L, "weeks 1-6", week <= 12L, "weeks 7-12", default = "weeks 13-18")
}

vvf_loss_anova <- function(d, cand, ref, by = c("season", "part")) {
  by <- match.arg(by)
  x <- d[!is.na(y) & is.finite(get(cand)) & is.finite(get(ref))]
  x[, grp := if (by == "season") as.character(season) else vvf_season_part(week, phase)]
  rbindlist(lapply(c("brier", "logloss"), function(loss) {
    f <- if (loss == "brier") bt_brier_vec else bt_logloss_vec
    x[, dl := f(get(cand), y) - f(get(ref), y)]
    a <- stats::anova(stats::lm(dl ~ 1, data = x), stats::lm(dl ~ factor(grp), data = x))
    m <- x[, .(m = mean(dl), n = .N), keyby = grp]
    data.table(candidate = cand, reference = ref, by = by, loss = loss, n = nrow(x), groups = nrow(m),
               F = a$F[2], df = as.integer(a$Df[2]), p = a$`Pr(>F)`[2],
               by_group = paste(sprintf("%s: %+.5f (%d)", m$grp, m$m, m$n), collapse = "; "))
  }))
}

vvf_team_effects <- function(d, family = "outcome", response = "y") {
  x <- if (family == "outcome") d[!is.na(y) & is.finite(lp_anchor)] else d[is.finite(get(response))]
  x[, `:=`(ht = factor(home_franchise), at = factor(away_franchise))]
  ct <- list(ht = "contr.sum", at = "contr.sum")
  if (family == "outcome") {
    m0 <- stats::glm(y ~ 1, offset = lp_anchor, family = stats::binomial(), data = x)
    m1 <- stats::glm(y ~ 1 + ht + at, offset = lp_anchor, family = stats::binomial(), data = x, contrasts = ct)
    stat <- m0$deviance - m1$deviance
    df <- as.integer(m0$df.residual - m1$df.residual)
    p <- stats::pchisq(stat, df, lower.tail = FALSE)
    test <- "LR chi2"
  } else {
    x[, r := get(response)]
    m1 <- stats::lm(r ~ 1 + ht + at, data = x, contrasts = ct)
    a <- stats::anova(stats::lm(r ~ 1, data = x), m1)
    stat <- a$F[2]; df <- as.integer(a$Df[2]); p <- a$`Pr(>F)`[2]
    test <- "F"
  }
  cf <- stats::coef(m1)
  side <- function(prefix, lev) {
    b <- cf[grep(paste0("^", prefix), names(cf))]
    data.table(side = if (prefix == "ht") "home" else "away", team = lev, effect = c(b, -sum(b)))
  }
  eff <- rbind(side("ht", levels(x$ht)), side("at", levels(x$at)))[order(-abs(effect))]
  data.table(family = family, n = nrow(x), test = test, stat = stat, df = df, p = p,
             largest = paste(sprintf("%s %s %+.3f", eff$side[1:3], eff$team[1:3], eff$effect[1:3]), collapse = "; "))
}

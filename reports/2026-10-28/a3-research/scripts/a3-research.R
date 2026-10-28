# A3 research (2026-10-28): the S4 null, the joint test, the cluster unit, late schedule changes.
# Exploratory, on v2's Tune window 2018-2022 (close-anchored); the loaders refuse 2025.
#   Rscript a3-research.R <section: s4|joint|cluster|late> <table.rds> <out_dir> [extra]
# Run from a tree that holds the A3 files (backtest/vvf/*.R, including s3_skill.R and s4_controls.R).
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
section <- args[1]; tab <- readRDS(args[2]); out <- args[3]
dir.create(out, recursive = TRUE, showWarnings = FALSE)
e <- environment()
for (f in c("common.R", "candidates/market.R", "candidates/elo.R", "candidates/epa_glm.R", "blends.R",
            "calibrators.R", "metrics.R", "controls.R")) sys.source(file.path("backtest", f), envir = e)
for (f in c("common.R", "features.R", "registry.R", "provenance.R", "s1_screen.R", "s3_skill.R", "s4_controls.R",
            "reproduce_v2.R")) sys.source(file.path("backtest", "vvf", f), envir = e)
full <- tab$full; feats <- tab$features; tune <- tab$tune
tn <- full[season %in% tune]
seeded <- function(seed, f) { old <- if (exists(".Random.seed", globalenv())) get(".Random.seed", globalenv()); set.seed(seed); on.exit(if (!is.null(old)) assign(".Random.seed", old, globalenv())); f() }

# ---------------------------------------------------------------------------------------------
if (section == "s4") {
  B <- 1000L; R <- as.integer(if (length(args) > 3) args[4] else 5)
  claims <- function(sk) c(above = sum(sk$skill_lo > 0), below = sum(sk$skill_hi < 0),
                           claims = sum(grepl("^incremental skill", sk$verdict)))
  perm_x <- function(d, seed) {
    x <- copy(d)
    seeded(seed, function() for (f in feats) {
      v <- x[[f]]; for (w in unique(x$wk)) { j <- which(x$wk == w); if (length(j) > 1) v[j] <- v[j][sample.int(length(j))] }
      set(x, j = paste0("perm_", f), value = v)
    })
    x
  }
  s3_cols <- function(d, cols, names_out) {     # S3 on arbitrary columns, scored like vvf_s3_screen
    weeks <- bt_week_schedule(d, tune)
    x <- d[season %in% tune, .(game_id, kickoff, season, week, wk, y, p_anchor)]
    for (k in seq_along(cols)) {
      p <- vvf_s3_refit(d, cols[k], weeks)
      x <- merge(x, p[, .(game_id, p_new = p)], by = "game_id", all.x = TRUE); setnames(x, "p_new", names_out[k])
    }
    vvf_s3_skill(x, names_out, order = names_out, ref = "p_anchor", B = B, seed = VVF_S3_SEED)
  }
  model_y <- function(d, seed, beta = 0, z = NULL) {
    x <- copy(d)
    seeded(seed, function() {
      i <- which(!is.na(x$y))
      eta <- x$lp_anchor[i] + if (beta != 0) beta * z[i] else 0
      set(x, i, "y", as.integer(stats::rbinom(length(i), 1, stats::plogis(eta))))
    })
    setattr(x, "vvf_anchor", attr(d, "vvf_anchor")); x
  }
  rows <- list()
  for (r in seq_len(R)) {
    sd0 <- 20261028L + r
    a <- vvf_s3_screen(vvf_shuffle_y(full, seed = sd0), feats, "close", tune, B = B)$skill
    b <- s3_cols(perm_x(full, sd0), paste0("perm_", feats), paste0("p_", feats))
    m <- vvf_s3_screen(model_y(full, sd0), feats, "close", tune, B = B)$skill
    rows[[length(rows) + 1]] <- rbind(data.table(null = "y within week (spec)", rep = r, t(claims(a))),
                                      data.table(null = "x permuted within week", rep = r, t(claims(b))),
                                      data.table(null = "y drawn from the anchor (consistency resampling)", rep = r, t(claims(m))))
    cat(sprintf("rep %d done\n", r))
  }
  res <- rbindlist(rows); fwrite(res, file.path(out, "s4_nulls.csv"))
  print(res[, .(reps = .N, mean_above = mean(above), max_above = max(above), mean_below = mean(below),
                reps_with_claim = sum(claims > 0)), by = null])
  # power: a planted effect on a real, non-anchor feature (rest_diff, standardized on Tune)
  z <- (full$rest_diff - mean(tn$rest_diff, na.rm = TRUE)) / stats::sd(tn$rest_diff, na.rm = TRUE)
  z[!is.finite(z)] <- 0
  pw <- rbindlist(lapply(c(0.05, 0.10, 0.20), function(beta) rbindlist(lapply(1:5, function(r) {
    d <- model_y(full, 20261100L + r, beta, z)
    sk <- vvf_s3_screen(d, "rest_diff", "close", tune, B = B)$skill
    data.table(beta = beta, rep = r, skill = sk$skill, lo = sk$skill_lo, claim = grepl("^incremental", sk$verdict))
  }))))
  fwrite(pw, file.path(out, "s4_power.csv"))
  print(pw[, .(detected = sum(claim), of = .N, mean_skill = signif(mean(skill), 3)), by = beta])
}

# ---------------------------------------------------------------------------------------------
if (section == "joint") {
  R <- as.integer(if (length(args) > 3) args[4] else 1000); Bw <- 999L
  d <- tn[!is.na(y) & is.finite(lp_anchor)]
  setnames_safe <- function(x) x
  sets <- list(situational = VVF_V2_SITUATIONAL, all = feats)
  wk <- d$wk; G <- uniqueN(wk); g_idx <- match(wk, sort(unique(wk)))
  # week random-effect SD of the outcome on the logit scale, by moments on the anchor residuals
  p0 <- d$p_anchor; e0 <- d$y - p0
  mw <- tapply(e0, g_idx, mean); nw <- tabulate(g_idx); vbin <- tapply(p0 * (1 - p0), g_idx, mean) / nw
  between <- max(0, stats::var(mw) - mean(vbin)); s_u <- sqrt(between) / mean(p0 * (1 - p0))
  cat(sprintf("G = %d week clusters; estimated week effect SD on the logit scale %.3f\n", G, s_u))
  Xof <- function(fs) {
    X <- as.matrix(d[, ..fs]); keep <- apply(X, 2, function(v) all(is.finite(v)) && stats::sd(v) > 0); X <- X[, keep, drop = FALSE]
    q <- qr(cbind(1, X)); X[, q$pivot[seq_len(q$rank)][-1] - 1, drop = FALSE]     # drop aliased columns
  }
  one <- function(X, y, W) {
    k <- ncol(X)
    m0 <- stats::glm(y ~ 1, offset = d$lp_anchor, family = stats::binomial())
    m1 <- stats::glm(y ~ 1 + X, offset = d$lp_anchor, family = stats::binomial())
    p_lr <- stats::pchisq(m0$deviance - m1$deviance, k, lower.tail = FALSE)
    b <- stats::coef(m1)[-1]; ok <- is.finite(b)
    V <- sandwich::vcovCL(m1, cluster = wk, type = "HC0")[-1, -1][ok, ok]
    w <- tryCatch(drop(t(b[ok]) %*% solve(V, b[ok])), error = function(e) NA_real_)
    p_wald <- stats::pchisq(w, sum(ok), lower.tail = FALSE)
    p_wald_f <- stats::pf(w / sum(ok), sum(ok), G - 1, lower.tail = FALSE)
    # restricted wild cluster score bootstrap (Kline & Santos 2012): the scores of b at the
    # restricted fit, summed by cluster; Rademacher weights; full and diagonal studentization
    pr <- stats::fitted(m0); wt <- pr * (1 - pr)
    Xc <- sweep(X, 2, colSums(X * wt) / sum(wt))
    Sg <- rowsum(Xc * (y - pr), g_idx)                                       # G x k
    S <- colSums(Sg); Vs <- crossprod(Sg); dg <- diag(Vs)
    Ws <- W %*% Sg                                                          # B x k bootstrap score sums
    t_diag <- sum(S^2 / dg); t_diag_b <- rowSums(sweep(Ws^2, 2, dg, "/"))
    full_ok <- qr(Vs)$rank == ncol(Vs)
    if (full_ok) { Vi <- solve(Vs); t_full <- drop(S %*% Vi %*% S); t_full_b <- rowSums((Ws %*% Vi) * Ws) } else { t_full <- NA; t_full_b <- NA }
    c(lr = p_lr, wald_chi2 = p_wald, wald_f = p_wald_f,
      score_boot_full = if (full_ok) (1 + sum(t_full_b >= t_full)) / (nrow(W) + 1) else NA_real_,
      score_boot_diag = (1 + sum(t_diag_b >= t_diag)) / (nrow(W) + 1))
  }
  res <- list()
  for (sn in names(sets)) {
    X <- Xof(sets[[sn]])
    # the estimated week effect is about 0 (the cluster section), so fixed SDs test robustness
    for (su in c(0, 0.10, 0.20)) {
      ps <- seeded(20261028L, function() t(vapply(seq_len(R), function(r) {
        u <- stats::rnorm(G, 0, su)[g_idx]
        y <- stats::rbinom(nrow(d), 1, stats::plogis(d$lp_anchor + u))
        W <- matrix(sample(c(-1, 1), Bw * G, replace = TRUE), Bw, G)
        one(X, y, W)
      }, numeric(5))))
      res[[length(res) + 1]] <- data.table(set = sn, k = ncol(X), G = G, week_sd = round(su, 3), test = colnames(ps),
                                           size = colMeans(ps < 0.05, na.rm = TRUE), n_ok = colSums(is.finite(ps)))
      cat(sprintf("%s k=%d week_sd=%.3f done\n", sn, ncol(X), su))
    }
  }
  # one season (22 clusters, k > G - 1): the CRVE is singular, only the diagonal bootstrap is defined
  d1 <- d; d <- d1[season == max(tune)]; wk <- d$wk; G <- uniqueN(wk); g_idx <- match(wk, sort(unique(wk)))
  X <- Xof(sets$situational)
  ps <- seeded(20261029L, function() t(vapply(seq_len(min(R, 500)), function(r) {
    y <- stats::rbinom(nrow(d), 1, stats::plogis(d$lp_anchor))
    W <- matrix(sample(c(-1, 1), Bw * G, replace = TRUE), Bw, G)
    one(X, y, W)
  }, numeric(5))))
  res[[length(res) + 1]] <- data.table(set = "situational, one season", k = ncol(X), G = G, week_sd = 0, test = colnames(ps),
                                       size = colMeans(ps < 0.05, na.rm = TRUE), n_ok = colSums(is.finite(ps)))
  r <- rbindlist(res); fwrite(r, file.path(out, "joint_size.csv"))
  print(dcast(r, set + k + G + week_sd ~ test, value.var = "size"))
}

# ---------------------------------------------------------------------------------------------
# the linear families (spread and total residuals against the close): the same five tests, with
# r* = mean + week effect + a resampled centred residual; week SDs in points (residual SD about 13)
if (section == "joint_linear") {
  R <- as.integer(if (length(args) > 3) args[4] else 1000); Bw <- 999L
  res <- list()
  for (resp in c("ats_resid", "tot_resid")) {
    d <- tn[is.finite(get(resp))]
    wk <- d$wk; G <- uniqueN(wk); g_idx <- match(wk, sort(unique(wk)))
    r0 <- d[[resp]]; e0 <- r0 - mean(r0)
    Xof <- function(fs) {
      X <- as.matrix(d[, ..fs]); keep <- apply(X, 2, function(v) all(is.finite(v)) && stats::sd(v) > 0); X <- X[, keep, drop = FALSE]
      q <- qr(cbind(1, X)); X[, q$pivot[seq_len(q$rank)][-1] - 1, drop = FALSE]
    }
    one <- function(X, r, W) {
      k <- ncol(X)
      m0 <- stats::lm(r ~ 1); m1 <- stats::lm(r ~ 1 + X)
      p_f <- stats::anova(m0, m1)$`Pr(>F)`[2]
      b <- stats::coef(m1)[-1]; ok <- is.finite(b)
      V <- sandwich::vcovCL(m1, cluster = wk, type = "HC0")[-1, -1][ok, ok]
      w <- tryCatch(drop(t(b[ok]) %*% solve(V, b[ok])), error = function(e) NA_real_)
      Xc <- sweep(X, 2, colMeans(X))
      Sg <- rowsum(Xc * (r - mean(r)), g_idx); S <- colSums(Sg); Vs <- crossprod(Sg); dg <- diag(Vs)
      Ws <- W %*% Sg
      t_diag <- sum(S^2 / dg); t_diag_b <- rowSums(sweep(Ws^2, 2, dg, "/"))
      full_ok <- qr(Vs)$rank == ncol(Vs)
      if (full_ok) { Vi <- solve(Vs); t_full <- drop(S %*% Vi %*% S); t_full_b <- rowSums((Ws %*% Vi) * Ws) }
      c(f = p_f, wald_chi2 = stats::pchisq(w, sum(ok), lower.tail = FALSE),
        wald_f = stats::pf(w / sum(ok), sum(ok), G - 1, lower.tail = FALSE),
        score_boot_full = if (full_ok) (1 + sum(t_full_b >= t_full)) / (nrow(W) + 1) else NA_real_,
        score_boot_diag = (1 + sum(t_diag_b >= t_diag)) / (nrow(W) + 1))
    }
    for (sn in c("situational", "all")) {
      X <- Xof(if (sn == "situational") VVF_V2_SITUATIONAL else feats)
      for (su in c(0, 1, 2)) {
        ps <- seeded(20261030L, function() t(vapply(seq_len(R), function(i) {
          r <- mean(r0) + stats::rnorm(G, 0, su)[g_idx] + e0[sample.int(length(e0), replace = TRUE)]
          W <- matrix(sample(c(-1, 1), Bw * G, replace = TRUE), Bw, G)
          one(X, r, W)
        }, numeric(5))))
        res[[length(res) + 1]] <- data.table(family = resp, set = sn, k = ncol(X), G = G, week_sd_points = su, test = colnames(ps),
                                             size = colMeans(ps < 0.05, na.rm = TRUE), n_ok = colSums(is.finite(ps)))
        cat(sprintf("%s %s k=%d week_sd=%g done\n", resp, sn, ncol(X), su))
      }
    }
  }
  r <- rbindlist(res); fwrite(r, file.path(out, "joint_size_linear.csv"))
  print(dcast(r, family + set + k + G + week_sd_points ~ test, value.var = "size"))
}

# ---------------------------------------------------------------------------------------------
if (section == "cluster") {
  d <- tn[!is.na(y)]
  d[, e_out := y - p_anchor]
  team_long <- function(v) rbind(d[, .(grp = paste(season, home_franchise), r = get(v))],
                                 d[, .(grp = paste(season, away_franchise), r = -get(v))])
  anova_icc <- function(r, grp) {
    ok <- is.finite(r) & !is.na(grp); r <- r[ok]; grp <- factor(grp[ok])
    a <- stats::anova(stats::lm(r ~ grp)); k <- nlevels(grp); n <- length(r)
    n0 <- (n - sum(table(grp)^2) / n) / (k - 1)
    msb <- a$`Mean Sq`[1]; msw <- a$`Mean Sq`[2]
    data.table(groups = k, F = a$`F value`[1], p = a$`Pr(>F)`[1], icc = max(0, (msb - msw) / (msb + (n0 - 1) * msw)))
  }
  res <- list()
  for (v in c("e_out", "ats_resid", "tot_resid")) {
    for (unit in c("season-week", "week of season", "game day", "team-season")) {
      r <- if (unit == "team-season") { t <- team_long(v); anova_icc(t$r, t$grp) } else
        anova_icc(d[[v]], switch(unit, "season-week" = d$wk, "week of season" = d$week, "game day" = d$gameday))
      res[[length(res) + 1]] <- cbind(data.table(residual = v, unit = unit), r)
    }
  }
  icc <- rbindlist(res); fwrite(icc, file.path(out, "cluster_icc.csv")); print(icc)
  # design effects: robust variance of each S1 coefficient clustered at a unit, over HC0
  de <- rbindlist(lapply(VVF_V2_SITUATIONAL, function(f) {
    x <- d[is.finite(get(f))]; if (stats::sd(x[[f]]) == 0) return(NULL)
    m <- stats::glm(y ~ 1 + get(f), offset = lp_anchor, family = stats::binomial(), data = x)
    hc <- sandwich::vcovHC(m, type = "HC0")[2, 2]
    data.table(feature = f,
               season_week = sandwich::vcovCL(m, cluster = x$wk, type = "HC0")[2, 2] / hc,
               week_of_season = sandwich::vcovCL(m, cluster = x$week, type = "HC0")[2, 2] / hc,
               game_day = sandwich::vcovCL(m, cluster = x$gameday, type = "HC0")[2, 2] / hc,
               two_way_week_team = sandwich::vcovCL(m, cluster = ~ wk + home_franchise, type = "HC0")[2, 2] / hc)
  }))
  fwrite(de, file.path(out, "cluster_design_effects.csv"))
  print(de[, lapply(.SD, function(v) round(stats::median(v), 3)), .SDcols = -1])
}

# ---------------------------------------------------------------------------------------------
if (section == "late") {
  lc <- fread(args[4])                          # flex-games.csv (one row per changed game and kind)
  lc <- lc[kind != "network only"]               # a network change alters no feature
  lc[, late := kind %in% c("date", "venue") | (week >= 17L & kind %in% c("primetime", "time", "other", "day"))]
  g <- lc[, .(changed = TRUE, late = any(late), primetime_change = any(kind == "primetime")), by = game_id]
  d <- merge(tn, g, by = "game_id", all.x = TRUE)
  for (v in c("changed", "late", "primetime_change")) set(d, which(is.na(d[[v]])), v, FALSE)
  cat(sprintf("Tune games %d: changed %d (%.1f%%), late %d, primetime moves %d\n", nrow(d), sum(d$changed),
              100 * mean(d$changed), sum(d$late), sum(d$primetime_change)))
  test <- function(ind) {
    o <- d[!is.na(y)]; o[, z := as.integer(get(ind))]
    m0 <- stats::glm(y ~ 1, offset = lp_anchor, family = stats::binomial(), data = o)
    m1 <- stats::glm(y ~ 1 + z, offset = lp_anchor, family = stats::binomial(), data = o)
    vo <- sandwich::vcovCL(m1, cluster = o$wk, type = "HC0")
    a <- stats::lm(ats_resid ~ as.integer(get(ind)), data = d[is.finite(ats_resid)])
    va <- sandwich::vcovCL(a, cluster = d[is.finite(ats_resid)]$wk, type = "HC0")
    data.table(indicator = ind, n_flag = sum(o$z),
               outcome_logodds = stats::coef(m1)[["z"]], outcome_p_lr = stats::pchisq(m0$deviance - m1$deviance, 1, lower.tail = FALSE),
               outcome_p_robust = 2 * stats::pnorm(-abs(stats::coef(m1)[["z"]] / sqrt(vo[2, 2]))),
               ats_points = stats::coef(a)[[2]], ats_p_robust = 2 * stats::pnorm(-abs(stats::coef(a)[[2]] / sqrt(va[2, 2]))))
  }
  tt <- rbindlist(lapply(c("changed", "late", "primetime_change"), test))
  fwrite(tt, file.path(out, "late_tests.csv")); print(tt)
  # sensitivity: S1 with the changed games out, against S1 on every Tune game
  s_all <- vvf_s1_screen(full[season %in% tune], feats, "close")$features
  s_out <- vvf_s1_screen(full[season %in% tune & !game_id %in% g$game_id], feats, "close")$features
  cmp <- merge(s_all[, .(family, feature, q_all = q_bh, est_all = estimate, verdict_all = verdict)],
               s_out[, .(family, feature, q_out = q_bh, est_out = estimate, verdict_out = verdict)], by = c("family", "feature"))
  cmp[, verdict_changed := substr(verdict_all, 1, 6) != substr(verdict_out, 1, 6)]
  fwrite(cmp, file.path(out, "late_s1_sensitivity.csv"))
  cat(sprintf("S1 verdicts changed by dropping the changed games: %d of %d; smallest q without them %.3f (%s)\n",
              sum(cmp$verdict_changed), nrow(cmp), min(cmp$q_out, na.rm = TRUE), cmp[which.min(q_out), paste(family, feature)]))
  print(cmp[feature %in% c("primetime", "thursday", "rest_diff", "neutral_site", "west_early"),
            .(family, feature, q_all = round(q_all, 3), q_out = round(q_out, 3), est_all = signif(est_all, 3), est_out = signif(est_out, 3))])
}

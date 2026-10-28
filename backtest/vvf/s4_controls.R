# =============================================================================
# VVF stage S4, controls (design 2026-10-20 §4). A failed gating control voids
# the run.
#   Leak canary: append an absurd future game; every feature value of every
#     earlier game must be unchanged (a generic build/append check, so it also
#     catches a leak in any later builder).
#   Placebo: 200 independent N(0,1) noise features through S1 at alpha = 0.05;
#     the rejection rate must lie in [0.020, 0.080], the binomial 95% band.
#   Shuffled labels (the spec's): permute y within week; every S3 skill
#     interval must include 0. Kept and reported, but it fails by construction
#     for S3's anchor-offset model: shuffled labels break the anchor, and a
#     feature that tracks the anchor then beats it (reports/2026-10-28/a3-research).
#   Anchor null (proposed): redraw y from the anchor, y* ~ Bernoulli(p_anchor)
#     (consistency resampling, Broecker and Smith 2007), the exact null of S3's
#     model with b = 0. Permuted-x null: permute each feature within week, with
#     y and the anchor kept together. Each passes when S3's own claim rule
#     claims no feature; an interval wholly below 0 is the cost of fitting noise.
#   Anchor copy: a candidate equal to the anchor scores skill exactly 0.
#   Reproducibility: a second run gives the same result_sha256.
# The spec's gating set includes the shuffle; the amended set (unsigned, owner
# decision) has the anchor null in its place. Every random draw uses a fixed
# seed and restores the caller's RNG.
# =============================================================================

VVF_PLACEBO_K <- 200L
VVF_PLACEBO_SEED <- 20261022L
VVF_PLACEBO_BAND <- c(0.020, 0.080)
VVF_SHUFFLE_SEED <- 20261023L
VVF_NULL_SEED <- 20261028L
VVF_CANARY_ID <- "CANARY_GAME"
VVF_S4_GATING_SPEC <- c("canary", "placebo", "shuffled_labels", "anchor_copy", "reproducibility")
VVF_S4_GATING_AMENDED <- c("canary", "placebo", "anchor_null", "anchor_copy", "reproducibility")

#' Leak canary: build(inputs) and build(append(inputs)) must agree on every
#' column for every row of the first, and the second must hold the extra row(s)
vvf_control_canary <- function(build, inputs, append, key = "game_id") {
  a <- build(inputs)
  b_all <- build(append(inputs))
  idx <- match(a[[key]], b_all[[key]])
  b <- b_all[idx]
  cols <- intersect(names(a), names(b))
  changed <- cols[!vapply(cols, function(cc) identical(a[[cc]], b[[cc]]), logical(1))]
  added <- nrow(b_all) - nrow(a)
  list(passed = !anyNA(idx) && added >= 1L && !length(changed), changed = changed, rows = nrow(a), added = added)
}

#' The VVF builder's canary: one week after the last game of `max_season`, a
#' 99-0 game at a neutral London venue with an unknown referee, inflated EPA
#' and a full injury report. `inputs` is list(v1, v2, max_season).
vvf_canary_append <- function(inputs) {
  v1 <- inputs$v1
  v2 <- inputs$v2
  last <- v1$games[season == inputs$max_season][which.max(kickoff)]
  g <- copy(last)
  g[, `:=`(game_id = VVF_CANARY_ID, kickoff = kickoff + 7 * 86400, week = week + 1L, home_score = 99L, away_score = 0L,
           location = "Neutral", neutral = TRUE, played = TRUE, tie = FALSE, y = 1L)]
  g[, wk := season * 100L + week]
  # keep kickoff_utc's own type (fread reads ISO times as POSIXct), or rbind would coerce every row
  if (inherits(g$kickoff_utc, "POSIXct")) g[, kickoff_utc := kickoff] else g[, kickoff_utc := format(kickoff, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")]
  v1$games <- rbind(v1$games, g, fill = TRUE)
  for (nm in c("team_games", "qb_games")) {
    r <- copy(v1[[nm]][game_id == last$game_id])
    r[, game_id := VVF_CANARY_ID]
    for (cc in intersect(c("epa_sum", "pass_epa_sum", "rush_epa_sum", "qb_epa_sum"), names(r))) set(r, j = cc, value = r[[cc]] + 500)
    v1[[nm]] <- rbind(v1[[nm]], r)
  }
  ctx <- copy(v2$game_context[game_id == last$game_id])
  ctx[, `:=`(game_id = VVF_CANARY_ID, week = week + 1L, stadium_id = "LON00", referee = "Canary Ref")]
  v2$game_context <- rbind(v2$game_context, ctx)
  inj <- copy(v2$injuries_team[1])
  num <- setdiff(names(inj), c("game_id", "season", "team"))
  for (cc in num) set(inj, j = cc, value = 9L)
  inj[, `:=`(game_id = VVF_CANARY_ID, season = last$season, team = last$home_franchise)]
  v2$injuries_team <- rbind(v2$injuries_team, inj)
  v2$injuries_qb <- rbind(v2$injuries_qb, data.table(game_id = VVF_CANARY_ID, season = last$season,
                                                     team = last$home_franchise, gsis_id = last$home_qb_id, status = "out"))
  list(v1 = v1, v2 = v2, max_season = inputs$max_season)
}

#' Placebo: k independent N(0,1) features through S1's test for `family`; the
#' share of combined p-values below alpha must lie in VVF_PLACEBO_BAND
vvf_control_placebo <- function(d, family = "outcome", response = "y", k = VVF_PLACEBO_K, seed = VVF_PLACEBO_SEED,
                                alpha = VVF_ALPHA, B = VVF_WILD_B) {
  dat <- if (family == "outcome") d[!is.na(y) & is.finite(lp_anchor)] else d[is.finite(get(response))]
  Z <- vvf_seeded(seed, function() matrix(stats::rnorm(nrow(dat) * k), nrow = nrow(dat)))
  p <- vapply(seq_len(k), function(j) {
    dat[, placebo := Z[, j]]
    vvf_s1_one(dat, family, "placebo", response, B = B)$p
  }, numeric(1))
  rate <- mean(p < alpha)
  list(k = k, n = nrow(dat), alpha = alpha, rate = rate, band = VVF_PLACEBO_BAND,
       passed = rate >= VVF_PLACEBO_BAND[1] && rate <= VVF_PLACEBO_BAND[2], p = p)
}

#' Permute y within each week ("wk", the default) or across all games ("all")
vvf_shuffle_y <- function(d, seed = VVF_SHUFFLE_SEED, within = c("wk", "all")) {
  within <- match.arg(within)
  x <- copy(d)
  i <- which(!is.na(x$y))
  vvf_seeded(seed, function() {
    if (within == "all") {
      set(x, i, "y", x$y[i][sample.int(length(i))])
    } else {
      for (w in unique(x$wk[i])) {
        j <- i[x$wk[i] == w]
        set(x, j, "y", x$y[j][sample.int(length(j))])
      }
    }
  })
  setattr(x, "vvf_anchor", attr(d, "vvf_anchor"))
  x
}

#' Shuffled labels: S3 on a within-week permutation; every interval must include 0
vvf_control_shuffle <- function(d, features, decision, eval_seasons, registry = vvf_registry(), within = "wk",
                                B = VVF_S3_B, seed = VVF_SHUFFLE_SEED) {
  s3 <- vvf_s3_screen(vvf_shuffle_y(d, seed, within), features, decision, eval_seasons, registry, B)
  sk <- s3$skill[, .(feature, skill, skill_lo, skill_hi)]
  list(passed = all(sk$skill_lo <= 0 & sk$skill_hi >= 0), within = within, skill = sk)
}

#' The anchor null's data: every labelled y redrawn as Bernoulli(p_anchor);
#' every other column, the unlabelled rows and the anchor attribute are kept
vvf_resample_y <- function(d, seed = VVF_NULL_SEED) {
  x <- copy(d)
  i <- which(!is.na(x$y))
  vvf_seeded(seed, function() set(x, i, "y", as.integer(stats::rbinom(length(i), 1L, x$p_anchor[i]))))
  setattr(x, "vvf_anchor", attr(d, "vvf_anchor"))
  x
}

#' The permuted-x null's data: a column perm_<f> for each feature, permuted
#' within week; y, lp_anchor and p_anchor are untouched
vvf_permute_x <- function(d, features, seed = VVF_NULL_SEED) {
  x <- copy(d)
  rows <- split(seq_len(nrow(x)), x$wk)
  vvf_seeded(seed, function() for (f in features) {
    v <- x[[f]]
    for (j in rows) if (length(j) > 1L) v[j] <- v[j][sample.int(length(j))]
    set(x, j = paste0("perm_", f), value = v)
  })
  setattr(x, "vvf_anchor", attr(d, "vvf_anchor"))
  x
}

#' Counts in an S3 skill table: features claimed by S3's rule, and intervals
#' wholly above and wholly below 0
vvf_s3_claims <- function(skill) {
  list(claims = sum(startsWith(skill$verdict, "incremental skill")), above = sum(skill$skill_lo > 0),
       below = sum(skill$skill_hi < 0))
}

#' S3 under a null: "anchor" redraws y from the anchor (vvf_resample_y),
#' "permuted_x" permutes each feature within week (vvf_permute_x). Passes when
#' S3's claim rule claims no feature.
vvf_control_null <- function(d, features, decision, eval_seasons, null = c("anchor", "permuted_x"), registry = vvf_registry(),
                             B = VVF_S3_B, seed = VVF_NULL_SEED) {
  null <- match.arg(null)
  vvf_assert_known_at(features, decision, registry)
  if (null == "anchor") {
    sk <- vvf_s3_screen(vvf_resample_y(d, seed), features, decision, eval_seasons, registry, B)$skill
  } else {
    vvf_assert_anchor(attr(d, "vvf_anchor"), decision)
    vvf_guard_table(d, "the permuted-x table")
    vvf_guard_seasons(eval_seasons, VVF_MAX_INPUT_SEASON, "S4 evaluation seasons")
    dp <- vvf_permute_x(d, features, seed)
    weeks <- bt_week_schedule(dp, eval_seasons)
    x <- dp[season %in% eval_seasons, .(game_id, kickoff, season, week, wk, y, p_anchor)]
    for (f in features) {
      p <- vvf_s3_refit(dp, paste0("perm_", f), weeks)
      x <- merge(x, p[, .(game_id, p_new = p)], by = "game_id", all.x = TRUE)
      setnames(x, "p_new", paste0("p_", f))
    }
    cols <- paste0("p_", features)
    sk <- vvf_s3_skill(x, cols, order = cols, ref = "p_anchor", B = B, seed = VVF_S3_SEED)
    sk[, feature := features]
    setcolorder(sk, "feature")
  }
  n <- vvf_s3_claims(sk)
  list(passed = n$claims == 0L, null = null, claims = n$claims, above = n$above, below = n$below,
       skill = sk[, .(feature, skill, skill_lo, skill_hi, dm_p_better_bh, verdict)])
}

#' Anchor copy: a candidate equal to the anchor scores exactly 0
vvf_control_anchor_copy <- function(d, eval_seasons, B = VVF_S3_B, seed = VVF_S3_SEED) {
  x <- d[season %in% eval_seasons & !is.na(y)]
  x[, p_copy := p_anchor]
  s <- vvf_s3_skill(x, "p_copy", order = "p_copy", ref = "p_anchor", B = B, seed = seed)
  list(passed = identical(s$skill, 0) && identical(c(s$skill_lo, s$skill_hi), c(0, 0)), skill = s$skill)
}

#' Reproducibility: run(out_dir) returns a result_sha256; two runs must agree
vvf_control_repro <- function(run) {
  a <- run(withr::local_tempdir())
  b <- run(withr::local_tempdir())
  list(passed = identical(a, b), sha = c(a, b))
}

#' One row per control; a failed gating control voids the run
vvf_s4_report <- function(controls, gating = names(controls)) {
  tab <- data.table(control = names(controls), passed = vapply(controls, function(x) isTRUE(x$passed), logical(1)))
  tab[, gates := control %in% gating]
  ok <- all(tab[gates == TRUE, passed])
  list(table = tab, all_passed = all(tab$passed), status = if (ok) "complete" else "void")
}

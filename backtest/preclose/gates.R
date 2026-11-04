# =============================================================================
# nfl_preclose_v1's gates (PROTOCOL.md "Gates") on one scored window. `x` has game_id,
# kickoff, season, wk, y (0/1, ties removed), p_open, p_close_venue, h_open, a_open,
# home_score, away_score, and one column per candidate (NA where it has no prediction:
# OA and LM start once 100 training rows exist). Each candidate is scored on its own
# rows; P2's BH runs across the three candidates' one-sided DM-HLN p.
# =============================================================================

PC_CANDIDATES <- c("PC-C2" = "p_pc2", "OA[E1]" = "p_oa", "LM[E1]" = "p_lm")
PC_TAU <- 0.03
PC_B <- 10000L
PC_SEED <- 20260929L
PC_ECE_SLACK <- 0.005

#' P1-P3, P5 and P7 for each candidate on its own rows, with the opener and the close's
#' own skill on the same rows
pc_score_window <- function(x, cands = PC_CANDIDATES, B = PC_B, seed = PC_SEED) {
  rows <- lapply(names(cands), function(nm) {
    col <- cands[[nm]]
    z <- x[is.finite(get(col)) & !is.na(y)]
    if (nrow(z) == 0L) return(data.table(candidate = nm, games = 0L))
    z[, p_close := p_close_venue]
    s <- bt_score_window(copy(z), c(col, "p_close"), "p_open", B = B, seed = seed)
    a <- s[[col]]; cl <- s[["p_close"]]; o <- s[["p_open"]]
    v <- bt_clv(copy(z), col, tau = PC_TAU, B = B, seed = seed)
    data.table(candidate = nm, games = a$n, weeks = a$weeks, brier = a$brier, brier_open = o$brier, logloss = a$logloss,
               skill = a$skill, skill_lo = a$skill_ci[1], skill_hi = a$skill_ci[2], dm_p_better = a$dm_p_better,
               slope = a$slope, slope_lo = a$slope_ci[1], slope_hi = a$slope_ci[2], ece = a$ece, ece_open = o$ece,
               close_skill = cl$skill,
               picks = v$n %||% 0L, mean_clv_bps = v$mean_clv_bps %||% NA_real_, clv_lo = if (is.null(v$clv_ci)) NA_real_ else v$clv_ci[1],
               clv_hi = if (is.null(v$clv_ci)) NA_real_ else v$clv_ci[2], roi = v$roi %||% NA_real_,
               roi_lo = if (is.null(v$roi_ci)) NA_real_ else v$roi_ci[1], roi_hi = if (is.null(v$roi_ci)) NA_real_ else v$roi_ci[2])
  })
  r <- rbindlist(rows, fill = TRUE)
  r[, dm_p_bh := stats::p.adjust(dm_p_better, "BH")]
  r[, `:=`(P1 = skill > 0 & skill_lo > 0, P2 = dm_p_bh < 0.05, P3 = slope_lo <= 1 & slope_hi >= 1 & ece <= ece_open + PC_ECE_SLACK,
           P7_void = skill > close_skill)]
  r[]
}

#' P4 for LM: the window's slope of the actual move on LM's predicted move (CI by
#' season-week), and movement skill 1 - sum((move_hat - move)^2) / sum(move^2)
pc_movement <- function(x) {
  z <- x[is.finite(move_hat) & is.finite(p_open) & is.finite(p_close_venue)]
  if (nrow(z) < 10L) return(data.table(games = nrow(z)))
  z[, move := bt_logit(bt_clip(p_close_venue)) - bt_logit(bt_clip(p_open))]
  f <- stats::lm(move ~ move_hat, data = z); V <- sandwich::vcovCL(f, cluster = z$wk, type = "HC1"); G <- uniqueN(z$wk)
  b <- unname(stats::coef(f)["move_hat"]); se <- sqrt(V["move_hat", "move_hat"])
  r <- data.table(games = nrow(z), clusters = G, slope = b, slope_lo = b - stats::qt(0.975, G - 1) * se, slope_hi = b + stats::qt(0.975, G - 1) * se,
                  movement_skill = 1 - sum((z$move_hat - z$move)^2) / sum(z$move^2))
  r[, P4 := slope > 0 & slope_lo > 0 & movement_skill > 0]
  r[]
}

#' A candidate is claimed on a window when it passes P1 and P2 there
pc_claims <- function(scored) scored[P1 %in% TRUE & P2 %in% TRUE, candidate]

# The final end-to-end check of one weekly run: the console log, the web bundle and the audit
# tables written by a single `Rscript run_week.R` (no arguments, so the week is resolved from the
# schedule). Prints PASS, FAIL or NOTE for each check and exits 1 on any FAIL.
#
# Usage: Rscript final_check.R <repo> <run log> <expected git sha> [<out dir>]
#   <repo>      the checkout run_week.R ran in (its bundles/ and artifacts/)
#   <run log>   the run's console output (stdout and stderr)
#   <out dir>   where the per-game table and the check results are written (default: the log's dir)
suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) >= 3)
repo <- args[1]
log_file <- args[2]
expect_sha <- args[3]
out_dir <- if (length(args) >= 4) args[4] else dirname(log_file)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

results <- data.table(id = character(), status = character(), detail = character())
check <- function(id, ok, detail, note = FALSE) {
  status <- if (note) "NOTE" else if (isTRUE(ok)) "PASS" else "FAIL"
  results <<- rbind(results, data.table(id = id, status = status, detail = detail))
  cat(sprintf("[%s] %s: %s\n", status, id, detail))
}
grab <- function(pattern) grep(pattern, run_log, value = TRUE, perl = TRUE)

# --- the console log --------------------------------------------------------------------------
run_log <- readLines(log_file, warn = FALSE, encoding = "UTF-8")
auto <- grab("^Auto-resolved \\d{4} week \\d+ ")
check("L1 week resolved from the schedule", length(auto) == 1, if (length(auto)) auto else "no Auto-resolved line")
target <- regmatches(auto, regexec("^Auto-resolved (\\d{4}) week (\\d+) \\((\\d+) games", auto))[[1]]
season <- as.integer(target[2]); week <- as.integer(target[3]); n_sched <- as.integer(target[4])

failed <- grab("ERROR DURING ANALYSIS|^Error|Execution halted")
check("L2 run finished without an error", length(failed) == 0, if (length(failed)) paste(failed, collapse = " | ") else "no error lines")

badge <- trimws(grab("^\\s*\\[.\\] (Injuries|Weather|Market|Calibration|Overall)[^:]*:"))
check("L3 data-quality badge", length(badge) > 0, paste(badge, collapse = " | "), note = TRUE)
inj <- grab("\\] Injuries: ")
check("L4 injuries loaded (not UNAVAILABLE)", length(inj) > 0 && !any(grepl("UNAVAILABLE", inj)), paste(trimws(inj), collapse = " | "))

neutral <- grab("Defense rankings unavailable|Defense rankings failed|Defense adjustments NEUTRAL|Defense adjustments skipped")
check("L5 defense rankings available to props (P13)", length(neutral) == 0,
      if (length(neutral)) sprintf("%d lines, first: %s", length(neutral), trimws(neutral[1])) else "no 'unavailable' or 'NEUTRAL' line")

qa <- grab("^\\s*QA: ")
check("L6 bundle QA", length(qa) == 1 && grepl("QA: passed", qa), if (length(qa)) trimws(qa) else "no QA line")

bundle_line <- grab("^\\s*Web bundle: ")
bundle <- sub("^\\s*Web bundle: ", "", bundle_line)
if (!nzchar(bundle[1] %||% "") || !dir.exists(bundle[1])) bundle <- file.path(repo, bundle)
check("L7 bundle written", length(bundle_line) == 1 && dir.exists(bundle[1]), if (length(bundle_line)) bundle[1] else "no Web bundle line")
bundle <- bundle[1]

# --- the bundle -------------------------------------------------------------------------------
rd <- function(name) fromJSON(file.path(bundle, paste0(name, ".json")), simplifyVector = TRUE)
man <- rd("manifest")
check("B1 manifest names the resolved week", identical(as.integer(man$season), season) && identical(as.integer(man$week), week),
      sprintf("cycle %s, season %s, week %s", man$cycle_id, man$season, man$week))
check("B2 manifest code state", identical(man$code_git_sha, expect_sha) && isFALSE(man$code_dirty),
      sprintf("code_git_sha %s, code_dirty %s", substr(man$code_git_sha, 1, 7), man$code_dirty))
sha_ok <- vapply(seq_len(nrow(man$files)), function(i) {
  identical(digest::digest(file = file.path(bundle, man$files$name[i]), algo = "sha256"), man$files$sha256[i])
}, logical(1))
check("B3 every file matches its manifest sha256", all(sha_ok), sprintf("%d of %d files", sum(sha_ok), length(sha_ok)))

games <- as.data.table(rd("games"))
sched <- as.data.table(nflreadr::load_schedules(seasons = season))[week == get("week", envir = globalenv())]
check("B4 every scheduled game is in the bundle", setequal(games$game_id, sched$game_id) && nrow(games) == n_sched,
      sprintf("%d in the bundle, %d on the schedule, resolver said %d", nrow(games), nrow(sched), n_sched))
games[, kickoff := as.POSIXct(kickoff_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")]
games[, kickoff_et := format(kickoff, "%a %Y-%m-%d %H:%M", tz = "America/New_York")]
sched_ko <- sched[, .(game_id, sched_et = paste(gameday, gametime))]
ko <- merge(games[, .(game_id, et = format(kickoff, "%Y-%m-%d %H:%M", tz = "America/New_York"))], sched_ko, by = "game_id")
check("B5 kickoffs match the schedule (ET)", all(ko$et == ko$sched_et), sprintf("%d of %d agree", sum(ko$et == ko$sched_et), nrow(ko)))

preds <- as.data.table(rd("game_predictions"))
c3 <- preds[candidate == "C3"]
c0 <- preds[candidate == "C0"]
check("B6 a simulator (C3) probability for every game, inside (0, 1)",
      setequal(c3$game_id, games$game_id) && all(c3$p_home_final > 0 & c3$p_home_final < 1),
      sprintf("%d C3 rows, range %.3f to %.3f", nrow(c3), min(c3$p_home_final), max(c3$p_home_final)))
# A game without a line at run time (nflverse posts lines during the week, so a later schedule
# load can differ) has no C0 price, never a substitute, and the run says so twice: the warning
# names it and the badge counts it (Market PARTIAL)
no_line <- sort(c0[is.na(p_home_mkt_novig), game_id])
warned <- grab("No market line for \\d+ game")
warned_ids <- if (length(warned)) sort(regmatches(warned, gregexpr("\\d{4}_\\d{2}_[A-Z]+_[A-Z]+", warned))[[1]]) else character()
badge_n <- suppressWarnings(as.integer(sub("^\\s*(\\d+) game\\(s\\) without market odds.*$", "\\1", grab("game\\(s\\) without market odds"))))
check("B7 a market (C0) probability for every game with a line, inside (0, 1)",
      setequal(c0$game_id, games$game_id) && all(c0$p_home_mkt_novig > 0 & c0$p_home_mkt_novig < 1, na.rm = TRUE),
      sprintf("%d C0 rows, %d priced; without a line at run time: %s", nrow(c0), sum(!is.na(c0$p_home_mkt_novig)),
              if (length(no_line)) paste(no_line, collapse = ", ") else "none"))
check("B7b every game without a line is named in the warning and counted in the badge",
      identical(warned_ids, no_line) && identical(if (length(badge_n)) badge_n[1] else 0L, length(no_line)),
      if (length(warned)) sprintf("warning names %s; badge counts %s", paste(warned_ids, collapse = ", "), badge_n[1]) else "no warning, no count (every game has a line)")

dists <- as.data.table(rd("score_distributions"))
mass <- dists[, .(mass = sum(bins[[1]]$p)), by = .(game_id, kind)]
check("B8 margin and total distributions for every game, each with the stated mass",
      nrow(mass) == 2 * nrow(games) && all(abs(mass$mass - man$config$distribution_mass) < 0.0015),
      sprintf("%d distributions, mass %.4f to %.4f (stated %.3f)", nrow(mass), min(mass$mass), max(mass$mass), man$config$distribution_mass))

src <- as.data.table(rd("source_status"))
check("B9 source status", all(src$status == "ok"), paste(sprintf("%s=%s", src$source, src$status), collapse = ", "),
      note = !all(src$status == "ok"))

# --- the audit tables -------------------------------------------------------------------------
bg <- fread(file.path(repo, "artifacts", "baseline_games.csv"))
bg <- bg[season == get("season", envir = globalenv()) & week == get("week", envir = globalenv())]
check("A1 one baseline_games row per game", setequal(bg$game_id, games$game_id) && nrow(bg) == nrow(games),
      sprintf("%d rows", nrow(bg)))
pair_ok <- with(bg, all(abs(blend_home_prob + blend_away_prob - 1) < 1e-9 & abs(market_home_prob + market_away_prob - 1) < 1e-9))
check("A2 each two-way pair sums to 1 (blend and market)", pair_ok,
      sprintf("max |sum - 1| blend %.1e, market %.1e", max(abs(bg$blend_home_prob + bg$blend_away_prob - 1)),
              max(abs(bg$market_home_prob + bg$market_away_prob - 1))))
bundle_c3 <- merge(c3[, .(game_id, p_c3 = p_home_final)], bg[, .(game_id, blend_home_prob, blend_home_prob_shrunk)], by = "game_id")
check("A3 the bundle's C3 is the audit table's shrunk blend (unshrunk without a line)", all(abs(bundle_c3$p_c3 - bundle_c3$blend_home_prob_shrunk) < 1e-9),
      sprintf("max difference %.1e", max(abs(bundle_c3$p_c3 - bundle_c3$blend_home_prob_shrunk))))
nm <- bg[game_id %in% no_line]
check("A5 no market price, source or bet for a game without a line",
      all(is.na(nm$market_home_ml) & is.na(nm$market_home_prob) & nm$prob_source == "none" & nm$blend_recommendation == "No Play"),
      if (nrow(nm)) paste(sprintf("%s: ml %s, source %s, %s", nm$game_id, nm$market_home_ml, nm$prob_source, nm$blend_recommendation), collapse = "; ") else "every game has a line")

bg[, margin_gap := blend_median_margin - market_implied_margin]
bg[, total_gap := blend_total_median - market_total]
big <- bg[abs(margin_gap) > 10 | abs(total_gap) > 10]
check("A4 margin and total gaps to the market above 10 points", TRUE,
      if (nrow(big)) paste(sprintf("%s margin %+.1f total %+.1f", big$game_id, big$margin_gap, big$total_gap), collapse = "; ") else "none",
      note = TRUE)

props_file <- file.path(repo, "artifacts", "baseline_props.csv")
if (file.exists(props_file)) {
  bp <- fread(props_file)
  per_game <- bp[, .N, by = game_id]
  missing <- setdiff(games$game_id, per_game$game_id)
  check("P1 props rows for every game", length(missing) == 0,
        sprintf("%d rows over %d games%s", nrow(bp), uniqueN(bp$game_id), if (length(missing)) paste0("; none for ", paste(missing, collapse = ", ")) else ""))
  check("P2 prop types", TRUE, paste(sprintf("%s=%d", names(table(bp$prop_type)), as.integer(table(bp$prop_type))), collapse = ", "), note = TRUE)
  probs <- bp[, abs(rowSums(cbind(p_over, p_under, fifelse(is.na(p_push), 0, p_push))) - 1)]
  # each probability is written with 4 decimals, so three of them can be off 1 by 1.5e-4
  check("P3 over + under + push = 1 on every row (4-decimal rounding)", all(probs <= 1.5e-4 + 1e-12, na.rm = TRUE) && !anyNA(probs),
        sprintf("max |sum - 1| %.1e", max(probs, na.rm = TRUE)))
  stake <- bp[["Final Stake (%)"]]
  bet <- !grepl("^PASS", toupper(bp$recommendation))
  check("P4 a stake only on a recommended bet, and every recommended bet staked", all((stake > 0) == bet, na.rm = TRUE),
        sprintf("%d recommended, %d staked, %d disagree", sum(bet), sum(stake > 0, na.rm = TRUE), sum((stake > 0) != bet, na.rm = TRUE)))
} else {
  check("P1 props rows for every game", FALSE, "no artifacts/baseline_props.csv")
}

# --- the per-game table the app should show -----------------------------------------------------
tab <- merge(games[, .(game_id, matchup = paste(away_team_id, "at", home_team_id), kickoff_et, roof)],
             c0[, .(game_id, market_home = round(p_home_mkt_novig, 4))], by = "game_id")
tab <- merge(tab, c3[, .(game_id, sim_home = round(p_home_final, 4))], by = "game_id")
tab <- merge(tab, bg[, .(game_id, spread = market_home_spread, market_margin = market_implied_margin,
                         sim_margin = blend_median_margin, market_total, sim_total = blend_total_median)], by = "game_id")
setorder(tab, kickoff_et, game_id)
fwrite(tab, file.path(out_dir, "games_week.csv"))
fwrite(results, file.path(out_dir, "final_check_results.csv"))
cat("\n"); print(tab, row.names = FALSE)
cat(sprintf("\n%d PASS, %d FAIL, %d NOTE\n", sum(results$status == "PASS"), sum(results$status == "FAIL"), sum(results$status == "NOTE")))
quit(status = if (any(results$status == "FAIL")) 1L else 0L)

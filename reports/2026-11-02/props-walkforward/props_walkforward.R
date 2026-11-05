# Exploratory (the owner, 2026-11-02: 2025 as history unlocks "a props test over weeks 2-8"): do the props module's base
# projections, rebuilt point in time for 2026 weeks 2-8, add information to Kalshi's close? Each week w uses
# load_player_projections(2026, w) (sports/nfl/props/data_sources.R, with #230's week filter): every player's equal-weight
# mean over 2024, 2025 (history) and 2026 before week w. Anytime touchdowns are a Poisson on the scoring-TD rate (the
# full module simulates them with the game; its defense and game-context adjustments are not applied here). Each week
# is scored by props_frame.R's module_props(), the code of nfl_props_v1's P5 and P6, and the weeks are stacked for one
# pooled information test and one timing test. Kalshi weeks 2-7 were seen by Family G and week 7 by Family M, so this is
# exploratory; P5 and P6's confirmatory test is weeks 9-18 with the frozen module. Run from the repository root:
#   Rscript reports/2026-11-02/props-walkforward/props_walkforward.R <out_dir> --settled=<csv.gz>,... --candles=<csv.gz>,...
suppressPackageStartupMessages({ library(data.table); library(dplyr) })
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) { h <- grep(sprintf("^--%s=", name), args, value = TRUE)
  if (length(h)) Filter(nzchar, strsplit(sub(sprintf("^--%s=", name), "", h[1]), ",", fixed = TRUE)[[1]]) else character(0) }
out <- grep("^--", args, value = TRUE, invert = TRUE)[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
source(file.path("reports", "2026-10-29", "hypotheses", "props_frame.R"))
pe <- new.env(); sys.source(file.path("sports", "nfl", "props", "data_sources.R"), envir = pe)
options(timeout = 900); set.seed(20261103)
read_gz <- function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE))
st <- unique(rbindlist(lapply(opt("settled"), read_gz), fill = TRUE), by = "ticker")
cn <- unique(rbindlist(lapply(opt("candles"), read_gz), fill = TRUE), by = "ticker")
stopifnot(!any(substr(st$close_time, 1, 4) == "2025"))
sched <- props_schedule()
ev <- props_event_games(st$event_ticker, sched)
WEEKS <- 2:8

# the module's base projections for week w, in baseline_props.csv's layout
mod_week <- function(w) {
  p <- as.data.table(pe$load_player_projections(season = 2026L, week = w, min_games = 3))
  p <- p[!is.na(recent_team)]
  rbind(p[position == "QB", .(player = player_name, team = recent_team, prop_type = "passing_yards", projection = avg_passing_yards, p_over = NA_real_)],
        p[position %in% c("QB", "RB"), .(player = player_name, team = recent_team, prop_type = "rushing_yards", projection = avg_rushing_yards, p_over = NA_real_)],
        p[position %in% c("WR", "TE", "RB"), .(player = player_name, team = recent_team, prop_type = "receiving_yards", projection = avg_receiving_yards, p_over = NA_real_)],
        p[position %in% c("WR", "TE", "RB"), .(player = player_name, team = recent_team, prop_type = "receptions", projection = avg_receptions, p_over = NA_real_)],
        p[position %in% c("WR", "TE", "RB", "QB"), .(player = player_name, team = recent_team, prop_type = "anytime_td", projection = avg_scoring_tds,
                                                     p_over = 1 - exp(-pmax(avg_scoring_tds, 0)))])[is.finite(projection)]
}
# the week's Kalshi contracts at the close, as score_week.R builds them
k_week <- function(w) {
  k <- merge(merge(st[, .(ticker, series, event_ticker, label, result_k = result, yk = settlement_value)], ev, by = "event_ticker")[week == w],
             cn[, .(ticker, bid = bid_close, ask = ask_close)], by = "ticker")
  k <- merge(k, sched[, .(game_id, home_team, away_team)], by = "game_id")
  k[result_k %in% c("yes", "no") & is.finite(bid) & is.finite(ask) & ask > 0 & ask >= bid & ask - bid <= MAX_SPREAD][, mid := (bid + ask) / 2][]
}
weekly <- list(); stack <- list()
for (w in WEEKS) {
  r <- tryCatch(module_props(k_week(w), st, ev, w, mod_week(w), cn), error = function(e) { message(sprintf("week %d: %s", w, conditionMessage(e))); NULL })
  if (is.null(r)) next
  weekly[[length(weekly) + 1L]] <- cbind(data.table(week = w), r$tests)
  stack[[length(stack) + 1L]] <- r$pr[, .(ticker, game_id, stat, kk, bid, ask, mid, yk, p_mod, p_g)]
}
weekly <- rbindlist(weekly); pc <- rbindlist(stack)
pooled <- rbind(cbind(forecast = "base projections (module, point in time)", info_test(pc, "yk", "p_mod", "mid")),
                cbind(forecast = "Family G projection", info_test(pc[is.finite(p_g)], "yk", "p_g", "mid")))
pooled[, `:=`(brier_kalshi = c(mean((pc$mid - pc$yk)^2), mean((pc[is.finite(p_g)]$mid - pc[is.finite(p_g)]$yk)^2)),
              brier_forecast = c(mean((pc$p_mod - pc$yk)^2), mean((pc[is.finite(p_g)]$p_g - pc[is.finite(p_g)]$yk)^2)))]
# the timing test on the stack: does the projection predict the move from 24 h before kickoff to the close?
tmv <- merge(pc, cn[, .(ticker, bid24 = bid_24h, ask24 = ask_24h)], by = "ticker")
tmv <- tmv[is.finite(bid24) & is.finite(ask24) & ask24 > 0 & ask24 >= bid24 & ask24 - bid24 <= MAX_SPREAD][, mid24 := (bid24 + ask24) / 2][mid24 > 0 & mid24 < 1]
tmv[, `:=`(move = lg(mid) - lg(mid24), lean = lg(p_mod) - lg(mid24))]
f <- stats::lm(move ~ lean, data = tmv); V <- sandwich::vcovCL(f, cluster = tmv$game_id, type = "HC1"); G <- uniqueN(tmv$game_id)
b <- unname(stats::coef(f)["lean"]); se <- sqrt(V["lean", "lean"])
timing <- data.table(test = "the base projection predicts the move from 24 h before kickoff to the close (one-sided > 0)", contracts = nrow(tmv), games = G,
                     estimate = b, lo = b - stats::qt(0.975, G - 1) * se, hi = b + stats::qt(0.975, G - 1) * se, p_one_sided = stats::pt(-b / se, G - 1))
s4 <- function(x) x[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 4) else v)]
fwrite(s4(weekly), file.path(out, "props_walkforward_weekly.csv"), eol = "\n"); fwrite(s4(pooled), file.path(out, "props_walkforward_pooled.csv"), eol = "\n")
fwrite(s4(timing), file.path(out, "props_walkforward_timing.csv"), eol = "\n")
options(width = 200); print(s4(weekly)); print(s4(pooled)); print(s4(timing))

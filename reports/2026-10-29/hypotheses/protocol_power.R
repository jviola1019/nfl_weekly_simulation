# The power each protocol hypothesis would have on fresh 2026 games (weeks 8-18 only, 11 weeks), at the effect seen in
# weeks 1-7 (or, for the market protocol, in the post-study seasons). The standard error scales with the square root of
# the games: SE_new = SE_seen x sqrt(games_seen / games_new); games_new = 11 x the games a week each series covered in
# weeks 6-7; power of a one-sided 5% test = pnorm(effect / SE_new - 1.645). Run from the repository root:
#   Rscript reports/2026-10-29/hypotheses/protocol_power.R <out_dir> --settled=<a>,<b>
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name) strsplit(sub(sprintf("^--%s=", name), "", grep(sprintf("^--%s=", name), args, value = TRUE)), ",", fixed = TRUE)[[1]]
o <- grep("^--", args, value = TRUE, invert = TRUE)[1]
source(file.path("reports", "2026-10-28", "feasibility", "props_common.R"))
options(timeout = 600)
st <- unique(rbindlist(lapply(opt("settled"), function(f) as.data.table(utils::read.csv(gzfile(f), stringsAsFactors = FALSE)))), by = "ticker")
sched <- props_schedule()
gw <- unique(merge(st[, .(series, event_ticker)], props_event_games(st$event_ticker, sched), by = "event_ticker")[, .(series, game_id, week)])
per_week <- function(s) gw[series %in% s & week %in% 6:7, uniqueN(game_id) / 2]
rd <- function(...) fread(file.path(o, ...))
cs <- rd("consistency", "consistency_tests.csv"); bh <- rd("behaviour", "behaviour_tests.csv"); kn <- rd("key", "key_numbers.csv")
cl <- fread(file.path("reports", "2026-10-28", "feasibility", "props", "close", "close_calibration.csv"))
ca <- rd("classic", "classic_anomalies.csv")[period == "after the study (test)"]
z <- stats::qnorm(0.95)
se_from_p2 <- function(est, p, df) abs(est) / stats::qt(1 - p / 2, df)          # a two-sided p
se_from_p1 <- function(est, p, df) abs(est) / stats::qt(1 - p, df)              # a one-sided p
rows <- list(
  data.table(protocol = "props", id = "P-A3", hypothesis = "protected contracts are underpriced against their twins (premium mispriced)",
             effect = cs[id == "A3", estimate], se = se_from_p2(cs[id == "A3", estimate], cs[id == "A3", p], cs[id == "A3", games] - 1),
             games_seen = cs[id == "A3", games], games_new = 11 * per_week(c("KXNFLRECPROT", "KXNFLRECYDSPROT", "KXNFLRSHYDSPROT", "KXNFLTDPROT"))),
  data.table(protocol = "props", id = "P-A5", hypothesis = "the binary ladder's mean predicts the stat beyond the scalar's",
             effect = cs[id == "A5", estimate], se = se_from_p2(cs[id == "A5", estimate], cs[id == "A5", p], cs[id == "A5", games] - 1),
             games_seen = cs[id == "A5", games], games_new = 11 * per_week(c("KXNFLLADDERREC", "KXNFLLADDERRECYDS", "KXNFLLADDERRSHYDS"))),
  data.table(protocol = "props", id = "P-B1s", hypothesis = "position-group teammates of an absent player are underpriced",
             effect = bh[id == "B1s", estimate], se = (bh[id == "B1s", hi] - bh[id == "B1s", lo]) / (2 * stats::qt(0.975, bh[id == "B1s", games] - 1)),
             games_seen = bh[id == "B1s", games], games_new = 11 * per_week(names(LADDERS))),
  data.table(protocol = "props", id = "P-INT", hypothesis = "the interception ladder is compressed (slope > 1)",
             effect = cl[series == "KXNFLPASSINT", slope] - 1, se = (cl[series == "KXNFLPASSINT", slope_hi] - cl[series == "KXNFLPASSINT", slope_lo]) / (2 * stats::qt(0.975, cl[series == "KXNFLPASSINT", games] - 1)),
             games_seen = cl[series == "KXNFLPASSINT", games], games_new = 11 * per_week("KXNFLPASSINT")),
  data.table(protocol = "market", id = "M-A1", hypothesis = "the key-number shape on Kalshi's median beats its spread ladder (exploratory in weeks 1-7)",
             effect = kn[series == "KXNFLSPREAD" & grepl("shape", model), skill], se = se_from_p1(kn[series == "KXNFLSPREAD" & grepl("shape", model), skill], kn[series == "KXNFLSPREAD" & grepl("shape", model), p_model_better], kn[series == "KXNFLSPREAD" & grepl("shape", model), games] - 1),
             games_seen = kn[series == "KXNFLSPREAD" & grepl("shape", model), games], games_new = 11 * per_week("KXNFLSPREAD")),
  data.table(protocol = "market", id = "M-E3", hypothesis = "unders, outdoors, wind >= 15 mph (rate above 0.5)",
             effect = ca[id == "E3", rate] - 0.5, se = se_from_p1(ca[id == "E3", rate] - 0.5, ca[id == "E3", p_rate], ca[id == "E3", clusters] - 1),
             games_seen = ca[id == "E3", bets], games_new = round(ca[id == "E3", bets] / 20 * 11 / 18)),
  data.table(protocol = "market", id = "M-E4", hypothesis = "the cold home team against a warm visitor (rate above 0.5)",
             effect = ca[id == "E4", rate] - 0.5, se = se_from_p1(ca[id == "E4", rate] - 0.5, ca[id == "E4", p_rate], ca[id == "E4", clusters] - 1),
             games_seen = ca[id == "E4", bets], games_new = round(ca[id == "E4", bets] / 17 * 11 / 18)))
pw <- rbindlist(rows)
pw[, se_new := se * sqrt(games_seen / pmax(games_new, 1))]
pw[, power := stats::pnorm(abs(effect) / se_new - z)]
# the games each would need for 80% power at the effect seen
pw[, games_for_80 := ceiling(games_seen * (se * (z + stats::qnorm(0.8)) / abs(effect))^2)]
fwrite(signif_dt(pw, 4), file.path(o, "protocol_power.csv"))
options(width = 220)
print(signif_dt(pw, 3))
cat("\nE3 and E4: games_seen and games_new count bets; their fresh games are the windy or cold 2026 weeks 8-18 (about 11 of 18 weeks of a season's share).\n")

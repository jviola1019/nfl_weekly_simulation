# Does nflverse's rest-day definition change any S1 verdict? nflverse's home_rest and away_rest follow the original
# schedule for late-season games moved to Saturday and count the cancelled 2022 BUF-CIN game (dates_audit.R: 34
# team-games). This rebuilds the five rest features from the days actually rested (each team's previous played
# game) and reruns S1 on the close-anchored Tune table beside the committed reproduction. Run from the repository
# root:  Rscript reports/2026-10-28/feasibility/rest_sensitivity.R <out_dir>
suppressPackageStartupMessages(library(data.table))
out <- commandArgs(trailingOnly = TRUE)[1]
e <- environment()
for (f in c("common.R", "candidates/market.R", "candidates/elo.R", "candidates/epa_glm.R", "blends.R", "calibrators.R",
            "metrics.R", "controls.R")) sys.source(file.path("backtest", f), envir = e)
for (f in c("common.R", "features.R", "registry.R", "provenance.R", "s1_screen.R", "s2_structure.R", "reproduce_v2.R",
            "input_schema.R")) sys.source(file.path("backtest", "vvf", f), envir = e)
x <- vvf_v2_table()$d
g <- fread(file.path("backtest", "data", "games.csv"))
played <- g[!is.na(home_score)]
long <- rbind(played[, .(game_id, season, team = home_franchise, side = "home", day = as.Date(gameday))],
              played[, .(game_id, season, team = away_franchise, side = "away", day = as.Date(gameday))])
setorder(long, team, day)
long[, rest_played := as.integer(day - shift(day)), by = .(team, season)]
w <- dcast(long, game_id ~ side, value.var = "rest_played")
setnames(w, c("away", "home"), c("away_rest_played", "home_rest_played"))
x <- merge(x, w, by = "game_id", all.x = TRUE)
setattr(x, "vvf_anchor", "close")   # merge drops the attribute
x[, `:=`(home_rest_played = fifelse(is.na(home_rest_played), home_rest, home_rest_played),
         away_rest_played = fifelse(is.na(away_rest_played), away_rest, away_rest_played))]
changed <- x[home_rest_played != home_rest | away_rest_played != away_rest, .(game_id, home_rest, home_rest_played, away_rest, away_rest_played)]
feats <- c("rest_diff", "home_short", "away_short", "home_bye", "away_bye")
base <- vvf_s1_screen(x, feats, "close")$features[, .(family, feature, q_nflverse = q_bh, p_nflverse = p, verdict_nflverse = verdict)]
y <- copy(x)
y[, `:=`(rest_diff = home_rest_played - away_rest_played, home_short = as.integer(home_rest_played <= 6),
         away_short = as.integer(away_rest_played <= 6), home_bye = as.integer(home_rest_played >= 13), away_bye = as.integer(away_rest_played >= 13))]
setattr(y, "vvf_anchor", "close")
fix <- vvf_s1_screen(y, feats, "close")$features[, .(family, feature, q_played = q_bh, p_played = p, verdict_played = verdict)]
m <- merge(base, fix, by = c("family", "feature"))
m[, verdict_changed := substr(verdict_nflverse, 1, 6) != substr(verdict_played, 1, 6)]
fwrite(changed, file.path(out, "rest_changed_games.csv"))
fwrite(m[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 5) else v)], file.path(out, "rest_sensitivity.csv"))
cat(sprintf("Tune games whose rest differs: %d of %d\n", nrow(changed), nrow(x)))
print(m[, .(family, feature, p_nflverse = signif(p_nflverse, 3), p_played = signif(p_played, 3), q_nflverse = signif(q_nflverse, 3),
            q_played = signif(q_played, 3), verdict_changed)])
cat(sprintf("verdicts changed: %d of %d (the q-values here are BH over these five features only)\n", sum(m$verdict_changed), nrow(m)))

# Family E of PLAN.md: published NFL line anomalies, each tested on the seasons after its study's sample (regular
# season, nflverse closing spreads, totals and odds; 1999-2024 and 2026 weeks 1-7; 2025 is never loaded into the
# analysis). Pushes are excluded. The rate's interval resamples season-weeks; the return uses nflverse's recorded odds,
# or -110 where there are none. BH over E1-E10 on the one-sided p of the predicted side's rate (E10: of the return).
# Run from the repository root:  Rscript reports/2026-10-29/hypotheses/classic_anomalies.R <out_dir>
suppressPackageStartupMessages(library(data.table))
out <- commandArgs(trailingOnly = TRUE)[1]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
options(timeout = 600)
s <- as.data.table(nflreadr::load_schedules(c(1999:2024, 2026)))
stopifnot(!any(s$season == 2025))   # the seal
s <- s[game_type == "REG" & !is.na(result)]
s[, `:=`(sw = paste(season, week), total = home_score + away_score)]

# the predicted side of each bet: home or away against the spread, over or under, away on the moneyline
s[, `:=`(home_cover = fifelse(result > spread_line, 1L, fifelse(result < spread_line, 0L, NA_integer_)),
         under = fifelse(total < total_line, 1L, fifelse(total > total_line, 0L, NA_integer_)))]
outdoor <- s$roof %in% c("outdoors", "open")
# a warm visitor: its home games that season were mostly under a roof, or its outdoor home games averaged 60 F or more
home_climate <- s[, .(indoor = mean(roof %in% c("dome", "closed")), temp = mean(temp[roof %in% c("outdoors", "open")], na.rm = TRUE)), by = .(season, team = home_team)]
s <- merge(s, home_climate[, .(season, away_team = team, away_indoor = indoor, away_home_temp = temp)], by = c("season", "away_team"), all.x = TRUE)
s[, warm_visitor := away_indoor >= 0.5 | (!is.na(away_home_temp) & away_home_temp >= 60)]
# the home team's previous game in the season, home or away: did it cover?
long <- rbind(s[, .(season, week, gameday, team = home_team, covered = home_cover)], s[, .(season, week, gameday, team = away_team, covered = 1L - home_cover)])
setorder(long, team, season, gameday)
long[, prev_covered := shift(covered), by = .(team, season)]
s <- merge(s, long[, .(season, week, home_team = team, home_prev_covered = prev_covered)], by = c("season", "week", "home_team"), all.x = TRUE)
s[, `:=`(tl_lo = stats::quantile(total_line, 0.1, na.rm = TRUE), tl_hi = stats::quantile(total_line, 0.9, na.rm = TRUE)), by = season]
nv <- function(h, a) { ih <- ifelse(h < 0, -h / (-h + 100), 100 / (h + 100)); ia <- ifelse(a < 0, -a / (-a + 100), 100 / (a + 100)); ih / (ih + ia) }
s[, p_home := nv(home_moneyline, away_moneyline)]
profit <- function(win, odds) { o <- fifelse(is.na(odds), -110, odds); fifelse(win == 1L, fifelse(o < 0, 100 / -o, o / 100), -1) }

H <- list(
  E1 = list(study = "Levitt (2004), 1980-2001", bet = "home underdog ATS", sel = quote(spread_line < 0), side = "home", oos = 2002:2024, ins = 1999:2001),
  E2 = list(study = "Borghesi (2007), late season", bet = "home underdog ATS, weeks 13+", sel = quote(spread_line < 0 & week >= 13), side = "home", oos = 2007:2024, ins = 1999:2006),
  E3 = list(study = "Borghesi (2008), 1984-2004", bet = "under, outdoors, wind >= 15 mph", sel = quote(outdoor & !is.na(wind) & wind >= 15), side = "under", oos = 2005:2024, ins = 1999:2004),
  E4 = list(study = "Borghesi (2007), home weather", bet = "home ATS, outdoors, <= 32 F, warm visitor", sel = quote(outdoor & !is.na(temp) & temp <= 32 & warm_visitor), side = "home", oos = 2008:2024, ins = 1999:2007),
  E5 = list(study = "Shank (2019), 2003-2016", bet = "away ATS in division games", sel = quote(div_game == 1), side = "away", oos = 2017:2024, ins = 2003:2016),
  E6 = list(study = "Shank (2019), 2003-2016", bet = "under in division games", sel = quote(div_game == 1), side = "under", oos = 2017:2024, ins = 2003:2016),
  E7 = list(study = "Shank (2018)", bet = "home underdog of 7+ ATS", sel = quote(spread_line <= -7), side = "home", oos = 2018:2024, ins = 1999:2017),
  E8 = list(study = "Shank (2018)", bet = "over, total in the season's bottom or top 10%", sel = quote(total_line <= tl_lo | total_line >= tl_hi), side = "over", oos = 2018:2024, ins = 1999:2017),
  E9 = list(study = "Shank (2018)", bet = "home ATS after the home team failed to cover", sel = quote(home_prev_covered == 0), side = "home", oos = 2018:2024, ins = 1999:2017),
  E10 = list(study = "Costa (2025), 2020-2024", bet = "away moneyline, home no-vig 0.3-0.7", sel = quote(p_home >= 0.3 & p_home <= 0.7), side = "away_ml", oos = 2026L, ins = 2020:2024))

score <- function(d, side) {
  d <- copy(d)
  d[, `:=`(win = switch(side, home = home_cover, away = 1L - home_cover, under = under, over = 1L - under, away_ml = as.integer(result < 0)),
           odds = switch(side, home = home_spread_odds, away = away_spread_odds, under = under_odds, over = over_odds, away_ml = away_moneyline))]
  d <- d[!is.na(win) & !(side == "away_ml" & result == 0)]
  d[, pnl := profit(win, odds)]
  if (nrow(d) < 10) return(data.table(bets = nrow(d)))
  cl <- d[, .(w = sum(win), n = .N, p = sum(pnl)), by = sw]
  rate <- sum(cl$w) / sum(cl$n); roi <- sum(cl$p) / sum(cl$n)
  # cluster-robust SEs of the ratio means (season-week clusters)
  G <- nrow(cl); se_r <- sqrt(G / (G - 1) * sum((cl$w - rate * cl$n)^2)) / sum(cl$n); se_p <- sqrt(G / (G - 1) * sum((cl$p - roi * cl$n)^2)) / sum(cl$n)
  set.seed(20261029)
  bt <- replicate(2000, { i <- sample.int(G, replace = TRUE); c(sum(cl$w[i]) / sum(cl$n[i]), sum(cl$p[i]) / sum(cl$n[i])) })
  data.table(bets = nrow(d), clusters = G, rate = rate, rate_lo = stats::quantile(bt[1, ], 0.025), rate_hi = stats::quantile(bt[1, ], 0.975),
             p_rate = stats::pnorm(-(rate - 0.5) / se_r), roi = roi, roi_lo = stats::quantile(bt[2, ], 0.025), roi_hi = stats::quantile(bt[2, ], 0.975),
             p_roi = stats::pnorm(-roi / se_p), odds_recorded = mean(!is.na(d$odds)))
}
res <- rbindlist(lapply(names(H), function(id) {
  h <- H[[id]]
  sel <- s[eval(h$sel, s)]   # h$sel is one of the quote()d filters written above, never outside input
  rbind(cbind(data.table(id = id, study = h$study, bet = h$bet, period = "after the study (test)", seasons = paste(range(h$oos), collapse = "-")), score(sel[season %in% h$oos], h$side)),
        cbind(data.table(id = id, study = h$study, bet = h$bet, period = "the study's years (replication)", seasons = paste(range(h$ins), collapse = "-")), score(sel[season %in% h$ins], h$side)),
        cbind(data.table(id = id, study = h$study, bet = h$bet, period = "2026 weeks 1-7", seasons = "2026"), score(sel[season == 2026], h$side)), fill = TRUE)
}), fill = TRUE)
test <- res$period == "after the study (test)"
res[, q_bh := NA_real_]
res[test, q_bh := stats::p.adjust(fifelse(id == "E10", p_roi, p_rate), "BH")]
fwrite(res[, lapply(.SD, function(v) if (is.numeric(v)) signif(v, 5) else v)], file.path(out, "classic_anomalies.csv"))
options(width = 220)
print(res[, .(id, period, seasons, bets, rate = round(rate, 4), rate_lo = round(rate_lo, 4), rate_hi = round(rate_hi, 4), p_rate = signif(p_rate, 2),
              roi = round(roi, 4), roi_lo = round(roi_lo, 4), roi_hi = round(roi_hi, 4), q_bh = signif(q_bh, 2), odds = round(odds_recorded, 2))], nrows = 100)
cat(sprintf("\ngames 1999-2024 and 2026: %d; seasons %s; the break-even rate at -110 is 0.5238\n", nrow(s), paste(range(s$season), collapse = "-")))

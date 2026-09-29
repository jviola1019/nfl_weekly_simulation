# Empirical open->close movement of NFL moneylines (ESPN core, keyless) and the
# implied sample size for the shootout's CLV "betting value" gate.
setwd("C:/Users/jviol/Downloads/nfl")
suppressPackageStartupMessages({ library(dplyr) })
source("R/capture_raw.R")
cfg <- new.env(); sys.source("config.R", envir = cfg)
out_dir <- "reports/2026-09-29/clv-power"
dir.create(out_dir, showWarnings = FALSE)

am_to_p <- function(a) { a <- suppressWarnings(as.numeric(sub("^\\+", "", a))); ifelse(a < 0, -a / (-a + 100), 100 / (a + 100)) }
get_ml <- function(side, when) { x <- side[[when]]$moneyLine$american; if (is.null(x)) NA_character_ else as.character(x) }

sched <- nflreadr::load_schedules(2024:2025) %>% filter(!is.na(espn), !is.na(home_score))
rows <- list(); fails <- 0L
for (i in seq_len(nrow(sched))) {
  id <- sched$espn[i]
  res <- capture_http_get(espn_game_odds_url(id), cfg$CAPTURE_USER_AGENT, cfg$CAPTURE_TIMEOUT_SEC,
                          cfg$CAPTURE_MAX_TRIES, cfg$CAPTURE_MIN_INTERVAL_SEC)
  if (is.null(res$body)) { fails <- fails + 1L; next }
  items <- jsonlite::fromJSON(rawToChar(res$body), simplifyVector = FALSE)$items
  for (it in items) {
    h <- it$homeTeamOdds; a <- it$awayTeamOdds
    if (is.null(h) || is.null(a)) next
    rows[[length(rows) + 1]] <- data.frame(
      game_id = sched$game_id[i], season = sched$season[i], week = sched$week[i],
      provider = it$provider$id %||% NA, provider_name = it$provider$name %||% NA,
      h_open = get_ml(h, "open"), a_open = get_ml(a, "open"),
      h_close = get_ml(h, "close"), a_close = get_ml(a, "close"),
      home_win = as.integer(sched$home_score[i] > sched$away_score[i]),
      stringsAsFactors = FALSE)
  }
  if (i %% 50 == 0) message(i, "/", nrow(sched), " games, fails=", fails)
}
d <- bind_rows(rows) %>%
  mutate(p_open = am_to_p(h_open) / (am_to_p(h_open) + am_to_p(a_open)),
         p_close = am_to_p(h_close) / (am_to_p(h_close) + am_to_p(a_close))) %>%
  filter(is.finite(p_open), is.finite(p_close))
write.csv(d, file.path(out_dir, "espn_open_close_2024_2025.csv"), row.names = FALSE)

# CLV of a home bet at open = 10000 * (p_close - p_open); an away bet is the negative.
# A random-side bettor has mean ~0; the SD is the per-bet noise any real edge must beat.
m <- d %>% group_by(provider_name) %>%
  summarise(games = n_distinct(game_id), sd_bps = sd(10000 * (p_close - p_open)),
            mad_bps = mean(abs(10000 * (p_close - p_open))),
            share_moved = mean(abs(p_close - p_open) > 0.005), .groups = "drop") %>% arrange(desc(games))
print(as.data.frame(m), digits = 4)

main <- d %>% filter(provider_name == m$provider_name[1])
sigma <- sd(10000 * (main$p_close - main$p_open))
# Week clustering: design effect from the intra-week correlation of CLV
wk <- main %>% mutate(clv = 10000 * (p_close - p_open)) %>% group_by(season, week) %>% summarise(mean_clv = mean(clv), n = n(), .groups = "drop")
m_bar <- mean(wk$n)
icc <- max(0, (var(wk$mean_clv) - sigma^2 / m_bar) / sigma^2)
deff <- 1 + (m_bar - 1) * icc
cat(sprintf("\nMain provider: %s | games=%d | sigma=%.0f bps | week ICC=%.3f | design effect=%.2f | fails=%d\n",
            m$provider_name[1], nrow(main), sigma, icc, deff, fails))
# Required n so a true mean CLV of mu bps has a 95% CI lower bound > 0 with 80% power,
# with Bonferroni for k candidates (conservative stand-in for BH) and the design effect.
req_n <- function(mu, sigma, k = 1, power = 0.8, alpha = 0.05, deff = 1) {
  z_a <- qnorm(1 - alpha / (2 * k)); z_b <- qnorm(power)
  ceiling(deff * ((z_a + z_b) * sigma / mu)^2)
}
grid <- expand.grid(true_clv_bps = c(50, 75, 100, 150), candidates = c(1, 8))
grid$required_picks <- mapply(req_n, grid$true_clv_bps, sigma, grid$candidates, MoreArgs = list(deff = deff))
print(grid)
# Same logic for ROI at -110 (per-bet SD of flat-stake return ~ 0.95 units)
cat(sprintf("\nFor comparison, flat ROI at -110: detecting +3%% ROI needs ~%d bets (single test)\n",
            ceiling(((qnorm(0.975) + qnorm(0.8)) * 0.954 / 0.03)^2)))

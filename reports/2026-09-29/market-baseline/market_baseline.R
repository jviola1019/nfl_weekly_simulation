suppressPackageStartupMessages(library(dplyr))
s <- nflreadr::load_schedules(2018:2025)
s <- s %>% filter(!is.na(home_score), !is.na(away_score))
amer_to_p <- function(ml) ifelse(ml < 0, -ml / (-ml + 100), 100 / (ml + 100))
out <- s %>%
  mutate(has_ml = is.finite(home_moneyline) & is.finite(away_moneyline),
         ph = amer_to_p(home_moneyline), pa = amer_to_p(away_moneyline),
         overround = ph + pa,
         p_mkt = ph / (ph + pa),
         y = as.integer(home_score > away_score),
         tie = home_score == away_score) %>%
  group_by(season) %>%
  summarise(games = n(), with_ml = sum(has_ml), ties = sum(tie),
            brier_mkt = mean((p_mkt - y)^2 * (!tie), na.rm = TRUE) * n() / sum(!tie & has_ml),
            logloss_mkt = -mean(ifelse(tie | !has_ml, NA, y * log(p_mkt) + (1 - y) * log(1 - p_mkt)), na.rm = TRUE),
            brier_coin = mean(((0.5 - y)^2)[!tie]),
            fav_acc = mean(((p_mkt > 0.5) == (y == 1))[!tie & has_ml]),
            med_overround = median(overround, na.rm = TRUE),
            .groups = "drop")
print(as.data.frame(out), digits = 4)
pooled <- s %>% mutate(ph = amer_to_p(home_moneyline), pa = amer_to_p(away_moneyline), p = ph / (ph + pa),
                       y = as.integer(home_score > away_score)) %>%
  filter(home_score != away_score, is.finite(p))
cat(sprintf("\nPooled 2018-2025: n=%d  market Brier=%.4f  log-loss=%.4f\n", nrow(pooled),
            mean((pooled$p - pooled$y)^2), -mean(pooled$y * log(pooled$p) + (1 - pooled$y) * log(1 - pooled$p))))

# Evidence for Plan 1b-1 Task 5 (audit M24): nflverse marks neutral sites with
# location == "Neutral"; the engine looks for neutral_site/neutral/is_neutral and finds none.
# Reads nflverse schedules for 2015-2024 and 2026 only (no 2025 data: sealed holdout).
suppressMessages(library(dplyr))
s <- suppressMessages(nflreadr::load_schedules(2015:2024))
cat("engine's neutral-column candidates present:", length(intersect(c("neutral_site", "neutral", "is_neutral"), names(s))),
    "| location values 2015-2024:", paste(names(table(s$location, useNA = "ifany")), table(s$location, useNA = "ifany"), sep = " ", collapse = ", "), "\n")
reg <- s |> filter(game_type == "REG")
cat("neutral games 2015-2024: regular season", sum(reg$location == "Neutral"), "| postseason", sum(s$game_type != "REG" & s$location == "Neutral"), "\n")

# Engine formula (NFLsimulation.R:3563-3610): league mean margin, team HFA shrunk with w = n / (n + 60)
hfa <- function(x) {
  league <- mean(x$home_score - x$away_score, na.rm = TRUE)
  x |> group_by(team = home_team) |>
    summarise(hfa_raw = mean(home_score - away_score, na.rm = TRUE), n = n(), .groups = "drop") |>
    mutate(hfa = n / (n + 60) * hfa_raw + (1 - n / (n + 60)) * league, league = league)
}
old <- hfa(reg); new <- hfa(reg |> filter(location != "Neutral"))
home15 <- reg |> filter(season == 2024, week == 15) |> pull(home_team)
d <- inner_join(old |> select(team, old = hfa), new |> select(team, new = hfa), by = "team") |>
  filter(team %in% home15) |> mutate(delta = pmin(pmax(new, -6), 6) - pmin(pmax(old, -6), 6))
cat(sprintf("league HFA %.4f -> %.4f | 2024 wk15 home teams %d | HFA_pts change %.2f..%.2f | |change| > 0.05: %s\n",
            old$league[1], new$league[1], nrow(d), min(d$delta), max(d$delta), paste(sort(d$team[abs(d$delta) > 0.05]), collapse = ", ")))

f <- suppressMessages(nflreadr::load_schedules(2026)) |> filter(is.na(home_score))
cat("2026 unplayed games:", nrow(f), "| location:", paste(names(table(f$location, useNA = "ifany")), table(f$location, useNA = "ifany"), sep = " ", collapse = ", "), "\n")

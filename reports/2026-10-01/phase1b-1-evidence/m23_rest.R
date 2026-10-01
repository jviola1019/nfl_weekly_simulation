# Evidence for Plan 1b-1 Task 6 (audit M23): rest days measured from the week's first
# kickoff vs each team's own game, and nflverse's own home_rest/away_rest columns.
# Reads nflverse schedules for 2023, 2024 and 2026 only (no 2025 data: sealed holdout).
suppressMessages(library(dplyr))
s <- suppressMessages(nflreadr::load_schedules(c(2023, 2024))) |> mutate(game_date = as.Date(gameday))

# 1. 2024 week 15 as the engine computes it today (NFLsimulation.R:4077-4103)
SEASON <- 2024; WEEK <- 15
slate <- s |> filter(season == SEASON, week == WEEK, game_type == "REG")
tg <- bind_rows(s |> filter(!is.na(home_score)) |> transmute(season, week, game_date, team = home_team),
                s |> filter(!is.na(away_score)) |> transmute(season, week, game_date, team = away_team))
last <- tg |> group_by(team) |> filter(season < SEASON | (season == SEASON & week < WEEK)) |>
  arrange(desc(game_date)) |> slice_head(n = 1) |> ungroup()
own <- bind_rows(slate |> transmute(team = home_team, own_date = game_date), slate |> transmute(team = away_team, own_date = game_date))
r <- own |> left_join(last, by = "team") |>
  mutate(today_days = as.numeric(slate$game_date[1] - game_date), own_days = as.numeric(own_date - game_date))
cat("2024 wk15 first slate row:", slate$game_id[1], format(slate$game_date[1]), "\n")
cat(sprintf("short rest (<= 6 days): today %d/%d teams, own game date %d/%d | rest days wrong for %d teams\n",
            sum(r$today_days <= 6), nrow(r), sum(r$own_days <= 6), nrow(r), sum(r$today_days != r$own_days)))

# 2. nflverse home_rest/away_rest vs own-date rest, every 2024 team-game
long <- bind_rows(s |> transmute(season, week, game_date, team = home_team, nfl_rest = home_rest),
                  s |> transmute(season, week, game_date, team = away_team, nfl_rest = away_rest)) |>
  arrange(team, game_date) |> group_by(team) |> mutate(own_days = as.numeric(game_date - lag(game_date))) |> ungroup() |>
  filter(season == 2024)
wk2 <- long |> filter(week >= 2)
cat(sprintf("2024 weeks 2+: nflverse rest == own-date rest in %d of %d team-games\n", sum(wk2$nfl_rest == wk2$own_days), nrow(wk2)))
w1 <- long |> filter(week == 1)
cat("2024 week 1 nflverse rest values:", paste(names(table(w1$nfl_rest)), table(w1$nfl_rest), sep = " x ", collapse = ", "),
    "| own-date range:", paste(range(w1$own_days), collapse = ".."), "\n")

# 3. Populated for unplayed games? (2026, the current season)
f <- suppressMessages(nflreadr::load_schedules(2026)) |> filter(is.na(home_score))
cat(sprintf("2026 unplayed games: %d | home_rest NA %d | away_rest NA %d\n", nrow(f), sum(is.na(f$home_rest)), sum(is.na(f$away_rest))))

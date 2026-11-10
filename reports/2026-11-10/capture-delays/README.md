# How late GitHub starts the scheduled odds captures, re-measured (2026-11-10)

**Status: a measurement.** The crons are not changed here; moving them is the owner's decision.

## The question

#228 moved every game-day slot of `odds-capture.yml` to 4 h 30 min or more before kickoff, because GitHub then started scheduled runs 132 to 237 minutes late. Is that margin still enough?

## The answer: no

The 8 slots since the new crons reached main (2026-11-04 20:45Z), from `capture_delays.csv`:

| | Before #228 (10 slots) | Since 2026-11-04 (8 slots) |
|---|---|---|
| Delay, minutes | 132–237 | 205–417 |
| Median | 196 | 309 |

**Two of week 9's 15 games had no game-day capture before kickoff:**

| Game | Its slot | The run started | Kickoff | Last capture before kickoff |
|---|---|---|---|---|
| CIN at ATL (international) | Sun 08:37Z | Sun 15:33Z | Sun 14:30Z | Sat 20:55Z |
| BUF at MIN (Monday night) | Mon 19:41Z | Tue 02:22Z | Tue 01:15Z | Sun 23:11Z |

The other windows were captured 43 to 128 minutes before their kickoffs.

## What it costs

- **Not the signed tests.** They score Kalshi's hourly candles at kickoff, fetched afterwards.
- **The public archive's line history:** for those two games it stops the day before.

## What follows

- **Recommended:** move each game-day slot to about 8 hours ahead, and measure again after two weeks. It is a workflow change, so it waits for the owner.

## Reproduce

```bash
gh run list --workflow odds-capture.yml --limit 100 --json createdAt,startedAt,event,conclusion,databaseId > capture_runs.json
Rscript reports/2026-10-28/feasibility/capture_delays.R capture_runs.json capture_delays.csv --since=2026-11-04T20:45:35Z
```

`capture_runs.json` here is the list as fetched on 2026-11-10, before 06:00Z. The earlier measurement is `reports/2026-10-28/feasibility/capture_delays.csv`.

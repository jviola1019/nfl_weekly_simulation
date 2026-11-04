# A live maker test of A3, the protected twins (for the owner to run by hand)

## Why it has to be live

A3 (P1 of `nfl_props_v1`) found Kalshi's protected player contracts priced below their unprotected twins (`HYPOTHESES.md` §2).
- **The pair:** long the protected YES, short the unprotected YES.
- **As a maker at the mids,** after the maker fee, it made **+0.50¢ per pair** (95% CI +0.22 to +0.81) in weeks 1–7.
- **That assumes both legs fill at the mid.** Price and trade data cannot show it (§4).
- **Only resting real orders measure** whether they fill, and whether fills come just before the price moves against them (adverse selection).

That needs a Kalshi account and money, so you place the orders by hand on Kalshi's site. No key, login or credential ever passes through Claude.

## What it measures

1. How often each leg fills, and how often a whole pair fills.
2. How long a fill takes.
3. **Adverse selection:** the mid's move from the fill to the kickoff, against the side that filled.
4. **The realized return:** per filled leg and per completed pair, net of the maker fee, against the +0.50¢ the data showed.

## The design, fixed before the first order

- **Series.** Only the four whose maker pair was positive in weeks 1–7 (`reports/2026-10-29/hypotheses/out/consistency/consistency_a3_by_series.csv`), each with its protected twin:

  | Series | Its protected twin |
  |---|---|
  | `KXNFLREC` | `KXNFLRECPROT` |
  | `KXNFLRECYDS` | `KXNFLRECYDSPROT` |
  | `KXNFLRSHYDS` | `KXNFLRSHYDSPROT` |
  | `KXNFLTD` | `KXNFLTDPROT` |

  The two QB series lost money and are left out.
- **Which pairs.** Choose 3 to 1 hours before a kickoff window. A pair is the same player and the same rung, both unprotected and protected. It qualifies when both quotes have a spread of 10¢ or less and a mid between 10¢ and 90¢.
- **Orders, one contract per leg:**
  - a limit **buy of the protected YES** at its mid, rounded down to the cent;
  - a limit **sell of the unprotected YES** at its mid, rounded up. On the site that is "Sell Yes", or buying No at 1 − that price.
- **Cancel** whatever has not filled 5 minutes before kickoff.
- **Size and risk:** at most 50 pairs a week and at most $100 at risk in total. A pair ties up about $1.
  - **A single filled leg** leaves you holding one contract outright. That is the main risk.
- **Duration:** weeks 10–12, or until 150 pairs have been placed.
- **Record every leg** in `maker_log.csv`, copied from `maker_log_template.csv` (whose rows are examples), one row per leg, at the time it happens:
  - `pair_id` (your own label), `placed_utc`, `ticker`;
  - `leg` (`protected_buy` or `unprotected_sell`), `limit_price` in dollars, `contracts`;
  - `filled_contracts`, `fill_utc` (the first fill, empty if none), `cancelled_utc`.

## Scoring

```
Rscript reports/2026-11-02/maker-test/score_maker_log.R <out_dir> --log=<maker_log.csv>
```

It fetches each logged contract's settlement and hourly candles (keyless) and writes:
- fill rates;
- time to fill;
- adverse selection;
- returns per leg and per completed pair, with 90% intervals that resample games.

## The decision rule, stated now

- **The maker edge counts as live** when both hold:
  - at least 30% of pairs complete;
  - the net return per completed pair has a 90% lower bound above 0.
- **Otherwise A3 stays a price relation.**
- **150 pairs is a pilot.** It can show whether orders fill and whether fills are adversely selected. Confirming a +0.5¢ edge would take thousands of pairs.

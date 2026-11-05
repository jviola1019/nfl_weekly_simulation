# Design: RotoBot verified as a source, every market prop type modelled and priced, and the verification sweep (2026-11-05)

Status: **draft for the owner's approval.** Nothing below is built until the owner approves this document (the brainstorming skill's gate). The implementation plans come after approval, written with the writing-plans skill.

## 1. The owner's requests, rewritten as precise prompts

The owner's words are quoted. Each prompt states the goal, the scope, the data, the tests and what "done" means.

| # | Owner's words (2026-11-04/05) | Precise prompt |
|---|---|---|
| P1 | "Rotobot simulator was an online simulation that has a pretty good outcome, which should be reviewed and looked into for accuracy, similar modeling"; "I do not have statistical validations that RotoBot is good; needs to be verified as a quality source prior to implementations. Verify the model compared to our models and markets." | **Goal:** decide, with a pre-registered test on real data, whether RotoBot's public prop projections are a quality source. Nothing is adopted until it passes.<br>**Scope:** its public NFL player pages only (no login, no Pro).<br>**Data:** captured pages, nflverse results, Kalshi/Smarkets/Pinnacle prices, our model's projections.<br>**Tests:** source qualification (§3.1), then a protocol scored on future weeks (§3.2).<br>**Done:** a RESULT with RotoBot against our model and the market, and an adopt or reject decision. |
| P2 | "All props need to be priced and considered in simulation when running weeks, using full possible data analysis and testing"; "Also model every market prop type" | **Goal:** every player prop that a keyless venue offers is simulated and priced when `run_week.R` runs: every line, against every venue, with EV against the best devigged price.<br>**Scope:** the ten stat types in §4.1; any new type a venue starts offering joins the inventory.<br>**Data:** real captures only.<br>**Tests:** recorded real fixtures, walk-forward calibration against settled markets, the app's props page in Playwright.<br>**Done:** a weekly run writes priced props for every inventoried type, and the props page shows them. |
| P3 | "Complete and fix the home field issues"; "choose whatever is recommended with extensive research" | **Goal:** production's home-field default becomes the evidence-supported estimator.<br>**Done:** merged with a golden-master attribution (§6). |
| P4 | "full app verifications (Playwright, etc.) and do not skip anything. Architectures, ERDs, documentation should be verified." | **Goal:** every gate runs on the merged main, and every architecture, ERD and documentation claim is checked against the code.<br>**Done:** `VERIFICATION_2026-11-05.md` with each gate's summary line and each doc finding fixed or tracked (§7). |
| P5 | "Rewrite prompts" | This table, plus CLAUDE.md's agent prompts (#235). |
| P6 | "look into using ponytail/other useful skills and repos for architecture/caching, prompting/Claude abilities" | **Goal:** a recommendation for each tool, with its evidence and cost. Installing anything waits on the owner (§8). |
| P7 | "Context should be reset" | Done: `nfl-worktrees/.prospective/CONTEXT_RESET.md`. Work continues from it, and HANDOFF.md carries the public parts. |

## 2. Constraints (in force)

- **Keyless data only:**
  - no keys we register for, no logins, no challenge cookies;
  - a 403, captcha or geo-fence drops the source, and is never evaded;
  - at most 1 request per second per domain, with a truthful user agent;
  - robots.txt is respected;
  - raw third-party payloads (sportsbooks, RotoBot) are never published.
- **Real data only** (owner, 2026-11-04): no synthetic data and no modelled stand-ins for RotoBot or the markets. Unit tests use recorded real payloads.
- **The 2025 season is sealed:** it may be model history, but it is never scored, and its prices are never computed.
- **`nfl_props_v1` is signed and frozen.** Its module (`4c1c377` in `props-v1-run`) is not touched. New props work is a new version with its own pre-registration.
- **Owner STOPs:** engine edits, `config.R` defaults, new dependencies, frozen protocols, merges, Claude Code configuration changes.
- **STOP-class edits approved for this work (owner, 2026-11-05, "Approve as designed"):**
  - **The props module** (`R/correlated_props.R`, `sports/nfl/props/`, `R/prop_odds_api.R`) writes every priced prop. No-market and unvalidated rows are flagged with stake 0.
  - **No config default changes:** `PROP_REQUIRE_MARKET_ODDS` keeps deciding what can be staked.
  - **`NFLsimulation.R`** is edited only where a plan names the exact lines.
  - **`KALSHI_TAKER_FEE_COEF`** is checked against Kalshi's fee schedule before EV uses it, or stays flagged unverified.
  - **New packages** need a separate yes.

## 3. RotoBot

### 3.1 Source qualification first (A0)

**What its public pages hold (probed 2026-11-04/05):**
- **Pages:** 600 NFL player pages, all allowed by robots.txt. Each shows one featured prop: market, line, a recommendation ("Consider - UNDER"), a median projection, "cleared x/y" (the player's past hit count against the line) and an evidence score. For example, Josh Allen: passing touchdowns 1.5, median 1.4, cleared 13/23, evidence 100/100.
- **Behind Pro** (a login and payment, so excluded): the full prop board, model projections, sportsbook odds and opponent splits.
- **No record:** RotoBot publishes no track record or accuracy figures.

**Red flags in the public data:**
- 599 of 600 NFL profiles in its sitemap were last modified at 2026-02-17, and the pages say "last refreshed Feb 17, 2026".
- No page names an opponent, a date or a week.
- One featured prop (Brandin Cooks: total touchdowns 0.5, "PassProj 0.06") has no recommendation, median or evidence score.
- Against that, Josh Allen's median read 1.3 on 2026-11-04 and 1.4 on 2026-11-05. So something updates, but what, and when, is unknown.

**The qualification test** runs on real captures only, before any scoring design:

| Question | Test | Pass |
|---|---|---|
| Q1 Current? | Capture all 600 profiles now (done 2026-11-05) and after each week's games. Compare the fields. | "cleared x/y" moves after the player's games in at least 80% of players who played |
| Q2 Tied to the next game? | Match each featured line with the player's next game's lines at Kalshi, Smarkets and Pinnacle (same stat). | At least 50% of featured lines equal a live market line for the next game, on at least 50 covered props |
| Q3 Timely? | Record when each change to the line or median appears, against kickoff | At least 80% of changes appear at least 1 hour before the player's kickoff, and no featured line refers to a game already played |

**Definitions (my calls, from the builder check):**
- **Next game:** the first game of the player's team after the capture time, from the nflverse schedule.
- **Q2's denominator:** featured props whose player has at least one line for the same stat in that game at Kalshi, Smarkets or Pinnacle, in the last snapshot before kickoff.
  - **"Equal":** the featured line equals a venue's main line exactly, or a Kalshi strike in its ladder.
  - **Too few:** under 50 covered props makes Q2 *inconclusive*, and capture continues.
- **Q3:** tests the line and median fields only. "Cleared x/y" moves after games by design.
- **Cadence:** a capture every day, plus one before each kickoff window (Thursday 18:00Z, Sunday 12:00Z, Monday 18:00Z). One capture takes about an hour, because the site answers in about 5 seconds a page.

- **If any question fails,** the public data cannot be scored as a predictive source. RotoBot is **rejected as unverifiable** without Pro, which the keyless rule excludes.
- **What it costs:** the capture is about 600 requests per snapshot at 1 per second.

### 3.2 If qualified: the verification protocol `nfl_rotobot_v1` (A1–A3)

- **Pre-registered** before the first scored week, like `nfl_props_v1`: a PROTOCOL.md hashed in `backtest/eval_windows/nfl_rotobot_v1.json`.
- **The unit** is one featured prop per player per game, captured in the last snapshot before kickoff.
- **The comparisons, on the same props:**
  - **RotoBot:** its direction (over or under) and its median.
  - **Our model:** the props simulation's P(over) and median at the same line. This is the frozen v1 module and the new v2 module, reported separately.
  - **The market:** the devigged P(over) at Kalshi, Smarkets or Pinnacle at the last pre-kickoff snapshot, and its median (the line).
- **Metrics:**
  - the directional hit rate (RotoBot's has no probability attached);
  - the median's absolute error against the result;
  - Brier and log loss for the two probabilistic sources;
  - paired differences on the same props, with a game-clustered bootstrap.
- **Decision rule:** RotoBot qualifies as a quality source only if its directional hit rate on the props it leans on beats the market's direction on the same props, with a one-sided interval wholly above zero after Holm across its tests. Agreeing with the market is not a pass.
- **Details (my calls, from the builder check):**
  - **"Props it leans on"** are those with a recommendation, or a median that differs from the line.
  - **"The market"** is the devigged consensus of the venues quoting that prop. The best single venue is reported alongside.
  - **Our models** (the frozen v1 and the new v2) are compared on the same props and reported. **Beating them is not enough to qualify,** because they do not beat the market themselves.
  - **The count** is market-matched featured props, not all featured props.
  - **Too little power:** if the season ends with a minimum detectable effect above 3 points, the result is *inconclusive*, and RotoBot is **not adopted**. Adoption needs positive evidence.
- **Power:** computed from A0's counts before signing. About 300 featured props a week for 9 weeks gives about 2,700. A 3-point edge in hit rate needs about 2,300 independent props (one-sided 5%, 80% power), before clustering. The protocol states its minimum detectable effect.
- **Adoption:** only if it passes. Candidates are its evidence score (sample sufficiency) and its situational splits, each a term that then goes through our own walk-forward admission.

## 4. Props: model and price every market prop type

### 4.1 Inventory (real, week 9 Tuesday capture, 15 games)

| Stat | Kalshi | Smarkets | Pinnacle | Our model today |
|---|---|---|---|---|
| Anytime TD (1+), 2+ TDs | 102 players | 257 players | – | `touchdowns.R` (1+) |
| Passing yards | 5 players | 21 | 2 | `passing_yards.R` |
| Passing TDs | 5 | 21 | 2 | **missing** |
| Interceptions | 1 | – | – | **missing** |
| Completions | 1 | – | – | **missing** |
| Pass attempts | 1 | – | – | **missing** |
| Rushing yards | 10 | 41 | 5 | `rushing_yards.R` |
| Carries | 2 | – | – | **missing** |
| Receiving yards | 30 | 86 | 13 | `receiving_yards.R` |
| Receptions | 12 | 65 | 13 | `receptions.R` |

Coverage grows toward kickoff. Bovada returned an empty coupon this week. Polymarket's player props, if any, are not in the capture's coverage table. Both are rechecked in plan step 2, not counted.

### 4.2 Modelling the missing types

Each new type is a draw from the same correlated game simulation (`R/correlated_props.R`, Gaussian copula on the game's draws), so every prop for a game is consistent with one simulated game.

| Type | Model | Inputs (point in time, before the week) |
|---|---|---|
| Pass attempts | the team's dropbacks from the simulated game script, times the QB's share | nflverse play-by-play: pass rate over expected, pace |
| Completions | binomial on simulated attempts with the QB's completion rate, shrunk to the league | weekly player stats |
| Passing TDs | from the simulated team touchdowns, split rush or pass by the team's pass-TD share, then QB attribution | play-by-play and team TD shares |
| Interceptions | Poisson on attempts with the QB's interception rate, shrunk (low counts) | play-by-play |
| Carries | the team's rushes from the game script, times the player's carry share | snap counts and depth charts |
| 2+ TDs | the same TD draws as anytime TD, at a threshold of 2 | as `touchdowns.R` |

- Every model is fit on 2018–2024 data, never 2025.
- Each type is validated before it prices anything (§4.4).

### 4.3 Pricing

**Built on what exists.** `R/prop_odds_api.R` already has a point-in-time quote cache with three parts:
- the loader, `resolve_prop_odds_cache()`;
- the lookup, `get_market_prop_quotes()` with `PROP_QUOTE_MAX_AGE_MIN` 120;
- player-ID attachment, `attach_player_ids()`.

The weekly capture writes normalized prices (`props_prices__*.csv` in the store). The new source loads those prices into that cache. There is no parallel path.

For every prop (player, stat, line, side, venue, price):
1. **The model's probability:** P(over) from the simulation at that exact line, so every line is priced, alternates included.
2. **The venue's probability:** devigged.
   - Two-sided markets use the multiplicative method, or Shin's.
   - A Kalshi binary uses yes ask and no ask, with the taker fee (0.07·p·(1−p), unverified).
   - Smarkets back and lay use its commission.
3. **The consensus** across venues; the best price; EV at the best price; 1/8 Kelly with the edge skepticism already in the module.
4. **Flags:** every prop with no market is flagged **no market**. It is never priced off the model's own line. Quotes older than `PROP_QUOTE_MAX_AGE_MIN` (120) are stale.
5. **Player mapping:** venue names are matched to gsis ids through nflverse rosters (name and team). An unmatched name is listed, never dropped.

### 4.4 Validation (real data, no synthetic)

- **Walk-forward calibration** of every type, against settled results. The data:
  - Kalshi 2026 weeks 1–8 settlements and pre-kickoff candles (the tools exist: `kalshi_settled.R`, `kalshi_candles.R`);
  - ESPN BET's 2024 prop archive (prices on a subset).
- **Measures, per type:** Brier and log loss against the venue's devigged price, the calibration slope, and reliability.
- **Admission:** a type prices live only if its calibration slope's interval covers 1 and it is not worse than the market by more than the pre-registered margin. Otherwise its rows say **model not admitted**.
- **Windows and samples (my calls, from the builder check):**
  - Each type is **fit on 2018–2023** and **validated on 2024** (ESPN BET's archive, where it has prices) and on **2026 weeks 1–8** (Kalshi settlements). Fit and validation never overlap.
  - Admission needs **at least 200 settled market observations** for the type. Interceptions, completions, attempts and carries had 1–2 Kalshi players in week 9, so they may stay below that for a while.
  - Until a type is admitted, its props are **priced and shown as "unvalidated", and never stake-eligible.** That meets "every type priced and considered" without presenting an untested model as evidence.
  - The admission criteria are written into each implementation plan before any data is scored.
  - `nfl_props_v2` remains the separate, pre-registered future-weeks test of beating the market.
- **Beating the market** is a separate question, for `nfl_props_v2` (pre-registered, future weeks only). The feasibility research found Kalshi props calibrated at kickoff (slope 0.958), so the honest expectation is no edge. The value lies in screening and line shopping.

### 4.5 Integration and the app

- **The weekly run:** `run_week.R` prices props after the simulation. The audit table `artifacts/baseline_props.csv` gains venue, devigged probability, consensus, EV and the flags.
- **The bundle and the app:** the web bundle gains a props file, validated against `contracts/schema/`. The Props page shows it, by game and player, with filters, and marks no-market and not-admitted rows. The page has been empty until now.
- **Tests:**
  - R unit tests on recorded payloads;
  - a contract test for the bundle;
  - vitest for the page;
  - Playwright, on the fixture and on a real bundle, including axe and reduced-motion checks.

## 5. Order of work

1. A0, the RotoBot qualification: the second capture follows week 9's games.
2. The props inventory and pricing for the five existing types.
3. The five new types, one at a time, each validated before it prices.
4. The bundle, the page and Playwright.
5. If RotoBot qualifies: sign `nfl_rotobot_v1` before the next week, then score.

Each step is its own PR, with the gates and CI.

## 6. Home-field default: league (P3)

- **The research:**
  - FiveThirtyEight's NFL Elo uses one league-wide home field, from a rolling 10-year average.
  - nfelo models a rolling league average plus situational adjustments, and finds "few, if any, teams possess predictably better HFA".
  - Open Source Football finds team home field "very unpredictable and almost random on a year over year basis".
  - A per-season hierarchical model (Tierney) finds team values converging since about 2015: "teams all start to look very similar to each other".
- **Our evidence:**
  - the gauntlet found the team estimator significantly worse than league (+0.0048 Brier, interval +0.0025 to +0.0072);
  - engine v2's point estimates favour league (−0.0018 against team_margin, not significant).
- **So:** `HFA_TEAM_ESTIMATOR` defaults to `league`, merged with its golden-master attribution.
- **How this was decided:** engine v2 itself was **void** by its validity gate (`reports/2026-11-04/hfa-engine-v2/RESULT.md`), so it decided nothing. Its result named a switch "the owner's call", and the owner made that call on 2026-11-05: "choose whatever is recommended with extensive research". The decision rests on the literature and the gauntlet; v2's direction is exploratory support only.
- **The window:** the ten-season window overstates home field by about 0.6 points. nfelo reports about 2.05 points over its last 5 seasons and about 1.5 in recent seasons. The window length goes to the term-admission backtest (M22); it is not changed here.

## 7. The verification sweep (P4)

On the merged main:
- **R:** `run_tests.R`, `verify_repo_integrity.R`, `run_matrix.R` 11/11, `run_week.R` with "QA: passed".
- **Web:** typecheck, lint, vitest with `REQUIRE_DB_TESTS`, Playwright on the fixture and on a real bundle (axe, `@parity`, `@sim`), `npm run local` page by page, `db-check`, `erd --check`.
- **Docs:** `docs/ARCHITECTURE.md`'s lineage, `docs/ERD.md` against the schema, the VVF input ERD, `docs/API.md`, README, GETTING_STARTED, DOCUMENTATION, CLAUDE.md and the ledgers. Each claim is checked against the code; each finding is fixed or tracked.
- **Known finding:** the ScoresAndOdds scraper in `R/prop_odds_api.R` sends a browser user agent (`Mozilla/5.0 … Chrome/120.0`). It is off by default, but it breaks the truthful-user-agent rule, so it is fixed or removed.

## 8. Tools (P6)

**Ponytail** (`DietrichGebert/ponytail`, MIT):
- **What it is:** a minimal-code skill.
- **Its hooks:** SessionStart injects its ruleset and a codebase map; UserPromptSubmit tracks its mode; it writes flag files under `~/.claude` and offers a statusline. The activation script makes no network calls.
- **Its claims:** −53% code and −26% cost, the maintainer's own benchmarks.
- **Recommendation:** an optional trial in its `lite` mode, or its on-demand `/ponytail-review` and `/ponytail-audit`. Measure token use before and after, because the repo's CLAUDE.md already enforces minimal diffs. Installing it changes Claude Code's configuration, so the owner decides.

**Caching** (architecture):
- the golden-master CI downloads nflverse once per run and shares it with all record jobs, instead of 53 parallel downloads (the cause of the 503s);
- a local filesystem cache for nflreadr in the weekly run;
- both proposed, each as its own PR.

**Prompting:**
- §1's precise prompts;
- CLAUDE.md's prompts (#235);
- subagent prompts follow the same goal, scope, data, tests and done structure.

## 9. Left to the builder

- **Library and function choices** within the repo's stack (R, data.table or dplyr as the module uses, Next.js and Drizzle).
- **Thresholds:** the exact devig method per venue and the admission margin are fixed in each plan before any data is scored.

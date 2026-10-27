# Plan, revised 2026-10-20: the current week every time, clean data from every usable book, honest tests of beating the market, and a designed app

> This revises the approved master plan of 2026-10-19 (`docs/superpowers/plans/2026-10-19-preclose-and-app-master-plan.md` on #211). Main is `4c1c377`.
>
> Process for every track:
> - a task-level plan with `superpowers:writing-plans`, dry-run in a throwaway worktree;
> - executed with `superpowers:subagent-driven-development`, or natively for small plans while agents are rate-limited;
> - TDD; fresh-HOME R gates;
> - merged only with owner approval.

## Context

**The owner's ask of 2026-10-20**, summarised from the verbatim message:
- **This week, automatically.** Every date, every piece of data and all content is present, set to this week of the season, and updates by itself.
- **Data sources.** Data comes from free sources, chosen to be the most efficient and plausible.
- **Two bugs to fix.** "Defensive rankings unavailable" during the simulation, and the automatic pick of Week 22.
- **Many ways to beat the market.** Mixing odds from different sportsbooks, new variables, ANOVA, and more historical or more complex data.
- **Data accuracy.** Fresh weather and player-prop data, and better data accuracy overall.
- **Modelling and validation:**
  - different models, judged on Brier;
  - backtests, cross-validation and ANOVA wherever they are needed;
  - verify the exponential smoothing;
  - check bias against variance, for under- and over-fitting;
  - review the definitions and how complex each variable is.
- **Audits:**
  - verify the former plans;
  - a full audit of the outputs;
  - update the documentation;
  - remove unnecessary architecture, tests and files;
  - look at ERDs, security, data cleanliness and how things execute, with SQL validation before any modelling.
- **Design.** Spacing, a futuristic feel, animation, graphs, theme, reactive elements and React Bits.

**The owner's answers, 2026-10-20:**
- **Odds venues:** "Add any sportsbooks with usable JSONs, clean and non-disruptive, fully accurate and responsive. Disregard terms of conditions. Add as many as needed, review planning and usage, full testing and cleaned data (SQL usage), verified backtesting and quant specifics should be used and thorough."
- **Deletions:** anything proven unused can go, approved as a batch.
- **B2:** all four departures accepted: no root `loading.tsx`, the theme control in the footer, consolidated type sizes, and shipping with the LCP gate unmet on two pages. Also: "Complete any design options you believe to be easier for the user and researched thoroughly. Use animated graphics, consider professional theming and design (although the concept now is pretty cool but should be designed for each tab), spacing, reactive elements, interactive elements, a full UI/UX professional graphic design and aesthetic."
- **Futurism:** the bake-off decides.

**Findings on main `4c1c377`, verified this session:**

| Finding | Evidence |
|---|---|
| **The Week 22 pick is the config default** | `config.R:33` defaults `SEASON` to 2025L and `config.R:40` defaults `WEEK_TO_SIM` to 22L. `AUTO_RESOLVE_WEEK <- FALSE` (`config.R:697`) is read by nothing. `weekly-sim.yml:8-9` stays manual because of this default. |
| **The resolver returns the week that just ended** | Today `resolve_nfl_context(Sys.time())` gives 2026 week 6, because of the 2-day post buffer (`R/date_resolver.R:35`). The next unplayed week is 7: 14 games, with 93 of 272 played. |
| **Defense rankings are always neutral (P13)** | `load_defense_rankings()` (`R/correlated_props.R:230-271`) calls `dplyr::if_else` with a scalar condition and 32-row branches, so it always errors and prints "Defense rankings unavailable".<br>It is defined a second time at `sports/nfl/props/data_sources.R:395`.<br>It reads the whole season's play-by-play, which looks ahead for past weeks.<br>Its test is skipped as `KNOWN-DEFECT P13`.<br>P1's Task 1 fixes all of this; P1 is planned and dry-run but not executed. |
| **The smoothing works but was never tuned** | `recency_weights()` (`NFLsimulation.R:2883`) weights the newest game first: rows are sorted `desc(sched_date)` at `:3500-3520`. The 3-game half-life was never validated out of sample.<br>A second weight function in the calibration path (`:4322`) has an unchecked row order.<br>`RECENCY_DECAY_RATE` (`config.R:132`) is read by nothing. |
| **Weather is stale for past games** | The engine calls the forecast endpoint for every date (`NFLsimulation.R:3293`), so past games get the defaults (audit M21, S3). |
| **Props fall back to old data** | With no current-season stats, projections fall back to an earlier season's week-18 averages (`sports/nfl/props/data_sources.R:236-241`). |
| **The database has no ERD or SQL checks** | Schema in `web/src/db/schema.ts`, migrations 0000 to 0002. Migration 0001 holds the CHECK constraints and append-only triggers. There is no ERD and no SQL data-quality suite. R cannot write to Postgres: DBI is locked, RPostgres is not. |
| **Test inventory** | 52 R test files, 15 web unit files and 9 e2e specs. One allowlisted skip (P13). |
| **Packages available without a new dependency** | `forecast`, `mgcv`, `glmnet`, `xgboost`, `sandwich`, `lmtest` and `car` are locked in renv. `covr` is not. |
| **The golden master is pinned** | It passes week 15 of 2024 explicitly (`golden-master.yml:31-32`), so an automatic default week cannot change it. |

**Done from the 2026-10-19 plan:**
- A0: #214 merged.
- A1: #213 merged, and the P1 plan committed as `d8b751a`.
- The pre-close validation design was approved.
- The B2 plan was committed as `66ea6ca`.
- D1: Tasks 1 and 2 are complete; Task 3 (`d4a2849`) is waiting for its re-review.
- The A3 planner reached step 1 of its log.
- Both agents stopped at the session limit, which resets at 23:00Z.

## Owner decisions in force

- **Keyless data.** No API keys we register for, and no logins.
- **Block handling.** A 403, a captcha, a bot challenge or a geo-fence drops that venue; it is never evaded. 429s are backed off.
- **Request etiquette.** At most 1 request per second per domain, a truthful user agent, and a 20 s timeout.
- **Terms of service.** Sportsbook terms are accepted as the owner's risk. Raw sportsbook payloads are never published: they go in no public release, artifact or public page.
- **The 2025 holdout stays sealed** except under a signed protocol.
- **Owner STOPs:**
  - config.R defaults (the auto-week change below is requested; the diff gets confirmed);
  - engine edits;
  - new dependencies;
  - `data_validation.R` signatures;
  - frozen protocols and `eval_windows`;
  - merges.
- **Deletions:** only what is proven unused, one PR per area that lists the evidence.
- **No silent fallbacks.** Every number comes from a script.
- **Run rules:**
  - attribute every golden-master change;
  - use a fresh HOME;
  - quote Linux shell arguments with `shQuote`;
  - end commits with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`;
  - run at most two agents at once.
- **Still in force from 2026-10-19:**
  - React Bits components are copied with their notice;
  - editing covers the picker, desk notes and settings, run control, dev mode and a full offline run, and offline looks exactly like online;
  - decision time is the opener plus live snapshots;
  - C3 shows the shrunk value.

## Order of work

There are two agent lanes plus my own inline work. When agents are rate-limited, I execute small plans myself.

| Wave | Lane A (R, data, model) | Lane B (web, ops) | Inline (controller) |
|---|---|---|---|
| 0 | P1 Task 1: the P13 defense-rankings fix | – | C1, the automatic week; V2, the output audit of 2026 week 7 |
| 1 | D1 Tasks 3–12 (resume the re-review) | B2 Tasks 1–13 | V1 plan verification; V3 docs truth |
| 2 | P1 Tasks 2–8, then K1 venue survey | C2 SQL checks and ERD, then B1 banner | – |
| 3 | A3 (VVF plus S5 diagnostics; amend the planner's brief) | B4-E1/E2, then B3 bake-off with concept E | – |
| 4 | K2/K3 venue providers, H historical openers, A4/A5 | B5 per-tab design, B4-E3/E4 | X cleanup PRs |
| 5 | G1, then G2 (term admission; weather from C2) | B4-E5 offline run | S security audit |
| 6 | M studies, then G3 and the shared holdout | evidence pages for each study | final docs-truth pass |

## Track V: verify the former plans, the outputs and the docs (first)

1. **V1, the claims of every former plan.**
   - **Sources:** phase0, 1a, 1b-1, A8, the roadmap, D1, P1, B2, the master plan and the design spec.
   - **Check:** each "done" or "verified" claim is checked on main: the test exists and passes, the behaviour reproduces, and every number traces to a script's output.
   - **Output:** `reports/2026-10-21/PLAN_VERIFICATION.md`, with PASS, FAIL or STALE and the file:line for each claim. Every FAIL becomes a task in the track that owns it.
2. **V2, an output audit of a real 2026 week 7 run.**
   - **Run:** fresh HOME. Until C1 lands, the command is `Rscript run_week.R 7 2026`.
   - **Game checks:**
     - all 14 games, each with its kickoff in ET and its weekday;
     - market (C0) and model (C3) probabilities, each inside (0, 1), with each pair summing to 1;
     - margins and totals against the market, listing every gap above 10 points;
     - props rows for every game.
   - **Data checks:**
     - the defense multipliers are not all 1;
     - the weather status is "full";
     - the data-quality badge;
     - bundle QA passes.
   - **App check:** every page shows week 7 with every section filled.
   - **Output:** `reports/2026-10-21/OUTPUT_AUDIT.md`.
3. **V3, docs truth.** README, GETTING_STARTED, DOCUMENTATION and CLAUDE.md. CLAUDE.md says "Last updated 2026-02-05" and cites line numbers that have since moved. Run every command they give, check every path, and fix them in a docs PR.
4. **V4, how things execute.** Wall time for each `run_week.R` stage, CI durations, and the golden master. Flag anything slow or flaky.

## Track C1: the current week, automatically (fixes the Week 22 pick)

- **The resolver.** Add `resolve_target_week(schedule, now)` to `R/date_resolver.R`. It returns the earliest week of the current season that still has a game not yet kicked off.

  | When | Week returned |
  |---|---|
  | Tuesday after Monday Night Football | next week |
  | Thursday before Thursday Night Football | that week |
  | Sunday afternoon | this week |
  | Before week 1 | week 1 |
  | After the Super Bowl | stops with "offseason: pass a week and season" |

  It is a pure function, tested on a fixed schedule fixture with no network.
- **Run configuration** (`R/run_config.R`).
  - With no week or season on the command line, it resolves them from `nflreadr::load_schedules()` and prints a line in the form `Auto-resolved <season> week <w> (<n> games, first kickoff <weekday date time> ET)`, with the values taken from the schedule.
  - If the schedule cannot load, the run stops. There is no default week.
  - Command-line arguments still override.
- **config.R** (requested; I confirm the diff).
  - `SEASON` and `WEEK_TO_SIM` default to automatic, and `AUTO_RESOLVE_WEEK` is wired in.
  - The unused `RECENCY_DECAY_RATE` is removed.
  - The golden master and `run_matrix` keep their explicit week; check each artifact does.
- **Workflows.**
  - `weekly-sim.yml` runs on a schedule at Tuesday 18:00Z and Friday 21:00Z, the two decision points, with the resolved week. Its refusal of 2025 stays.
  - `capture-archive.yml` also archives the weekly-sim bundles.
- **The local app.**
  - `npm run local -- --latest` downloads the newest successful weekly-sim artifact (`gh run download`), checks the sha256s in its manifest, and ingests it.
  - Offline, it uses the newest local bundle, and the context line shows the bundle's age.
- **Tests:**
  - the resolver table;
  - `run_config`;
  - the pinned workflow crons;
  - the week the web shows comes from the bundle.

## Track P1 (planned and dry-run): props correctness, with P13 first

- **Task 1.** One `load_defense_rankings(season, weeks, pbp)` that builds real multipliers from games through week w−1 only. The duplicate goes, and so does the P13 skip.
- **Tasks 2–8.** The key helpers, P14, then the remaining rows as the plan sets them out.
- **Order.** Executed now, because the owner asked for this fix.

## Track C2: fresh, clean data, and SQL checks before any model run

- **Input checks** (`R/input_checks.R`). These run on schedules, play-by-play, player stats, rosters and depth charts, injuries and odds.

  | Check | What it enforces |
  |---|---|
  | Shape | the expected columns and types |
  | Keys | each key is unique |
  | Missing values | NA rates stay under a threshold |
  | Values | every value is inside its range |
  | Team codes | canonical codes (LA/LAR, OAK/LV, SD/LAC, STL/LA) |
  | Freshness | the latest week present is the target week minus 1 |

  Results are logged through the existing `update_*_quality()` API, with no signature change. A critical failure stops the run.
- **Weather that is never stale.**
  - The forecast endpoint is used only within 16 days of kickoff, and each value is stamped with its `fetched_at`.
  - Past games use Open-Meteo's historical-forecast API, which returns what was forecast at the time. nflverse `temp`, `wind` and `roof` are the observed reference.
  - Lookups are keyed by stadium coordinates (`stadium_id`); domes are skipped.
  - A game without weather is logged and fails QA; there is no Kansas default.
  - This is an engine edit: owner checkpoint 2.
- **Props that are never stale.**
  - Current-season stats through week w−1, shrunk toward the prior season according to games played (empirical Bayes). This replaces the week-18 fallback.
  - Current depth charts and injury status.
  - Every prop row carries its `data_as_of`.
  - Prices from the K venues.
- **SQL.**
  - **Ingest.** Odds and model outputs reach Postgres through the TypeScript ingest, as an odds bundle under `contracts/schema/`. This needs no R database driver.
  - **Checks.** `web/scripts/db-check.ts` runs assertion queries that must return zero rows:
    - orphan rows;
    - probabilities outside [0, 1];
    - distributions that do not sum to 1;
    - duplicate natural keys;
    - a close taken after kickoff;
    - a two-way market whose implied probabilities sum outside [1.00, 1.15];
    - a venue more than 8 points from the cross-venue median, which is flagged.
  - **When.** After every ingest, locally and in CI, and before every backtest.
  - **Constraints.** Range CHECK constraints go into migration 0003 (checkpoint 7).
- **ERD.**
  - `docs/ERD.md`, a Mermaid `erDiagram`, is generated from `schema.ts` by `web/scripts/erd.ts`. A docs-truth test fails if the two disagree.
  - A lineage diagram (sources → inputs → features → model → bundle → tables → pages) goes in `docs/ARCHITECTURE.md`.

## Track K: every usable sportsbook, collected cleanly

1. **K1, the survey.**
   - **Venues probed once each:** DraftKings, FanDuel, BetMGM, Caesars, BetRivers/Kambi, Fanatics, Bovada, Pinnacle (the sharp benchmark), Circa, BetOnline, Polymarket, ProphetX, Novig, and ESPN's provider list.
   - **Recorded for each:** the URL pattern, what the request needs, its markets (moneyline, spread, total, props), timestamps, coverage, history and stability.
   - **Output:** `reports/.../VENUE_SURVEY.md`.
   - **Excluded:** any venue that needs a registered key, a login or a challenge cookie.
2. **K2, the providers.**
   - Each venue that passes becomes `R/odds/providers/<venue>.R` on D1's HTTP layer (rate floor, backoff, block breaker, raw sha256) and D1's snapshot shape.
   - **Tests:** fixture tests from saved payloads, and a schema-drift test for each venue.
   - Each book joins the venue catalog.
3. **K3, capture and storage** (checkpoint 3).
   - Sportsbook captures run where their raw data stays private: my recommendation is a private companion repository's scheduled workflow, or the local runner. Kalshi, ESPN and nflverse stay in the public archive.
   - Every snapshot is validated (`validate_odds_snapshots`), then SQL-checked after ingest.
   - Public pages show only consensus figures. Prices for each venue appear on the desk and offline.
4. **What this data cannot do.** Sportsbook JSON has no history, so every multi-book test is prospective from 2026 week 7 on, and each result says so.

## Track H: more and richer history

- **Free historical odds with openers,** such as AusSportsBetting's NFL file and the SBR archives.
  - **Admission test.** A source is admitted only if it agrees with the nflverse closes (spreads within 0.5 points, no-vig probabilities within 2 points) and with ESPN's 2023–24 openers.
  - **Why it matters.** If it is admitted, the pre-close Tune window grows from 205 games to thousands, and the minimum detectable effect shrinks roughly with the square root of n.
  - **The 2025 seal.** The file contains 2025 rows. The loader drops them as it parses, and a test proves none survive (checkpoint 4).
- **Longer nflverse history:** closing moneylines back to 2006 for training and the close-anchored screens, and play-by-play features from 1999.
- **New feature families for the screen,** each with its `known_at` class:
  - **team efficiency:** EPA per play and success rate (opponent-adjusted and smoothed), PROE and CPOE;
  - **tracking and charting:** NGS, and FTN charting from 2022;
  - **personnel:** snap counts, depth-chart changes, Friday injuries, and coaching and QB changes;
  - **context:** rest and travel (after the M23 and M24 fixes), weather forecasts, the referee crew;
  - **market:** the opener's level, early movement, and how far venues disagree.

## Track A3: variable ledger and validation framework, plus bias–variance diagnostics

Stages S0–S4 follow the approved design. Stage S5 is added; this amendment goes to the A3 planner, which resumes from its log.

- **Validation curves** for every smoothing and shrinkage setting:

  | Setting | Values tried |
  |---|---|
  | `RECENCY_HALFLIFE` | 1 to 8, and ∞ |
  | `GLMM_BLEND_W` | grid |
  | `SOS_STRENGTH` | grid |
  | `SHRINKAGE` | 0.5 to 0.9 |
  | `N_RECENT` | grid |

  Each is scored on walk-forward log-loss and Brier over the Tune seasons, with week-block bootstrap intervals. Choose by the one-standard-error rule.
- **Over- and under-fitting:**
  - in-sample against walk-forward loss for each season;
  - learning curves over 2 to 10 training seasons;
  - the calibration slope (below 1 means overconfident, above 1 underconfident);
  - a Murphy decomposition of Brier (reliability, resolution, uncertainty) for C0, C3 and the blends;
  - bias and variance of the margin and total errors;
  - CRPS;
  - PIT histograms for the NB distributions.
- **Exponential smoothing:**
  - unit tests that both weight functions give the newest game weight 1 and halve every half-life;
  - a property test that the weighted mean equals an EWMA with α = 1 − 2^(−1/h);
  - candidate alternatives: an α fitted per team with `forecast::ets`, and a local-level state-space (Kalman) rating.
- **Cross-validation:** walk-forward only, never random k-fold. It is nested: tuning happens inside Tune and evaluation on Confirm. The holdout stays sealed.
- **ANOVA additions:**
  - loss differences by season and by part of the season;
  - team-level residual effects;
  - feature × season interactions.
- **Complexity:** each ledger row records its parameter count, and each model reports its effective degrees of freedom.

## Track A4–A5: `nfl_preclose_v1` (as approved)

- **Information sets.** IS-A is primary and IS-B secondary.
- **Windows.**
  - Tune 2023: 205 games.
  - Confirm 2024: 284 games.
  - Holdout 2025: shared with v2 and opened once.
- **Candidates and gates.** PC-C2, OA[E1], LM[E1] and C3@open. Gates P1–P7, including the implausibility guard, plus the disclosures.
- **If H admits historical openers,** an amendment moves Tune to 2006–2022 before the owner signs.

## Track M: ways to beat the market, each pre-registered and each shown on the evidence pages

| # | Idea | Data | Test |
|---|---|---|---|
| M1 | Beat the close on accuracy | nflverse 2006–24, ESPN | Brier and log-loss skill against the no-vig close (the ceiling; null so far) |
| M2 | Beat the opener (CLV) | ESPN 2023–24, H, 2026 live | `nfl_preclose_v1` |
| M3 | The best devig | ESPN's two books, Kalshi, K | proportional, additive, power and Shin, compared on log-loss (high power) |
| M4 | Consensus and sharp-weighted consensus | K, 2026 onward | consensus against the best single venue on Brier; Pinnacle lead–lag (`nfl_venues_v1`) |
| M5 | Line shopping and stale lines | K | best-of-N price gain in bps; realized CLV of soft-book lines that lag; how often arbitrage appears |
| M6 | A model and market ensemble | all | stacked logit pooling, ridge, Tune only (#209 found nothing; retested with the new features) |
| M7 | Thinner markets: props, totals, spreads | Kalshi touchdowns, K props, ESPN lines | `nfl_props_v1`; CRPS and cover rates |
| M8 | Information timing | Tuesday against Friday | does injury news move lines, and does the model see it first |

**Model families,** all run walk-forward and tested at S3:
- Elo with margin and a QB adjustment;
- Bayesian dynamic ratings (state space);
- the GLMM;
- ridge logistic with a market offset (`glmnet`);
- a GAM for rest, travel and weather (`mgcv`);
- boosted trees on the market residual (`xgboost`, with S5 watching for overfitting);
- the NB/copula simulator (C3).

The honest expectation is that most of these will not beat the close. The banner shows whatever the gates show.

## Track G1–G3 (unchanged)

- **G1:** point-in-time features, resumed from `g1dry`. Its `injury_scalp.R` edit is a STOP.
- **G2:** term admission, using weather from C2.
- **G3:** sign `nfl_games_v2`, score Confirm, then open the shared 2025 holdout once.

## Track X: remove what is proven unused (batch approval)

**Proof required for every item:** no grep hits, then `run_matrix` 11/11, the full test suite and the integrity checks all green after removal. Each PR lists that evidence.

**Candidates:**
- **Dead config:** `RECENCY_DECAY_RATE`, and `AUTO_RESOLVE_WEEK` unless C1 wires it.
- **The invalid ensemble calibrator:** `ensemble_calibration_implementation.R` and `ensemble_calibration_production.rds`, if their code path is dead while calibration is disabled.
- **Ad hoc scripts:** `validation/*.R`, if no artifact uses them.
- **Duplicate loaders:** removed by P1.
- **Tests:**
  - existence-only checks, such as `test-player-props.R:599`, become behaviour tests or go;
  - duplicates are merged;
  - the count of behavioural assertions never falls.
- **Scratch state,** once their plans have run: the worktrees `b2base`, `b2dry`, `d1dry`, `g1dry` and `p1dry`, and the scratch databases `nfl_b2dry*` and `nfl_b2base`.

Removals inside `NFLsimulation.R` or `NFLmarket.R` stay STOPs.

## Track S: security and execution audit

**Method:** `/security-review` on every branch, plus one pass over the whole repo.

**Scope:**
- secrets anywhere in git history;
- least-privilege workflow permissions, with actions pinned;
- CSP and response headers;
- desk authentication: cookie flags and a login rate limit;
- SQL: parameterized queries, and a review of any raw SQL;
- `system2` quoting;
- the `jsonlite::fromJSON` file and URL branch, which D1 deferred; the fix is `parse_json`;
- fetchers limited to an allowlist of hosts;
- `npm audit`;
- the loopback runner from B4-E3.

**Output:** `reports/.../SECURITY_AUDIT.md`, with one PR per fix.

## Track B: design, editing and offline

- **B2,** approved with all four departures: execute it now (13 tasks).
- **B1, the banner:** unchanged.
- **B3, the bake-off,** which decides the look.
  - **Concepts:** Control, A Scoreboard, B Turf grid, C Telestrator, D Effects, and a new **E, Night-game HUD**. E has:
    - a WebGL2 background;
    - glow;
    - chart lines that draw themselves in;
    - readouts that count up;
    - cards that react to hover;
    - a theme cross-fade through the View Transitions API.
  - **Gates, the same for every concept:**
    - LCP and CLS;
    - axe;
    - reduced motion;
    - zero differing pixels on `@parity` once settled;
    - contrast;
    - First Load JS no more than 25 KB above Control.
  - **The ban on glow and gradients** in spec §4 is lifted only if D or E wins (checkpoint 6).
- **B5, a design for each tab** (new), on the winning concept:

  | Tab | Design |
  |---|---|
  | Home | a live scoreboard slate with sort and filter chips |
  | Game | the field, animated distributions, and a line-movement chart with venue lines (desk and offline only) |
  | Evidence | animated skill intervals and reliability, linked on hover |
  | Methodology | explainer graphics for the model and the gates |
  | Data health | a status board with the age of each source |
  | Props | player cards, model against line |
  | Desk | a workspace |

  - **Interaction:** charts linked on hover and focus, keyboard support and tooltips.
  - **Motion:** every transition respects reduced motion.
  - **Method:** the frontend-design and dataviz skills; every chart passes the dataviz palette validator.
  - **Review:** a contact sheet at 3 widths × 2 themes, as a private Artifact for the owner.
- **B4, editing and offline:** E1–E5 unchanged (the picker, desk notes and settings with migration 0003, run control, dev mode, and a full offline run from snapshots).

## Owner checkpoints

1. The config.R diff for the automatic week.
2. Engine edits: weather (C2), G1's `injury_scalp.R`, and anything in `NFLsimulation.R` or `NFLmarket.R`.
3. Where sportsbook captures run and where they are stored, which must not be in public releases.
4. Historical openers that contain 2025 rows (dropped as they are parsed), and any protocol amendment.
5. Signing `nfl_preclose_v1`, `nfl_venues_v1` and `nfl_props_v1`.
6. The design concept, its dependencies (gsap, motion) and the spec §4 text.
7. Migration 0003, the dispatch token, and new workflow inputs.
8. Opening the 2025 holdout.
9. Every merge.

## Verification

- **R:**
  - fresh-HOME `run_tests.R`, `verify_repo_integrity.R`, and `run_matrix.R` at 11/11;
  - the golden master unchanged, or every change attributed;
  - the VVF known-answer tests and the reproduction of v2;
  - the S5 report;
  - `result_sha256` reproduces on a second run.
- **Data:**
  - the input checks pass on the week 7 run;
  - `db-check.ts` returns zero rows after every ingest;
  - the ERD docs-truth test passes;
  - each venue's fixture and drift tests pass;
  - no 2025 rows anywhere.
- **The automatic week:**
  - the resolver tests;
  - `run_week.R` with no arguments on 2026-10-20 picks week 7;
  - the scheduled weekly-sim writes a week 7 bundle;
  - `npm run local -- --latest` shows it.
- **Web:**
  - typecheck, lint, and vitest with `REQUIRE_DB_TESTS`;
  - the full Playwright suite, including `@parity` (0 px), axe with best-practice rules, reduced motion, and the flag check;
  - Lighthouse mobile medians;
  - the slopScan, designLanguage, docsTruth, tokens and thirdPartyNotices tests.
- **Reports:** every FAIL in V1, V2, V3 and S is either resolved or tracked.
- **Tools:**
  - the Playwright and Lighthouse CLIs, since the MCPs time out;
  - the dataviz validator;
  - the frontend-design and security-review skills;
  - `gh` for CI.

## Risks

| Risk | Handling |
|---|---|
| A sportsbook endpoint changes or blocks us | Drift tests; a block drops the venue and is never evaded |
| Terms-of-service exposure (accepted by the owner) | Raw payloads are never published; low request rate; truthful user agent |
| Multi-book data has no history | Prospective tests, each with a power statement; M3 uses the history that exists |
| Quality of historical openers | The admission test against nflverse and ESPN |
| Underpowered nulls | The minimum detectable effect is pre-registered, and the banner reports nulls |
| Overfitting across many settings and models | S5's one-standard-error rule, nested validation, and the sealed holdout |
| Agent and session limits | Native execution for small plans; ledgers and logs on disk; resume with SendMessage |

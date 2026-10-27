# Plan: beat the market before the close (honestly), and a finished Broadcast Line app, editable and offline (2026-10-19)

> This replaces the 2026-09-28 overhaul plan, whose Phases 0–1b-1 and A8 are merged; main is `210f791`. It folds in the modeling roadmap (PR #211) and the three phase plans D1, P1 and G1. Each track below gets task-level plans written with `superpowers:writing-plans`, dry-run in a throwaway worktree, executed with `superpowers:subagent-driven-development` (TDD; haiku transcribes, sonnet judges, an opus final review), and merged only with owner approval.

## Context

**What the owner asked for (2026-10-19), verbatim:**
- "Full planning/auditing for model accuracy over market, UI/UX improvements, editing and offline usage, design and graphic implementation with React Bits … perfected spacing, context and full HTML professionalability."
- "Finalize accuracy and authenticity of modeling and attempt to defeat market prior to close time. Use full testing, model architecture, variable fixing, ANOVA/statistical validations for variables … If cannot pass, still show modeling on HTML but note largely at top."

**Why the work changes direction.**
- **Nothing beats the close.** v1 Confirm 2023–24 and blend research #209 both found it.
- **The v2 "ANOVA" screen tested the wrong anchor for this goal.** It ran 36 point-in-time features beyond the **close**: likelihood-ratio tests with the close as offset, week-clustered robust tests and BH correction. Every result was null; the joint p-value was 0.63. The owner's goal is value **before** the close. The right anchor is the **opener**, and the information that arrives between open and close.
- **v1's opener→close CLV leans positive but is under-powered:** C2 +93 bps [+40, +149] on 214 picks and K[E1] +66 bps [+8, +125], both below the 400-pick gate. That is the target.

**Authenticity problems found today, all verified:**
- **2025 prices and outcomes were already read.** `reports/2026-09-29/clv-power/espn_open_close_2024_2025.csv` holds 2025 ESPN opener and close prices. `clv_power.R:13,29` loaded 2025 scores. No model was fit on them, but the 400-pick gate's σ came from that study. It must be disclosed, and a test must keep backtest code from reading the file.
- **The capture misses Sunday games mid-week.** `CAPTURE_HORIZON_HOURS <- 36` (`config.R:919`, used by `select_capture_events()` at `R/capture_raw.R:60`) means the Tuesday and Thursday runs skip every Sunday game for ESPN.
- **The game-day runs start after kickoff.** GitHub cron starts lag about 2.2 hours: on 2026-10-18, runs set for 16:15, 19:20 and 23:35Z started at 18:38, 21:34 and 01:33Z.
- **The captures expire:** they are 90-day artifacts (`odds-capture.yml:55`).
- **v1's C2 used information an opener bettor did not have:** week w−1 results and the actual starting QB.

**What the UI audit found (`web/` at `210f791`):**
- The design tokens cover colour only. There are 114 arbitrary utilities, including 16 text sizes, plus six card paddings, eight hand-copied tables and inconsistent section gaps.
- Layout bugs:
  - the phone flags sit about 33 px off their markers (`games/[id]/page.tsx:108` against `Field.tsx:154`);
  - the game page's top offset is 32 px, against 48 px elsewhere;
  - the mobile nav takes a third row;
  - the theme flashes after hydration;
  - there is no `loading.tsx` or `error.tsx`.
- Editing is a theme toggle only.
- Offline friction: a restart per bundle, a production build per edit, manual desk seeding.
- Game-page LCP is 2.67 s, against the 2.5 s gate.

**React Bits constraints:**
- License: MIT plus Commons Clause, and this repo is public.
- All 218 components are `'use client'`.
- CSP: `style-src-attr 'unsafe-inline'` already allows style attributes (`web/src/lib/security/csp.ts:25`). But 22 components inject un-nonced `<style>` and Noise needs `blob:`, so those are out.
- The slopScan test bans gradient, blur, glow and particles, and the shipped Counter, ShapeGrid and DotGrid trip it until adapted.

**Intended outcome:**
- An authentic, pre-registered test of decision-time value, at the opener plus live 2026 snapshots.
- A variable pipeline where every variable is fixed, dated by when it becomes known, and statistically validated.
- The model shown everywhere, with a large status banner at the top built from the test results.
- A tokenized, professional UI with the best-testing React Bits concept.
- Full editing, plus offline operation that looks pixel-identical online.

## Owner decisions in force (2026-10-19, plus earlier)

- **React Bits.** "Consider all options, test different concepts and see what would look the best. Include effects/backgrounds if accessible." Copy the components with the license notice; the repo stays public.
- **Editing.** All of these, and "full run should be possible offline; online service should look exactly the same":
  - a run and week picker;
  - offline run control;
  - desk notes and settings;
  - a live-edit dev mode.
- **Decision time.** "Opener + live snapshots": the new protocol uses Tune 2023, Confirm 2024 and the 2025 Holdout scored once. The prospective 2026 track compares captured mid-week prices with the close.
- **Earlier rules, still binding:**
  - keyless data only;
  - 2025 stays sealed except under a signed protocol;
  - the owner STOPs: config.R defaults, engine edits, dependencies, `data_validation.R` signatures, deletions, merges;
  - no silent fallbacks;
  - numbers come only from scripts;
  - golden-master attribution;
  - fresh `HOME` for local gates;
  - `shQuote` for Linux;
  - commit trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`;
  - at most two agents at once (the weekly API limit was hit on 2026-10-14).

## Two lanes, in order

| Step | Lane A (R / model) | Lane B (web / ops) |
|---|---|---|
| 1 | A0 capture fixes · A1 close out the P1 plan, fix `bw_git_state` | B2 tokens, components, bugs, LCP |
| 2 | A2 execute D1 (already dry-run) | B1 banner · B4-E1 picker |
| 3 | A3 variable ledger + validation framework | B4-E2 desk notes/settings · B3 bake-off |
| 4 | A4 `nfl_preclose_v1` → **owner signs** → Tune 2023 → A5 Confirm 2024 | B3 rollout · B4-E3 run control · E4 dev mode |
| 5 | A6 G1 (resume the plan from `g1dry`, then dry-run it) | B4-E5 full offline run · line-movement view |
| 6 | A7 G2 (term admission) → A8 G3 plus one shared 2025 Holdout | pre-close evidence pages |

---

## Track A: accuracy and authenticity

**A0: capture fixes** (owner checkpoint 1)
- **Horizon.** Add a separate ESPN game-odds horizon of 9 days. This is a new config constant; props keep 36 hours.
- **Timing.** Move the game-day crons about 3 hours earlier to absorb the scheduler lag. Exact pre-kickoff prices still come from Kalshi hourly candles and ESPN's labelled close.
- **Archive.** Add `capture-archive.yml`. Once a week it packs the artifacts with SHA256SUMS into a release asset. Only this job gets `contents: write`. It must first run before 2026-12-28, when the oldest artifacts expire.
- **Opener timing.** Measure when each game is first quoted (the first ESPN BET appearance and the Kalshi open), which shows what an opener bettor knew.

**A1: housekeeping**
- Finish the P1 plan: run its `run_matrix` gate, then commit it to #211.
- Fix `bw_git_state()` in `R/bundle_writer.R` the way `a30c61c` fixed `sb_git_state()`.
- List, then remove, the `p1base` worktree.

**A2: execute D1** (`docs/superpowers/plans/2026-10-13-d1-keyless-odds-layer.md`, 12 tasks). This builds the `R/odds/` providers, the closing rule, and the 2023–24 archive (both an opener and a close for 205 games in 2023 and 284 in 2024). Its owner checkpoints CP1–CP7 apply, including the terms-of-service sign-off and `CAPTURE_MIN_INTERVAL_SEC`.

**A3a: the variable ledger** (`docs/VARIABLE_LEDGER.md`). One row per variable: definition, source, when it becomes known, its unit test, known defects, the fix and the phase that owns it, and its screen result.

| Variable | Defect | Fix (phase) |
|---|---|---|
| HFA, rho, points cap | Windows include later games (M5); team `n()` counts unplayed games | `features_asof`; count played games only; append canary (G1) |
| GLMM prior | No season term, silent `try`, unversioned NB cache key (M9) | Add a season term, log failures, version the key (G1) |
| QB / QB change | Actual starter used; backup quality silently 0.35 under the 2026 depth-chart schema | Use the previous starter at the opener; flag the schema change (G1) |
| Team time zone `LAR`/`LA` | Join mismatch | G1, an engine edit (STOP) |
| Injuries | Computed, never in the means (M18) | Admit only through the test, at the close and the Friday decision point (G2) |
| Weather | Joined by stadium name; forecast endpoint used for history; the Kansas fallback (M21, S3) | Key by `stadium_id`, use historical forecasts, log misses (G2) |
| Neutral-site travel | Measured from the home stadium | Venue coordinates (G2) |
| Turnover term | NaN source (M22) | Explicit NA rule plus a test (G2) |
| 21.5/10.0, `safe_mu`/`safe_sd` | Silent substitution | Remove (G1) |
| `load_defense_rankings`, `load_red_zone_efficiency` | Each defined twice | Keep one, a source-order test (P1); deletion needs approval |

**A3b: the validation framework** (`backtest/vvf/`). No new packages: `sandwich`, `lmtest` and `car` are locked. It reuses `bt2_screen_one` and `bt2_screen_joint` from #205 (`backtest/v2/screen.R`), along with these existing helpers:
- `bt_assert_asof` (`backtest/common.R:38`);
- `bt_boot_counts`, `bt_score_window`, `bt_dm_hln` and `bt_clv` (`backtest/metrics.R`);
- `bt_control_canary` and `bt_shuffle_scores` (`backtest/controls.R`);
- `bt_check_protocol` and `bt_gates` (`backtest/walk_forward.R`).

Every stage takes an **anchor**, the opener or the close:

| Stage | What it does |
|---|---|
| S0 provenance | Each feature declares when it becomes known. `vvf_assert_known_at()` refuses any feature known after the decision time. |
| S1 screen ("ANOVA") | Nested LR test of `y ~ offset(logit anchor) + x`. Spread and total F tests. A **movement** target, logit(close) − logit(open). Week-clustered robust p (wild-cluster bootstrap when there are fewer than 30 weeks). BH within each family. Effect size and MDE per SD. |
| S2 structure | VIF ≤ 5. Season stability: per-season signs plus a feature × season LR test. |
| S3 incremental skill | Base + x against base, refit weekly. Paired loss, week-block bootstrap (B = 10,000), DM-HLN, BH over a declared order. |
| S4 controls | Leak canary; a placebo noise feature (false-positive rate ≈ α over 200 draws); shuffled labels; the anchor copied as a candidate; the same `result_sha256` on a second run. |

**Known-answer tests:** a planted effect is detected, a null is not, and the LR statistic equals `anova()`.

**A4–A5: `nfl_preclose_v1`.** It is drafted, then the owner signs it (checkpoint 3). Its hash goes in `backtest/eval_windows/nfl_preclose_v1.json`, and scoring is gated by `bt_check_protocol`.
- **Information sets:**
  - **IS-A (primary):** results through week w−2, the previous game's starting QB, and schedule facts. This is executable whenever the opener was posted.
  - **IS-B (secondary):** results through week w−1, labelled "may not be executable" until the A0 timing study decides.
  - **Never at the opener:** injury reports, inactives, actual starters, observed weather.
- **Windows:**
  - Base models train on 2010–22.
  - **Tune 2023:** 205 games with an opener (weeks 1–5 have none).
  - **Confirm 2024:** 284 games.
  - **Holdout 2025:** opened once, in a single build shared with `nfl_games_v2`.
- **Confirmatory candidates,** with BH across them:
  - **PC-C2:** v1's C2 on IS-A.
  - **OA[E1]:** ridge `y ~ logit(open) + logit(E1)`.
  - **LM[E1]:** a line-movement model, Δ̂ = a + b·(logit E1 − logit open).
  - **C3@open:** `predict_week(asof)`, only if G1 lands in time.
  - E1 and K[E1] are descriptive only.
- **Endpoints and gates** (the Holdout decides):
  - Brier skill against the no-vig opener, with the close's skill as the ceiling. Beating the close's own skill voids the run as implausible.
  - Movement slope b > 0 and movement skill.
  - CLV in bps for picks with |p − p_open| ≥ 0.03, against the A2 gate (≥ 400 picks, mean ≥ +100 bps, CI lower bound > 0).
  - Calibration slope and ECE.
  - All controls pass.
- **Disclosure:** v1 already looked at 2024 opener CLV, and the 2025 clv-power read happened. Both are disclosed above.
- **Prospective 2026:**
  - Decision points are Tuesday 18:00Z (primary) and Friday 21:00Z (exploratory, after the injury report).
  - The price is the Kalshi mid at the first qualifying hourly candle, plus ESPN captures once A0 lands. The close follows D1's closing rule.
  - Bundles are archived before kickoff; `track_append.R` refuses late ones.
  - The evaluation is one look after week 18, with interim weekly reports labelled as such.
- **Realism:** σ is 514 bps per pick. A +100 bps edge needs 375 picks across eight candidates, and v1 made 214 from 284 games. Confirm plus Holdout gives roughly 400, which is enough only for the new candidates. **A null is the likely result.** It is published, and the banner says so.

**A6–A8.**
- **G1:** resume the plan in `g1dry`, which already has `R/features_asof.R` and `R/predict_core.R`. Its `injury_scalp.R` edit is an owner STOP.
- **G2:** term admission is S3 run on C3 variants over 2018–22. The order and α are pre-hashed in `nfl_mu_admission_v1.json`. Each term gets accuracy labels (Brier, plus CRPS of margin and total) and market labels (B1[C3] against the close), and the placebo term must be rejected.
- **G3:** sign `nfl_games_v2`, score Confirm, then open the shared 2025 Holdout once (owner checkpoint 7).

## Track B1: the always-on validation banner (the owner's "note largely at top")

- **Content.** `bannerState(gates, metrics, windows, fieldLine)` in `web/src/lib/validationBanner.ts` is a pure function. It builds every figure from ingested rows: protocol, seasons, n, the best skill with its CI, and CLV status. With no evidence ingested it shows the strictest wording.
- **Copy it replaces:** the hard-coded "570 games" in `policy.ts:59`, the Tune 2018–22 text on the game page, and the small notes in `fieldLineNote`/`fieldLineShortNote` (`policy.ts:55-72`), which become the banner's details.
- **Rendering.** `ValidationBanner` is server-rendered in `app/layout.tsx` above `{children}`: full width, with an icon and a label, no clock and no client state. It is therefore pixel-identical offline and online (`@parity` with no new mask).
- **Contract.** The backtest manifest gains `protocol_id`, and ingest sets a pointer `backtest:<protocol_id>`.
- **Tests:** table-driven vitest, plus an e2e that the banner is on every page.

## Track B2: perfected spacing, context and professional HTML

- **Tokens.** Add type, spacing, radius and section-gap tokens in `@theme` (`web/src/app/globals.css`). A `tokens.test.ts` ratchet means the arbitrary-utility count can only fall, and `text-[Npx]` is allowed only in `ui.tsx` and `Field.tsx`.
- **One component of each kind** in `web/src/components/ui.tsx`:
  - `Section`;
  - `PageHeader`, with a breadcrumb or context slot showing the run, week and data date;
  - Card variants;
  - `SectionTitle`;
  - `StatTile`;
  - `DataTable`, with caption, `scope` and `<time dateTime>`.

  These replace the six paddings, eight table copies and three hand-copied titles.
- **Bugs:**
  - Render the phone flags inside `Field`, with an e2e check that each flag sits on its marker within 1 px at 390, 768 and 1440 px.
  - The game page's top offset.
  - A two-row mobile header.
  - A 44 px theme control, with the theme stored in a cookie and rendered server-side so it never flashes.
  - Add `loading.tsx` and `error.tsx`.
- **Context.** Every number carries its label, unit and source line. Definitions are linked to `/methodology`, and each page states which run and when its data is from.
- **LCP:**
  - One `publicGates()` query wrapped in React `cache()` replaces `evidence()`'s seven queries on the home and game pages.
  - The page's queries run with `Promise.all`.
  - Measure with five-run A/B medians against main; the target is a mobile LCP under 2.5 s.
- **Professional HTML:** per-page `metadata`, landmark audit, axe best-practice rules, and a print stylesheet for the game and evidence pages.

## Track B3: React Bits, all concepts tested, the best one shipped (owner checkpoint 5)

**Bake-off worktree:** `nfl-worktrees/rbits`. It is never merged, and test-only dependencies are allowed in it. One build serves every concept: the env flag `DESIGN_CONCEPT` sets `<html data-concept>`.

| Concept | Idea | Components (adapted) | New dependencies |
|---|---|---|---|
| Control | Today's design with B2 applied | – | – |
| A, Scoreboard | Probabilities roll like a stadium board | Counter odometers (the server renders the final value), CountUp, FadeContent below the fold | gsap (Counter needs none) |
| B, Turf grid | Field geometry as texture | ShapeGrid as static 5-yard hash marks, DotGrid that settles behind the game hero | none (2D canvas) |
| C, Telestrator | Broadcast pen strokes in market blue and model gold | Threads or Beams (WebGL2, no dependency) behind the home hero; SplitText on section titles, never the LCP h1 | gsap, @gsap/react |
| D, Effects | The owner asked for effects if accessible | SpotlightCard and GlareHover on cards, ShinyText on the wordmark, all tokenized | none |

**Every concept is adapted:**
- colours from tokens, re-read when the theme changes;
- live reduced-motion handling with a static first frame;
- paused when off-screen;
- a same-size placeholder in the server render;
- no inline `<style>`, no `blob:`, no three.js, no CDN or remote fonts.

**Gates, pass or fail:**
- screenshots at 3 widths × 2 themes, with and without reduced motion, on a contact sheet published as a private Artifact for the owner;
- Lighthouse mobile medians, with LCP under 2.5 s and CLS under 0.1;
- axe, with no serious or critical issues;
- reduced motion: no `requestAnimationFrame` calls after settling, and identical canvas frames;
- `@parity` with zero differing pixels;
- background contrast at most 1.3:1 against the surface, with the text contrast on top still AA;
- First Load JS no more than 25 KB gzipped above Control.

I review the screenshots myself. The owner picks among the concepts that pass.

**Rollout:**
- Vendor the winners into `web/src/components/vendor/react-bits/`. Copy each file from pinned SHA `c2a1408` with `gh api`, not the shadcn CLI, and give it a header with its source path, SHA, license and changes.
- `THIRD_PARTY_NOTICES.md` carries the full MIT + Commons Clause text, "Copyright (c) 2026 David Haz". A `thirdPartyNotices.test.ts` checks every vendored file.
- Amend spec §4 in the owner's words.
- slopScan gains `vendor-header` and `canvas-scope` rules, and is relaxed only for an explicit allowlist when concept D or another effect wins.
- designLanguage allows backgrounds only through `<Backdrop aria-hidden>`.
- Adding `gsap`, `@gsap/react` or `motion@12` is confirmed at this checkpoint.

## Track B4: editing and offline, identical online

- **E1, run and week picker.**
  - `listWeeklyRuns()` returns the QA-passed runs; `resolveRun()` reads `?run=`.
  - The game page looks for the newest run that contains the game, which fixes 404s on older games.
  - The picker is a GET form with a native select, so it works without JavaScript.
  - Today there is a single `weekly` pointer, in `web/src/lib/data/queries.ts:13-21`.
- **E2, desk notes and settings** (owner checkpoint 6).
  - Drizzle migration 0003 adds `desk_notes`, `app_settings`, `user_settings`, an append-only `publish_events` and `run_jobs`.
  - The server actions live in `app/desk/actions.ts`: `requireUser`, zod validation, `revalidatePath`. They cover notes, settings, and "Publish this run".
  - Settings change presentation only, never the gates.
  - Public queries cannot reach the desk tables (a test enforces it). The designLanguage page list gains `/desk/runs` and `/desk/settings`.
- **E3, run control** (the same panel offline and online).
  - **Offline:** `web/scripts/local/runner.ts` listens on loopback with a token and runs one job at a time.
    - It spawns `Rscript run_week.R` with an argument array and refuses 2025.
    - It parses the `Web bundle:` and `QA:` lines, then calls `ingestBundle`: live with no restart.
    - It can cancel a job by killing its process tree.
    - An `fs.watch` publishes runs started from the terminal.
  - **Online:** dispatch `weekly-sim.yml` through the GitHub API with a fine-grained token in the Vercel environment. The workflow gains a `job_id` input and a final `if: always()` status step.
  - **Without a runner,** the server shows the same panel saying "this server cannot start runs". The panel and the job history are read from the database, so offline and online render identical pixels.
- **E4, live-edit dev mode.** `npm run local:dev` uses the same cluster, ingest and runner with `next dev` hot reload. It adds a `NFL_LOCAL_PORT` setting, detects the PostgreSQL install, and seeds the desk user from environment variables.
- **E5, full run offline.** nflreadr's own cache expires after 24 hours, so a snapshot is needed:
  - `scripts/snapshot_week.R`, run online, records every input URL (the nflreadr `*_from_url` reads, Open-Meteo, Sleeper) into `data/snapshots/<cycle>/MANIFEST.json` with sha256s.
  - `run_week.R --offline=<dir>` replays only from the snapshot.
  - A missing file is a loud failure, or a QA failure that names the missing URLs. Never a silent fallback.

## Owner checkpoints
1. **A0:** the capture horizon constant, the cron change, and the archive workflow (`contents: write`).
2. **#205's screen code as the framework's base:** merge or port it.
3. **Sign `nfl_preclose_v1`:** IS-A against IS-B, and the shared Holdout.
4. **The G1 engine edits,** including `g1dry`'s `injury_scalp.R`, plus P1's deletions and duplicate-loader removal.
5. **The design concept, its dependencies,** the spec §4 text and the slopScan changes.
6. **Migration 0003,** the dispatch token, and the new workflow input.
7. **Opening the 2025 Holdout,** with or without C3.
8. **Every merge,** and the D1 terms-of-service sign-off.

## Verification
- **Model:**
  - `HOME=<fresh> Rscript scripts/run_tests.R`, `verify_repo_integrity.R` and `run_matrix.R`.
  - The VVF known-answer tests.
  - Scoring refuses a protocol that isn't frozen.
  - A second run reproduces `result_sha256`.
  - The controls pass.
  - Golden master: "no differences" for A3 and A4, and CI-attributed changes for G1 and G2.
  - Ledger rows exist for every result, including nulls.
- **Web:**
  - `npm run typecheck`, `npm run lint`, and `npx vitest run` with `REQUIRE_DB_TESTS=1` against the scratch PG on 5436.
  - The full Playwright suite, including `@parity` (zero differing pixels, only `[data-age]` masked), axe at 3 widths × 2 themes, reduced motion, and the flag-geometry spec.
  - Lighthouse with mobile LCP under 2.5 s.
  - The slopScan, designLanguage, docsTruth, tokens and thirdPartyNotices tests.
- **Editing and offline:**
  - pg integration tests for the actions; desk e2e flows; runner tests against a stub Rscript.
  - The 2024 week 15 snapshot replayed with `--offline` matches the golden master; a deleted snapshot file makes the run fail clearly.
  - `npm run local` and `local:dev`, offline then online, give the same screenshots.
- **Tools:**
  - The Playwright and Chrome DevTools MCPs: they timed out this session, so use the Playwright CLI and the Lighthouse CLI as fallback.
  - The dataviz skill for the line-movement chart.
  - The frontend-design skill for the concepts.
  - An Artifact for the concept contact sheet.
  - `gh` for CI.

## Risks
| Risk | Handling |
|---|---|
| Underpowered nulls | Pre-register the MDE and publish nulls; the banner reports them |
| Opener timing unknown | IS-A is primary; 2026 prices carry timestamps |
| Cron lag and artifact expiry | Kalshi candles and labelled closes; the archive job runs before 2026-12-28 |
| Canvas frames differ between runs | That concept fails its gate; no new mask is added |
| Commons Clause | Notices are kept; the components are never redistributed on their own |
| Runner abuse | Loopback only, a token, login, an argument array with no shell |
| nflreadr internals change | A test checks that the hooked functions exist |
| API limits | At most two lanes; briefs, logs and ledgers stay on disk; resume with SendMessage |

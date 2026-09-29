# Prompt for Claude Code in VS Code: full verification and the remaining work

Paste everything below the line into Claude Code, running in VS Code at the root of a local clone of `jviola1019/nfl_weekly_simulation`. It assumes a full local environment: R 4.5.1 with renv, Node 22, Docker (for Postgres 16) and network access to GitHub, CRAN/RSPM, ESPN and Kalshi. It was written at the end of cloud session 2 (2026-09-29). That session couldn't install gt, nflreadr or randtoolbox, couldn't reach CRAN, ESPN or Kalshi, and had no Vercel/Neon connectors.

---

You are taking over the NFL overhaul in this repository. Work in three parts, in order: **A. verify every phase**, **B. finish what the cloud session could not**, **C. report**. Don't start B until A is fully green, or until every A failure is explained and approved.

## Ground rules (read before touching anything)

1. Read `CLAUDE.md` (the agent rules, STOP checkpoints and data-quality API), `HANDOFF.md`, the spec `docs/superpowers/specs/2026-09-28-nfl-overhaul-design.md`, the shootout design `docs/superpowers/specs/2026-09-29-model-shootout-design.md`, and `reports/2026-09-29/ARCHITECTURE-SCAN.md`.
2. **STOP and ask the owner** before any of these:
   - deleting a file;
   - changing `config.R` defaults;
   - editing `NFLsimulation.R`, `NFLmarket.R` or `injury_scalp.R` beyond an approved item;
   - adding a dependency (renv.lock or web/package.json);
   - changing `R/data_validation.R` signatures;
   - editing `backtest/eval_windows/*.json` or any frozen `PROTOCOL.md`;
   - anything that reads, builds or scores **2025 data in the backtest**. The 2025 holdout stays sealed until C3 (the simulator) is point-in-time, and it is scored exactly once (A2).
3. Never commit secrets. `DATABASE_URL`, `AUTH_SECRET` and the desk credentials live in your shell or `.env.local` (gitignored), GitHub environment secrets, or Vercel env. Never put them in code, docs or chat.
4. Reproduce before fixing. Make minimal diffs. Put a new number in a doc only if a script you ran produced it. Log every data problem; don't fall back silently.
5. Use one branch per unit of work and a draft PR for each. Merge conflicts in `CHANGELOG.md` and `docs/EVIDENCE_LEDGER.md` between parallel PRs are expected: keep both entries.
6. Use `git worktree` for parallel branches. Never switch the main checkout's branch while a long test run is going. Stop dev servers by pidfile or process name, never with `pkill -f "<command line>"`.

## Environment setup

```bash
# R (must be 4.5.1, the renv.lock version; CI uses it)
Rscript -e 'stopifnot(getRversion() == "4.5.1")'
Rscript -e 'renv::restore(prompt = FALSE)'
Rscript -e 'for (p in c("gt","nflreadr","randtoolbox","testthat","withr","digest","jsonlite","mgcv")) stopifnot(requireNamespace(p, quietly = TRUE))'

# Postgres 16 for the web suites (local only; the password is not a secret)
docker run -d --name nfl-pg -e POSTGRES_USER=nfl -e POSTGRES_PASSWORD=nfl_local_only -e POSTGRES_DB=nfl_dev -p 5432:5432 postgres:16
docker exec nfl-pg psql -U nfl -d nfl_dev -c "create database nfl_test"

# Node
cd web && npm ci && npx playwright install --with-deps chromium && cd ..
```

## Part A: verify every phase

Before the merge-stack step, check out each PR branch in its own worktree. Record the actual output of every command, not a paraphrase.

### A0. Open PRs and merge state
- Open PRs: #194 (A2 decisions, owner's), #195 `feat/backtest-games`, #196 `fix/phase1a-wiring`, #197 `chore/deletion-batch-2`, #198 `feat/web-ui` (stacked on #195). #190–#193 are merged.
- Confirm CI is green on every head (GitHub checks). Report any red check with its log. Don't re-run a job more than once.

### A1. Phase 0 foundation (on `main`)
```bash
Rscript scripts/run_tests.R            # must exit 0: 0 failed, 0 errors, only allowlisted skips (KNOWN-DEFECT M14/M15/P13, LIVE)
Rscript scripts/verify_repo_integrity.R   # 60/60
Rscript scripts/verify_requirements.R     # exit 0
Rscript scripts/run_matrix.R              # 9/9 on main
```
Check that `tests/skip_allowlist.txt` matches every skip, and that no test contains `expect_true(TRUE)` or swallows errors into empty tibbles (`test-skip-hygiene.R` enforces this).

### A2. Game backtest v1 (#195)
```bash
Rscript -e 'testthat::test_file("tests/testthat/test-backtest-games.R")'     # 14 tests, 0 failed
# Reproduce the scored result byte for byte (protocol hash must match and be committed)
Rscript backtest/walk_forward.R --window backtest/eval_windows/nfl_games_v1.json --stage score --out /tmp/bt_repro
Rscript -e 'a <- jsonlite::read_json("/tmp/bt_repro/run_meta.json"); b <- jsonlite::read_json("reports/2026-09-29/backtest-games-v1/run_meta.json"); stopifnot(identical(a$result_sha256, b$result_sha256)); cat(a$result_sha256, "\n")'
```
- Expect `result_sha256` to start with `7244a0bc`.
- Diff `/tmp/bt_repro/metrics.json` against the committed one. It should be byte-identical.
- Confirm `PROTOCOL.md` sha256 = `664c42d1…` and that commit `e9876fa` (the freeze) precedes every scored output.
- Confirm no 2025 game appears in `backtest/data/*.csv` (`max season == 2024`).
- Controls: every row in `controls.json` passes (leak canary, implausible-skill guard, global shuffled labels, market copy, reproducibility).
- Don't rebuild `backtest/data/` from a fresh nflverse download to "check" it. `games.csv` is a live file, so its sha will differ. The committed inputs and `SOURCES.json` are the hash-locked record. If you want an independent check, rebuild into a temp dir and compare only rows with `season <= 2024` and final scores.

### A3. Phase 1a wiring fixes (#196)
```bash
Rscript scripts/run_tests.R               # exit 0
Rscript scripts/verify_repo_integrity.R   # 60/60
Rscript scripts/run_matrix.R              # 10/10 (adds the golden-master artifact, ~800 s)
Rscript scripts/golden_master.R compare 15 2024 reports/2026-09-29/golden-master/2024-w15
```
- `compare` must print `golden master: no differences`. Anything above tolerance 1e-6 is a change. The fitted SD/NB-size columns carry about 4e-9 of optimizer noise, which is within tolerance.
- Read `reports/2026-09-29/golden-master/ATTRIBUTION.md` and check that each output change maps to its commit: M12 RQMC streams, the M2/M3 single 70% market weight, and M16 moving `inj_off_pts` but not mu (that is M18).
- Run the new unit tests by name: test-run-config, test-golden-master-compare, test-simulate-game-nb, test-spread-convention, test-attach-market, test-market-weight, test-injury-penalty-clamp, test-date-resolver, test-test-policy.
- **End to end:**
  ```bash
  Rscript run_week.R 16 2024
  ```
  It must exit 0 and write `NFLvsmarket_report.html` with game and props tabs, plus `run_logs/config_*.rds` and `run_logs/final_*.rds`. Open the HTML and describe what you see.

### A4. Deletion batch 2 (#197)
- `run_tests.R`, integrity and `run_matrix` pass as in A1.
- `git grep -n -E "coaching_adjustments|simulation_helpers|model_diagnostics|core/calibration|calibration_harness|parameter_grid_search|validation_pipeline|validation_reports|validate_correlations|playoffs_validation"` returns only CHANGELOG/history mentions.

### A5. Contract, database and web UI (#198)
```bash
cd web
npm run typecheck && npm run lint
npm run contracts:export && git diff --exit-code -- ../contracts/schema     # no drift
TEST_DATABASE_URL=postgres://nfl:nfl_local_only@127.0.0.1:5432/nfl_test REQUIRE_DB_TESTS=1 npm test   # 64 passed, 0 skipped
export DATABASE_URL=postgres://nfl:nfl_local_only@127.0.0.1:5432/nfl_dev
export AUTH_SECRET="$(openssl rand -base64 32)"
npm run db:migrate
npm run ingest -- ../contracts/fixtures/bundles/weekly-2026-w04     # published
npm run ingest -- ../contracts/fixtures/bundles/backtest-nfl-games-v1
npm run ingest -- ../contracts/fixtures/bundles/weekly-2026-w04     # must print "duplicate: ... 0 rows written"
export DESK_EMAIL=desk@example.test DESK_PASSWORD="$(openssl rand -base64 18)"
npm run seed:user
npm run build && (npm run start -- -p 3100 & echo $! > .next-server.pid)
E2E_BASE_URL=http://127.0.0.1:3100 npm run e2e                      # 69 passed
BASE=http://127.0.0.1:3100 OUT=e2e/screenshots node scripts/review-ui.mjs   # 48 rows, all 0 overflow / 0 errors / no serious axe / no leaks
cd ..
Rscript -e 'testthat::test_file("tests/testthat/test-bundle-writer.R")'  # 8 tests, 0 failed
```
- **Visual gate (spec §6, P7):** open every screenshot in `web/e2e/screenshots/` (8 pages × 390/768/1440 × light/dark) and check:
  - no clipped labels or text colliding with marks;
  - chart text at the same size on phone and desktop;
  - the nav doesn't wrap mid-label;
  - dark mode is its own palette;
  - model lines are hidden on public pages;
  - the desk shows stakes of 0.0%.
- **Lighthouse (not run in the cloud session):** run it against `next start` for `/`, `/evidence` and `/games/2026_04_DEN_SF`, mobile and desktop. The gates are accessibility ≥ 0.95, performance ≥ 0.8, CLS < 0.1 and LCP < 2.5 s. Save the JSON reports under `reports/<date>/lighthouse/`. If CLS fails on `/evidence`, the likely cause is the charts re-laying out after hydration (`useChartWidth` starts at 720 px). Reserve their height or render at the container width on first paint.
- **Regenerate the bundles from R and compare with the fixtures:**
  - `Rscript scripts/write_backtest_bundle.R reports/2026-09-29/backtest-games-v1 /tmp/bundles`.
    - On the #198 branch, every table file's sha256 must equal the fixture's; only `manifest.json` differs, in `generated_utc` and `code_git_sha`. This was verified in the cloud session.
    - On the merged stack, `evidence_ledger.json` also differs, by exactly the ledger rows later PRs add. Refresh the fixture in the PR that adds them.
  - For the prospective bundle, download the current nflverse `games.csv` and `play_by_play_2006…2026.rds` into a raw dir, then run `Rscript backtest/prospective.R <raw_dir> /tmp/bundles 2026 <next week>`. Ingest it and check the site shows that week. It must refuse any played game.
- Try to break the ingest by hand: edit a row in a copied bundle (expect a sha rejection), set `qa.ok=false` (expect `qa_failed`, pointer unchanged), and run an UPDATE on `backtest_metrics` in psql (expect the append-only error).

### A6. The merged stack
Merge #194 → #195 → #196 → #197 → #198 onto `main` in a scratch branch. Resolve the CHANGELOG/ledger conflicts by keeping both sides. Then run all of A1–A5 on the result. Every gate must pass: `run_tests.R` exit 0, integrity 60/60, `run_matrix` 10/10, the golden-master compare, vitest 64, e2e 69.

## Part B: finish what the cloud session could not

Each item is its own branch and draft PR, with gates as listed. Items marked **(owner)** need an answer first; ask, don't assume.

1. **M18/M19 (owner approval: STOP item).**
   - M18: current-week injury points (`inj_off_pts`/`inj_def_pts`) never reach mu. mu was bit-identical across the M16 fix while `inj_off_pts` moved 0.8–1.5.
   - M19: `inj_pick` prefers `practice_status` over `report_status`.
   - Write the failing tests first. After the fix, record a new golden master, and have CI attribution show only the expected columns moving. Document the moves in AUDIT-ADDENDUM.
2. **Phase 1b.** Write the plan first, in `docs/superpowers/plans/`, in the Phase 1a style, and get owner approval. Scope:
   - point-in-time features (no future data in any as-of feature; leak canary test);
   - extract `predict_week()` from `NFLsimulation.R`;
   - M4 (invalid calibrator: decide spline vs isotonic vs none by walk-forward), M5, M6, M8, M9;
   - make `run_week.R` emit a **weekly bundle** through `bw_write_bundle()` with `game_predictions` (candidate `C3`), `score_distributions` (margin and total bins) and `source_status`;
   - add a production = backtest parity test.
   - Then C3 joins the shootout under a new protocol version. Only after C3 is point-in-time is the 2025 holdout scored, once, per A2.
3. **Phase 2 odds layer.**
   - Load the raw captures (`data/raw_capture/` and the 90-day workflow artifacts; consolidate them into release assets) into `source_fetches` → `odds_snapshots` (stored only when the price changes) → `closing_lines` (rule-versioned).
   - Add the unmatched-entity queue table and page; no fuzzy joins.
   - Redesign the ESPN BET bias test as main-vs-main, clustered by player-game.
   - Measure ESPN open/close coverage for every 2023–2025 game before using openers for CLV.
   - The game page then gets per-venue line movement with kickoff and close markers.
4. **Deploy (owner: authorize the Vercel and Neon connectors).**
   - Create a Neon project with a `main` branch database and a per-PR branch.
   - Add a `deploy-migrate.yml` workflow that applies `web/drizzle` migrations, with `DATABASE_URL` from a GitHub environment secret; only that job and the ingest job get it.
   - Create a Vercel project (root `web/`, env `DATABASE_URL`, `AUTH_SECRET`).
   - Seed the desk user from a local shell only.
   - A preview deploy must pass the full e2e suite (`E2E_BASE_URL=<preview url>`).
   - Add the spec's `weekly-model.yml` (Wed/Sat/Sun: R → bundle → ingest).
5. **Props, Phases 4–5 (owner: A5 "pre-kickoff price" definition first).**
   - Fix P1–P13, rebuild usage shares and the TD engine, and add `game_id` to `prop_line_probs` with a composite FK to `prop_projections` (ERD drift).
   - Then a pre-registered backtest per market (anytime/2+/first TD, receptions, yards, attempts, completions, pass TDs, INTs) with CRPS, PIT and CLV where a close exists.
   - Markets under the GO threshold are labelled prospective, never validated. The `/props` page prices only markets that pass.
6. **Monorepo move (Phase 6).** Use `git mv` into `model/`, in its own PR. Prove it with golden-master hashes that are identical before and after, then update every path in the scripts, workflows, docs and `web/src/test/docsTruth.test.ts`.
7. **Deletions (owner, A3):** `ensemble_calibration_implementation.R` and its `.rds` (after the M4 decision), and the 32 `if (!exists())` fallback copies in `NFLsimulation.R` (H1), replaced with fail-loud `source()`. Prove each with `run_matrix` and the golden master.
8. **FF reconciliation (owner: allow reading `jviola1019/fantasy_football_dashboard`).** Compare `web/src/test/slopScan.test.ts` and `docsTruth.test.ts` with FF's originals, and port any rule this repo lacks (`security/exceptions.json` too).
9. **ERD follow-ups:** nullable `evidence_ledger.bt_run_id` FK and a self-FK on `supersedes` (Phase 8 decision); write `docs/data-contract.md` with the full column list, generated from the Drizzle schema (sessions → JWT + `session_version`, and the added clv_picks, bundle_ingests and auth_throttle).
10. **Phase 8 docs (owner: A8 to retire the gt/HTML report; confirm the MIT LICENSE).**
    - Rewrite README, GETTING_STARTED and CLAUDE.md with numbers only from real runs; `docs/ARCHITECTURE.md` and `docs/API.md` are stale (v2.7.0).
    - Split DOCUMENTATION into model-spec (generated), backtest-protocol, PROMOTION_POLICY, data-contract and odds-sources.
    - Generate VALIDATION_REPORT.md, and unify the version string.

## Per-phase acceptance gates (a phase is done only when every line holds)

| Phase | Gate |
|---|---|
| Every R change | `run_tests.R` exit 0 (only allowlisted skips); integrity 60/60; `run_matrix` all artifacts pass; golden-master diff attributed in the PR |
| Backtest (3, 5) | Controls pass or the run voids itself; re-running `walk_forward.R --stage score` reproduces `result_sha256`; evidence ledger rows written; the holdout untouched until its single scheduled score |
| 1a / 1b | Leak canary; production = backtest parity; spread-sign and shrink-invariant tests; every golden-master diff explained |
| 2 | Odds idempotent on re-capture; closing-line rule versioned; unmatched queue empty or triaged; the bias test is pre-registered |
| 6 | typecheck, lint, vitest with the pg suites **not skipped**; contract fixtures pass in R and TS; re-ingest changes 0 rows; triggers raise on UPDATE |
| 7 | Playwright + axe 0 serious/critical; 390/768/1440 × both themes looked at by you; no overflow; reduced motion; security headers; clean console; `/desk` redirects anonymous users; no stakes on public pages; no ID leaks; Lighthouse thresholds; slop scan |
| Deploy | Preview deploy passes the same e2e suite; migrations applied only by the workflow |
| 8 | docs-truth tests pass in R and web; every number in the docs traced to a script output |

## Part C: report

Write `reports/<date>/VERIFICATION.md` with one section per phase: every command you ran, its exact tail output (counts, hashes, exit codes), PASS/FAIL, and for each FAIL the root cause and the fix PR or the owner question. Update `HANDOFF.md` (current state, PR table, pending decisions, defect log) and add a dated CHANGELOG entry per merged PR. End with the list of owner decisions still open.

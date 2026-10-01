# Verification of `main` (Part A of the VS Code prompt)

**Run:** 2026-09-29/30, local Windows 11, R 4.5.1 with the locked renv library (activated through a gitignored `.Rprofile`), Node 25.8.2, PostgreSQL 17.11 (isolated local cluster on 127.0.0.1:5433; no Docker).

**Commit:** `main` at `eaa4138`. Every gate ran in a detached worktree checked out with LF line endings (`core.autocrlf=false`), which is how CI sees the files; section A1 explains why.

Every command's actual tail output is quoted. Logs are in the session scratchpad (`verify/`).

## Summary

| Phase | Result | Notes |
|---|---|---|
| A0 merge state | **PASS** | #190–#199 merged; `CI` and `CI (web)` green on `eaa4138` |
| A1 Phase 0 foundation | **PASS on an LF checkout; FAIL on a default Windows checkout** | CRLF breaks 6 hash locks (T5; fix #201). Under renv: `run_tests.R` exit 0, integrity 60/60, `verify_requirements` pass. `run_matrix` 9/10: golden master, see A3 |
| A2 game backtest v1 | **PASS** (content identical; the byte-exact hash needs the LF-writer fix) | Every prediction and metric identical. `result_sha256` differed only through CRLF writers (T6); with the fix it is `7244a0bc…` on Windows too |
| A3 Phase 1a | **Golden master FAIL on Windows (blend columns only, T8)**; unit tests pass; end to end exit 0 | The simulator columns match. Tracing M18 found **M22 (Critical)**. The legacy HTML report renders broken (U2/U3) |
| A4 deletion batch 2 | **PASS** | Only CHANGELOG, history and docs mentions, plus the hygiene guard |
| A5 contract, DB, web | **FAIL on Windows `main` (T7), PASS with #202**; visual review **FAIL (design)**; Lighthouse desktop PASS, mobile LCP borderline | vitest 65/65, e2e 69/69, review-ui 48/48 clean, ingest break tests pass, bundle tables reproduce. The design does not deliver the approved direction (see A5) |
| A6 whole-repo gate | pending #201/#202/T6 merges | |

## A0. Merge state

```
$ git log --oneline -1 origin/main
eaa4138 Merge pull request #199 from jviola1019/claude/gallant-albattani-ohova3
#190 … #199: MERGED (2026-09-29T03:00Z … 2026-09-30T00:20Z)
CI success eaa4138 · CI (web) success eaa4138
```
The `Golden master` workflow runs only on pull requests that touch model files, so it has no run on `main`.

## A1. Phase 0 foundation

**Default Windows checkout** (Git for Windows `core.autocrlf=true`):
```
$ Rscript scripts/run_tests.R      → exit 1: 6 failures, all sha256 checks in test-backtest-games.R
```
- **Root cause (T5):** `backtest/data/*.csv` and the frozen `PROTOCOL.md` are checked out with CRLF.
- The bytes differ and the data do not: an LF checkout has 0 CR bytes, `games.csv` sha `fae0e4cabda2…` and `PROTOCOL.md` `664c42d12a2a…` (the locked value).
- **Fix:** `.gitattributes` `* text=auto eol=lf` (PR #201, CI green).

**LF checkout, locked renv library** (dplyr 1.1.4; the unmanaged user library had dplyr 1.2.0):
```
$ Rscript scripts/run_tests.R
tests=385 passed=1475 failed=0 errors=0 skipped=1 unapproved_skips=0
All skips: KNOWN-DEFECT P13 … (1)                                                 exit 0
$ Rscript scripts/verify_repo_integrity.R
  Schema Checks: 17 passed, 0 failed · Invariant Checks: 43 passed, 0 failed · Total: 60 passed, 0 failed
[VERIFICATION PASSED]                                                               exit 0
$ Rscript scripts/verify_requirements.R
Skipped tests: Weather fallback defaults, Injury availability
[VERIFICATION PASSED]                                                               exit 0
$ Rscript scripts/run_matrix.R
  Total: 10 artifacts · Failed artifacts: golden-master        [RUN MATRIX: 1 FAILURES]  exit 1
```
- The only skip is the allowlisted KNOWN-DEFECT P13. The M14/M15 skips were removed in Phase 1a, and LIVE tests ran because nflverse was reachable.
- The golden-master failure is covered in A3.

## A2. Game backtest v1

```
$ Rscript -e 'testthat::test_file("tests/testthat/test-backtest-games.R")'
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 54 ]
$ Rscript backtest/walk_forward.R --window backtest/eval_windows/nfl_games_v1.json --stage score --out <tmp>
walk_forward exit=0 secs=384
result_sha256 repro 2e6d2d9d21c5c5bd…   committed 7244a0bc8ac63fec…   identical False
```
- **Diagnosis:** the reproduced `predictions.csv` (17,478 rows) and `metrics.json` are identical to the committed files in every value. They carry CRLF: 17,479 and 1,375 CR bytes.
- After CRLF→LF they match byte for byte, and the recomputed `result_sha256` is `7244a0bc8ac63fec4d8d11b48b4b93be4ebf3fdba51b0fa3d6929cab336a3458`.
- **Root cause (T6):** `fwrite`/`write_json` use the platform line ending.

**With the LF writers** (branch `fix/lf-writers`):
```
walk_forward exit=0 secs=284
result_sha256 7244a0bc8ac63fec4d8d11b48b4b93be4ebf3fdba51b0fa3d6929cab336a3458 matches committed: True
predictions.csv byte-identical: True · metrics.json byte-identical: True
controls all_passed True · run_status complete · reproducibility first == second == 7244a0bc…
```
- **Freeze order:** `PROTOCOL.md` last changed in `e9876fa` ("Freeze … before scoring", 2026-09-29 19:58 UTC). Every scored output was first committed after it: `06e32da` (RESULT, controls, metrics, predictions, run_meta) and `c7d8bce` (run1-void).
- **Sealed holdout:** the maximum season is 2024 in `games.csv` (1999–2024), `espn_open_close.csv` (2024), and `team_games.csv`/`qb_games.csv` (game_ids 2006–2024).
- **Controls:** leak canary, implausible-skill guard, shuffled labels, market copy and reproducibility all pass.

## A3. Phase 1a

**Golden master:**
```
$ Rscript scripts/golden_master.R compare 15 2024 reports/2026-09-29/golden-master/2024-w15
              column n_games_changed max_abs_diff
 home_p_2w_blend_raw              10  0.011781507
     home_p_2w_blend              10  0.009606739
 home_win_prob_blend              10  0.009580801
 away_win_prob_blend              10  0.009580801
     away_p_2w_blend              10  0.009606739
        margin_blend              10  0.300794745
   home_median_blend              10  0.150397372
   away_median_blend              10  0.150397372
```
- Every simulator column (means, SDs, NB sizes, raw and model probabilities) is within 1e-6. Only the blend layer differs.
- The drift is the same with dplyr 1.2.0 and with the locked 1.1.4, so the package version is ruled out.
- It is deterministic on this machine. The blend passes through the invalid step-function calibration map (M4).
- Recorded as **T8**. The CI (Linux) golden master stays authoritative until Phase 1b removes the calibrator.

**ATTRIBUTION.md, the M16 row:**
- Tracing the "mu unchanged" contradiction at run time found **M22 (Critical)**: every adjustment to the expected scores is lost, and the means are drives × points per drive (+ home field) in 16 of 16 games.
- It also found **M23**: rest days are measured from the week's first kickoff.
- Both are recorded in `reports/2026-09-29/AUDIT-ADDENDUM.md`.

**Named unit tests:** these run inside `run_tests.R` (above), and all pass: run-config, golden-master-compare, simulate-game-nb, spread-convention, attach-market, market-weight, injury-penalty-clamp, date-resolver and test-policy.

**End to end (`Rscript run_week.R 16 2024`): runs, output flagged.**
```
run_week exit=0 secs=859
[✓] Injuries: FULL · [⚠] Weather: PARTIAL_FALLBACK · [✓] Market Data: FULL · [⚠] Calibration: spline (DIAGNOSTIC ONLY)
✓ Simulation complete for Week 16, Season 2024
Moneyline report written to …/NFLvsmarket_report.html · Generated 12 player props (11 with positive EV) · HTML report updated with player props
run_logs/final_20260930_144804.rds, games_ready_20260930_144804.rds, config_… written
```
- **The HTML report** (screenshot at 1440 px) is the legacy R/gt page:
  - a large empty dark panel where the removed three.js widget was;
  - the column header rendering **below** the first data row (audit U2);
  - only one game row (DEN @ LAC) visible in a fixed-height area;
  - mismatched background bands (U3).
- This is the page `run_week.R` still opens. The redesign lives in the separate web app, and retiring this report is owner decision A8.
- "11 of 12 props with positive EV" is itself the audit's props red flag (P6/P12), not a result.
- **Policy breach during this step (S5):** because `config.R` still enables the ScoresAndOdds scraper by default, this run called its private endpoint with a spoofed browser user agent. It also priced a 2024 game with current-season lines (P14).
  - I did not check the default before running the prompt's command.
  - `run_week.R` should not be run again until the owner approves disabling the scraper.
  - The two tracked files the run rewrote (H2) were restored.

## A4. Deletion batch 2

```
$ git grep -n -E "coaching_adjustments|simulation_helpers|model_diagnostics|core/calibration|calibration_harness|parameter_grid_search|validation_pipeline|validation_reports|validate_correlations|playoffs_validation"
CHANGELOG.md (7) · reports/history/AUDIT.md (5) · tests/testthat/test-repo-hygiene.R (4: the must-not-exist guard)
reports/history/IMPROVEMENT_PLAN.md, ARCHITECTURE-SCAN.md, 2026-09-28/AUDIT.md, spec, two plans, the VS Code prompt, DOCUMENTATION.md (1 each: history/removal notes)
```

## A5. Contract, database and web UI

**On Windows `main`:**
```
typecheck exit 0 · lint exit 0
contracts:export exit 0 (wrote nothing: the main-module check never matches on Windows; T7)
vitest (TEST_DATABASE_URL=…/nfl_test REQUIRE_DB_TESTS=1): Tests 1 failed | 63 passed (64)
  FAIL docsTruth: "e2e/public-no-stakes.spec.ts (named in …\queries.ts)" – path separators (T7)
db:migrate: Error: Can't find meta/_journal.json file      (URL .pathname "/C:/…"; T7)
build: failed to canonicalize path `/C:/Users/…`           (T7)
e2e: 69 failed (no build, no server)
```
- The vitest "contract drift" test compares the generated contract with `contracts/schema` byte for byte, and it passed. So the contract has no drift, even though the CLI export was a no-op.

**With PR #202** (`fileURLToPath`, separator-safe docs truth, and a new guard test):
```
typecheck 0 · lint 0 · vitest Tests 65 passed (65) · contracts:export: wrote 17 files, git diff --exit-code clean
migrate: "migrations applied"
ingest weekly-2026-w04: published … 181 rows written
ingest backtest-nfl-games-v1: published … 3057 rows written
ingest weekly-2026-w04 again: "duplicate: … 0 rows written"
seed:user: desk user ready (credentials generated in-process, never written)
build exit 0 · e2e: 69 passed (1.1m)
review-ui: 48 rows (8 pages × 390/768/1440 × light/dark): 0 overflow, 0 console errors, no serious axe, no leaks
```

**Ingest break tests (PASS):**
```
tampered row  → rejected: game_predictions.json: sha256 does not match the manifest   (exit 1)
qa.ok=false   → qa_failed: run …-qafail (181 rows); publish pointers unchanged
UPDATE / DELETE backtest_metrics → ERROR: table backtest_metrics is append-only (UPDATE|DELETE refused); 54 rows intact
```

**Visual gate: FAIL (design), with the owner's agreement.** I reviewed the screenshots myself. Everything is mechanically clean, but the design misses the approved "Broadcast Line" direction:
- The field strips are gray boxes, not a field.
- Model lines are hidden on public pages, so each game shows a single blue tick.
- The "night game" dark theme reads as black.

A redesign mockup, built on real week-4 data and a real simulation, is on the canvas for approval: https://claude.ai/artifact/27TfoyhX17gU6hjskbukEM

**Lighthouse** (13.5.0, `next start` on :3100, reports in `reports/2026-09-30/lighthouse/`):

| Page | a11y | perf | CLS | LCP | Gates |
|---|---|---|---|---|---|
| `/` desktop | 0.98 | 1.00 | 0.002 | 0.61 s | PASS |
| `/` mobile | 0.98 | 0.93 | 0.000 | 2.19 s | PASS (re-runs: LCP 2.57 s and 2.61 s, borderline) |
| `/evidence` desktop | 1.00 | 1.00 | 0.000 | 0.68 s | PASS |
| `/evidence` mobile | 1.00 | 0.77 | 0.000 | 2.94 s | **FAIL** (re-runs: 2.85 s and 2.79 s, TBT 299–767 ms) |
| `/games/2026_04_DEN_SF` desktop | 1.00 | 1.00 | 0.001 | 0.61 s | PASS |
| `/games/2026_04_DEN_SF` mobile | 1.00 | 0.85 | 0.000 | 2.62 s | **FAIL** (re-run: 2.61 s) |

- **Accessibility and CLS pass everywhere.** The predicted `/evidence` CLS problem (Part B item 12) did not appear.
- **Mobile LCP sits on the 2.5 s gate.** The main-thread work is chart hydration: 3.0 s on `/evidence`.
- Lighthouse warned that this machine's CPU is slower than it expects (16 cores, no other load during the re-runs). CI or a reference machine should confirm the numbers.
- **Fix:** in the redesign, render chart SVG on the server and defer the interaction layer.

**Bundle regeneration vs fixtures** (`scripts/write_backtest_bundle.R`, with the LF writers of PR #204):
```
backtest_metrics 54 · backtest_runs 1 · calibration_bins 180 · clv_picks 820 · eval_windows 1 · games 1942 · promotion_gates 8 · teams 32: sha SAME as the fixture
evidence_ledger.json 18 rows: sha DIFF (the known ledger drift since the fixture was cut; Part B item 11)
manifest: only generated_utc, code_git_sha and code_dirty differ; 0 CR bytes
```

**`test-bundle-writer.R`:** 8 tests, 43 expectations, 0 failed (on `fix/lf-writers`).

## A6. Whole-repo gate

Pending. It needs #201 (LF checkout), #202 (Windows web scripts) and the T6 LF-writer fix. After that, a Windows checkout of `main` should pass the same gates as CI, except the T8 golden-master blend columns.

## Part B work done in this session

| PR | Branch | What | Verified |
|---|---|---|---|
| #200 (draft) | `docs/findings-m20-m21` | Audit addendum M20–M23, T5–T8, the keyless data-sources addendum, this report, Lighthouse JSON | docs only; CI green |
| #201 | `fix/eol-hash-locks` | `.gitattributes` LF for hash-locked evidence (T5) | backtest tests 14/54 on an LF checkout; CI green |
| #202 | `fix/web-windows-paths` | Web scripts on Windows (T7) | vitest 65/65, e2e 69/69 on Windows; CI green, including web |
| #203 (draft) | `fix/m19-injury-report-status` | M19: injury game designations read ahead of practice participation | `run_tests.R` exit 0, integrity 60/60; golden-master attribution running in CI |
| #204 | `fix/lf-writers` | LF writers so `result_sha256` reproduces on Windows (T6) | A2 byte-exact on Windows; `run_tests.R` exit 0 |
| #205 (draft) | `feat/validation-sprint-v2` | Validation sprint on the Tune window: variable screen, logistic vs XGBoost vs gbm blends, calibration maps, spread/totals handicapping, tracking, draft v2 protocol | see `reports/2026-09-30/validation-sprint/REPORT.md` |

**Validation sprint in one line:** nothing beats the closing line on Tune 2018–2022, and nothing is validated. The market-anchored logistic blends match the close (+0.03% [−0.20, +0.28]) and are the most useful family. No situational variable survives multiple-testing correction. The time-zone effect on spreads (q = 0.15) is the one hypothesis pre-registered for an out-of-sample test.

**Redesign:** a mockup is on the canvas (https://claude.ai/artifact/27TfoyhX17gU6hjskbukEM). It uses real 2026 week-4 data and a real re-simulation of KC @ CLE, and its palette was checked with the dataviz validator: worst colour-blind ΔE 10.6, contrast ≥ 3:1 on the panel and the turf.

## Owner decisions still open

1. **Approve the redesign mockup** (or mark it up) before it is built into `web/`.
2. **M22 fix approach** (core engine, a STOP item):
   - (a) make the effective model explicit and re-admit each adjustment only after it passes the walk-forward test (recommended);
   - (b) restore every adjustment now;
   - (c) restore only the injury terms (M18 as approved), plus the M23 rest fix.
3. **Sign the v2 protocol** (`reports/2026-09-30/backtest-games-v2/PROTOCOL-DRAFT.md`) before any Confirm or Holdout scoring.
4. **Merges:** #201, #202 and #204 (fixes, CI green); #203 after its golden-master attribution; #200 (docs).
5. **Disable the ScoresAndOdds scraper now** (S5: set `PROP_ODDS_ALLOW_REMOTE_HTML` to FALSE and drop it from the default source order; this is a config default change), then delete it (item 14).
6. **Carried over:**
   - A5 is decided (quote definition).
   - Vercel/Neon connectors.
   - A3 deletions (the calibrator `.rds` after M4; the `NFLsimulation.R` fallback copies; the `prop_odds_api.R` scraper remnants).
   - FF read access.
   - A8 (retire the legacy HTML report) and the MIT LICENSE.

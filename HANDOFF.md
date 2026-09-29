# HANDOFF

Resume point for the NFL overhaul. Read this first, then the spec.

## Current state — 2026-09-29 03:15Z (Phase 0 in progress, A0 approved)

- **Spec (approved 2026-09-28):** `docs/superpowers/specs/2026-09-28-nfl-overhaul-design.md`
- **Phase 0 task plan:** `docs/superpowers/plans/2026-09-29-phase0-foundation.md`. It covers Tasks 1–6 and awaits the owner's review.
- **Audit ledger:** `reports/2026-09-28/AUDIT.md`
- **`main` = `cbaf3eb`:** PR #190 (forward capture) merged 2026-09-29 03:00Z.
- **The "Odds capture" workflow is live on GitHub.** The manual run 36515215104 succeeded: 184/184 requests, artifact 945 KB, expires 2026-12-28.

| Branch | Where | State |
|---|---|---|
| `feat/forward-capture` | main checkout `nfl/` | Merged (#190). The checkout can now move to any branch. |
| `docs/overhaul-spec` | worktree `../nfl-worktrees/overhaul-spec` | PR #191 open: spec, audit, HANDOFF, Phase 0 plan. |

**A0 approvals (2026-09-28):**
- the deletion batch
- untracking plus scoped settings
- deps plus CI
- the honest default
- push and PRs, and merging the capture PR

Merging #191 and the later Phase 0 PRs still needs approval.

## Context-reset packet

**Objective.** Make the model's numbers trustworthy, prove them with a pre-registered walk-forward backtest (games and props, incl. every TD market), then rebuild the UI as a Next.js app ("Broadcast Line") that only shows what the evidence supports.

**Done**
- Full read-only audit (M1–M13, P1–P12, S1–S4, U1–U10, T1–T4, H1–H2, D1, SEC1–4) with file:line evidence.
- Keyless data sources probed and chosen: nflverse, ESPN core API, Kalshi public API. No keys, no trials.
- Palette validated (dataviz validator, both themes, all pairs).
- Forward capture live: first run 2026-09-28 21:03Z, 186/186 requests OK, 0 hash mismatches.

**Not yet done (Phase 0 remainder)**
1. **A0 is approved, so execute plan Tasks 1–4 on `chore/phase0-foundation`:**
   - the deletion batch (with the plan's recorded deviations: keep `core/calibration.R`; the calibrator and golden master move to Phase 1)
   - untracking and scoped settings
   - testthat in renv (httptest2 in Phase 2)
   - CI R 4.5.1
   - CLAUDE.md edits
   - `STAKING_MODE = "paper"`
   - removing the three.js CDN script and escaping the fallback
2. Honest default: `docs/EVIDENCE_LEDGER.md` with every M7 claim as Withdrawn; report banner; `leakage_free = FALSE`.
3. Test harness: `setup.R` must `stop()` on a missing module (it only warns today); skip meta-test; fix T1; offline `run_matrix`.
4. Golden master for a seeded fixture week.
5. Keyless data spike report with the GO rule and the ESPN BET selection-bias test.

**Confirmed facts (verified this session)**
- The full suite on `feat/forward-capture` had 313 tests: 951 expectations passed, 0 failed, 0 errors, 51 skipped.
- `verify_repo_integrity.R`: 56 passed / 1 failed (pre-existing T1).
- `run_matrix.R`: 8/9 (the failing artifact is `verify_repo_integrity.R`).
- Kalshi 2026 TD markets: series `KXNFLTD` (1+/2+). The 2025 series was `KXNFLANYTD`. Settled markets are only under `/historical/...`.
- ESPN DraftKings propBets: lines only, no prices, gone after kickoff.

**Open risks**
- Kalshi prop history is short (~Dec 2025 onward), so many prop markets will start as prospective-only.
- The ESPN BET archive has partial pricing and possible selection bias.
- The 8,640-line `NFLsimulation.R` refactor.
- Workflow artifacts expire after 90 days; they need consolidating into release assets (Phase 2).

**Contradictions to resolve**
- Docs say 60% or 70% shrinkage; the code does neither (M2, M3).
- Docs claim correlations 0.75/0.60/0.50/0.40; config has 0.40/0.09/0.30/0.17.

**Next target.** The owner reviews the Phase 0 plan → execute Tasks 1–6 (subagent-driven, per spec §9) → Phase 1 (M1, then the golden master, then M2/M3, M10, M11, M12).

**Test-suite facts for the harness task:** the 51 skips break down as 34 "X.R not loaded/not found" (tests use `getwd()` = `tests/testthat` instead of `.test_project_root`), 5 "NFLmarket.R not loaded" (it sources `NFLbrier_logloss.R` relative to the working directory), 5 "empty test", 4 date resolution, 3 On CRAN, 1 missing export, 2 schedule loads. `setup.R` loads only 7 of 13 `R/` modules.

## Owner actions

- Approve A0 (list above).
- Before Phase 6: authorize the Vercel and Neon connectors (`/mcp` or claude.ai connector settings).

## Session defect log

| # | Defect | Evidence it was real |
|---|---|---|
| 1 | Switching the main checkout to another branch would have broken tonight's scheduled captures (the script exists only on `feat/forward-capture`) | Caught before the first scheduled run; docs work moved to a worktree |
| 2 | The local background captures for MNF (23:45Z, 00:08Z) never ran: the `sleep` timer stalled (likely machine sleep), and the job was still "waiting" at 03:00Z | The manifest had only the 21:0x entries. Recovery: Kalshi closes come back from `/historical` candles; only DraftKings line movement in the last 3h before kickoff is lost. The fix is GitHub-scheduled capture (#190), which doesn't depend on this machine. **Never rely on local sleeps for time-critical capture.** |
| 3 | The Phase 0 plan draft had a regex-escaping bug in the ledger parser (`"\\\\|"` with `fixed = TRUE`) and compared config `0.4` to the ledger text `"0.40"` as strings | Caught by running the parser on the real ledger text before handing off (7/7 claims matched, 2 near-miss strings correctly not matched) |
| 4 | Bash heredocs in this environment collapse `\\` to `\` even when quoted | A generated R script failed with "'\|' is an unrecognized escape". Write R scripts with the file tool, not heredocs. |

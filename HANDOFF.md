# HANDOFF

Resume point for the NFL overhaul. Read this first, then the spec.

## Current state — 2026-09-28 (Phase 0 in progress)

- **Spec (approved 2026-09-28):** `docs/superpowers/specs/2026-09-28-nfl-overhaul-design.md`
- **Audit ledger:** `reports/2026-09-28/AUDIT.md`
- `main` is unchanged at `7723e3b`. Nothing pushed.

| Branch | Where | State |
|---|---|---|
| `feat/forward-capture` | main checkout `nfl/` | Committed `a5ecde3`: keyless ESPN + Kalshi raw capture, tests, workflow. Not pushed. |
| `docs/overhaul-spec` | worktree `../nfl-worktrees/overhaul-spec` | Spec, audit ledger, reports/README, this file, `.gitignore` un-ignores `reports/`. |

**Why the main checkout must stay on `feat/forward-capture` tonight:** two background captures (≈23:45Z and 00:08Z, PHI@CHI MNF) run `scripts/capture_odds_raw.R` from it.

## Context-reset packet

**Objective.** Make the model's numbers trustworthy, prove them with a pre-registered walk-forward backtest (games and props, incl. every TD market), then rebuild the UI as a Next.js app ("Broadcast Line") that only shows what the evidence supports.

**Done**
- Full read-only audit (M1–M13, P1–P12, S1–S4, U1–U10, T1–T4, H1–H2, D1, SEC1–4) with file:line evidence.
- Keyless data sources probed and chosen: nflverse, ESPN core API, Kalshi public API. No keys, no trials.
- Palette validated (dataviz validator, both themes, all pairs).
- Forward capture live: first run 2026-09-28 21:03Z, 186/186 requests OK, 0 hash mismatches.

**Not yet done (Phase 0 remainder)**
1. **Checkpoint A0 (needs owner approval):**
   - the deletion batch (spec §5)
   - untracking `run_logs/` and `.claude/settings.local.json`, and scoping `.claude/settings.json`
   - adding `testthat` + `httptest2` to renv
   - CI R 4.5.1
   - CLAUDE.md edits
   - `STAKING_MODE = "paper"`
   - pushing branches and opening PRs (the capture workflow only runs on schedule after it reaches `main`)
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

**Next target.** Checkpoint A0 decision → Phase 0 remainder → Phase 1 (M1, M2/M3, M10, M11, M12 first).

## Owner actions

- Approve A0 (list above).
- Before Phase 6: authorize the Vercel and Neon connectors (`/mcp` or claude.ai connector settings).

## Session defect log

| # | Defect | Evidence it was real |
|---|---|---|
| 1 | Switching the main checkout to another branch would have broken tonight's scheduled captures (the script exists only on `feat/forward-capture`) | Caught before the first scheduled run; docs work moved to a worktree |

# HANDOFF

Resume point for the NFL overhaul. Read this first, then the spec.

## Current state — 2026-09-29 (Phase 0 complete in review; merges await owner approval)

| Artifact | Where |
|---|---|
| Spec (approved 2026-09-28) | `docs/superpowers/specs/2026-09-28-nfl-overhaul-design.md` |
| Model shootout design (draft, A2) | `docs/superpowers/specs/2026-09-29-model-shootout-design.md` |
| Phase 0 plan | `docs/superpowers/plans/2026-09-29-phase0-foundation.md` |
| Phase 1a plan (awaits A1a) | `docs/superpowers/plans/2026-09-29-phase1a-wiring-fixes.md` |
| Audit | `reports/2026-09-28/AUDIT.md` + `reports/2026-09-29/AUDIT-ADDENDUM.md` (M14, M15, M16, P13; on #192) |
| Measured market baseline | `reports/2026-09-29/market-baseline/` (no-vig closing Brier 0.2108 over 2,219 games, 2018–2025) |

| PR | Branch | State |
|---|---|---|
| #190 | feat/forward-capture | **Merged** (`cbaf3eb`). The GitHub "Odds capture" schedule is live (keyless ESPN + Kalshi). |
| #191 | docs/overhaul-spec | Open. Spec, audit, plans, shootout design, baseline, this file. CI red only on the pre-existing T4 (`rg` missing), which #192 fixes. |
| #192 | chore/phase0-foundation | Open. Phase 0 Tasks 1–4, close-out fixes, final-review fixes, M16 record. **CI green.** |
| #193 | spike/keyless-data | Open. Keyless data spike (Task 5). Needs a fresh CI event after #192 merges. |

**Phase 0 gates at #192 head** (run 2026-09-29; CI run 36603435228 green):
- `scripts/run_tests.R` exit 0: 340 tests, 1245 passed, 0 failed, 0 errors, 8 skips (6 × M14, 1 × M15, 1 × P13), 0 LIVE, 0 unapproved.
- `scripts/verify_repo_integrity.R`: 60/60.
- `scripts/verify_requirements.R`: exit 0.
- `scripts/run_matrix.R`: 9/9.
- The final whole-branch review simulated main + #191 + #192 + #193: no merge conflicts in any order, all gates green.

**Merge order:** #191 → #192 → #193. Any order is conflict-free. After #192, give #193 a new CI event ("Update branch").

## Owner decisions pending

1. **Merge** #191, #192, #193.
2. **A1a (Phase 1a):** approve the edits to NFLsimulation.R/NFLmarket.R/config.R and the deletions in the Phase 1a plan:
   - M1 week/season via options
   - one 70% market-weight stage (remove the anti-shrink and playoff variants)
   - M10 spread convention
   - M11 flagging
   - M12 per-game RQMC streams
   - M14, M15
   - **M16 inverted injury clamp** (new, High)
   - neutralized leaked-Brier console strings
3. **A2 (shootout protocol):** answer the three open questions in the shootout design:
   - the minimum number of recommendations for the betting-value gate (300 vs 500)
   - whether playoffs are in the headline
   - holdout timing
4. **A5 agenda (before any props backtest):** define "pre-kickoff price". The spike's GO verdict depends on it:
   - As a trade or a two-sided quote (report definition): every market is GO; the tightest margin is passing yards, +90 at the lower bound.
   - With a spread cap ≤ 0.05 or "traded in the final hour": passing yards fails at the lower bound, receptions drops (7/15), and the spec rule (anytime TD + ≥3 yardage markets) is **not met**.
   - Last-candle age is unmeasured: 42 of 107 full-window picks lack hourly candles.
   - Two zero-volume markets were counted as priced (bid 0.05 / ask 0.99).
5. **Connectors:** authorize Vercel and Neon (`/mcp` or claude.ai connector settings) before Phase 6.

## Context-reset packet

**Objective.** Make the model's numbers trustworthy, prove them with a pre-registered walk-forward backtest (games and props, including every TD market), then rebuild the UI as a Next.js app ("Broadcast Line") that shows only what the evidence supports. The owner asked (2026-09-29) for professional-grade outputs that beat the market's Brier, comparing different models and blends. The shootout design is the answer to that; the baseline to beat is 0.2108.

**Done**
- Audit (M1–M16, P1–P13, S1–S4, U1–U10, T1–T4, H1–H2, D1, SEC1–4).
- Keyless forward capture live (#190).
- Phase 0:
  - hygiene;
  - honest default: ledger with 8 withdrawn claims, paper staking, config-driven banner, no CDN script, escaped HTML;
  - a harness that fails loudly: skip policy, connectivity-checked LIVE skips, no vacuous tests, no module shadowing;
  - CI on R 4.5.1;
  - the keyless data spike.
- Phase 1a plan, shootout design, market baseline.

**Next target.** After the owner decisions:
1. Execute Phase 1a (subagent-driven).
2. Write the Phase 1b plan: point-in-time features, `predict_week()` extraction, M4/M5/M6/M8/M9.
3. In parallel with 1b: build the shootout harness plus C0/C1/C2/B1/B2 (independent of the simulator).

**Confirmed facts**
- nflverse closing moneylines cover 100% of games from 2018–2025.
- Kalshi 2026 TD markets live under `KXNFLTD`. Settled markets appear only under `/historical/…`, with a historical cutoff at 2026-07-31.
- ESPN DraftKings propBets carry lines only, and disappear at kickoff.
- `config.R` derives `.playoff_context` and the test window from WEEK/SEASON while it is being sourced. That is why M1 uses R options.

**Open risks**
- Kalshi prop history is short: 2025 season plus 2026 prospective.
- The ESPN BET bias test is confounded (main lines vs alternate rungs). Phase 2 must redesign it with main-vs-main comparisons clustered by player-game.
- ESPN game open/close coverage rests on 5 games per season. Phase 2/3 must measure every 2023–2025 game before using openers for CLV.
- Refactoring `NFLsimulation.R` (Phase 1b).
- Workflow artifacts expire after 90 days; consolidate them into release assets (Phase 2).

## Session defect log

| # | Defect | Evidence it was real |
|---|---|---|
| 1 | Switching the main checkout to another branch would have broken the scheduled captures | Caught before the first scheduled run; docs work moved to a worktree |
| 2 | The local background MNF captures never ran (the sleep stalled, likely machine sleep) | The manifest had only 21:0x entries. The fix is GitHub-scheduled capture. **Never rely on local sleeps for time-critical capture.** |
| 3 | Phase 0 plan draft: regex-escaping bug and a string comparison of 0.4 vs "0.40" | Caught by running the parser on the real ledger before handoff |
| 4 | Bash heredocs here collapse `\\` to `\` | Use the file tool for R scripts |
| 5 | Two subagents hit the model API rate limit mid-task (Task 5, final fix wave) | Resumed with SendMessage, including the on-disk state; no work lost |
| 6 | Implementers wrote their own "complete" lines into the controller ledger | The controller corrected them; dispatches now say "don't edit progress.md" |
| 7 | Phase 0 gate regressions (verify_requirements path, run_matrix timeout) were missed by the task reviews, which never ran those scripts | Caught by the controller's close-out gate run; the final review re-ran all gates on the merged tree |
| 8 | My Phase 0 plan omitted the spec's "offline fixture run_matrix" item | Found in reconciliation; carried into Phase 1a Task 9 Step 0a (Ruling R14) |

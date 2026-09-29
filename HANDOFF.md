# HANDOFF

Resume point for the NFL overhaul. Read this first, then the spec. To verify everything and finish the remaining work in a full local environment (VS Code), use `docs/handoff/2026-09-29-vscode-prompt.md`.

## Current state — 2026-09-29, end of session 2

Session 2 covered:
- the pre-registered game backtest, scored end to end;
- Phase 1a;
- a second deletion batch;
- the data contract, Postgres schema and Broadcast Line web UI (built and verified locally, not deployed);
- an architecture/ERD scan of the whole stack merged together.

| Artifact | Where |
|---|---|
| Spec (approved 2026-09-28) | `docs/superpowers/specs/2026-09-28-nfl-overhaul-design.md` |
| Shootout design (A2 decided) | `docs/superpowers/specs/2026-09-29-model-shootout-design.md` (#194) |
| Plans | `docs/superpowers/plans/2026-09-29-phase0-foundation.md`, `…-phase1a-wiring-fixes.md` |
| Audit | `reports/2026-09-28/AUDIT.md` + `reports/2026-09-29/AUDIT-ADDENDUM.md` (M14–M19, P13) |
| Market baseline | `reports/2026-09-29/market-baseline/` (no-vig close Brier 0.2108, 2,219 games 2018–2025) |
| **Backtest v1 result** | `reports/2026-09-29/backtest-games-v1/` (PROTOCOL.md sha `664c42d1…` frozen in `e9876fa` before scoring; RESULT.md; `result_sha256 7244a0bc…`) (#195) |
| **Golden master** | `reports/2026-09-29/golden-master/2024-w15/` + ATTRIBUTION.md; CI workflow `golden-master.yml` (#196) |
| **Architecture/ERD scan** | `reports/2026-09-29/ARCHITECTURE-SCAN.md` (this branch) |
| **Web app** | `web/` + `web/README.md`; contract in `contracts/` (#198) |

| PR | Branch | State |
|---|---|---|
| #190–#193 | forward capture, spec, Phase 0, spike | **Merged** |
| #194 | docs/a2-protocol-decisions | Open (owner's). A2: a 400-pick betting-value gate, pooled headline, and the holdout scored once after C3 is point-in-time. |
| #195 | feat/backtest-games | Draft, stacked on #194. CI green. |
| #196 | fix/phase1a-wiring | Draft. **15/15 checks green** at `54d03fc`, including golden-master attribution: the head differs from its parent only by ~2e-10 float noise. |
| #197 | chore/deletion-batch-2 | Draft. CI green. |
| #198 | feat/web-ui | Draft, stacked on #195. **`ci-web` green**: 64 vitest (Postgres suites ran), re-ingest is a no-op, 69 Playwright. |

**Merge order:** #194 → #195 → #196 → #197 → #198.
- #196 and #197 conflict only in `CHANGELOG.md` (and #196 also in `docs/EVIDENCE_LEDGER.md`), where parallel entries sit at the same spot. Keep both sides.
- After each merge, bring `main` into the next PR and let CI re-run.
- Tested on a scratch merge of all five: integrity 60/60, and the R suite shows no failure that isn't also present on #196 alone in a container without nflreadr/randtoolbox.

### Results that matter

- **Backtest v1 (Confirm 2023–24, 570 games):** no candidate beats the no-vig close.

  | Candidate | Brier | Skill vs close [95% interval] |
  |---|---|---|
  | C0 (close) | 0.2098 | – |
  | C1 Elo | – | −5.64% |
  | C2 EPA GLM | – | −4.94% |
  | E1 ensemble | – | −4.47% |
  | B1[E1] market stack | – | +0.02% [−0.38%, +0.45%] |
  | B2[E1] | – | −0.07% |

  All controls passed. CLV at the ESPN BET opener is descriptive only (C2 +93 bps [+40, +149] on 214 picks, below the 400-pick gate).
- **Public policy in effect:** the site shows the market only; model lines stay hidden until a candidate passes its gates. The desk shows C2 paper leans at stake 0.
- **Phase 1a:** M1, M2/M3, M10, M11, M12, M14, M15 and M16 are fixed. The golden master is recorded per commit, and every output change is attributed (M12 moves blends by up to 0.0129 because calibration history is re-simulated).
- **Found, not fixed (awaiting approval):**
  - M18 (High): current-week injury points never reach mu.
  - M19 (Med): `inj_pick` prefers `practice_status` over `report_status`.

### Gates at the PR heads

| Branch | Gates |
|---|---|
| #196 | CI: `run_tests.R` exit 0, integrity 60/60, `run_matrix` 10/10 (golden-master artifact added) |
| #198 | Local: typecheck and lint clean; vitest 64/64 with `REQUIRE_DB_TESTS=1`; Playwright 69/69; axe 0 serious/critical at 390/768/1440 in both themes; `test-bundle-writer.R` 8/8; integrity 60/60. CI: the same. |
| This container | R 4.3.3 without gt, nflreadr or randtoolbox, so `run_tests.R` locally exits 1 on those skips only. CI (R 4.5.1 + renv) is authoritative. |

## Owner decisions pending

1. **Merge** #194–#198 in the order above. Draft PRs need marking ready first.
2. **M18/M19 fix approval.** Both touch `injury_scalp.R`/`NFLsimulation.R` (a STOP item). The golden master will attribute the change.
3. **A5 (before any props backtest):** define "pre-kickoff price" (a trade or two-sided quote, vs a spread cap ≤ 0.05 or "traded in the final hour"). The spike's GO verdict depends on it (see the previous HANDOFF text in git history, `8adcc79:HANDOFF.md`).
4. **A7 (public launch gate):** confirm the policy above, market-only until a candidate passes.
5. **Connectors:** authorize **Vercel** and **Neon** (`/mcp` or the claude.ai connector settings) to deploy #198. Secrets go only into GitHub environment secrets and Vercel env.
6. **Deletions still pending** (A3): `ensemble_calibration_implementation.R` and its `.rds` (after the M4 calibrator decision), and the 32 `if (!exists())` fallback copies in `NFLsimulation.R` (H1).
7. **Access:** allow reading `jviola1019/fantasy_football_dashboard` so the ported slopScan/docsTruth can be reconciled with the originals (this session wrote them fresh; reading FF was not permitted here).
8. **Phase 8:** confirm the LICENSE (MIT, as DESCRIPTION says).

## Context-reset packet

**Objective.** Make the model's numbers trustworthy and prove them with a pre-registered walk-forward backtest (games, then props including every TD market). Then serve only what the evidence supports through the Next.js "Broadcast Line" site. The baseline to beat is the no-vig close (0.2108 overall; 0.2098 on Confirm 2023–24).

**Done:** audit; forward capture; Phase 0; A2 decisions; backtest v1 (Tune/Confirm scored, holdout sealed); Phase 1a plus the golden master; deletion batches 1–2; contract, DB, ingest and web UI with tests and CI.

**Next target:**
1. Merge the stack.
2. Phase 1b: point-in-time features, `predict_week()` extraction, M4/M5/M6/M8/M9, M18/M19 if approved, and the simulator emitting a weekly bundle through `R/bundle_writer.R` (with `score_distributions`). This makes C3 point-in-time, after which the 2025 holdout is scored once.
3. Phase 2 odds layer: load the raw captures into `source_fetches`/`odds_snapshots`/`closing_lines`, add the unmatched-entity queue, redesign the ESPN bias test.
4. Deploy (after item 5 above).
5. Phases 4–5 (props, after A5), then the monorepo move and Phase 8 docs.

**Confirmed facts**
- nflverse closing moneylines cover 100% of games 2018–2025. The consensus line carries no timestamp or book.
- Kalshi 2026 TD markets live under `KXNFLTD`; settled markets only under `/historical/…` (cutoff 2026-07-31).
- ESPN DraftKings propBets carry lines only and vanish at kickoff.
- `config.R` derives `.playoff_context` from WEEK/SEASON while sourcing, so M1 uses `options(nfl.season, nfl.week)`.
- Per-bet CLV noise σ ≈ 514 bps; 400 picks gives 83% power for +100 bps across 8 candidates (A2).

**Open risks**
- Kalshi prop history is short (2025 plus 2026 prospective).
- The ESPN BET bias test is confounded. It needs main-vs-main comparisons clustered by player-game (Phase 2).
- ESPN game open/close coverage has been measured on only 5 games per season so far.
- Workflow artifacts expire after 90 days; consolidate them into release assets.
- The simulator isn't yet connected to the contract (ARCHITECTURE-SCAN finding 1).
- Blend calibration is extreme (BAL@NYG blend 0.003), which ties to M4.

## Session defect log

| # | Defect | Evidence it was real |
|---|---|---|
| 1 | Switching the main checkout to another branch would have broken the scheduled captures | Caught before the first scheduled run; docs work moved to a worktree |
| 2 | Local background captures never ran (the sleep stalled) | The manifest had only 21:0x entries; captures now run on GitHub's schedule |
| 3 | Phase 0 plan draft: a regex-escaping bug and a 0.4 vs "0.40" comparison | Caught by running the parser on the real ledger |
| 4 | Bash heredocs collapse `\\` to `\` | Use the file tool for R scripts |
| 5 | Subagents hit the API rate limit mid-task | Resumed with SendMessage; no work lost |
| 6 | Implementers wrote "complete" lines into the controller ledger | Corrected by the controller |
| 7 | Phase 0 gate regressions missed by task reviews | Caught by the close-out gate run |
| 8 | The Phase 0 plan omitted the offline run_matrix item | Carried into Phase 1a |
| 9 | Backtest shuffled-label control failed for B1 under a within-week shuffle (it preserves weekly information) | Switched to a global permutation **before** the protocol freeze and disclosed it |
| 10 | The first score run was void: the reproducibility subprocess ran with `--no-controls` | Fixed in `c7d8bce`; the re-run was byte-identical (`run1-void/`) |
| 11 | A background test run was corrupted by switching branches mid-run | Re-ran; all later work used worktrees |
| 12 | The deletion batch exposed a hidden `mgcv` dependency in test-calibration.R | The test now loads it explicitly |
| 13 | `pkill -f "<command string>"` killed the agent's own shell | Stop servers by process name or pidfile only |
| 14 | A stale `next start` held port 3100, so one accessibility review ran against an old build | Found via EADDRINUSE in the log; the restart helper now kills by process name |
| 15 | Chart SVG text scaled with the viewBox (6px on phones, 20px on desktop) | Found in the visual review; charts now lay out at measured width |
| 16 | `recommendations.rec_id` was a global PK, so a second run of the same week collided | Found by the Postgres ingest test; migration 0002 fixed it (drizzle-kit emitted it out of order, so it was ordered by hand) |
| 17 | The root `.gitignore` `bundles/` also ignored `contracts/fixtures/bundles/` | Caught before the commit; anchored to `/bundles/` |

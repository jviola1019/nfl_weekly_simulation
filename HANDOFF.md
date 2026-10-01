# HANDOFF

Resume point for the NFL overhaul. Read this first, then the spec. To verify everything and finish the remaining work in a full local environment (VS Code), use `docs/handoff/2026-09-29-vscode-prompt.md`.

## Current state — 2026-09-30, session 3 (VS Code verification and validation sprint)

**Part A verification of `main` (`eaa4138`):** `reports/2026-09-30/VERIFICATION.md`.
- Every gate passes on an LF checkout with the locked renv library, with three exceptions, each diagnosed:
  - Windows line endings (T5, T6) and web paths (T7) are fixed in #201, #204 and #202.
  - The golden-master blend columns differ across operating systems (T8). Every simulator column matches.
- The A2 backtest reproduces byte for byte on Windows once #204 is in: `result_sha256 7244a0bc…`.

**New defects** (audit addendum, #200):
- **M22 (Critical):** the simulator's expected scores are drives × points per drive (+ home field) in 16 of 16 games. A NaN turnover term forces a rescue that drops every other adjustment. This is the root cause of M18.
- **M23:** rest days are measured from the week's first kickoff.
- **M20/M21:** the Sleeper injury look-ahead, and venues joined by name.
- **T5–T8:** cross-OS reproducibility.

**Validation sprint** (#205, `reports/2026-09-30/validation-sprint/REPORT.md`):
- Tune 2018–2022 only; the Holdout stays sealed.
- No variable beats the close after BH correction.
- Market-anchored logistic blends match the close (+0.03% [−0.20, +0.28]) and beat boosting on stability and cost. Unanchored XGBoost loses 0.86%. Calibration maps don't help, and isotonic hurts.
- Nothing beats the close on spreads or totals.
- The time-zone spread effect (q = 0.15) is pre-registered in the draft v2 protocol (`reports/2026-09-30/backtest-games-v2/PROTOCOL-DRAFT.md`, awaiting the owner's signature).

**Design:** the owner rejected the shipped look. A redesign mockup (real data, dataviz-validated palette) is on the canvas: https://claude.ai/artifact/27TfoyhX17gU6hjskbukEM. Awaiting approval before it is built into `web/`.

| PR | Branch | State |
|---|---|---|
| #200 | docs/findings-m20-m21 | Draft: audit rows M20–M23 and T5–T8, data-sources addendum, VERIFICATION.md, Lighthouse JSON |
| #201 | fix/eol-hash-locks | Open, CI green: `.gitattributes` LF |
| #202 | fix/web-windows-paths | Open, CI green (including web): Windows web scripts |
| #203 | fix/m19-injury-report-status | Draft: M19 fix; golden-master attribution in CI |
| #204 | fix/lf-writers | Open: LF evidence writers (golden master: no change) |
| #205 | feat/validation-sprint-v2 | Draft: validation sprint (screen, blends, calibration, handicapping, tracking) and the v2 protocol draft |
| #206 | fix/disable-scoresandodds | ScoresAndOdds scraping off by default (S5); owner approved 2026-10-01; merging after CI |
| #207 | feat/broadcast-redesign | Broadcast Line redesign from the approved mockup (fields, scoreboard, research line labelled unvalidated); verified, awaiting the owner's merge |

**Merged 2026-10-01 (owner-approved):** #201, #202, #204. The main checkout was re-checked out with LF endings, so the hash locks pass locally.

**Local environment notes:**
- Postgres 17 cluster on 127.0.0.1:5433 (data dir in the session scratchpad; it stops when the machine restarts).
- renv is activated by a gitignored `.Rprofile` in each worktree.
- The worktrees are in `../nfl-worktrees/`.

## State at the end of session 2 (everything merged)

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
| #194 | docs/a2-protocol-decisions | **Merged** 2026-09-29 (`0b0f02b`). A2: a 400-pick betting-value gate, pooled headline, and the holdout scored once after C3 is point-in-time. |
| #195 | feat/backtest-games | **Merged** (`96ff3f2`) |
| #196 | fix/phase1a-wiring | **Merged** (`b5d1ac4`) after merging `main` in (CHANGELOG sections kept; C-SHRINK ledger row combined). CI green on the merge commit. |
| #197 | chore/deletion-batch-2 | **Merged** (`526ec9d`) after merging `main` in. CI green. |
| #198 | feat/web-ui | **Merged** (`37e92d8`) after merging `main` in and retargeting to `main`; `CI` and `CI (web)` green |
| #199 | claude/gallant-albattani-ohova3 | This hand-off (HANDOFF, architecture scan, VS Code prompt); merged last |

The owner asked (2026-09-30) to merge everything and move the remaining work to the VS Code list. Merge conflicts were parallel doc entries only, resolved by keeping both sides.

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
| Phase 1a | CI: `run_tests.R` exit 0, integrity 60/60, `run_matrix` 10/10 (golden-master artifact added) |
| Web UI | Local: typecheck and lint clean; vitest 64/64 with `REQUIRE_DB_TESTS=1`; Playwright 69/69; axe 0 serious/critical at 390/768/1440 in both themes; `test-bundle-writer.R` 8/8; integrity 60/60. CI: the same. |
| This container | R 4.3.3 without gt, nflreadr or randtoolbox, so `run_tests.R` locally exits 1 on those skips only. CI (R 4.5.1 + renv) is authoritative. |

## Owner decisions pending

1. **Remaining work** is listed in `docs/handoff/2026-09-29-vscode-prompt.md` Part B (items 1–19).
2. **Decided 2026-09-30:**
   - M18–M21 approved (M19 is in #203; M18 turned out to be M22, see item 3).
   - A5: a two-sided quote, spread ≤ 0.10, updated ≤ 60 min before kickoff; the mid is the fair price and ask + fee the executable price.
   - A7: validate by every means (done on Tune; see the sprint report).
   - Postgres: local cluster.
3. **Decided 2026-10-01:**
   - Disable the scraper now and delete it later (#206).
   - **M22:** explicit model, and each term must earn its place (Phase 1b plan).
   - Mockup approved and built (#207).
   - **A7 public policy changed:** the fields show the E1 research line labelled unvalidated; stakes stay private.
   - Merge #201, #202, #204.
4. **Still open:**
   - **M22 fix approach.** Recommended: make the effective model explicit, then re-admit each adjustment only after it passes the walk-forward test.
   - **Sign the v2 protocol draft.**
   - **Approve the redesign mockup.**
   - **Merges:** #201, #202, #204; #203 after attribution; #200.
5. **Connectors:** authorize **Vercel** and **Neon** (`/mcp` or the claude.ai connector settings) to deploy #198. Secrets go only into GitHub environment secrets and Vercel env.
6. **Deletions still pending** (A3): `ensemble_calibration_implementation.R` and its `.rds` (after the M4 calibrator decision), and the 32 `if (!exists())` fallback copies in `NFLsimulation.R` (H1).
7. **Access:** allow reading `jviola1019/fantasy_football_dashboard` so the ported slopScan/docsTruth can be reconciled with the originals (this session wrote them fresh; reading FF was not permitted here).
8. **Phase 8:** confirm the LICENSE (MIT, as DESCRIPTION says).

## Context-reset packet

**Objective.** Make the model's numbers trustworthy and prove them with a pre-registered walk-forward backtest (games, then props including every TD market). Then serve only what the evidence supports through the Next.js "Broadcast Line" site. The baseline to beat is the no-vig close (0.2108 overall; 0.2098 on Confirm 2023–24).

**Done:**
- audit; forward capture; Phase 0; A2 decisions;
- backtest v1 (Tune/Confirm scored, holdout sealed);
- Phase 1a plus the golden master; deletion batches 1–2;
- contract, DB, ingest and web UI with tests and CI;
- **session 3:** Part A verification (VERIFICATION.md), Windows fixes, M19, the Tune-window validation sprint, and the v2 protocol draft.

**Next target:**
1. Owner answers (the M22 approach, the v2 protocol signature, the mockup), then merge the green PRs.
2. **Phase 1b** (write the plan first, get it approved). Scope:
   - point-in-time features;
   - extract `predict_week()`;
   - **M22 per the owner's choice** and M23;
   - M4 (calibration: the sprint says none or Platt, never the leaked spline), M5, M6, M8, M9;
   - M20/M21;
   - a weekly bundle from the simulator.
   Then C3 joins v2 and the 2025 holdout is scored once.
3. **The redesign** (after mockup approval): rebuild the pages on the validated palette; server-render charts to bring mobile LCP under 2.5 s.
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
| 18 | A session restart stopped the background validation subagent mid-run (its data build was uncommitted) | The worktree kept the files; they were reviewed, tested and committed first (`0a0e1e5`), and the sprint was finished inline |
| 19 | The first verification of A2 and the web suites on Windows reported failures that were line-ending and path artefacts, not model or app defects | Diagnosed to CRLF writers/checkouts and POSIX path assumptions; fixed in #201/#202/#204 and verified byte for byte |
| 20 | The first "no contract drift" reading was vacuous (the export never ran on Windows) | Caught from the missing "wrote N files" line; the vitest drift test was the real check |
| 21 | The first mockup palette failed the dataviz validator (lightness band, contrast on turf, numbers coloured by series) | Re-stepped to the validated palette with a darker turf, and republished |
| 22 | **A delete without looking first:** a screenshot path passed unconverted made Playwright create `C:\c\Users\…\rd_shots`; I moved the images and ran `rm -rf /c/c` without first checking `C:\c` for other content | It very likely held only that run's output (a top-level `C:\c` is unusual), but this was not verified; disclosed to the owner. Rule: list a directory before any delete |
| 23 | The ScoresAndOdds scraper ran during the A3 end-to-end step because config still enabled it (S5) | Disclosed; defaults turned off in #206; `run_week.R` not run again |

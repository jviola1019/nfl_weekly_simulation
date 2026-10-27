# Review: planning, architecture, skills, structure, design, documentation (2026-10-27)

The owner asked for this review on 2026-10-26. Every finding cites a file, a command or a measured number. The items marked **Do** are the recommended next actions, most valuable first.

## 1. Planning and process

**State.** Main is still `4c1c377`; nothing has merged since 2026-10-19. Eight PRs are open:
- #215 auto week;
- #216 P13;
- #217 Tuesday capture;
- #218 sealed diagnostics;
- #219 stadium ids;
- #220 P1 props;
- #221 B2 (draft);
- #211, the roadmap (draft).

Two more branches are ready for PRs: C2 SQL checks and the F11 calibration fix. Work keeps stacking on an unmoving main, and every branch carries its own CHANGELOG entry at the top of `[Unreleased]`. That file is touched by nine of the ten open branches.

**Merge order.** Which branches touch the same files, from `git diff --name-only 4c1c377...<branch>`:

| Order | PR | Must follow | Why |
|---|---|---|---|
| 1 | #215 auto week | – | touches `config.R`, `weekly-sim.yml`, `tests/testthat/setup.R` and `README.md`, which others also touch |
| 2 | #216 P13 | – | #220 contains its commits |
| 3 | #220 P1 props | #216 | the same props files |
| 4 | #217 Tuesday capture | – | D1 cherry-picked it (`1e68b2b`) |
| 5 | #218 sealed diagnostics | #215 | `config.R` |
| 6 | #219 stadium ids | – | engine edit |
| 7 | F11 calibration fix | #219 | the same file, `NFLsimulation.R`, in a different region |
| 8 | #221 B2 | – | web only |
| 9 | C2 SQL checks | #221, #215 | `web/README.md` and `weekly-sim.yml` |
| 10 | D1 odds layer | #217, #215 | `R/capture_raw.R` and `setup.R` |

**Plans.**
- **Plans were far longer than the code they described:** P1 has 3,217 lines, D1 4,578 and B2 about 5,800. Every task brief and every review re-read them, which is a large part of the 47% subagent usage.
- **The C2 plan (2026-10-26) is about 330 lines.** It carried every decision and still produced working code on the first GREEN, with each slip caught by its own tests.
- **Dry runs doubled the work.** Each plan was executed twice: once in a dry-run tree (`b2dry`, `d1dry`, `p1dry`, `g1dry`, `a3dry`) and again for real.
- **The A3 and G1 plans are unfinished.** The A3 planner, on Opus, stopped twice at usage limits mid-dry-run.

**Do:**
- Merge in the order above.
- Write new plans under the 400-line budget, with no dry-run tree: the TDD steps already prove each task.
- Finish A3 inline from its partial state in `a3dry` and the planner log, not by resuming the Opus planner.

## 2. Architecture

- **Global state caused the F11 bug.** `NFLsimulation.R` (7,470 lines) runs top to bottom when sourced. Tables built for the week being simulated are shared with the calibration backtest.
  - F11 is the result: `hfa_tbl` was built only for the slate's teams (`NFLsimulation.R:2798`) but joined for every team of every past week (`:4387`). Every bye team's calibration games became 21.5–21.5 coin flips: 317 of 1,355 games in the 2026 week 7 run.
  - `calib_cache_key` has no week, so the first run of a season cached that broken fit for the rest of the season.
  - The fix is `fix/calib-hfa-all-teams` (`922dae6`).

  **Do:**
  - Merge the F11 fix (an owner-gated engine edit).
  - Make the planned `predict_week()` extraction (G1) the next engine track. Each engine bug found so far (M22–M24, F11, F14) comes from this shared global state.
- **The slate path still substitutes a value silently.** `safe_mu()` replaces a non-finite mean with 21 (`NFLsimulation.R:5406-5430`). The calibration path now stops instead (`assert_finite_means`). **Do:** the same for the slate path (A3a item).
- **The engine still prints "HIGH CONFIDENCE BETTING OPPORTUNITIES"** (output audit F4), although it is worse than the market over the calibration window (ΔLog-loss +0.0131 [0.0025, 0.0260]). That window includes the 317 coin-flip games, so the gap must be re-measured after F11 is fixed. **Do:** relabel the output as unvalidated model–market gaps (an engine edit).
- **The odds layer (D1) is in good shape:**
  - one provider contract (`R/odds/provider.R`) and one HTTP layer (1 request/second per domain, backoff, a block breaker);
  - status rules shared by every provider (failed, stale, unavailable);
  - blocks that are never worked around: since Task 7, a challenge page served as 200 also stops the domain for the session.

  Nothing ingests odds into Postgres yet (the K3 odds bundle), so C2's odds checks are ready but have no data to check.
- **The web layer is sound.** Contracts are generated from the Drizzle schema, ingest is idempotent with append-only evidence tables, and the C2 checks cover what constraints cannot. One gap: in the deployed ingest the check runs after the commit, so it flags bad data but cannot stop it being published. **Do:** run the checks inside the ingest transaction, before the publish pointer moves.

## 3. Skills, plugins and agents

- **Cost.** /usage (2026-10-26) put `general-purpose` subagents at 47% of usage, `writing-plans` at 10% and the superpowers plugin at 10%. The drivers are:
  - the subagent-driven loop: an implementer, a task reviewer and a re-reviewer per task, each re-reading the codebase;
  - Opus planners running dry runs;
  - the plugin's "invoke a skill at a 1% chance" bootstrap, re-injected at every start, clear and compact.
- **Applied with the owner (2026-10-26):**
  - subagents forced to Haiku (`CLAUDE_CODE_SUBAGENT_MODEL` + `_FORCE`);
  - inline execution with one review per branch;
  - `writing-plans` on Sonnet at medium effort, with a 400-line budget and "Native" as the default;
  - superpowers off in three projects that do not use it.
- **What one review per branch caught.** The single Haiku review of B2 found two real defects, both fixed test-first:
  - a protocol-relative redirect in the theme route;
  - a glossary definition that contradicted the number it defines.
- **Remaining levers:**
  - `using-superpowers` (3.2 KB) is injected at every start, clear and compact. Its "1% chance" rule is what drives skill loads.
  - `subagent-driven-development` costs about 53 KB when loaded.

  **Do:** if usage stays high, soften the 1% rule in the plugin's bootstrap. That is a plugin-cache edit, so it must be re-applied after updates.

## 4. Structure

- **Worktrees.** There are 21 besides `main`. Seven are detached scratch or dry-run trees: `a3dry`, `audit`, `b2base`, `b2dry`, `d1dry`, `g1dry`, `p1dry`. Each feature worktree belongs to an open PR. **Do:** once their plans are done, remove the seven detached trees and the scratch databases (`nfl_b2`, `nfl_main_ab`, `nfl_audit`) in one batch, under the owner's "proven unused" rule.
- **Dead code to prove and remove (track X):**
  - the invalid ensemble calibrator (F12);
  - `R/date_resolver.R`, once #215 merges;
  - `RECENCY_DECAY_RATE`, which nothing reads;
  - `validation/*.R`, after A3.
- **Golden master blind spot.** It pins 2024 week 15, a week with no byes, so it could not see F11. **Do:** add a bye-week case, such as 2026 week 7 or a 2024 week with byes, as a second golden master or a regression test.
- **Flakes under load.** Playwright cases hit their 30 s timeout, and `scripts/local/discover.test.ts` (a synchronous fixture copy) hit its 5 s one. **Do:** give `discover.test.ts` an explicit timeout. CI runs alone, so this only affects local runs.

## 5. Design (web)

- **B2 is complete (draft #221).** It brings:
  - one token and component system;
  - a context line on every page and sources on every number;
  - one-line navigation, and a theme the server renders;
  - axe best-practice checks clean;
  - offline and online pixel parity at 0 differing pixels.
- **Performance.** Mobile LCP is within 0.25 s of main on every page, but the 2.5 s gate is unmet on both trees on a loaded machine. **Do:** measure on CI or a quiet machine before deciding on font subsetting.
- **Not started:**
  - B3, the design bake-off: concepts A–E including the Night-game HUD, React Bits, and a motion budget;
  - B5, a design per tab, as the owner asked.

  These carry the "futuristic, animated, reactive" part of the request; B2 only laid the foundation. **Do:** start B3 after #221 merges, with the dataviz validator on every chart palette.
- **Audit F8.** Mid-week lines are labelled "close" in more places after B2: `page.tsx:193`, `desk/page.tsx:86`, `games/[id]/page.tsx:130` and `glossary.ts:13-17`. **Do:** fix them in one small PR after #221.

## 6. Documentation

- **`CLAUDE.md`**, the single source of truth for agents, is dated 2026-02-05.
  - It gives `NFLsimulation.R` as 8,300+ lines (it is 7,470) and `NFLmarket.R` as 3,900+ (it is 2,659).
  - It points to `NFLsimulation.R lines 3144-3150`, which have moved.
- **`docs/ARCHITECTURE.md`** describes 60% shrinkage (`:40`, `:116`, `:311`; the engine uses 0.70) and spline calibration (`:156`; the calibrator is invalid and diagnostic only).
- **`HANDOFF.md`** holds a section for each track, so it grows with every branch.

**Do:** run V3, the docs-truth pass, once #215 merges. It covers:
- `CLAUDE.md`, rewritten from the code with no line numbers;
- `ARCHITECTURE.md`, with the lineage diagram planned in C2;
- `GETTING_STARTED.md`, with a test, like `web/src/test/docsTruth.test.ts`, that fails when a documented command, path or number drifts.

## What this review did not cover

- Statistical validity of the models beyond F11 and F4. That is A3, A4–A5 and the M studies.
- A security review of the whole repo (track S).

# C2 part 1: SQL data checks after every ingest, and a generated ERD — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every ingest into Postgres is followed by SQL assertion queries that must return zero rows, failing CI and the deployed ingest when the data is not clean; and the data model is documented by an ERD generated from `web/src/db/schema.ts`, which a test keeps in step with the code.

**Architecture:** A registry of checks in `web/src/lib/dbcheck/` (each a SQL query that returns one `detail` row per violation, with an id and a severity), a runner and a report shared by the `npm run db-check` CLI, the CI and weekly-sim workflows, and the local app. The ERD is rendered from Drizzle's table metadata (`getTableConfig`) into `docs/ERD.md` as a Mermaid `erDiagram`; `npm run erd` writes it and a vitest docs-truth test fails when the file and the schema disagree.

**Tech Stack:** TypeScript, Drizzle ORM 0.45.3 (`drizzle-orm/pg-core`), postgres.js, vitest, PostgreSQL 17 locally / 16 in CI, GitHub Actions.

**Spec:** Track C2 of `docs/superpowers/plans/2026-10-20-plan-revision.md` ("SQL" and "ERD" bullets), owner-approved 2026-10-20. Inputs: `reports/2026-10-21/OUTPUT_AUDIT.md` F7 (distribution mass) and the B2 Task 3 deferred minor (`backtest_runs.run_id` is not unique).

## Global Constraints

- No new dependency: `web/package.json` gains two `scripts` entries (`db-check`, `erd`) and nothing in `dependencies` or `devDependencies`; `web/package-lock.json` is unchanged.
- No migration: range CHECK constraints in migration 0003 are owner checkpoint 7 and are NOT part of this plan. Nothing in `web/drizzle/` changes.
- No R file, `contracts/` file or bundle contract changes.
- No silent fallbacks: every violation is printed with its check id and sample rows; CI and the deployed ingest fail on any `error` check.
- The 2025 holdout stays sealed: checks read only what is already in the database; nothing fetches or scores data.
- Secrets never in code, docs or logs: the CLI reads `DATABASE_URL` from the environment and never prints it.
- Commits end with a blank line, then exactly `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. One branch, `feat/c2-db-checks-erd`, from `main`; a draft PR; merging needs owner approval.
- Postgres suites run with `TEST_DATABASE_URL` (a database whose name ends in `_test`) and `REQUIRE_DB_TESTS=1`; they must not skip.
- Windows and Git Bash: write files with the file tools; pass `C:/` paths to node.

## Review Focus

1. A legitimate real bundle that passed bundle QA must pass every `error` check (a false positive would fail the deployed ingest): the score distributions of a run cover its central `config.distribution_mass` (0.999), so their bins sum to 0.99908–0.99932, not 1 (F7 is by design) — Task 1 tests the simulator fixture and a 0.9991 sum.
2. Postgres `double precision` accepts `NaN` and `Infinity`: a check written as `p < 0 OR p > 1` must still catch them — Task 1 plants a NaN.
3. A two-way spread is quoted as home −3.5 and away +3.5: grouping the pair by `line` would split it; the overround check pairs by `abs(line)` — Task 2 plants a spread pair.
4. An odds venue quoting only one side, or an exchange row with bid/ask and no American price, must not trip the overround check — Task 2 plants both.
5. A check whose SQL errors (a renamed column) must fail the run with the check id, not be skipped — Task 1 tests that the runner names the failing check.

---

## File structure

| File | Responsibility |
|---|---|
| `web/src/lib/dbcheck/checks.ts` | `DB_CHECKS`: every check (id, severity, what it means, the query) |
| `web/src/lib/dbcheck/run.ts` | `runDbChecks()`, `formatReport()`, `reportDbChecks()` |
| `web/src/lib/dbcheck/checks.test.ts` | Postgres: clean fixtures give zero violations; each planted violation fires its check |
| `web/scripts/db-check.ts` | CLI: `npm run db-check` |
| `web/src/test/ciWiring.test.ts` | every workflow step that ingests is followed by `npm run db-check` in the same job |
| `web/src/lib/erd.ts` | `renderErd()`: Mermaid ERD text from the schema |
| `web/src/lib/erd.test.ts` | entities, keys, relationships, and docs truth for `docs/ERD.md` |
| `web/scripts/erd.ts` | CLI: `npm run erd` writes `docs/ERD.md`; `--check` compares |
| `docs/ERD.md` | generated; committed |

Modified: `web/package.json` (two scripts), `web/scripts/local.ts` (report after its ingest loop), `.github/workflows/ci-web.yml`, `.github/workflows/weekly-sim.yml`, `web/README.md`, `docs/ARCHITECTURE.md` (one pointer line), `CHANGELOG.md`.

Out of scope, by decision: the "before every backtest" clause of the spec. The R backtests read committed CSVs (`backtest/data/`), not Postgres, so a database check cannot gate them; the R-side input checks (`R/input_checks.R`) are C2 part 2. The lineage diagram for `docs/ARCHITECTURE.md` goes to V3 (docs truth), since that file is stale beyond one diagram.

---

### Task 1: The check registry, the runner and the non-odds checks

**Files:**
- Create: `web/src/lib/dbcheck/checks.ts`, `web/src/lib/dbcheck/run.ts`, `web/src/lib/dbcheck/checks.test.ts`

**Interfaces:**
- Produces:
  - `type Severity = "error" | "warning"`
  - `interface DbCheck { id: string; severity: Severity; what: string; query: SQL }` — `query` (a `drizzle-orm` `sql` template) selects exactly one text column named `detail`, one row per violation, each naming the table, the key and the offending value(s), e.g. `game_predictions run=weekly:… game=2026_04_DEN_SF candidate=C0 p_home_final=1.2`.
  - `const DB_CHECKS: readonly DbCheck[]` (Task 2 appends the odds checks to the same array).
  - `interface CheckResult { id: string; severity: Severity; what: string; count: number; samples: string[] }`
  - `runDbChecks(db: Db, checks?: readonly DbCheck[], sampleSize?: number): Promise<CheckResult[]>` — default `DB_CHECKS`, `sampleSize` 5; samples sorted; a query that throws is rethrown as `Error("db-check <id>: <original message>")`.
  - `formatReport(results: CheckResult[]): { text: string; errors: number; warnings: number }` — `errors`/`warnings` count checks with `count > 0`; `text` lists each violated check as `<SEVERITY> <id> (<count>): <what>` followed by its samples indented, then the last line `db-check: <n> checks, <errors> error(s), <warnings> warning(s)`.
  - `reportDbChecks(db: Db, log?: (line: string) => void): Promise<{ errors: number; warnings: number }>` — runs, logs `text`, returns the counts.

The checks of this task (all `error`). "Outside [0, 1]" means `NOT (x BETWEEN 0 AND 1)` for a non-null `x`, which is true for `NaN` and `±Infinity`.

| id | A row is a violation when |
|---|---|
| `prob.game_predictions` | `p_home_raw`, `p_home_final` or `p_home_mkt_novig` is outside [0, 1] |
| `prob.recommendations` | `p_model` or `p_mkt_novig` is outside [0, 1] |
| `prob.prop_line_probs` | `p_over` or `p_push` is outside [0, 1], or `p_over + p_push > 1 + 1e-9` |
| `prob.calibration_bins` | `p_mean` or `y_mean` is outside [0, 1], or `n < 0` |
| `backtest_metrics.ranges` | `brier`, `accuracy` or `ece` outside [0, 1]; `logloss < 0` or not finite; `n <= 0`; `slope` not in [`slope_lo`, `slope_hi`]; `skill` not in [`skill_lo`, `skill_hi`] |
| `score_distributions.mass` | the sum of the bins' `p` is below the run's `model_runs.config->>'distribution_mass'` minus 1e-9 or above 1 + 1e-9; or the run has no numeric `distribution_mass`; or a bin's `p` is outside [0, 1] |
| `score_distributions.shape` | `kind` is not `margin` or `total`; `bins` is not a non-empty JSON array; the bins' `x` are not consecutive ascending integers |
| `games.natural_key` | two `game_id`s share (`season`, `week`, `home_team_id`, `away_team_id`); or `home_team_id = away_team_id` |
| `games.scores` | exactly one of `home_score`, `away_score` is null; a score is negative; a game has a score and `kickoff_utc > now()` |
| `model_runs.publication` | more than one run of a `kind` has status `published`; a `publish_pointers` row's run is not `published`, has `qa_ok = false`, or is the wrong kind (`weekly` → `weekly`, `backtest_games` → `backtest`); a `model_runs` row has no `bundle_ingests` row with its `run_id`, or a `bundle_ingests` row's `run_id` is not in `model_runs` |
| `backtest_runs.run_key` | a `run_id` has more than one `backtest_runs` row (the B2 Task 3 minor); a `backtest_runs` row's run is not of kind `backtest` |
| `enum.values` | `source_status.status` ∉ {ok, stale, failed, unavailable}; `recommendations.side` ∉ {home, away, none}; `games.game_type` ∉ {REG, WC, DIV, CON, SB}; `markets.scope` ∉ {game, player}; `markets.outcome_kind` ∉ {line, yes_no}; `backtest_metrics.split` ∉ {tune, confirm, holdout}; `backtest_metrics.phase` ∉ {pooled, REG, POST}; `bet_grades.outcome` ∉ {win, loss, push, void}; `score_distributions.kind` is covered by `.shape` |

The `score_distributions.bins` element shape is `{x, p}` (R `sb_bins`), not the `{x0, x1, p}` the comment in `schema.ts:218` says: fix that comment in this task.

- [ ] **Step 1: Write the failing tests** in `web/src/lib/dbcheck/checks.test.ts`, inside `describe.skipIf(!hasDb)(...)` as in `src/lib/data/queries.test.ts`, each on a `freshDb()` that has ingested the three fixture bundles oldest first (`weekly-2026-w04`, `backtest-nfl-games-v1`, `weekly-sim-2024-w15`):

```ts
it("the three fixture bundles violate no check", async () => {
  const results = await runDbChecks(db);
  expect(results.filter((r) => r.count > 0)).toEqual([]);
  expect(results.map((r) => r.id)).toEqual(DB_CHECKS.map((c) => c.id)); // every check ran
});

it("every check id is unique", () => {
  expect(new Set(DB_CHECKS.map((c) => c.id)).size).toBe(DB_CHECKS.length);
});

it("a distribution covering the stated mass passes, one below it fails (F7 is by design)", async () => {
  // set one simulator total distribution to sum 0.9991, then 0.9980 (mass 0.999)
  // expect .mass count 0, then 1 with a sample naming run, game and kind
});

it("NaN and Infinity are outside [0, 1]", async () => {
  // insert game_predictions rows (candidate "CX", "CY") with p_home_final 'NaN' and 'Infinity'
  // expect prob.game_predictions count 2
});
```

Then one planted-violation test per remaining check, each asserting that check's `count` is exactly the number of planted rows and that a sample contains the planted key: `prob.recommendations` (p_model 1.5), `prob.prop_line_probs` (p_over 0.7, p_push 0.4 — needs a `players` and a `markets` row), `prob.calibration_bins` (y_mean −0.1, a new bin number), `backtest_metrics.ranges` (slope outside its interval, a new candidate), `score_distributions.mass` (a weekly-2026-w04 distribution, whose run has no `distribution_mass`), `score_distributions.shape` (bins with x 0, 2), `games.natural_key` (a second game id for an existing matchup), `games.scores` (home score set, away score null), `model_runs.publication` (a second `published` weekly run, and a `bundle_ingests` row for an unknown run), `backtest_runs.run_key` (a second `backtest_runs` row for the backtest fixture's run), `enum.values` (a `source_status` row with status `unknown`).

And the runner:

```ts
it("a check whose SQL fails is reported by id, not skipped", async () => {
  const broken = [{ id: "test.broken", severity: "error", what: "x", query: sql`SELECT no_such_column AS detail FROM games` }] as const;
  await expect(runDbChecks(db, broken)).rejects.toThrow(/^db-check test\.broken: /);
});

it("formatReport counts violated checks and ends with the summary line", () => {
  const r = formatReport([
    { id: "a", severity: "error", what: "A", count: 2, samples: ["x", "y"] },
    { id: "b", severity: "warning", what: "B", count: 1, samples: ["z"] },
    { id: "c", severity: "error", what: "C", count: 0, samples: [] }
  ]);
  expect([r.errors, r.warnings]).toEqual([1, 1]);
  expect(r.text.trim().split("\n").at(-1)).toBe("db-check: 3 checks, 1 error(s), 1 warning(s)");
  expect(r.text).toContain("ERROR a (2): A");
});
```

- [ ] **Step 2: Run them and see RED**

Run (`web/`): `TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test REQUIRE_DB_TESTS=1 npx vitest run src/lib/dbcheck/checks.test.ts`
Expected: FAIL: the module `./checks` (or `./run`) cannot be found.

- [ ] **Step 3: Implement `checks.ts` and `run.ts`** with the interfaces above. Each query is one `SELECT … AS detail` (a `UNION ALL` where a check covers several tables or conditions); `runDbChecks` wraps each as `SELECT count(*)::int AS n, (array_agg(detail ORDER BY detail))[1:<sampleSize>] AS samples FROM (<query>) q`.

- [ ] **Step 4: Run them and see GREEN**

Same command. Expected: every test passes, none skipped.

- [ ] **Step 5: Gates and commit**

Run (`web/`): `npm run typecheck && npm run lint && TEST_DATABASE_URL=postgres://ci@127.0.0.1:5436/nfl_test REQUIRE_DB_TESTS=1 npx vitest run`
Expected: exit 0; the file count is main's plus one.

```bash
git add web/src/lib/dbcheck web/src/db/schema.ts
git commit -m "feat(web): SQL data checks with zero-row assertions, and a runner that names each failing check (C2)"
```

### Task 2: The odds checks

**Files:**
- Modify: `web/src/lib/dbcheck/checks.ts` (append to `DB_CHECKS`), `web/src/lib/dbcheck/checks.test.ts`

**Interfaces:**
- Consumes: `DbCheck`, `DB_CHECKS`, `runDbChecks` (Task 1).
- Produces: five more checks in `DB_CHECKS`. No other code reads the odds tables yet (the K3 odds bundle will); these checks are ready for it.

American odds `a` → implied probability: `a >= 100` → `100 / (a + 100)`; `a <= -100` → `-a / (-a + 100)`.

| id | severity | A row is a violation when |
|---|---|---|
| `odds.quote_shape` | error | an `odds_snapshots` row has no `price_american` and no `bid`, `ask` or `last`; `price_american` is in (−100, 100); `bid > ask`; or, for a market with `outcome_kind = 'yes_no'`, `bid`, `ask` or `last` is outside [0, 1] |
| `odds.overround` | error | for rows with a `price_american`, grouped by (`game_id`, `market_id`, `venue_id`, `coalesce(player_id, '')`, `abs(coalesce(line, 0))`, `captured_at`) with exactly two distinct `side`s: the two implied probabilities sum outside [1.00, 1.15] |
| `odds.close_after_kickoff` | error | a `closing_lines` row's snapshot `captured_at` is later than its game's `kickoff_utc` |
| `odds.close_snapshot_mismatch` | error | a `closing_lines` row's snapshot has a different `game_id`, `market_id`, `venue_id` or `side` than the closing-line row |
| `odds.cross_venue` | warning | per (`game_id`, `market_id`, `side`, `abs(coalesce(line, 0))`, the UTC hour of `captured_at`) with at least three venues: a venue's proportionally devigged probability (its pair from `odds.overround`'s grouping, normalised to sum 1) is more than 0.08 from the median of the venues' |

- [ ] **Step 1: Write the failing tests**: on the Task 1 fixture database plus the planted rows each test needs (a `venues` row per venue, a `markets` row per market, a `source_fetches` row, `odds_snapshots` rows on fixture game `2026_04_DEN_SF`):
  - `odds.overround`: a moneyline pair −110 / −110 passes (sum 1.0476); +150 / +150 fails (0.80); a spread pair home −3.5 at −110 and away +3.5 at −110 passes as ONE pair (count 0, not 2 singles); a one-sided quote is not a violation; an exchange row (bid/ask, no price) is not paired.
  - `odds.quote_shape`: a row with `price_american = 50` fails; a yes_no row with `ask = 1.2` fails; a row with `bid 0.6, ask 0.5` fails.
  - `odds.close_after_kickoff`: a closing line whose snapshot is captured 5 minutes after kickoff fails; one 5 minutes before passes.
  - `odds.close_snapshot_mismatch`: a closing line pointing at a snapshot of another venue fails.
  - `odds.cross_venue`: three venues at 0.60, 0.61, 0.75 home probability in the same hour flag the third (count 1, severity warning) and `formatReport(...).errors` is 0 for that database.

- [ ] **Step 2: Run and see RED**: Expected: each new test fails on an unknown check id (the result list has no such id).

- [ ] **Step 3: Implement the five checks.**

- [ ] **Step 4: Run and see GREEN**, then the Task 1 file again: the clean-fixture test still gives zero violations.

- [ ] **Step 5: Gates (as Task 1) and commit**

```bash
git add web/src/lib/dbcheck
git commit -m "feat(web): odds checks: overround, quote shape, closes before kickoff, cross-venue outliers (C2)"
```

### Task 3: `npm run db-check`, and every ingest followed by it

**Files:**
- Create: `web/scripts/db-check.ts`, `web/src/test/ciWiring.test.ts`
- Modify: `web/package.json` (`"db-check": "tsx scripts/db-check.ts"`), `web/scripts/local.ts`, `.github/workflows/ci-web.yml`, `.github/workflows/weekly-sim.yml`, `web/README.md`

**Interfaces:**
- Consumes: `reportDbChecks(db, log)` (Task 1).
- CLI contract: exit 0 when no `error` check is violated (warnings are printed), 1 when one is, 2 when `DATABASE_URL` is unset (message: `db-check: DATABASE_URL is not set`). It never prints the URL.
- `local.ts`: after its ingest loop and the pointer hints, `await reportDbChecks(db)`; on `errors > 0` it prints `db-check: the database fails <n> check(s) (listed above); the pages show data that is not clean` and keeps serving (the local runner already serves past a rejected bundle; CI and the deployed ingest are the gates).

Workflow wiring (each a step or a line right after the ingests, in the same job):
- `ci-web.yml`, job e2e: after "Migrate, ingest the fixture bundles, seed the desk user" and after the simulator-run ingest.
- `ci-web.yml`, job parity: in the online path, after the ingest loop.
- `weekly-sim.yml`, job ingest: after "Migrate, then ingest".

- [ ] **Step 1: Write the failing test** `web/src/test/ciWiring.test.ts`: for `.github/workflows/ci-web.yml` and `.github/workflows/weekly-sim.yml`, parse each job's `steps[].run` text in order (read the YAML as text and split on `- name:`, the way `docsTruth.test.ts` reads docs; no YAML dependency), and assert that after the last line containing `npm run ingest` in each job there is a later line, in the same job, equal to `npm run db-check` (trimmed). Assert also that `package.json` has the `db-check` script, and that `local.ts` calls `reportDbChecks(`.

- [ ] **Step 2: Run and see RED** (`npx vitest run src/test/ciWiring.test.ts`): the assertions name both workflows and the missing script.

- [ ] **Step 3: Write the CLI, the `local.ts` call and the workflow lines; add `npm run db-check` to the README's checks table** ("SQL data checks: zero rows from every assertion query; run after every ingest") and to its local-runner paragraph.

- [ ] **Step 4: GREEN**: the wiring test passes; then by hand on the scratch database in the fixture state (`DATABASE_URL` set): `npm run db-check` prints `db-check: <n> checks, 0 error(s), 0 warning(s)` and exits 0; after planting one `game_predictions` row with `p_home_final = 1.5` it prints `ERROR prob.game_predictions (1)` and exits 1; with `DATABASE_URL` unset it exits 2.

- [ ] **Step 5: Gates and commit**

```bash
git add web/scripts/db-check.ts web/src/test/ciWiring.test.ts web/package.json web/scripts/local.ts web/README.md .github/workflows/ci-web.yml .github/workflows/weekly-sim.yml
git commit -m "feat(web): npm run db-check after every ingest, in CI, the deployed ingest and the local app (C2)"
```

### Task 4: The ERD, generated from the schema

**Files:**
- Create: `web/src/lib/erd.ts`, `web/src/lib/erd.test.ts`, `web/scripts/erd.ts`, `docs/ERD.md`
- Modify: `web/package.json` (`"erd": "tsx scripts/erd.ts"`), `web/README.md`, `docs/ARCHITECTURE.md`

**Interfaces:**
- Produces: `renderErd(): string` — the whole content of `docs/ERD.md`, deterministic:
  1. A heading `# Data model (ERD)` and a paragraph: generated by `npm run erd` from `web/src/db/schema.ts`, do not edit by hand (`npm run erd` rewrites it; `src/lib/erd.test.ts` fails when it is stale); it is the column list the 2026-09-28 design spec §3 promised as `docs/data-contract.md`; the invariants SQL enforces are in `web/drizzle/0001_invariants.sql` and the checks run after every ingest are `npm run db-check` (`web/src/lib/dbcheck/checks.ts`).
  2. One fenced `mermaid` block: `erDiagram`, then one entity per table **sorted by SQL table name**, columns in definition order as `<type> <column_name>[ <keys>]`, then one relationship line per foreign key sorted by (parent, child, columns).
- Types: `column.getSQLType()`, with `timestamp with time zone` → `timestamptz` and `double precision` → `float8`; any other SQL type containing a space throws `Error("renderErd: no ERD name for SQL type <t>")`.
- Keys: `PK` for a primary-key column (single or composite), `FK` for a column in a foreign key, `UK` for a `.unique()` column or a single-column `uniqueIndex`; several joined as `PK, FK`.
- Relationships: `<parent> ||--o{ <child> : "<child columns joined by ', '>"` when every FK column is NOT NULL, `<parent> |o--o{ <child> : "…"` when any is nullable.
- `scripts/erd.ts`: writes `docs/ERD.md` (repo root, resolved from the script's directory); `npm run erd -- --check` exits 1 with `docs/ERD.md is stale: run npm run erd` when the file differs.

- [ ] **Step 1: Write the failing tests** `web/src/lib/erd.test.ts`:

```ts
it("has one entity per table, sorted, with every column", () => {
  // every PgTable export of ../db/schema appears as "  <sql name> {" in table-name order,
  // and the number of attribute lines under it equals the table's column count
});
it("marks keys: composite primary keys, foreign keys and unique columns", () => {
  expect(erd).toMatch(/game_predictions \{[^}]*text run_id PK, FK/);
  expect(erd).toMatch(/users \{[^}]*text email UK/);
  expect(erd).toMatch(/model_runs \{[^}]*text bundle_sha256 UK/);
  expect(erd).toMatch(/games \{[^}]*timestamptz kickoff_utc\n/);
});
it("draws one relationship per foreign key, optional when a column is nullable", () => {
  expect(erd).toContain('teams ||--o{ games : "away_team_id"');
  expect(erd).toContain('teams ||--o{ games : "home_team_id"');
  expect(erd).toContain('players |o--o{ odds_snapshots : "player_id"');
  expect(erd).toContain('recommendations ||--o{ bet_grades : "run_id, rec_id"');
  // the count of relationship lines equals the total number of foreign keys over all tables
});
it("docs/ERD.md is what the schema renders (run npm run erd after a schema change)", () => {
  expect(readFileSync(join(REPO, "docs", "ERD.md"), "utf8")).toBe(renderErd());
});
```

- [ ] **Step 2: RED** (`npx vitest run src/lib/erd.test.ts`): cannot find `./erd`.

- [ ] **Step 3: Implement `renderErd` with `getTableConfig` from `drizzle-orm/pg-core` (and `is(x, PgTable)` from `drizzle-orm` to pick the tables out of the schema module); write `scripts/erd.ts`; run `npm run erd` to write `docs/ERD.md`.** Add the README checks-table row ("ERD: docs/ERD.md is what the schema renders") and one line under `docs/ARCHITECTURE.md` "## Data Flow": `The database tables and their keys: [docs/ERD.md](ERD.md) (generated from web/src/db/schema.ts).`

- [ ] **Step 4: GREEN**: the four tests pass; `npm run erd -- --check` exits 0; after adding a throwaway column to a table in `schema.ts`, the docs-truth test fails and `--check` exits 1 (revert the column).

- [ ] **Step 5: Gates and commit**

```bash
git add web/src/lib/erd.ts web/src/lib/erd.test.ts web/scripts/erd.ts web/package.json web/README.md docs/ERD.md docs/ARCHITECTURE.md
git commit -m "docs(web): the ERD generated from the schema, kept in step by a docs-truth test (C2)"
```

### Task 5: Close-out

**Files:** Modify `CHANGELOG.md`.

- [ ] **Step 1: Contract**: `git diff --exit-code main -- web/package-lock.json web/drizzle contracts` exits 0; `git diff main -- web/package.json` shows only the two `scripts` lines; no file deleted (`git diff --name-status main | grep '^D' || echo none`).
- [ ] **Step 2: Gates** (`web/`): typecheck 0, lint 0, `vitest` with `REQUIRE_DB_TESTS=1` all pass, none skipped; `Rscript scripts/verify_repo_integrity.R` 63/0 from the repo root (fresh HOME).
- [ ] **Step 3: The local app**: `npm run local` on scratch `NFL_LOCAL_BUNDLES` (copies of the three fixture bundles) and `NFL_LOCAL_PGDATA` prints `db-check: <n> checks, 0 error(s), 0 warning(s)` after its ingests and serves; stop it with `npm run local:stop` and the web server by PID.
- [ ] **Step 4: CHANGELOG** entry under `[Unreleased]`: the checks (ids and what each enforces, the count), where they run, the F7 explanation (bins cover the run's stated mass, 0.999), the `backtest_runs.run_id` check, the ERD and how it stays current; the numbers from Steps 2–3.
- [ ] **Step 5: Commit, push and open a draft PR** against `main` titled `C2: SQL data checks after every ingest, and a generated ERD`, with the gates' output and a note that migration 0003 (range CHECK constraints) is owner checkpoint 7 and not in this PR. Do not merge.

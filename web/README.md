# Broadcast Line (web)

The public site and private desk for the NFL model. The web app reads only from Postgres. The R engine writes bundles, and the ingest CLI loads them. Design and contract: `docs/superpowers/specs/2026-09-28-nfl-overhaul-design.md` §3–4.

**Stack:** Next.js 16 (App Router, `src/proxy.ts`), React 19, Tailwind 4, Drizzle ORM on Postgres (postgres.js), next-auth v5 (credentials, JWT sessions), and visx scales for the charts.

## Run it offline (the results viewer)

This is how you look at a model run. `Rscript run_week.R <week> <season>` writes a weekly bundle to `bundles/<season>-w<WW>-sim-<UTC stamp>/` (the HTML report was retired at checkpoint A8). Then:

```bash
cd web
npm ci                      # once, with a network
npm run local               # http://127.0.0.1:3000, no network needed
npm run local:stop          # stops the local database (Ctrl+C stops the web server)
```

`npm run local` (`scripts/local.ts`) creates a private PostgreSQL cluster in <repo>/.local/pgdata on 127.0.0.1:5434 with a random password, adds `DATABASE_URL` and `AUTH_SECRET` to web/.env.local if they are missing, applies the migrations, ingests every bundle under `bundles/` oldest first (so the newest weekly run is published), runs the SQL data checks (`npm run db-check`) and prints any violation, builds only when the sources changed, and serves on 127.0.0.1:3000. Secrets are never printed. The evidence page needs the backtest bundle: run `Rscript scripts/write_backtest_bundle.R` once. Settings: `PG_BIN` (PostgreSQL's bin directory; default `C:/Program Files/PostgreSQL/17/bin` on Windows, PATH elsewhere), `NFL_LOCAL_PGDATA`, `NFL_LOCAL_PGPORT`, `NFL_LOCAL_BUNDLES`. The font is committed (`src/app/fonts/archivo-latin.woff2`, SIL OFL), so a build needs no network either.

Online, the deployed app reads the same bundle: `.github/workflows/weekly-sim.yml` (started by hand with a week and season) runs `run_week.R`, checks the bundle with `npm run check-bundle` (the ingest's own loader, no database), keeps it as an artifact for 90 days, and runs `npm run ingest` against the deployed database only when the `DATABASE_URL` secret exists. Deployment is pending the owner's approval of the hosting connectors.

### View the online run's bundle offline (while nothing is deployed)

The workflow keeps its bundle as the `sim-bundle` artifact. `download-artifact` writes the bundle's files (with `manifest.json`) at the root of the directory you give it, which is exactly the layout `npm run local` discovers (a directory under `bundles/` with `manifest.json` at its root):

```bash
gh run download <run-id> -n sim-bundle -D bundles/<cycle_id>   # <cycle_id> is the "cycle_id" in the downloaded manifest.json
cd web && npm run local
```

Or put the directory anywhere and point `NFL_LOCAL_BUNDLES` at its parent. The offline app then shows the same pages from the same code and the same data as the deployed one would. If you download straight into `bundles/` the runner says that a `manifest.json` outside a cycle directory is not ingested.

### Offline and online look the same

Both paths run one `next build`; the only difference is who ingested the bundles (`scripts/local.ts` offline, `npm run db:migrate && npm run ingest -- <dir>` online). `e2e/parity.spec.ts` (`@parity`) proves the pages render the same pixels: build once, serve the offline path (`npm run local` with `NFL_LOCAL_BUNDLES` and `NFL_LOCAL_PGDATA` pointing at scratch copies) on :3000 and the online path (`next start -p 3100` with `DATABASE_URL` at a scratch database that received the same bundles through `db:migrate` and `ingest`, oldest first), then:

```bash
E2E_BASE_URL=http://127.0.0.1:3000 E2E_PARITY_SNAPSHOTS=<scratch>/parity npx playwright test --grep @parity --update-snapshots
E2E_BASE_URL=http://127.0.0.1:3100 E2E_PARITY_SNAPSHOTS=<scratch>/parity npx playwright test --grep @parity   # zero differing pixels
```

It covers every public page (home, two game pages, evidence, methodology, data health, props, login, not found) and `/desk` after login at 390, 768 and 1440 px in light and dark. `E2E_PARITY_GAMES` names the game pages. The one masked element is `[data-age]` ("x min ago" reads the request-time clock). CI runs it in the `parity` job of `ci-web.yml`.

## Run it locally (development)

You need Node 20.9+ and a Postgres 16+ you can create databases on.

```bash
cd web
npm ci
export DATABASE_URL=postgres://USER:PASS@127.0.0.1:5432/nfl_dev
export AUTH_SECRET=$(openssl rand -base64 32)   # sessions; never commit it
npm run db:migrate
npm run ingest -- ../contracts/fixtures/bundles/weekly-2026-w04
npm run ingest -- ../contracts/fixtures/bundles/backtest-nfl-games-v1
DESK_EMAIL=you@example.test DESK_PASSWORD='12+ characters' npm run seed:user
npm run build && npm run start   # or: npm run dev
```

Every page renders on demand from the database (the CSP nonce requires it). A committed ingest is live on the next request.

## Checks

| Command | What it proves |
|---|---|
| `npm run typecheck` | TypeScript, strict |
| `npm run lint` | ESLint (`eslint-config-next`) |
| `npm test` | vitest: contract drift, shared row fixtures, CSP, passwords, policy, slop scan, docs truth, offline fonts, design language, the local runner's rules, score distributions |
| `TEST_DATABASE_URL=postgres://…/nfl_test REQUIRE_DB_TESTS=1 npm test` | adds the Postgres suites: ingest idempotency, tamper rejection, the qa_failed pointer, append-only triggers, the tier/stake CHECK, and public queries without stakes. The database name must end in `_test`; the harness drops its schema. |
| `npm run e2e -- --grep-invert @sim` | Playwright against a running server (`E2E_BASE_URL`, default `http://127.0.0.1:3100`) with the fixture bundles: axe, overflow, security headers, `/desk` redirect, stakes never public, ID leaks, reduced motion, and offline rendering (every request served by this server) |
| `npx playwright test --grep @sim` | with a simulator run published (the committed `weekly-sim-2024-w15` fixture, or `E2E_SIM_BUNDLE` pointing at a run's bundle): the market and simulator probabilities on the pages equal the bundle's at the displayed precision, and the margin and total distributions render with no axe issue |
| `E2E_PARITY_SNAPSHOTS=<dir> npx playwright test --grep @parity` | offline versus online pixel parity (see above); skips without the variable |
| `npm run contracts:export` | regenerates `contracts/schema/*.json` from the Drizzle schema; CI fails if the committed files differ |
| `npm run erd` | writes `docs/ERD.md`, the data model as a Mermaid ERD generated from `src/db/schema.ts`; `src/lib/erd.test.ts` fails when the file is stale (`npm run erd -- --check` says so too) |
| `npm run db-check` | SQL data checks against `DATABASE_URL` (`src/lib/dbcheck/checks.ts`): every assertion query must return zero rows. Errors exit 1 and warnings are printed. They run after every ingest: in CI, in the deployed ingest (`weekly-sim.yml`) and in `npm run local` |

`scripts/review-ui.mjs` takes full-page screenshots at 390, 768 and 1440 px in both themes and prints overflow, console and axe results for a visual review (`GAME=<game_id>` picks the game page; default `2026_04_DEN_SF` from the fixture).

## The contract

`src/db/schema.ts` is the single owner. `src/lib/contracts/bundle.ts` derives a zod row schema per bundle table with drizzle-zod, and `npm run contracts:export` writes those schemas to `contracts/schema/`, where `R/bundle_writer.R` validates rows before it writes. `contracts/fixtures/rows.json` holds valid and invalid rows. Both validators must agree on every one of them (`src/lib/contracts/bundle.test.ts` and `tests/testthat/test-bundle-writer.R`).

A bundle is `bundles/<cycle_id>/manifest.json` plus one JSON array per table. The ingest (`src/lib/ingest/ingest.ts`):

1. checks every file's sha256 and row count against the manifest, the schema major version, and every row;
2. writes the bundle in one transaction and is idempotent on the manifest's sha256;
3. stores a QA-failed bundle as `qa_failed` without moving the publish pointer.

Bundle tables: `teams`, `games`, `venues`, `markets`, `game_predictions`, `score_distributions`, `recommendations`, `source_status`, `eval_windows`, `backtest_runs`, `backtest_metrics`, `calibration_bins`, `promotion_gates`, `clv_picks`, `evidence_ledger`.

## Security

- Per-request CSP nonce (`src/lib/security/csp.ts`, set in `src/proxy.ts`) plus static headers (`src/lib/security/securityHeaders.mjs`).
- Passwords are scrypt (N=65536, r=8, p=2) and checked in constant time. A DB-backed throttle applies per account, per IP and globally. Seeding the user again bumps `session_version`, which revokes existing sessions.
- `/desk` calls `requireUser()`. Public pages select public columns only, and stakes are never rendered on them (tested at both the query and the page level).

# Broadcast Line (web)

The public site and private desk for the NFL model. The web app reads only from Postgres. The R engine writes bundles, and the ingest CLI loads them. Design and contract: `docs/superpowers/specs/2026-09-28-nfl-overhaul-design.md` §3–4.

**Stack:** Next.js 16 (App Router, `src/proxy.ts`), React 19, Tailwind 4, Drizzle ORM on Postgres (postgres.js), next-auth v5 (credentials, JWT sessions), and visx scales for the charts.

## Run it locally

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
| `npm test` | vitest: contract drift, shared row fixtures, CSP, passwords, policy, slop scan, docs truth |
| `TEST_DATABASE_URL=postgres://…/nfl_test REQUIRE_DB_TESTS=1 npm test` | adds the Postgres suites: ingest idempotency, tamper rejection, the qa_failed pointer, append-only triggers, the tier/stake CHECK, and public queries without stakes. The database name must end in `_test`; the harness drops its schema. |
| `npm run e2e` | Playwright against a running server (`E2E_BASE_URL`, default `http://127.0.0.1:3100`): axe, overflow, security headers, `/desk` redirect, stakes never public, ID leaks, reduced motion |
| `npm run contracts:export` | regenerates `contracts/schema/*.json` from the Drizzle schema; CI fails if the committed files differ |

`scripts/review-ui.mjs` takes full-page screenshots at 390, 768 and 1440 px in both themes and prints overflow, console and axe results for a visual review.

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

# reports/

Committed, dated evidence. One folder per date: `reports/YYYY-MM-DD/`.

Rules:
- Files here are **frozen** once committed. A correction is a new dated file that says what it supersedes.
- A backtest writes its `PROTOCOL.md` (and its sha256) **before** scoring, then `RESULT.md` after. The pair is the evidence.
- Never commit raw command output, secrets, or raw odds captures (those live in `data/raw_capture/`, gitignored, archived as release assets).
- Any claim in README/CLAUDE.md/docs that states a metric must cite a file in this folder through `docs/EVIDENCE_LEDGER.md`.
- `reports/history/` holds superseded audit documents moved out of the repo root.

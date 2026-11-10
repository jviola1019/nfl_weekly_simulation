# The scheduled weekly simulation failed at "Resolve the week" (2026-11-07)

**Status: fixed in this change.** One finding is recorded for the owner: `renv.lock` records 29 packages nothing uses.

## The failure

- **The run:** `Weekly simulation`, run 42319264760, event `schedule`, 2026-11-07 00:36Z, on `85fd35a`. It was the workflow's first scheduled run; the Friday 21:00Z cron started 3 h 36 min late.
- **The step:** "Resolve the week (empty inputs mean the upcoming week from the nflverse schedule)", in job `simulate`.
- **The log:**

  ```
  Auto-resolved 2026 week 9 (15 games, first kickoff Thu 2026-11-05 20:15 ET)
  ##[error]Unable to process file command 'output' successfully.
  ##[error]Invalid format '- The project is out-of-sync -- use `renv::status()` for details.'
  ```

- **What was lost:** week 9's Friday bundle from the workflow. Nothing was ingested anywhere, because no database is configured.

## The cause

- **The step** ran `Rscript scripts/resolve_week.R "$WEEK" "$SEASON" >> "$GITHUB_OUTPUT"`. Every line R wrote to stdout became a step output.
- **renv** prints "- The project is out-of-sync ..." to stdout when R starts in a project whose lockfile, library and code disagree. GitHub rejects a line that is not `name=value`.
- **The week was resolved correctly.** Only the hand-off to the next step failed.
- **Why the tests passed:** the script's test ran it with `--vanilla`, which skips the project start-up that the workflow has. The workflow test pinned the redirect itself.

## The fix

- **`scripts/resolve_week.R`** appends `week=` and `season=` to the file `$GITHUB_OUTPUT` names (binary append, LF endings). It still prints both lines.
- **`.github/workflows/weekly-sim.yml`** no longer redirects the script's stdout.
- **Tests,** each seen failing first:
  - `test-run-config.R`: with a start-up profile that prints renv's line, the output file holds exactly the two lines after what was already in it;
  - `test-workflows.R`: the step is pinned without the redirect;
  - `test-workflows.R`: no workflow step may append an R process's stdout to `$GITHUB_OUTPUT`, `$GITHUB_ENV` or `$GITHUB_PATH`.

## Why renv calls the project out of sync (recorded, not changed)

`renv::status()` (renv 1.1.7) on this commit, with every recorded package installed (`renv_status.txt`):

- **29 packages are recorded in `renv.lock` and used by nothing:** `bayestestR`, `broom.mixed`, `caret`, `class`, `clock`, `coda`, `datawizard`, `diagram`, `doParallel`, `e1071`, `future.apply`, `gbm`, `gower`, `hardhat`, `insight`, `ipred`, `KernSmooth`, `lava`, `ModelMetrics`, `performance`, `plyr`, `pROC`, `prodlim`, `proxy`, `recipes`, `reshape2`, `rpart`, `sparsevctrs`, `SQUAREM`.
- **No R file names** `caret`, `gbm`, `performance`, `broom.mixed`, `doParallel` or `diagram` as a package (`git grep`).
- **`gt` and `reactable` are not on the list,** although no code uses them: `DESCRIPTION` still imports `gt`, and `gt` brings `reactable`.
- **The `pkgload` row** in `renv_status.txt` belongs to the local library the check ran against, not to CI.

**The owner's decision:** remove the unused packages from `renv.lock`, and `gt` from `DESCRIPTION`. It changes `renv.lock`, so it is not done here. The golden master runs on such a change and is expected to show no differences.

## Reproduce

```bash
# renv's status for a checkout, against libraries that hold every recorded package
Rscript --vanilla reports/2026-11-10/weekly-sim/renv_status.R <checkout> <library> [<library> ...]

# the script as the workflow step runs it
GITHUB_OUTPUT=<file> Rscript scripts/resolve_week.R "" ""
```

# =============================================================================
# GitHub Actions workflows (A8). actionlint is not installed here, so every workflow must
# at least parse as YAML with read-only contents permission, and weekly-sim.yml (the
# online path: the same simulator bundle the offline app reads) must keep its job graph,
# its season guard and its secret gate: nothing is ingested unless DATABASE_URL exists.
# =============================================================================

wf_dir <- file.path(.test_project_root, ".github", "workflows")
wf_read <- function(name) yaml::read_yaml(file.path(wf_dir, name))
wf_on <- function(w) if (!is.null(w[["on"]])) w[["on"]] else w[["TRUE"]]   # YAML 1.1 reads the key `on` as TRUE
wf_runs <- function(job) paste(vapply(job$steps, function(s) if (is.null(s$run)) "" else s$run, ""), collapse = "\n")
wf_uses <- function(job) vapply(job$steps, function(s) if (is.null(s$uses)) "" else s$uses, "")

test_that("every workflow parses as YAML and grants read-only contents permission", {
  files <- list.files(wf_dir, pattern = "\\.ya?ml$")
  expect_true("weekly-sim.yml" %in% files)
  for (f in files) {
    w <- wf_read(f)
    expect_true(is.list(w$jobs) && length(w$jobs) > 0, info = f)
    expect_identical(w$permissions, list(contents = "read"), info = f)
  }
})

test_that("weekly-sim runs on demand with an explicit week and season, and refuses the sealed 2025", {
  w <- wf_read("weekly-sim.yml")
  on <- wf_on(w)
  expect_identical(names(on), "workflow_dispatch")
  expect_true(isTRUE(on$workflow_dispatch$inputs$week$required) && isTRUE(on$workflow_dispatch$inputs$season$required))
  sim <- w$jobs$simulate
  expect_match(wf_runs(sim), 'if [ "$SEASON" = "2025" ]; then', fixed = TRUE)
  expect_match(wf_runs(sim), 'Rscript run_week.R "$WEEK" "$SEASON"', fixed = TRUE)
})

test_that("weekly-sim rejects a malformed week or season before anything else runs (final review M5)", {
  sim <- wf_read("weekly-sim.yml")$jobs$simulate
  runs <- vapply(sim$steps, function(s) if (is.null(s$run)) "" else s$run, "")
  guard <- which(grepl("[0-9]{1,2}", runs, fixed = TRUE) & grepl("[0-9]{4}", runs, fixed = TRUE))
  sealed <- which(grepl('"$SEASON" = "2025"', runs, fixed = TRUE))
  expect_length(guard, 1)
  expect_lt(guard, sealed)   # the input check runs before the 2025 check
  expect_match(runs[guard], '"$WEEK" =~ ^[0-9]{1,2}$', fixed = TRUE)
  expect_match(runs[guard], '"$SEASON" =~ ^[0-9]{4}$', fixed = TRUE)
  expect_match(runs[guard], "::error::", fixed = TRUE)
  env <- sim$steps[[guard]]$env
  expect_identical(env$WEEK, "${{ inputs.week }}")      # via env, never interpolated into the script
  expect_identical(env$SEASON, "${{ inputs.season }}")
})

test_that("weekly-sim builds the bundle with the same R path as the local app, checks it and keeps it", {
  sim <- wf_read("weekly-sim.yml")$jobs$simulate
  uses <- wf_uses(sim)
  expect_true(all(c("actions/checkout@v4", "r-lib/actions/setup-r@v2", "r-lib/actions/setup-renv@v2",
                    "actions/setup-node@v4", "actions/upload-artifact@v4") %in% uses))
  setup_r <- sim$steps[[which(uses == "r-lib/actions/setup-r@v2")]]
  expect_identical(setup_r$with$`r-version`, "4.5.1")
  setup_node <- sim$steps[[which(uses == "actions/setup-node@v4")]]
  expect_equal(setup_node$with$`node-version`, 22)  # the Node ci-web.yml tests on
  runs <- wf_runs(sim)
  expect_match(runs, "npm run check-bundle --", fixed = TRUE)
  # run_week.R is the only bundle writer: it calls R/sim_bundle.R's write_sim_bundle(), as for npm run local
  run_week <- readLines(file.path(.test_project_root, "run_week.R"), warn = FALSE)
  expect_true(any(grepl("write_sim_bundle(", run_week, fixed = TRUE)))
  upload <- sim$steps[[which(uses == "actions/upload-artifact@v4")]]
  expect_identical(upload$with$name, "sim-bundle")
  expect_identical(upload$with$`if-no-files-found`, "error")
})

test_that("weekly-sim ingests only after the bundle is built and only when the DATABASE_URL secret exists", {
  jobs <- wf_read("weekly-sim.yml")$jobs
  expect_setequal(names(jobs), c("simulate", "gate", "ingest"))
  expect_setequal(unlist(jobs$ingest$needs), c("simulate", "gate"))
  expect_identical(jobs$ingest$`if`, "needs.gate.outputs.has_db == 'true'")
  gate_step <- jobs$gate$steps[[1]]
  expect_identical(gate_step$env$DATABASE_URL, "${{ secrets.DATABASE_URL }}")
  expect_match(gate_step$run, 'if [ -n "$DATABASE_URL" ]', fixed = TRUE)
  expect_identical(jobs$gate$outputs$has_db, "${{ steps.check.outputs.has_db }}")
  ingest_runs <- wf_runs(jobs$ingest)
  expect_match(ingest_runs, "npm run db:migrate", fixed = TRUE)
  expect_match(ingest_runs, "npm run ingest -- ../sim-bundle", fixed = TRUE)
  # the secret reaches only the gate and the ingest step, never the simulation
  expect_false(grepl("secrets.", paste(unlist(jobs$simulate), collapse = " "), fixed = TRUE))
})

test_that("odds-capture's game-day runs start about 3 h 45 min before kickoff (owner A0, 2026-10-19)", {
  crons <- vapply(wf_on(wf_read("odds-capture.yml"))$schedule, `[[`, "", "cron")
  expect_identical(crons, c("0 18 * * 2", "0 18 * * 4", "30 20 * * 4", "0 18 * * 6",
                            "15 13 * * 0", "20 16 * * 0", "35 20 * * 0", "30 20 * * 1"))
})

test_that("capture-archive keeps the raw captures past their 90-day artifact life, and only it can write", {
  w <- wf_read("capture-archive.yml")
  on <- wf_on(w)
  expect_setequal(names(on), c("schedule", "workflow_dispatch"))
  job <- w$jobs$archive
  # the write grant is job-level and as narrow as releases allow; the top level stays read-only
  expect_identical(job$permissions, list(contents = "write", actions = "read"))
  runs <- wf_runs(job)
  expect_match(runs, "--workflow odds-capture.yml", fixed = TRUE)
  expect_match(runs, "gh run download", fixed = TRUE)
  expect_match(runs, "sha256sum", fixed = TRUE)
  expect_match(runs, "gh release create", fixed = TRUE)
  # a hand-started backfill is bounded to the artifacts' 90-day life and validated first
  expect_match(runs, '[[ ! "$DAYS" =~ ^[0-9]{1,2}$ ]]', fixed = TRUE)
  expect_match(runs, '"$DAYS" -gt 90', fixed = TRUE)
  # no other workflow is granted write access
  others <- setdiff(list.files(wf_dir, pattern = "\\.ya?ml$"), "capture-archive.yml")
  for (f in others) {
    for (j in wf_read(f)$jobs) expect_false(identical(j$permissions$contents, "write"), info = f)
  }
})

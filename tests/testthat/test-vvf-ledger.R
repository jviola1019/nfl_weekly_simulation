# The variable ledger (docs/VARIABLE_LEDGER.md) is generated from the registry
# and the committed VVF results (design 2026-10-20 §5): this docs-truth test
# fails when the two disagree, and checks that every row's evidence exists.

vl <- vvf_test_env(c("common.R", "registry.R", "s1_screen.R", "input_schema.R", "ledger.R"))

test_that("the committed ledger equals a fresh render of the registry and results", {
  withr::local_dir(PROJECT_ROOT)
  expect_identical(vl$vvf_render_ledger(), readLines(file.path("docs", "VARIABLE_LEDGER.md"), warn = FALSE))
})

test_that("every registry row, defect and disclosure appears in the ledger", {
  withr::local_dir(PROJECT_ROOT)
  txt <- vl$vvf_render_ledger()
  reg <- vl$vvf_registry()
  for (nm in reg$name) expect_true(any(startsWith(txt, sprintf("| `%s` |", nm))), info = nm)
  ids <- unique(unlist(lapply(reg$defects, function(ds) vapply(ds, `[[`, "", "id"))))
  for (id in ids) expect_true(any(grepl(sprintf("^\\| %s \\|", id), txt)), info = id)
  for (id in vl$vvf_disclosures()$id) expect_true(any(grepl(sprintf("^\\| %s \\|", id), txt)), info = id)
})

test_that("every screened feature carries its close-anchored S1 and S2 results, with the run's hash", {
  withr::local_dir(PROJECT_ROOT)
  txt <- vl$vvf_render_ledger()
  meta <- jsonlite::read_json(file.path("reports", "2026-10-22", "vvf-v2-repro", "run_meta.json"))
  expect_true(any(grepl(meta$result_sha256, txt, fixed = TRUE)))
  for (f in vl$VVF_V2_FEATURES) {
    row <- txt[startsWith(txt, sprintf("| `%s` |", f))]
    expect_match(row, "\\| [0-9.]+ / [0-9.]+ / [0-9.]+ \\|", info = f)
  }
  expect_match(txt[startsWith(txt, "| `cold_obs` |")], "not screened \\(post-hoc\\)")
})

test_that("every unit test the registry names exists, and pipes inside cells are escaped", {
  withr::local_dir(PROJECT_ROOT)
  reg <- vl$vvf_registry()
  paths <- unique(reg$unit_test[startsWith(reg$unit_test, "tests/")])
  for (p in paths) expect_true(file.exists(p), info = p)
  expect_identical(vl$vvf_md_cell("|p - 0.5| > 0.3"), "\\|p - 0.5\\| > 0.3")
  txt <- vl$vvf_render_ledger()
  expect_true(all(grepl("^[ -~]*$", txt)))   # ASCII only, so the bytes match on every OS
})

test_that("the ledger shows each feature's S3 skill and admission from the committed A3b run", {
  withr::local_dir(PROJECT_ROOT)
  txt <- vl$vvf_render_ledger()
  run <- file.path("reports", "2026-10-28", "vvf-a3b-close")
  s3 <- data.table::fread(file.path(run, "s3_skill.csv"))
  s1 <- data.table::fread(file.path("reports", "2026-10-22", "vvf-v2-repro", "s1_features.csv"))[family == "outcome"]
  meta <- jsonlite::read_json(file.path(run, "run_meta.json"))
  expect_true(any(grepl(meta$result_sha256, txt, fixed = TRUE)))
  r <- s3[feature == "lp_anchor"]
  expect_match(txt[startsWith(txt, "| `lp_anchor` |")], sprintf("%.4f [%.4f, %.4f]", r$skill, r$skill_lo, r$skill_hi), fixed = TRUE)
  for (f in vl$VVF_V2_FEATURES) {
    adm <- vl$vvf_admission(s1[feature == f, q_bh], s3[feature == f, verdict], meta$s4_status)
    expect_match(txt[startsWith(txt, sprintf("| `%s` |", f))], adm, fixed = TRUE, info = f)
  }
})

test_that("admission follows S3, then S1, then S4", {
  sk <- "incremental skill (CI above 0, BH p < 0.05)"
  expect_identical(vl$vvf_admission(0.01, "no incremental skill", "complete"), "excluded: no incremental skill on Tune (S3)")
  expect_identical(vl$vvf_admission(NA_real_, NA_character_, "complete"), "excluded: no incremental skill on Tune (S3)")
  expect_identical(vl$vvf_admission(0.20, sk, "complete"), "excluded: no S1 signal (q >= 0.05)")
  expect_identical(vl$vvf_admission(0.01, sk, "void"), "held: S4 void")
  expect_identical(vl$vvf_admission(0.01, sk, "complete"), "candidate: Confirm 2023-24 under G3")
})

test_that("the ledger draws the input ERD and shows its checks against the data", {
  withr::local_dir(PROJECT_ROOT)
  txt <- vl$vvf_render_ledger()
  erd <- vl$vvf_render_erd()
  i <- which(txt == "```mermaid")
  expect_length(i, 1L)
  expect_identical(txt[(i + 1L):(i + length(erd))], erd)
  expect_identical(txt[i + length(erd) + 1L], "```")
  expect_true(any(txt == "| reference resolves | injuries_qb | game_id, team -> injuries_team.game_id, team | 0 |"))
  expect_false(any(grepl(paste0("^\\| (key complete|key unique|reference complete|reference resolves|team in game|rows per game|",
                                "no sealed season) \\|.* \\| ([1-9][0-9]*|-) \\|$"), txt)))
})

test_that("an S3 run without an S4 status is refused, never read as void (review M-18)", {
  dir <- withr::local_tempdir()
  data.table::fwrite(data.table::data.table(feature = "rest_diff", skill = 0, skill_lo = -0.001, skill_hi = 0.001,
                                            verdict = "no incremental skill"), file.path(dir, "s3_skill.csv"))
  jsonlite::write_json(list(result_sha256 = "x"), file.path(dir, "run_meta.json"), auto_unbox = TRUE)
  expect_error(vl$vvf_ledger_results(data.table::data.table(dir = dir)), "has no s4_status")
})

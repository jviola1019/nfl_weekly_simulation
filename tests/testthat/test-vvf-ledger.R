# The variable ledger (docs/VARIABLE_LEDGER.md) is generated from the registry
# and the committed VVF results (design 2026-10-20 §5): this docs-truth test
# fails when the two disagree, and checks that every row's evidence exists.

vl <- vvf_test_env(c("common.R", "registry.R", "ledger.R"))

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

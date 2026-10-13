# =============================================================================
# The legacy HTML report is retired (checkpoint A8; spec §5 Phase 8). Results are
# viewed in the local web app; the computations other code uses are kept.
# =============================================================================

RETIRED_FUNCTIONS <- c("export_moneyline_comparison_html", "open_moneyline_report", "moneyline_report",
                       "validate_moneyline_report_schema", "moneyline_report_schema_contract",
                       "render_model_status_banner", "html_escape_cell")

test_that("no R file defines or calls the retired report functions", {
  files <- c(list.files(.test_project_root, pattern = "\\.R$", full.names = TRUE),
             list.files(file.path(.test_project_root, c("R", "scripts", "tests/testthat", "sports/nfl/props")),
                        pattern = "\\.R$", full.names = TRUE))
  files <- setdiff(normalizePath(files, winslash = "/"),
                   normalizePath(file.path(.test_project_root, "tests/testthat/test-report-retired.R"), winslash = "/"))
  hits <- character()
  for (f in files) {
    names_used <- tryCatch(all.names(parse(f, keep.source = FALSE)), error = function(e) character())
    found <- intersect(RETIRED_FUNCTIONS, names_used)
    if (length(found)) hits <- c(hits, sprintf("%s: %s", basename(f), paste(found, collapse = ", ")))
  }
  expect_equal(hits, character())
  expect_false(file.exists(file.path(.test_project_root, "R", "report_banner.R")))
})

test_that("NFLmarket.R keeps the comparison computations and drops the HTML hooks", {
  env <- nflmarket_env()
  for (fn in RETIRED_FUNCTIONS) expect_false(exists(fn, envir = env, inherits = FALSE), info = fn)
  expect_true(is.function(env$build_moneyline_comparison_table))
  expect_true(is.function(env$evaluate_market_vs_blend))
  expect_false(any(c("html_output_path", "html_vig", "html_title") %in% names(formals(env$evaluate_market_vs_blend))))
})

test_that("NFLsimulation.R still saves its run logs and exports draws for props, and renders no widget", {
  code <- readLines(file.path(.test_project_root, "NFLsimulation.R"), warn = FALSE, encoding = "UTF-8")
  for (line in c('saveRDS(final, file.path(log_dir, paste0("final_", run_id, ".rds")))',
                 'saveRDS(games_ready, file.path(log_dir, paste0("games_ready_", run_id, ".rds")))',
                 'assign("last_simulation_results", last_simulation_results, envir = .GlobalEnv)',
                 "moneyline_report_inputs <- list(")) {
    expect_true(any(grepl(line, code, fixed = TRUE)), info = line)
  }
  expect_false(any(grepl("reactable|gt_available|pal_fav|pal_total|primary_report_tbl|has_namespace", code)))
})

test_that("every static anchor in scripts/audit_verify.sh (CI) still matches its file", {
  sh <- readLines(file.path(.test_project_root, "scripts", "audit_verify.sh"), warn = FALSE)
  anchors <- regmatches(sh, regexec('^rg -n "(.+)" (\\S+) >/dev/null$', sh))
  anchors <- Filter(length, anchors)
  expect_gte(length(anchors), 3L)
  for (a in anchors) {
    src <- readLines(file.path(.test_project_root, a[[3]]), warn = FALSE, encoding = "UTF-8")
    expect_true(any(grepl(a[[2]], src, perl = TRUE)), info = sprintf("%s in %s", a[[2]], a[[3]]))
  }
})

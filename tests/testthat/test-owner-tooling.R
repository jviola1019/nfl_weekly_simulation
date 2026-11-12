# =============================================================================
# The owner's shell is Windows PowerShell 5.1. It rejects `&&` ("not a valid statement separator"),
# has no `export`, cannot run a .sh file, and `R` is its alias for Invoke-History. A command the
# owner copies from these documents, or reads in the run's console output, must run there as
# written (each form was run in PowerShell 5.1 on 2026-11-11 and 2026-11-12; CHANGELOG.md has the results).
# =============================================================================

PS_FILES <- c("README.md", "GETTING_STARTED.md", "CLAUDE.md", "docs/API.md", "docs/modeling.md",
              "run_week.R", "R/sim_bundle.R")
PS_BASH_ONLY <- c("`&&` between commands" = "(cd [A-Za-z_./]+|npm [a-z: -]+) &&",
                  "`export VAR=`" = "^\\s*export [A-Z_]+=",
                  "`R -e` (use Rscript -e)" = "^\\s*R -e ",
                  "a .sh script" = "^\\s*(\\./|bash )scripts/[a-z_]+\\.sh",
                  "`VAR=value command`" = "^\\s*[A-Z][A-Z0-9_]+=\\S.* (npm|npx|Rscript) ")

test_that("no command in the owner-facing documents or console hints needs bash", {
  for (f in PS_FILES) {
    lines <- readLines(file.path(.test_project_root, f), warn = FALSE)
    for (what in names(PS_BASH_ONLY)) {
      hit <- grep(PS_BASH_ONLY[[what]], lines)
      expect_identical(sprintf("%s:%d", f, hit), character(0), info = what)
    }
  }
})

test_that("the patterns catch the forms PowerShell 5.1 rejects, and leave its own forms alone", {
  rejected <- c("cd web && npm run local", "cd web && npm run typecheck && npm run lint && npm test",
                "export HOME=$(mktemp -d)", "R -e \"renv::restore()\"", "./scripts/audit_verify.sh",
                "E2E_SIM_BUNDLE=<bundle dir> npm run e2e")
  accepted <- c("npm --prefix web run local", "Rscript -e \"renv::restore()\"", "Rscript scripts/run_tests.R",
                "$env:E2E_SIM_BUNDLE = \"<bundle dir>\"; npm --prefix web run e2e", "cd web")
  caught <- function(x) any(vapply(PS_BASH_ONLY, function(p) grepl(p, x), TRUE))
  expect_true(all(vapply(rejected, caught, TRUE)))
  expect_false(any(vapply(accepted, caught, TRUE)))
})

test_that(".lintr parses, so the editor can lint R files", {
  # .lintr is a DCF file: a continuation line must start with white space. A closing parenthesis in
  # column 1 made lintr stop with "Malformed config file", and VS Code showed that on every R file.
  cfg <- read.dcf(file.path(.test_project_root, ".lintr"))
  expect_setequal(colnames(cfg), c("linters", "exclusions"))
})

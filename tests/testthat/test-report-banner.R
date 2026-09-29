test_that("banner derives every number from its arguments", {
  html <- render_model_status_banner(0.70, 0.125, 0.02, "paper")
  expect_match(html, "70% market weight", fixed = TRUE)
  expect_match(html, "1/8 Kelly", fixed = TRUE)
  expect_match(html, "2% max stake", fixed = TRUE)
  expect_false(grepl("60%", html, fixed = TRUE))
})

test_that("banner states the model is unvalidated and stakes are paper", {
  html <- render_model_status_banner(0.70, 0.125, 0.02, "paper")
  expect_match(html, "Unvalidated model", fixed = TRUE)
  expect_match(html, "Paper stakes", fixed = TRUE)
  expect_match(html, "docs/EVIDENCE_LEDGER.md", fixed = TRUE)
})

test_that("banner refuses missing or invalid inputs instead of printing NA", {
  expect_error(render_model_status_banner(NA, 0.125, 0.02, "paper"), "shrinkage")
  expect_error(render_model_status_banner(0.7, 0.125, 0.02, "yolo"), "staking_mode")
  expect_error(render_model_status_banner(1.2, 0.125, 0.02, "paper"), "shrinkage")
})

test_that("config declares paper staking by default", {
  expect_identical(STAKING_MODE, "paper")
})

test_that("html_escape_cell escapes markup and blanks NA", {
  expect_identical(html_escape_cell("<script>alert(1)</script>"), "&lt;script&gt;alert(1)&lt;/script&gt;")
  expect_identical(html_escape_cell("A&B <b>"), "A&amp;B &lt;b&gt;")   # text content: quotes need no escaping
  expect_identical(html_escape_cell(NA), "")
  expect_identical(html_escape_cell(3.5), "3.5")
})

# Source guards (static): the report must not load remote scripts, and the
# no-gt fallback must escape cell values (audit SEC3, SEC4, U5).
test_that("NFLmarket.R loads no CDN scripts and escapes fallback cells", {
  src <- readLines(file.path(PROJECT_ROOT, "NFLmarket.R"), warn = FALSE, encoding = "UTF-8")
  expect_false(any(grepl("cdnjs|three\\.min\\.js", src)))
  expect_true(any(grepl("display_value <- html_escape_cell(cell_value)", src, fixed = TRUE)))
})

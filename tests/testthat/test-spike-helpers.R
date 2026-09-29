source(file.path(.test_project_root, "scripts", "spike", "spike_helpers.R"))

test_that("kalshi_event_date parses YYMONDD tickers", {
  expect_equal(kalshi_event_date("KXNFLANYTD-26JAN25LASEA"), as.Date("2026-01-25"))
  expect_equal(kalshi_event_date("KXNFLTD-26SEP28PHICHI"), as.Date("2026-09-28"))
  expect_true(is.na(kalshi_event_date("KXNFLWINS-NO")))
})

test_that("espn_row_is_priced needs an American price on over or under", {
  priced <- list(open = list(over = list(american = "-110"), target = list(value = 45.5)))
  line_only <- list(open = list(target = list(value = 45.5)), current = list(target = list(value = 44.5)))
  expect_true(espn_row_is_priced(priced))
  expect_false(espn_row_is_priced(line_only))
})

test_that("bias_test reports the hit-rate difference and a two-sided p-value", {
  same <- bias_test(50, 100, 500, 1000)
  expect_equal(same$diff, 0)
  expect_gt(same$p_value, 0.9)
  skewed <- bias_test(80, 100, 300, 1000)
  expect_equal(skewed$diff, 0.5)
  expect_lt(skewed$p_value, 1e-6)
})

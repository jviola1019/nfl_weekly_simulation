# Audit M2/M3: exactly one market-weight stage, and it never moves away from the market

test_that("final probability never moves away from the market (single-stage invariant)", {
  set.seed(5)
  p_model <- runif(500, 0.05, 0.95); p_mkt <- runif(500, 0.05, 0.95)
  p_final <- shrink_probability_toward_market(p_model, p_mkt, shrinkage = SHRINKAGE)
  expect_true(all(abs(p_final - p_mkt) <= abs(p_model - p_mkt) + 1e-12))
  expect_equal(p_final, (1 - SHRINKAGE) * p_model + SHRINKAGE * p_mkt)   # inputs are inside (0.05, 0.95), so clamping is a no-op
})

# Source guards (static): the removed stages must not return (audit M2, M3)
test_that("no dynamic or playoff-specific shrinkage remains", {
  sim <- readLines(file.path(PROJECT_ROOT, "NFLsimulation.R"), warn = FALSE)
  mkt <- readLines(file.path(PROJECT_ROOT, "NFLmarket.R"), warn = FALSE)
  cfg <- readLines(file.path(PROJECT_ROOT, "config.R"), warn = FALSE)
  expect_false(any(grepl("dynamic_shrinkage|get_playoff_shrinkage\\(", sim)))
  expect_false(any(grepl("PLAYOFF_SHRINKAGE|SUPER_BOWL_SHRINKAGE", c(mkt, cfg))))
  expect_false(any(grepl("^(USE_DYNAMIC_SHRINKAGE|SHRINKAGE_BASE|SHRINKAGE_[A-Z_]+_(ADJ|THRESHOLD))\\s*<-", cfg)))
  expect_false(any(grepl("6\\.9% Brier|2\\.1% Brier improvement|Ensemble test Brier:", sim)))
})

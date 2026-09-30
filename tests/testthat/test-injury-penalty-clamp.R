# Audit M16: the offensive injury penalty is clamped to [INJURY_OFF_PTS_FLOOR, 0] and
# counts only offensive non-QB positions; defensive injuries raise opponents' points.
inj_env <- load_script_functions(file.path(PROJECT_ROOT, "NFLsimulation.R"), "calc_injury_impacts")

impacts <- function(rows) inj_env$calc_injury_impacts(as.data.frame(rows), group_vars = "team")

test_that("one questionable WR costs a little, not the old -1.5 floor", {
  r <- impacts(data.frame(team = "AAA", position = "WR", status = "Questionable"))
  expect_lt(r$inj_off_pts, 0)
  expect_gt(r$inj_off_pts, -1.5)
  expect_equal(r$inj_off_pts, -0.20 * INJURY_POS_MULT_SKILL * (1 / 9), tolerance = 1e-12)
  expect_equal(r$inj_def_pts, 0)
})

test_that("many OUT offensive starters hit the floor and not beyond", {
  rows <- data.frame(team = "AAA", position = rep(c("T", "G", "C", "WR", "TE", "RB"), each = 4), status = "Out")
  r <- impacts(rows)
  expect_equal(r$inj_off_pts, INJURY_OFF_PTS_FLOOR)
  expect_gte(r$inj_off_pts, -4.0)
})

test_that("a defensive injury does not lower the team's offensive points", {
  r <- impacts(data.frame(team = "AAA", position = "CB", status = "Out"))
  expect_equal(r$inj_off_pts, 0)
  expect_gt(r$inj_def_pts, 0)
  expect_lte(r$inj_def_pts, INJURY_DEF_PTS_CAP)
})

test_that("teams without injury rows are absent, so callers' coalesce(..., 0) applies", {
  r <- impacts(data.frame(team = c("AAA", "AAA"), position = c("WR", "CB"), status = c("Out", "Out")))
  expect_equal(r$team, "AAA")
  expect_false("BBB" %in% r$team)
})

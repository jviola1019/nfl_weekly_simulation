# Audit M12: every game must get its own reproducible random stream
sim_env <- load_script_functions(file.path(PROJECT_ROOT, "NFLsimulation.R"),
                                 c("simulate_game_nb", "nb_size_from_musd"))
sim_env$NB_SIZE_MIN <- 5; sim_env$NB_SIZE_MAX <- 50; sim_env$SEED <- 471

run_sim <- function(seed, n = 4000) {
  set.seed(seed)
  sim_env$simulate_game_nb(24, 10, 21, 10, n_trials = n, rho = 0.1, cap = 70)
}

test_that("different RNG states give different score streams (audit M12)", {
  expect_false(identical(run_sim(1)$margin, run_sim(2)$margin))
})

test_that("the same RNG state reproduces draws exactly", {
  expect_identical(run_sim(7), run_sim(7))
})

test_that("score means stay within Monte Carlo tolerance of the targets", {
  s <- run_sim(11, n = 40000)
  expect_lt(abs(mean(s$home) - 24), 0.3)
  expect_lt(abs(mean(s$away) - 21), 0.3)
  expect_true(all(s$home >= 0 & s$home <= 70))
})

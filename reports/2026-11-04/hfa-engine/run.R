# One engine run of the golden-master week (Rscript run.R 15 2024, from the repository root) with the home-field
# estimator in env HFA_EST (league, strength_free or team_margin). The run's calibration cache, keyed by the
# estimator, holds the engine's simulated probabilities for every game of the five seasons before 2024.
est <- Sys.getenv("HFA_EST")
stopifnot(est %in% c("league", "strength_free", "team_margin"))
options(nfl_sim.hfa_estimator = est)
source("run_week.R")

# nfl_props_v1 (reports/2026-11-02/props-v1/PROTOCOL.md): the registration matches the frozen files, the confirmatory
# window stays weeks 9-18 of 2026, and the scorer's known-answer run reproduces the exploration's effects.

reg_path <- file.path(PROJECT_ROOT, "backtest", "eval_windows", "nfl_props_v1.json")
# the sha256 of a text file as git stores it (LF), as props_v1_score.R computes it
sha_lf <- function(f) { b <- readBin(f, "raw", file.size(f)); cr <- which(b == as.raw(13L))
  cr <- cr[cr < length(b) & b[pmin(cr + 1L, length(b))] == as.raw(10L)]
  digest::digest(if (length(cr)) b[-cr] else b, algo = "sha256", serialize = FALSE) }

test_that("the props protocol and its registered code match their recorded sha256", {
  reg <- jsonlite::read_json(reg_path, simplifyVector = TRUE)
  expect_identical(reg$protocol_id, "nfl_props_v1")
  expect_identical(sha_lf(file.path(PROJECT_ROOT, reg$protocol_path)), reg$protocol_sha256)
  for (i in seq_len(nrow(reg$code))) {
    expect_identical(sha_lf(file.path(PROJECT_ROOT, reg$code$path[i])), reg$code$sha256[i], label = reg$code$path[i])
  }
  expect_identical(as.integer(reg$weeks), 9:18)
  expect_identical(as.integer(reg$season), 2026L)
  expect_true(isTRUE(reg$kalshi_2025_sealed))
  expect_true(any(grepl("props_v1_score\\.R$", reg$code$path)))
})

test_that("the props scorer's known-answer run reproduces the effects the protocol was built on", {
  ka <- data.table::fread(file.path(PROJECT_ROOT, "reports", "2026-11-02", "props-v1", "known_answer", "props_v1_results.csv"))
  h <- file.path(PROJECT_ROOT, "reports", "2026-10-29", "hypotheses", "out")
  cs <- data.table::fread(file.path(h, "consistency", "consistency_tests.csv"))
  bh <- data.table::fread(file.path(h, "behaviour", "behaviour_tests.csv"))
  cl <- data.table::fread(file.path(PROJECT_ROOT, "reports", "2026-10-28", "feasibility", "props", "close", "close_calibration.csv"))
  mt <- data.table::fread(file.path(h, "model_vs_books", "props_tests.csv"))
  tm <- data.table::fread(file.path(h, "model_vs_books", "props_timing.csv"))
  seen <- c(P1 = cs[id == "A3", estimate], P2 = cs[id == "A5", estimate], P3 = cl[series == "KXNFLPASSINT", slope],
            P4 = bh[id == "B1s", estimate], P5 = mt[forecast == "props module", coef], P6 = tm[id == "MT1", estimate])
  got <- stats::setNames(ka$estimate, ka$id)[names(seen)]
  expect_equal(unname(got), unname(seen), tolerance = 1e-3)
  # one-sided p: half the exploration's two-sided p where its effect was positive, the same where it was one-sided
  expect_equal(ka[id == "P2", p_one_sided], cs[id == "A5", p] / 2, tolerance = 1e-3)
  expect_equal(ka[id == "P4", p_one_sided], bh[id == "B1s", p_greater], tolerance = 1e-3)
  expect_equal(ka[id == "P5", p_one_sided], mt[forecast == "props module", p_one_sided], tolerance = 1e-3)
  expect_equal(ka[id == "P6", p_one_sided], tm[id == "MT1", p_one_sided], tolerance = 1e-3)
  expect_true(all(grepl("^known-answer", ka$mode)))
})

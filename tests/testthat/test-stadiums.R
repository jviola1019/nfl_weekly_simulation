# =============================================================================
# Venues by nflverse stadium_id (audit M21/S3; output audit F6, 2026-10-21)
# =============================================================================
# The engine joined a hand-typed table of 29 venues by NAME. Renamed venues (Heinz Field,
# CenturyLink Field, Mercedes-Benz Superdome, ...), Atlanta's Mercedes-Benz Stadium and every
# international venue fell back to league-average weather in Kansas and lost their roof.
# data/reference/stadiums.csv is keyed by the id nflverse keeps across renames.

stadium_ref_path <- file.path(.test_project_root, "data", "reference", "stadiums.csv")

# Every stadium_id in nflreadr::load_schedules(2006:2026), listed on 2026-10-21 (55 ids; no game
# has an NA id). A new id makes this test fail, so it is added to the reference, not defaulted.
NFLVERSE_STADIUM_IDS_2006_2026 <- c(
  "ATL00", "ATL97", "BAL00", "BOS00", "BUF00", "BUF01", "CAR00", "CHI98", "CIN00", "CLE00",
  "DAL00", "DAL99", "DEN00", "DET00", "FRA00", "GER00", "GNB00", "HOU00", "IND00", "IND99",
  "JAX00", "KAN00", "LAX01", "LAX97", "LAX99", "LON00", "LON01", "LON02", "MAD01", "MEL00",
  "MEX00", "MIA00", "MIN00", "MIN01", "MIN98", "MUN01", "NAS00", "NOR00", "NYC00", "NYC01",
  "OAK00", "PAR00", "PHI00", "PHO00", "PIT00", "RIO00", "SAO00", "SDG00", "SEA00", "SFO00",
  "SFO01", "STL00", "TAM00", "VEG00", "WAS00"
)

test_that("the stadium reference covers every nflverse stadium id, once, with coordinates and a roof type", {
  ref <- load_stadium_reference(stadium_ref_path)
  expect_setequal(ref$stadium_id, NFLVERSE_STADIUM_IDS_2006_2026)
  expect_false(anyDuplicated(ref$stadium_id) > 0)
  expect_true(all(is.finite(ref$lat) & is.finite(ref$lon)))
  expect_true(all(abs(ref$lat) <= 90 & abs(ref$lon) <= 180))
  expect_true(all(ref$roof_type %in% c("outdoors", "dome", "retractable")))
  expect_true(all(nzchar(ref$name)))
})

test_that("US venues sit inside the continental US and the international ones outside it", {
  ref <- load_stadium_reference(stadium_ref_path)
  abroad <- c("BUF01", "FRA00", "GER00", "LON00", "LON01", "LON02", "MAD01", "MEL00", "MEX00",
              "MUN01", "PAR00", "RIO00", "SAO00")
  us <- ref[!ref$stadium_id %in% abroad, ]
  expect_true(all(us$lat > 24 & us$lat < 49.5 & us$lon > -125 & us$lon < -66))
  intl <- ref[ref$stadium_id %in% abroad, ]
  expect_false(any(intl$lat > 24 & intl$lat < 49.5 & intl$lon > -125 & intl$lon < -66 & intl$stadium_id != "BUF01"))
})

test_that("a game is indoors when its roof is closed, or a dome; a pre-game retractable counts as closed", {
  roof      <- c("closed",      "open",        NA,            NA,     NA,         "dome",     "outdoors",    "dome", "closed")
  roof_type <- c("retractable", "retractable", "retractable", "dome", "outdoors", "outdoors", "retractable", "dome", "outdoors")
  # nflverse calls some open-air international venues "dome" (Stade de France, the MCG): the
  # reference's roof type wins, and a venue without a roof is never indoors
  expect_identical(stadium_is_indoor(roof, roof_type), c(TRUE, FALSE, TRUE, TRUE, FALSE, FALSE, FALSE, TRUE, FALSE))
  expect_identical(stadium_is_indoor(character(), character()), logical())
})

test_that("attach_stadiums joins by stadium_id and names any game whose venue is unknown", {
  ref <- load_stadium_reference(stadium_ref_path)
  slate <- data.frame(game_id = c("2026_07_SF_ATL", "2026_07_PIT_NO", "2026_99_X_Y"),
                      stadium_id = c("ATL97", "PAR00", "ZZZ99"), roof = c(NA, "dome", "outdoors"),
                      stringsAsFactors = FALSE)
  expect_message(out <- attach_stadiums(slate, ref), "2026_99_X_Y", fixed = TRUE)
  expect_equal(out$dome, c(TRUE, FALSE, FALSE))              # Atlanta's roof; Paris is open-air
  expect_equal(round(out$lat[1:2], 2), c(33.76, 48.92))
  expect_true(is.na(out$lat[3]) && is.na(out$lon[3]))
  expect_equal(nrow(out), nrow(slate))
})

test_that("the engine joins venues by stadium_id, not by name", {
  src <- readLines(file.path(.test_project_root, "NFLsimulation.R"), warn = FALSE)
  expect_false(any(grepl("stadium_coords <- tribble(", src, fixed = TRUE)))
  expect_true(any(grepl("attach_stadiums(week_slate", src, fixed = TRUE)))
  expect_false(any(grepl("left_join(stadium_coords", src, fixed = TRUE)))
})

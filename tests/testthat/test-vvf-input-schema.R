# The input ERD (backtest/vvf/input_schema.R): every key and reference the
# schema declares holds on the committed inputs, a planted violation of each
# kind is reported, and the Mermaid diagram names every table and relation.

vi <- vvf_test_env(c("common.R", "input_schema.R"), v1_files = VVF_TEST_V1_FILES)

vvf_test_inputs <- function() {
  withr::local_dir(PROJECT_ROOT)
  v1 <- vi$vvf_load_v1_inputs(max_season = vi$VVF_MAX_INPUT_SEASON)
  v2 <- vi$vvf_load_inputs()
  c(v1[c("games", "team_games", "qb_games", "espn_open_close")], v2[c("game_context", "venues", "injuries_team", "injuries_qb")])
}

test_that("the committed inputs satisfy every key and reference in the schema", {
  withr::local_dir(PROJECT_ROOT)
  chk <- vi$vvf_check_inputs(vvf_test_inputs())
  expect_setequal(unique(chk$table), vapply(vi$VVF_INPUT_SCHEMA, `[[`, "", "name"))
  expect_true(all(c("key unique", "reference resolves", "team in game", "rows per game", "no sealed season") %in% chk$check))
  expect_identical(chk[violations > 0, paste(table, check, detail)], character())
  expect_equal(nrow(chk[check == "reference resolves"]), 7L)
})

test_that("a duplicate key, an orphan reference and a third team row are each reported", {
  withr::local_dir(PROJECT_ROOT)
  base <- vvf_test_inputs()
  dup <- data.table::copy(base)
  dup$venues <- rbind(dup$venues, dup$venues[1])
  r <- vi$vvf_check_inputs(dup)
  expect_equal(r[table == "venues" & check == "key unique", violations], 1L)
  orphan <- data.table::copy(base)
  orphan$injuries_qb[1, team := "XXX"]
  r <- vi$vvf_check_inputs(orphan)
  expect_equal(r[table == "injuries_qb" & check == "reference resolves", violations], 1L)
  third <- data.table::copy(base)
  extra <- data.table::copy(third$team_games[1])
  extra[, team := "XXX"]
  third$team_games <- rbind(third$team_games, extra)
  r <- vi$vvf_check_inputs(third)
  expect_equal(r[table == "team_games" & check == "rows per game", violations], 1L)
  expect_equal(r[table == "team_games" & check == "team in game", violations], 1L)
  sealed <- data.table::copy(base)
  sealed$game_context[1, season := 2025L]
  expect_equal(vi$vvf_check_inputs(sealed)[table == "game_context" & check == "no sealed season", violations], 1L)
})

test_that("the ERD names every table and relation in the schema", {
  erd <- vi$vvf_render_erd(vi$VVF_INPUT_SCHEMA)
  expect_identical(erd[1], "erDiagram")
  for (t in vi$VVF_INPUT_SCHEMA) {
    expect_true(any(grepl(sprintf("^  %s \\{$", t$name), erd)), info = t$name)
    for (r in t$refs) expect_true(any(grepl(sprintf("^  %s \\|\\|--o[|{] %s : ", r$table, t$name), erd)), info = paste(r$table, t$name))
  }
  expect_true(any(grepl("^  games \\|\\|--o\\| game_context : ", erd)))     # one context row per game
  expect_true(any(grepl("^  games \\|\\|--o\\{ team_games : ", erd)))       # two team rows per game
  expect_true(all(grepl("^[ -~]*$", erd)))
})

# =============================================================================
# The VVF input ERD: every table the stages read, its key and its references,
# declared once. vvf_check_inputs() verifies them on the data (the SQL-style
# checks before any modelling) and vvf_render_erd() draws them, so the diagram
# in docs/VARIABLE_LEDGER.md and the checks cannot disagree.
# The v1 tables are pinned by backtest/eval_windows/nfl_games_v1.json, the VVF
# tables by backtest/vvf/data/SOURCES.json; both loaders verify the sha256s.
# =============================================================================

vvf_ref <- function(cols, table, table_cols = cols) list(cols = cols, table = table, table_cols = table_cols)

VVF_INPUT_SCHEMA <- list(
  list(name = "games", source = "backtest/data/games.csv", key = "game_id", refs = list()),
  list(name = "team_games", source = "backtest/data/team_games.csv", key = c("game_id", "team"),
       refs = list(vvf_ref("game_id", "games")), team = "team", max_per_game = 2L),
  list(name = "qb_games", source = "backtest/data/qb_games.csv", key = c("game_id", "team", "qb_id"),
       refs = list(vvf_ref(c("game_id", "team"), "team_games"))),
  list(name = "espn_open_close", source = "backtest/data/espn_open_close.csv", key = "game_id",
       refs = list(vvf_ref("game_id", "games"))),
  list(name = "game_context", source = "backtest/vvf/data/game_context.csv", key = "game_id",
       refs = list(vvf_ref("game_id", "games"), vvf_ref("stadium_id", "venues"))),
  list(name = "venues", source = "backtest/vvf/data/venues.csv", key = "stadium_id", refs = list()),
  list(name = "injuries_team", source = "backtest/vvf/data/injuries_team.csv", key = c("game_id", "team"),
       refs = list(vvf_ref("game_id", "games")), team = "team", max_per_game = 2L),
  list(name = "injuries_qb", source = "backtest/vvf/data/injuries_qb.csv", key = c("game_id", "team", "gsis_id"),
       refs = list(vvf_ref(c("game_id", "team"), "injuries_team"))))

#' One row per check: each key is complete and unique, each reference is
#' complete and resolves, each team row's team is one of its game's two
#' franchises, no game has more than max_per_game team rows, and no row carries
#' a sealed season (by its season column, else its game_id). A missing key or
#' reference value is a violation, never skipped.
#' `tables` is a named list of data.tables holding every schema table.
vvf_check_inputs <- function(tables, schema = VVF_INPUT_SCHEMA, sealed = vvf_sealed_seasons()) {
  missing <- setdiff(vapply(schema, `[[`, "", "name"), names(tables))
  if (length(missing)) stop(sprintf("vvf_check_inputs: missing tables: %s", paste(missing, collapse = ", ")), call. = FALSE)
  row <- function(check, table, detail, violations) data.table(check = check, table = table, detail = detail,
                                                                 violations = as.integer(violations))
  games <- tables$games[, .(game_id, home_franchise, away_franchise)]
  out <- list()
  for (t in schema) {
    d <- tables[[t$name]]
    out[[length(out) + 1L]] <- row("key complete", t$name, paste(t$key, collapse = ", "),
                                   sum(!stats::complete.cases(d[, t$key, with = FALSE])))
    out[[length(out) + 1L]] <- row("key unique", t$name, paste(t$key, collapse = ", "), sum(duplicated(d[, t$key, with = FALSE])))
    for (r in t$refs) {
      what <- sprintf("%s -> %s.%s", paste(r$cols, collapse = ", "), r$table, paste(r$table_cols, collapse = ", "))
      done <- stats::complete.cases(d[, r$cols, with = FALSE])
      out[[length(out) + 1L]] <- row("reference complete", t$name, what, sum(!done))
      parent <- unique(tables[[r$table]][, r$table_cols, with = FALSE])
      bad <- d[done, r$cols, with = FALSE][!parent, on = stats::setNames(r$table_cols, r$cols)]
      out[[length(out) + 1L]] <- row("reference resolves", t$name, what, nrow(bad))
    }
    if (!is.null(t$team)) {
      j <- merge(d[, c("game_id", t$team), with = FALSE], games, by = "game_id")
      tm <- j[[t$team]]
      out[[length(out) + 1L]] <- row("team in game", t$name, sprintf("%s is the home or away franchise", t$team),
                                     sum(tm != j$home_franchise & tm != j$away_franchise))
      out[[length(out) + 1L]] <- row("rows per game", t$name, sprintf("at most %d", t$max_per_game),
                                     sum(d[, .N, by = game_id]$N > t$max_per_game))
    }
    s <- if ("season" %in% names(d)) d$season else if ("game_id" %in% names(d)) suppressWarnings(as.integer(substr(d$game_id, 1L, 4L)))
    if (!is.null(s)) out[[length(out) + 1L]] <- row("no sealed season", t$name, paste(sealed, collapse = ", "), sum(s %in% sealed))
  }
  rbindlist(out)
}

#' The checks, run before any stage: stops on any violation, naming each, and
#' returns the check table invisibly
vvf_assert_inputs <- function(tables, schema = VVF_INPUT_SCHEMA) {
  chk <- vvf_check_inputs(tables, schema)
  bad <- chk[is.na(violations) | violations > 0L]
  if (nrow(bad)) {
    stop(sprintf("input check failed: %s", paste(sprintf("%s %s (%s): %s", bad$table, bad$check, bad$detail, bad$violations),
                                                 collapse = "; ")), call. = FALSE)
  }
  invisible(chk)
}

#' The v1 and VVF input tables the schema covers, as one named list. A run
#' that cuts v1's games at `max_season` checks every table cut there too (by
#' its season column, else its game_id), so a later game's rows are not
#' orphans; a row with no season is kept, so a missing key is still reported.
vvf_schema_tables <- function(inp_v1, inp, max_season = NULL) {
  tabs <- c(inp_v1[c("games", "team_games", "qb_games", "espn_open_close")],
            inp[c("game_context", "venues", "injuries_team", "injuries_qb")])
  if (is.null(max_season)) return(tabs)
  lapply(tabs, function(d) {
    s <- if ("season" %in% names(d)) d$season else if ("game_id" %in% names(d)) suppressWarnings(as.integer(substr(d$game_id, 1L, 4L)))
    if (is.null(s)) d else d[is.na(s) | s <= max_season]
  })
}

#' The schema as a Mermaid erDiagram: one relation per reference (one-to-one
#' when the child's key is the reference, else one-to-many), and each table's
#' key and reference columns
vvf_render_erd <- function(schema = VVF_INPUT_SCHEMA) {
  rel <- unlist(lapply(schema, function(t) vapply(t$refs, function(r) {
    sprintf("  %s ||--%s %s : \"%s\"", r$table, if (setequal(t$key, r$cols)) "o|" else "o{", t$name, paste(r$cols, collapse = ", "))
  }, "")))
  ent <- unlist(lapply(schema, function(t) {
    fk <- unique(unlist(lapply(t$refs, `[[`, "cols")))
    cols <- unique(c(t$key, fk))
    c(sprintf("  %s {", t$name),
      vapply(cols, function(cc) sprintf("    string %s %s", cc, paste(c(if (cc %in% t$key) "PK", if (cc %in% fk) "FK"),
                                                                   collapse = ", ")), "", USE.NAMES = FALSE),
      "  }")
  }))
  c("erDiagram", rel, ent)
}

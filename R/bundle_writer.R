# =============================================================================
# Bundle writer: the R side of the R -> web contract (spec §3)
# =============================================================================
# A bundle is a directory bundles/<cycle_id>/ with one JSON array per table and a
# manifest.json that pins every file's sha256. Rows are validated against the
# generated JSON Schemas in contracts/schema/ (owned by web/src/db/schema.ts via
# drizzle-zod) before anything is written. A validation failure does not stop the
# write: the bundle records qa$ok = FALSE and the failures, and the web ingest
# stores it as qa_failed without moving the publish pointer (NBA publish_policy).
# =============================================================================

BW_SCHEMA_VERSION <- "1.0.0"

#' Read a contract schema (contracts/schema/<name>.schema.json)
bw_read_schema <- function(name, contracts_dir = file.path("contracts", "schema")) {
  path <- file.path(contracts_dir, paste0(name, ".schema.json"))
  if (!file.exists(path)) stop("bw_read_schema: no contract for '", name, "' at ", path, call. = FALSE)
  jsonlite::read_json(path, simplifyVector = FALSE)
}

# Types a (sub)schema allows, flattening "type": [..] and "anyOf"
bw_schema_types <- function(prop) {
  if (!is.null(prop$anyOf)) return(unique(unlist(lapply(prop$anyOf, bw_schema_types))))
  if (is.null(prop$type)) return(c("string", "number", "integer", "boolean", "null", "object", "array"))
  unlist(prop$type)
}

# The first subschema carrying numeric bounds / enum / pattern
bw_schema_rule <- function(prop, key) {
  if (!is.null(prop[[key]])) return(prop[[key]])
  for (sub in prop$anyOf) if (!is.null(sub[[key]])) return(sub[[key]])
  NULL
}

#' Validate a data frame against a contract row schema. Returns character failures
#' ("<table>.<column>: <reason> (rows i, j)"); empty means valid. NA is treated as an
#' absent field (jsonlite omits it when writing rows).
bw_validate_rows <- function(df, schema, table) {
  fails <- character()
  props <- schema$properties
  required <- unlist(schema$required)
  cols <- names(df)
  for (col in setdiff(required, cols)) fails <- c(fails, sprintf("%s.%s: required column missing", table, col))
  if (isFALSE(schema$additionalProperties)) {
    for (col in setdiff(cols, names(props))) fails <- c(fails, sprintf("%s.%s: column not in contract", table, col))
  }
  where <- function(bad) paste(utils::head(which(bad), 5), collapse = ", ")
  for (col in intersect(cols, names(props))) {
    prop <- props[[col]]
    x <- df[[col]]
    types <- bw_schema_types(prop)
    if (is.list(x) && !is.data.frame(x)) {
      if (!any(c("object", "array") %in% types)) fails <- c(fails, sprintf("%s.%s: list column where a scalar is required", table, col))
      next
    }
    present <- !is.na(x)
    if (col %in% required && any(!present)) fails <- c(fails, sprintf("%s.%s: missing value in required column (rows %s)", table, col, where(!present)))
    if (!any(present)) next
    v <- x[present]
    ok_type <- switch(
      class(v)[1],
      character = "string" %in% types,
      logical = "boolean" %in% types,
      integer = any(c("integer", "number") %in% types),
      numeric = if ("number" %in% types) TRUE else if ("integer" %in% types) all(v == round(v)) else FALSE,
      FALSE
    )
    if (!ok_type) {
      fails <- c(fails, sprintf("%s.%s: type %s not allowed (%s)", table, col, class(v)[1], paste(types, collapse = "|")))
      next
    }
    if (is.numeric(v)) {
      if (any(!is.finite(v))) fails <- c(fails, sprintf("%s.%s: non-finite number", table, col))
      lo <- bw_schema_rule(prop, "minimum"); hi <- bw_schema_rule(prop, "maximum")
      if (!is.null(lo) && any(v < lo)) fails <- c(fails, sprintf("%s.%s: below minimum %s", table, col, lo))
      if (!is.null(hi) && any(v > hi)) fails <- c(fails, sprintf("%s.%s: above maximum %s", table, col, hi))
    }
    enum <- bw_schema_rule(prop, "enum")
    if (!is.null(enum) && any(!(v %in% unlist(enum)))) {
      fails <- c(fails, sprintf("%s.%s: value not in enum (%s)", table, col, paste(utils::head(unique(v[!(v %in% unlist(enum))]), 3), collapse = ", ")))
    }
    pattern <- bw_schema_rule(prop, "pattern")
    if (!is.null(pattern) && is.character(v) && any(!grepl(pattern, v, perl = TRUE))) {
      fails <- c(fails, sprintf("%s.%s: does not match %s", table, col, pattern))
    }
  }
  fails
}

#' ISO-8601 UTC timestamp string
bw_utc <- function(t = Sys.time()) format(as.POSIXct(t, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

bw_sha256_file <- function(path) digest::digest(file = path, algo = "sha256")

#' Canonical JSON for a config list, and its sha256
bw_config_hash <- function(config) {
  txt <- jsonlite::toJSON(config[order(names(config))], auto_unbox = TRUE, digits = NA, null = "null")
  digest::digest(as.character(txt), algo = "sha256", serialize = FALSE)
}

#' Write a bundle. `tables` is a named list of data frames (names = contract table
#' names). `meta` supplies cycle_id, season, week, model_label, data_asof_utc,
#' code_git_sha, code_dirty, config, seed, n_sims. Returns the manifest (invisibly)
#' with bundle_sha256 attached.
bw_write_bundle <- function(out_root, kind, meta, tables, extra_qa_failures = character(),
                            contracts_dir = file.path("contracts", "schema"), renv_lock = "renv.lock") {
  kinds <- jsonlite::read_json(file.path(contracts_dir, "bundle_kinds.json"), simplifyVector = TRUE)$kinds
  if (!kind %in% names(kinds)) stop("bw_write_bundle: unknown bundle kind '", kind, "'", call. = FALSE)
  spec <- kinds[[kind]]
  allowed <- c(spec$required, spec$optional)
  fails <- as.character(extra_qa_failures)
  for (nm in setdiff(spec$required, names(tables))) fails <- c(fails, sprintf("bundle: required table '%s' missing", nm))
  for (nm in setdiff(names(tables), allowed)) stop("bw_write_bundle: table '", nm, "' is not allowed in a ", kind, " bundle", call. = FALSE)

  dir <- file.path(out_root, meta$cycle_id)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  files <- list()
  for (nm in names(tables)) {
    df <- as.data.frame(tables[[nm]], stringsAsFactors = FALSE)
    fails <- c(fails, bw_validate_rows(df, bw_read_schema(nm, contracts_dir), nm))
    path <- file.path(dir, paste0(nm, ".json"))
    jsonlite::write_json(df, path, dataframe = "rows", auto_unbox = TRUE, digits = NA, pretty = FALSE)
    files[[length(files) + 1]] <- list(name = paste0(nm, ".json"), sha256 = bw_sha256_file(path), rows = nrow(df))
  }
  config <- if (is.null(meta$config)) list() else meta$config
  manifest <- list(
    schema_version = BW_SCHEMA_VERSION,
    bundle_kind = kind,
    cycle_id = meta$cycle_id,
    season = meta$season,
    week = meta$week,
    model_label = meta$model_label,
    generated_utc = bw_utc(),
    data_asof_utc = meta$data_asof_utc,
    code_git_sha = meta$code_git_sha,
    code_dirty = isTRUE(meta$code_dirty),
    config_hash = bw_config_hash(config),
    config = if (length(config)) config else structure(list(), names = character()),
    seed = meta$seed,
    n_sims = meta$n_sims,
    renv_lock_sha256 = bw_sha256_file(renv_lock),
    files = files,
    qa = list(ok = length(fails) == 0, failures = I(unique(fails)))
  )
  mpath <- file.path(dir, "manifest.json")
  txt <- jsonlite::toJSON(manifest, auto_unbox = TRUE, digits = NA, null = "null", pretty = TRUE)
  writeLines(txt, mpath, useBytes = TRUE)
  manifest$bundle_sha256 <- bw_sha256_file(mpath)
  manifest$dir <- dir
  invisible(manifest)
}

#' Current git commit and whether tracked files differ from it
bw_git_state <- function() {
  sha <- tryCatch(system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
  dirty <- tryCatch(length(system2("git", c("status", "--porcelain", "--untracked-files=no"), stdout = TRUE, stderr = FALSE)) > 0,
                    error = function(e) NA)
  list(code_git_sha = sha[1], code_dirty = dirty)
}

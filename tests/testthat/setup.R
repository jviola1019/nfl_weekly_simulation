# =============================================================================
# NFL Prediction Model - Test Setup
# =============================================================================
# This file is automatically sourced by testthat before running tests.
# It loads all R/ module files so individual tests don't need source() calls.
# =============================================================================

# Find project root using DESCRIPTION file as anchor
find_project_root <- function() {
  # Try multiple methods to find project root

  # Method 1: rprojroot if available
  if (requireNamespace("rprojroot", quietly = TRUE)) {
    tryCatch({
      return(rprojroot::find_root(rprojroot::has_file("DESCRIPTION")))
    }, error = function(e) NULL)
  }

 # Method 2: Walk up from test directory
  test_dir <- getwd()
  current <- test_dir

  for (i in 1:5) {
    if (file.exists(file.path(current, "DESCRIPTION"))) {
      return(current)
    }
    current <- dirname(current)
  }

  # Method 3: Try common relative paths
  candidates <- c(
    "../..",           # From tests/testthat/
    "../../..",        # From deeper test dirs
    ".",               # Current directory
    normalizePath(".") # Absolute current
  )

  for (path in candidates) {
    full_path <- normalizePath(file.path(path), mustWork = FALSE)
    if (file.exists(file.path(full_path, "DESCRIPTION"))) {
      return(full_path)
    }
  }

  stop("Could not find project root (no DESCRIPTION file found)")
}

# Get project root
PROJECT_ROOT <- find_project_root()

# Helper to source R/ modules; a missing module stops the run
source_module <- function(module_name) {
  path <- file.path(PROJECT_ROOT, "R", paste0(module_name, ".R"))
  if (!file.exists(path)) {
    stop(sprintf("Test setup: required module missing: R/%s.R", module_name), call. = FALSE)
  }
  source(path, local = FALSE)
  message(sprintf("  Loaded: R/%s.R", module_name))
}

# Load config.R first (defines all global parameters)
config_path <- file.path(PROJECT_ROOT, "config.R")
if (!file.exists(config_path)) stop("Test setup: config.R not found at: ", config_path, call. = FALSE)
message("Loading config from: ", config_path)
source(config_path, local = FALSE)
message("  Loaded: config.R")

# Load all R/ modules in dependency order
message("Loading R modules from: ", PROJECT_ROOT)

# Core modules first, then every other R/*.R alphabetically
LOAD_FIRST <- c("logging", "utils", "capture_raw", "data_validation", "playoffs", "date_resolver", "test_policy")
all_modules <- sub("\\.R$", "", list.files(file.path(PROJECT_ROOT, "R"), pattern = "\\.R$"))
for (m in c(LOAD_FIRST, setdiff(sort(all_modules), LOAD_FIRST))) source_module(m)

# Load player props configuration (v2.9.0)
props_config_path <- file.path(PROJECT_ROOT, "sports", "nfl", "props", "props_config.R")
if (!file.exists(props_config_path)) {
  stop("Test setup: sports/nfl/props/props_config.R not found", call. = FALSE)
}
source(props_config_path, local = FALSE)
message("  Loaded: sports/nfl/props/props_config.R")

message("Test setup complete.\n")

# Export project root for tests that need it
.test_project_root <- PROJECT_ROOT

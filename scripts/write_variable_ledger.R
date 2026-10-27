#!/usr/bin/env Rscript
# Render docs/VARIABLE_LEDGER.md from backtest/vvf/registry.R and the committed
# VVF results (design 2026-10-20 §5). Run from the repository root:
#   Rscript scripts/write_variable_ledger.R
if (!file.exists(file.path("backtest", "vvf", "registry.R"))) stop("Run from the repository root", call. = FALSE)
e <- environment()
sys.source(file.path("backtest", "common.R"), envir = e)
for (f in c("common.R", "registry.R", "ledger.R")) sys.source(file.path("backtest", "vvf", f), envir = e)
vvf_write_text(vvf_render_ledger(), file.path("docs", "VARIABLE_LEDGER.md"))
cat("wrote docs/VARIABLE_LEDGER.md\n")

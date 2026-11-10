# renv's own status report for a checkout, read against the given library paths (first wins).
# On CI the library is restored from the lockfile, so every recorded package is installed there: the rows that
# matter for CI are the ones where "recorded" and "used" differ. Nothing is installed or snapshotted.
# Usage: Rscript --vanilla renv_status.R <checkout> <lib1> [<lib2> ...]
a <- commandArgs(TRUE)
.libPaths(c(a[-1], .libPaths()))
cat("renv", as.character(packageVersion("renv")), "from", find.package("renv"), "\n")
s <- renv::status(project = a[1], library = a[-1])
cat("\nsynchronized:", isTRUE(s$synchronized), "\n")
lock <- names(s$lockfile$Packages)
lib <- names(s$library$Packages)
cat("recorded in the lockfile:", length(lock), "| in these libraries:", length(lib), "\n")

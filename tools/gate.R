#!/usr/bin/env Rscript
#
# gate.R — run the test suite in gate mode, where a skip counts as a failure.
#
# tests/testthat.R is the CI entry point and tolerates skips, because the
# vault-present mirror check cannot run on a runner. This entry point is for
# the one moment where that tolerance is wrong: just before house-style-v1
# moves, on a machine that does have the vault. There, "the mirror check did
# not run" and "the mirror is stale" have the same consequence -- ten repos
# recompose against sources nobody verified -- so they get the same exit code.

suppressMessages(library(testthat))

script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (!length(file_arg)) stop("Run this file with Rscript.", call. = FALSE)
  dirname(normalizePath(sub("^--file=", "", file_arg[1])))
}

HERE <- script_dir()
source(file.path(HERE, "..", "R", "compose.R"))

res <- as.data.frame(test_dir(
  file.path(HERE, "..", "tests", "testthat"),
  reporter = "summary",
  stop_on_failure = FALSE
))

broken <- res[res$failed > 0L | res$error, , drop = FALSE]
skipped <- res[res$skipped, , drop = FALSE]

if (nrow(broken)) {
  cat("\nGATE FAIL: ", nrow(broken), " test(s) failed.\n", sep = "", file = stderr())
  for (i in seq_len(nrow(broken))) {
    cat("  ", broken$file[i], " :: ", broken$test[i], "\n", sep = "", file = stderr())
  }
}

if (nrow(skipped)) {
  cat("\nGATE FAIL: ", nrow(skipped), " test(s) skipped. In gate mode a skip is a failure --\n",
      "an unrun check is not a passed check.\n", sep = "", file = stderr())
  for (i in seq_len(nrow(skipped))) {
    cat("  ", skipped$file[i], " :: ", skipped$test[i], "\n", sep = "", file = stderr())
  }
  cat("\nThe usual cause is the Obsidian vault not being mounted. Move the tag from a\n",
      "machine with the vault, so sources/ is actually compared against it.\n",
      sep = "", file = stderr())
}

if (nrow(broken) || nrow(skipped)) quit(status = 1L)

cat("\nGATE OK: every test ran and passed; sources/ was compared against the vault.\n")
quit(status = 0L)

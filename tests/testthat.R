# Run with: Rscript tools/house-style/tests/testthat.R
library(testthat)

# Resolve this script's directory from the Rscript invocation. Do NOT use
# sys.frame(1)$ofile — under Rscript there is no such frame and it throws
# "not that many frames on the stack" before any fallback can fire.
script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (!length(file_arg)) {
    stop("Run this file with Rscript, not interactively.", call. = FALSE)
  }
  dirname(normalizePath(sub("^--file=", "", file_arg[1])))
}

here <- script_dir()
source(file.path(here, "..", "R", "compose.R"))
source(file.path(here, "..", "R", "status.R"))

test_dir(file.path(here, "testthat"), reporter = "summary", stop_on_failure = TRUE)

#!/usr/bin/env Rscript
#
# write-manifest.R — regenerate sources/MANIFEST from the files in sources/.
#
# Run this after syncing the mirror from the vault. CI verifies the result,
# so a sync that forgets this step reddens the next push rather than shipping
# an unpinned mirror.

script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (!length(file_arg)) stop("Run this file with Rscript.", call. = FALSE)
  dirname(normalizePath(sub("^--file=", "", file_arg[1])))
}

HERE <- script_dir()
source(file.path(HERE, "..", "R", "compose.R"))

mirror <- file.path(HERE, "..", "sources")
out <- file.path(mirror, MANIFEST_FILE)

writeLines(format_manifest(source_hashes(mirror)), out)
cat("WROTE ", normalizePath(out), "\n", sep = "")

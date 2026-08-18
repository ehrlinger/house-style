#!/usr/bin/env Rscript
#
# status.R -- what state is the governed portfolio in?
#
# `compose-house-style.R --check --all` already answers "does each artifact
# match the vault?". This adds the two things that check cannot see: whether
# each artifact is committed on the branch its CI reads, and how far
# house-style-v1 trails origin/main.
#
# Usage:
#   tools/status.R              # fetch, then report
#   tools/status.R --no-fetch   # report against the local ref
#
# Exit codes: 0 = every repo clean, 1 = environment failure,
#             2 = one or more repos need attention.
#
# Tag lag never sets exit 2. A lagging tag is the normal state between a merge
# and a deliberate tag move; making it a failure would leave this permanently
# red and therefore unread.

suppressWarnings(suppressMessages({
  ok <- requireNamespace("yaml", quietly = TRUE) &&
        requireNamespace("digest", quietly = TRUE)
}))
if (!ok) {
  cat("ERROR: this script needs the 'yaml' and 'digest' packages.\n",
      "Install with: install.packages(c(\"yaml\", \"digest\"))\n",
      sep = "", file = stderr())
  quit(status = 1L)
}

script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (!length(file_arg)) {
    stop("Run this file with Rscript, not interactively.", call. = FALSE)
  }
  dirname(normalizePath(sub("^--file=", "", file_arg[1])))
}

HERE      <- script_dir()
REPO_ROOT <- normalizePath(file.path(HERE, ".."))

source(file.path(REPO_ROOT, "R", "compose.R"))
source(file.path(REPO_ROOT, "R", "status.R"))

if (nchar(Sys.which("git")) == 0L) {
  cat("ERROR: git is not on PATH.\n", file = stderr())
  quit(status = 1L)
}

args     <- commandArgs(trailingOnly = TRUE)
do_fetch <- !("--no-fetch" %in% args)

unknown <- setdiff(args, "--no-fetch")
if (length(unknown)) {
  cat("Usage: tools/status.R [--no-fetch]\n", file = stderr())
  quit(status = 1L)
}

VAULT_DIR  <- path.expand("~/Documents/ObsidianVault/memory")
MIRROR_DIR <- file.path(REPO_ROOT, "sources")

if (dir.exists(VAULT_DIR)) {
  vault <- VAULT_DIR
} else {
  vault <- MIRROR_DIR
  cat("WARNING: vault not found at ", VAULT_DIR, ".\n",
      "         Checking against the CI mirror instead, which answers a\n",
      "         different question: whether the artifacts match the mirror,\n",
      "         not whether the mirror matches the vault.\n",
      sep = "", file = stderr())
}

registry <- tryCatch(
  load_registry(file.path(REPO_ROOT, "repos.yml")),
  error = function(e) {
    cat("ERROR: could not read repos.yml: ", conditionMessage(e), "\n",
        sep = "", file = stderr())
    quit(status = 1L)
  }
)

# compose-house-style.R:143 guards this the same way: a missing or unreadable
# source document is an environment failure, not portfolio drift.
sources <- tryCatch(read_sources(vault), error = function(e) {
  cat("ERROR: could not read sources from ", vault, ": ", conditionMessage(e), "\n",
      sep = "", file = stderr())
  quit(status = 1L)
})

# See the comment above artifact_git_state() in R/status.R for why
# `committed` and the other states read from different trees.
rows <- lapply(registry, function(entry) {
  res    <- check_repo(sources, entry)
  branch <- if (dir.exists(entry$path)) default_branch(entry$path) else NA_character_
  list(name           = entry$name,
       content_ok     = isTRUE(res$ok),
       content_reason = if (isTRUE(res$ok)) "" else res$reason,
       git_state      = artifact_git_state(entry$path, branch))
})

lag <- tag_lag(REPO_ROOT, fetch = do_fetch)

cat(paste(format_status(rows, lag, vault), collapse = "\n"), "\n", sep = "")

quit(status = status_exit_code(rows))

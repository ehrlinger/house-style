#!/usr/bin/env Rscript
#
# compose-house-style.R — compose the R package documentation house style.
#
# The four source documents in the Obsidian vault are the single source of
# truth. This script composes them into one self-contained house-style.md per
# repository, filtered by that repository's profile.
#
# Usage:
#   compose-house-style.R --repo <name-or-path>     # write one repo's artifact
#   compose-house-style.R --all                     # write every registered repo
#   compose-house-style.R --check --repo <name>     # verify one repo
#   compose-house-style.R --check --all             # verify all (CI mode)
#   compose-house-style.R --vault <dir>             # override the vault path
#
# Exit codes: 0 = clean, 1 = usage or missing source, 2 = drift detected.

suppressWarnings(suppressMessages({
  ok <- requireNamespace("yaml", quietly = TRUE) &&
        requireNamespace("digest", quietly = TRUE)
}))
if (!ok) {
  cat("ERROR: this script needs the 'yaml' and 'digest' packages.\n",
      "Install with: install.packages(c(\"yaml\", \"digest\"))\n", sep = "", file = stderr())
  quit(status = 1L)
}

script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg)) return(dirname(normalizePath(sub("^--file=", "", file_arg[1]))))
  getwd()
}

HERE <- script_dir()
source(file.path(HERE, "R", "compose.R"))

VAULT_DIR  <- path.expand("~/Documents/ObsidianVault/memory")
MIRROR_DIR <- file.path(HERE, "sources")

args <- commandArgs(trailingOnly = TRUE)

# Returns the value following `flag` in args, or NULL if `flag` was not
# given at all. Errors (exit 1) if `flag` was given but its value is
# missing or is itself another flag (e.g. `--repo --check`), since that
# almost always means the user forgot to supply `flag`'s value. If `flag`
# appears more than once, the first occurrence wins (unchanged behaviour)
# but a warning names every value seen and which one is used.
get_opt <- function(flag) {
  idx <- which(args == flag)
  if (!length(idx)) return(NULL)

  value_after <- function(i) {
    if (i == length(args) || startsWith(args[i + 1L], "--")) NA_character_
    else args[i + 1L]
  }

  if (length(idx) > 1L) {
    vals <- vapply(idx, value_after, character(1))
    cat("WARNING: '", flag, "' was given ", length(idx), " times (",
        paste(vals, collapse = ", "), "); using the first value '", vals[1L], "'.\n",
        sep = "", file = stderr())
  }

  val <- value_after(idx[1L])
  if (is.na(val)) {
    cat("ERROR: '", flag, "' requires a value.\n", sep = "", file = stderr())
    quit(status = 1L)
  }
  val
}

do_check <- "--check" %in% args
do_all   <- "--all" %in% args
repo_sel <- get_opt("--repo")

if (do_all && !is.null(repo_sel)) {
  cat("ERROR: '--all' and '--repo' are mutually exclusive.\n", file = stderr())
  quit(status = 1L)
}

if (!do_all && is.null(repo_sel)) {
  cat("Usage: compose-house-style.R [--check] (--all | --repo <name-or-path>) [--vault <dir>]\n",
      file = stderr())
  quit(status = 1L)
}

vault_opt      <- get_opt("--vault")
vault_explicit <- !is.null(vault_opt)

if (vault_explicit) {
  # path.expand(): a quoted --vault "~/dir" reaches R with a literal tilde,
  # which file.exists() and read_sources() would report as missing.
  vault <- path.expand(vault_opt)
} else if (dir.exists(VAULT_DIR)) {
  vault <- VAULT_DIR
} else {
  vault <- MIRROR_DIR
  cat("WARNING: vault not found at ", VAULT_DIR, "; falling back to the CI mirror at ",
      MIRROR_DIR, ".\n",
      "The mirror is for --check verification only and may be stale; it is not a valid",
      " composition source.\n", sep = "", file = stderr())
}

using_mirror <- normalizePath(vault, mustWork = FALSE) == normalizePath(MIRROR_DIR, mustWork = FALSE)

if (!do_check && using_mirror && !vault_explicit) {
  cat("ERROR: refusing to write from the CI mirror (", vault, ").\n",
      "The mirror exists only so --check can run in CI without the vault mounted; it is",
      " not a valid source for composing artifacts. Pass --vault explicitly if you really",
      " mean to compose from this directory, or mount the vault and retry.\n",
      sep = "", file = stderr())
  quit(status = 1L)
}

cat("sources: ", vault, "\n", sep = "")

registry <- load_registry(file.path(HERE, "repos.yml"))

if (!do_all) {
  # --repo accepts either a registry name or a filesystem path. Try an
  # exact name match first (a bare name like "hvtiPlotR" must never be
  # run through path normalisation); only if that fails, fall back to
  # comparing normalised, trailing-slash-stripped paths so that
  # "~/Documents/GitHub/hvtiPlotR/" and "./hvtiPlotR" (run from
  # ~/Documents/GitHub) both resolve to the registry's stored path.
  norm_path <- function(p) sub("/+$", "", normalizePath(path.expand(p), mustWork = FALSE))

  hit <- Filter(function(e) identical(e$name, repo_sel), registry)
  if (!length(hit)) {
    want <- norm_path(repo_sel)
    hit <- Filter(function(e) norm_path(e$path) == want, registry)
  }
  if (!length(hit)) {
    cat("ERROR: '", repo_sel, "' is not in repos.yml. Known repos:\n",
        paste0("  ", vapply(registry, function(e) e$name, character(1)), collapse = "\n"),
        "\n", sep = "", file = stderr())
    quit(status = 1L)
  }
  registry <- hit
}

sources <- tryCatch(read_sources(vault), error = function(e) {
  cat("ERROR: ", conditionMessage(e), "\n", sep = "", file = stderr())
  quit(status = 1L)
})

drift <- character(0)

for (entry in registry) {
  if (!dir.exists(entry$path)) {
    if (do_check) {
      cat("DRIFT ", entry$name, " (path not found: ", entry$path, ")\n", sep = "")
      drift <- c(drift, entry$name)
    } else {
      cat("SKIP  ", entry$name, " (path not found: ", entry$path, ")\n", sep = "")
    }
    next
  }

  if (do_check) {
    res <- check_repo(sources, entry)
    if (res$ok) {
      cat("OK    ", entry$name, "\n", sep = "")
    } else {
      cat("DRIFT ", entry$name, " (", res$reason, ")\n", sep = "")
      drift <- c(drift, entry$name)
    }
  } else {
    path <- write_house_style(sources, entry)
    cat("WROTE ", entry$name, " -> ", path, "\n", sep = "")
  }
}

if (length(drift)) {
  cat("\n", length(drift), " repo(s) out of date with the vault sources: ",
      paste(drift, collapse = ", "),
      "\nRecompose with: compose-house-style.R --repo <name>\n", sep = "", file = stderr())
  quit(status = 2L)
}

quit(status = 0L)

# compose.R — house style composition functions.
#
# Sourced by compose-house-style.R (the CLI) and by the test runner. Contains
# no side effects at load time and never touches the filesystem except through
# an explicit path argument, so tests run against fixtures rather than the
# real vault.

`%||%` <- function(x, y) if (is.null(x)) y else x

# Source documents, in composition order. Names are the internal keys;
# values are the filenames expected in the vault memory directory.
SOURCE_FILES <- c(
  voice     = "writing-voice.md",
  personas  = "writing-reader-profile.md",
  context   = "writing-context.md",
  structure = "r-package-structure.md"
)

# Which sources each profile actually composes -- and therefore which ones
# its provenance header records.
#
# The header is not only documentation: check_repo() recomposes and compares
# bytes, so every line in it is load-bearing. Hashing a source a profile
# excludes makes the drift check strictly more sensitive than the artifact
# it guards. `book` omits the structural rules, so an edit to them cannot
# change a byte of a book's body -- yet before this table, it still changed
# the recorded hash, and hvti_graphics reported drift for a change that
# provably could not affect it. That is the failure this whole mechanism
# exists to prevent, reproduced inside the mechanism itself.
#
# Kept as data, not a function, on purpose. The determinism test in
# test-compose.R is a direct-body check: it greps each guarded function's
# deparsed body and does not follow calls into helpers. A shared helper
# between provenance_header() and compose_house_style() would be a hole in
# that guard. Indexing a literal list is not a call, so both functions stay
# fully covered while still reading the rule from one place.
#
# Order within each entry follows SOURCE_FILES, so header lines never churn.
PROFILE_SOURCES <- list(
  `package-internal` = c("voice", "personas", "context", "structure"),
  `package-cran`     = c("voice", "personas", "context", "structure"),
  `book`             = c("voice", "personas", "context")
)

# Derived, so a profile can never be registry-valid but composition-unknown.
VALID_PROFILES <- names(PROFILE_SOURCES)

load_registry <- function(path) {
  raw <- yaml::yaml.load_file(path)
  entries <- raw$repos

  if (!length(entries)) {
    stop("Registry ", path, " contains no repos.", call. = FALSE)
  }

  lapply(entries, function(e) {
    for (field in c("name", "path", "profile", "default_persona")) {
      if (is.null(e[[field]]) || !nzchar(e[[field]])) {
        stop("Registry entry is missing required field '", field, "'.", call. = FALSE)
      }
    }
    if (!e$profile %in% VALID_PROFILES) {
      stop("Registry entry '", e$name, "' has unknown profile '", e$profile,
           "'. Valid: ", paste(VALID_PROFILES, collapse = ", "), call. = FALSE)
    }
    list(
      name               = e$name,
      path               = path.expand(e$path),
      profile            = e$profile,
      default_persona    = e$default_persona,
      secondary_personas = as.character(e$secondary_personas %||% character(0))
    )
  })
}

# --- Registry paths --------------------------------------------------------
#
# A registry entry whose `path:` is not a directory on disk is a configuration
# error, not drift. The distinction is load-bearing because the two have
# opposite remedies: drift is fixed by recomposing, a moved clone is fixed by
# editing repos.yml. Folding the second into the first sends the reader to a
# remedy that provably cannot work -- which is what happened when three clones
# were renamed at once and all three reported as "out of date with the vault
# sources".
#
# Returns NULL when the path is usable, so callers can Filter() on it.

repo_path_problem <- function(entry) {
  if (dir.exists(entry$path)) return(NULL)
  if (file.exists(entry$path)) "not-a-directory" else "absent"
}

# The remedy, printed once however many entries are broken. Kept next to the
# classifier so the two cannot drift apart.
PATH_PROBLEM_HINT <- paste0(
  "A registry path that is not a directory is a configuration error, not drift:",
  " nothing can be checked or composed there, and recomposing cannot fix it.",
  " Usually the local clone was renamed, moved, or never made. Update the",
  " entry's 'path:' in repos.yml, or put the clone where it points.\n"
)

format_path_problem <- function(entry, problem) {
  what <- switch(problem,
    "absent"          = "no directory at ",
    "not-a-directory" = "not a directory: ",
    stop("Unknown path problem '", problem, "'.", call. = FALSE)
  )
  paste0("ERROR: ", entry$name, ": ", what, entry$path, "\n")
}

# --- Source manifest -------------------------------------------------------
#
# `sources/` is a mirror of the vault, and CI has no vault to compare it
# against. The manifest is the one check a runner can actually perform: it
# pins the bytes of each mirrored file, so a hand edit to `sources/` reddens
# CI instead of propagating to ten repositories as a phantom drift report.
#
# It does NOT detect vault drift -- nothing running without the vault can.
# That check lives in test-mirror.R and in the pre-tag gate.
#
# The hash is over file bytes, not over the strings read_sources() returns:
# the provenance header answers "what was composed", the manifest answers
# "what is on disk", and a stray trailing newline matters to the second.

MANIFEST_FILE <- "MANIFEST"

source_hashes <- function(dir) {
  paths <- file.path(dir, SOURCE_FILES)
  missing <- SOURCE_FILES[!file.exists(paths)]

  if (length(missing)) {
    stop("Missing source document(s) in ", dir, ": ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

  out <- vapply(paths, function(p) digest::digest(file = p, algo = "sha256"), character(1))
  stats::setNames(out, SOURCE_FILES)
}

format_manifest <- function(hashes) {
  # Emitted in SOURCE_FILES order regardless of the input's order, so the
  # committed file is a function of content alone and never churns.
  c(
    "# sha256 of each file in this directory. Generated -- do not edit by hand.",
    "# Regenerate with: Rscript tools/write-manifest.R",
    sprintf("%-30s %s", SOURCE_FILES, hashes[SOURCE_FILES])
  )
}

parse_manifest <- function(lines) {
  body <- grep("^\\s*(#|$)", lines, value = TRUE, invert = TRUE)
  fields <- strsplit(trimws(body), "\\s+")

  bad <- vapply(fields, function(f) length(f) != 2L || !grepl("^[0-9a-f]{64}$", f[2L]), logical(1))
  if (any(bad)) {
    stop("Malformed manifest line(s): ", paste(body[bad], collapse = "; "),
         "\nEach line must be '<filename> <sha256>'.", call. = FALSE)
  }

  out <- stats::setNames(
    vapply(fields, `[`, character(1), 2L),
    vapply(fields, `[`, character(1), 1L)
  )

  # identical() on sorted names rather than setequal(): setequal() ignores
  # multiplicity, so a manifest naming a source twice would pass and then
  # lose the duplicate to out[SOURCE_FILES], which keeps only the first
  # match. A silently dropped line in the file whose job is to catch edits
  # to sources/ is the exact failure this manifest exists to prevent.
  if (!identical(sort(names(out)), sort(unname(SOURCE_FILES)))) {
    dupes <- unique(names(out)[duplicated(names(out))])
    stop("Manifest must name each source document exactly once. Duplicated: ",
         paste(dupes, collapse = ", "),
         "; unexpected: ", paste(setdiff(names(out), SOURCE_FILES), collapse = ", "),
         "; missing: ", paste(setdiff(SOURCE_FILES, names(out)), collapse = ", "),
         call. = FALSE)
  }

  out[SOURCE_FILES]
}

read_sources <- function(vault_dir) {
  paths <- file.path(vault_dir, SOURCE_FILES)
  missing <- SOURCE_FILES[!file.exists(paths)]

  if (length(missing)) {
    stop("Missing source document(s) in ", vault_dir, ": ",
         paste(missing, collapse = ", "),
         "\nThe vault is the source of truth; composition cannot proceed without it.",
         call. = FALSE)
  }

  out <- lapply(paths, function(p) paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n"))
  names(out) <- names(SOURCE_FILES)

  empty <- SOURCE_FILES[vapply(out, function(x) !nzchar(trimws(x)), logical(1))]
  if (length(empty)) {
    stop("Empty or whitespace-only source document(s) in ", vault_dir, ": ",
         paste(empty, collapse = ", "),
         "\nA source with no content would silently drop whole sections from the",
         " composed artifact.",
         call. = FALSE)
  }

  out
}

# Persona sections are level-2 headings of the form "## (a) Title".
PERSONA_HEADING <- "^## \\(([a-z])\\)"

filter_personas <- function(personas_md, keep) {
  lines <- strsplit(personas_md, "\n", fixed = TRUE)[[1]]
  starts <- grep(PERSONA_HEADING, lines)

  if (!length(starts)) {
    stop("No persona sections found. Expected level-2 headings like '## (a) ...'.",
         call. = FALSE)
  }

  ids <- sub(paste0(PERSONA_HEADING, ".*$"), "\\1", lines[starts])
  unknown <- setdiff(keep, ids)
  if (length(unknown)) {
    stop("Requested persona(s) not present in the source: ",
         paste(unknown, collapse = ", "), call. = FALSE)
  }

  ends <- c(starts[-1] - 1L, length(lines))
  sel <- which(ids %in% keep)            # document order, not `keep` order
  body <- unlist(Map(seq, starts[sel], ends[sel]))
  preamble <- if (starts[1] > 1L) seq_len(starts[1] - 1L) else integer(0)

  paste(lines[c(preamble, body)], collapse = "\n")
}

# Deliberately no timestamp. A date would make the artifact non-deterministic
# and turn --check permanently red, which is the failure mode this whole
# mechanism exists to prevent. The source hashes are the identity; git records
# when the file changed.
provenance_header <- function(sources, entry) {
  keys <- PROFILE_SOURCES[[entry$profile]]
  if (is.null(keys)) {
    stop("Cannot compose a provenance header for unknown profile '", entry$profile,
         "'. Valid: ", paste(VALID_PROFILES, collapse = ", "),
         "\nWithout a source list the header would name no sources at all, and",
         " --check would compare against a document nothing can be drifted from.",
         call. = FALSE)
  }

  hashes <- vapply(
    keys,
    function(k) substr(digest::digest(sources[[k]], algo = "sha256", serialize = FALSE), 1L, 12L),
    character(1)
  )

  source_lines <- sprintf("    %-30s sha256:%s", SOURCE_FILES[keys], hashes[keys])

  paste(c(
    "<!--",
    "  GENERATED FILE - DO NOT EDIT.",
    "",
    "  Composed by compose-house-style.R in the ehrlinger/house-style",
    "  repository. Edit the sources in the Obsidian vault (memory/), then",
    "  recompose. Editing this file directly will be reverted by the next",
    "  compose and flagged by --check.",
    "",
    sprintf("  repo:            %s", entry$name),
    sprintf("  profile:         %s", entry$profile),
    sprintf("  default persona: (%s)", entry$default_persona),
    "  sources:",
    source_lines,
    "-->"
  ), collapse = "\n")
}

compose_house_style <- function(sources, entry) {
  keys <- PROFILE_SOURCES[[entry$profile]]
  if (is.null(keys)) {
    stop("Cannot compose for unknown profile '", entry$profile,
         "'. Valid: ", paste(VALID_PROFILES, collapse = ", "),
         "\nAn unrecognised profile would silently drop every optional section",
         " rather than fail, producing a document that still looked plausible.",
         call. = FALSE)
  }

  keep <- unique(c(entry$default_persona, entry$secondary_personas))
  personas <- filter_personas(sources$personas, keep = keep)

  rule <- c("", "---", "")

  parts <- c(
    provenance_header(sources, entry),
    "",
    sprintf("# House Style — %s", entry$name),
    "",
    sprintf(
      "Default reader persona for this repository: **(%s)**. Write for one persona at a time.",
      entry$default_persona
    ),
    rule,
    sources$voice,
    rule,
    personas,
    rule,
    sources$context
  )

  if ("structure" %in% keys) {
    parts <- c(parts, rule, sources$structure)
  }

  paste(c(parts, ""), collapse = "\n")
}

artifact_path <- function(entry) {
  file.path(entry$path, ".claude", "house-style.md")
}

write_house_style <- function(sources, entry) {
  path <- artifact_path(entry)
  target_dir <- dirname(path)
  if (!dir.exists(target_dir)) {
    created <- dir.create(target_dir, showWarnings = FALSE, recursive = TRUE)
    if (!created) {
      stop("Could not create directory ", target_dir, call. = FALSE)
    }
  }
  # enc2utf8() before charToRaw(): charToRaw emits the string's *current*
  # encoding, and the composed document mixes UTF-8-marked source text with
  # sprintf() output carrying the native encoding. On a non-UTF-8 locale that
  # would write bytes check_repo() reads back as UTF-8, so the artifact would
  # differ by platform -- the non-determinism --check exists to rule out.
  content <- enc2utf8(compose_house_style(sources, entry))
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(content), con)
  invisible(path)
}

# Trailing-only trim: absorbs a stray editor newline at end of file without
# masking drift at the start of the document (see check_repo()).
trim_trailing <- function(x) sub("[[:space:]]+$", "", x)

check_repo <- function(sources, entry) {
  path <- artifact_path(entry)

  if (!file.exists(path)) {
    return(list(ok = FALSE, reason = "missing"))
  }

  expected <- compose_house_style(sources, entry)
  actual <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  if (identical(trim_trailing(expected), trim_trailing(actual))) {
    list(ok = TRUE, reason = "")
  } else {
    list(ok = FALSE, reason = "stale")
  }
}

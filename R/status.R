# Status reporting for the governed portfolio.
#
# `compose-house-style.R --check --all` answers "does each artifact match the
# vault?". It reads the working tree, so it cannot see whether that artifact is
# committed, and it says nothing about how far house-style-v1 trails main.
# This file adds those two signals and no new drift detection: content drift
# still comes from check_repo().
#
# The split below is deliberate. The git-backed functions are thin wrappers
# over one or two commands returning a small tagged value; every branch,
# alignment and pluralisation decision lives in the two pure functions, which
# are the ones worth testing exhaustively.

ARTIFACT_REL <- file.path(".claude", "house-style.md")

# Git states that mean a human should act. `committed` is the only state that
# is not a fault. Kept as data rather than inline so status_exit_code() and
# the tests agree by construction.
FAULT_STATES <- c("branch-only", "untracked-only", "absent",
                  "no-clone", "not-a-repo", "unknown-branch")

GIT_LABEL <- c(
  "committed"      = "yes",
  "branch-only"    = "NO (branch only)",
  "untracked-only" = "NO (untracked)",
  "absent"         = "NO (absent)",
  "no-clone"       = "NO (no clone)",
  "not-a-repo"     = "NO (not a repo)",
  "unknown-branch" = "NO (branch?)"
)

# The single definition of "needs attention". status_exit_code() and
# format_status() must never disagree about which repos are faulted, so they
# share one rule rather than each carrying a copy of it.
needs_attention <- function(rows) {
  if (!length(rows)) return(logical(0))
  vapply(rows, function(r) {
    !isTRUE(r$content_ok) || r$git_state %in% FAULT_STATES
  }, logical(1))
}

# any(logical(0)) is FALSE, so an empty registry exits 0 without a special case.
status_exit_code <- function(rows) {
  if (any(needs_attention(rows))) 2L else 0L
}

format_status <- function(rows, lag, sources) {
  names_col <- vapply(rows, function(r) r$name, character(1))
  w <- max(c(nchar("REPO"), nchar(names_col)))

  header <- if (is.na(lag$behind)) {
    sprintf("house-style-v1  %s  ->  lag unknown", lag$tag_sha)
  } else if (lag$behind == 0L) {
    sprintf("house-style-v1  %s  ->  up to date with origin/main", lag$tag_sha)
  } else {
    sprintf("house-style-v1  %s  ->  %d behind origin/main (%s)",
            lag$tag_sha, lag$behind, lag$main_sha)
  }
  if (!isTRUE(lag$fetched)) header <- paste0(header, " [as of last fetch]")

  line <- function(name, content, committed) {
    sprintf("%-*s  %-16s %s", w, name, content, committed)
  }

  out <- c(header,
           paste0("sources: ", sources),
           "",
           line("REPO", "CONTENT", "COMMITTED"))

  for (r in rows) {
    content <- if (isTRUE(r$content_ok)) {
      "OK"
    } else {
      sprintf("DRIFT (%s)", r$content_reason)
    }
    out <- c(out, line(r$name, content, unname(GIT_LABEL[r$git_state])))
  }

  bad <- needs_attention(rows)
  if (any(bad)) {
    out <- c(out, "",
             sprintf("%d repo(s) need attention: %s",
                     sum(bad), paste(names_col[bad], collapse = ", ")))
  }
  out
}

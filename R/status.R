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

# Binds the label table to the states artifact_git_state() can actually
# produce. Without this, an eighth state added there later would silently
# render as NA in format_status() and exit 0 -- a fault nobody sees rather
# than a fault that fails loudly at load time.
stopifnot(setequal(names(GIT_LABEL), c("committed", FAULT_STATES)))

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

# Runs git in `dir` and returns list(ok, out). A non-zero exit is data here,
# not an error: "this path is not on that branch" is reported by git the same
# way a real failure is, and the caller tells them apart by which command it
# ran. Signalling would force every call site into tryCatch().
git_run <- function(dir, args) {
  out <- suppressWarnings(
    system2("git", c("-C", dir, args), stdout = TRUE, stderr = FALSE)
  )
  status <- attr(out, "status")
  list(ok = is.null(status) || identical(as.integer(status), 0L),
       out = as.character(out))
}

default_branch <- function(path) {
  head_ref <- git_run(path, c("symbolic-ref", "--quiet", "refs/remotes/origin/HEAD"))
  if (head_ref$ok && length(head_ref$out)) {
    return(sub("^refs/remotes/origin/", "", head_ref$out[1]))
  }
  for (candidate in c("main", "master")) {
    probe <- git_run(path, c("rev-parse", "--verify", "--quiet", candidate))
    if (probe$ok && length(probe$out)) return(candidate)
  }
  NA_character_
}

# States are checked in this order, first match wins: no-clone, not-a-repo,
# unknown-branch, committed, branch-only, untracked-only, absent. The ordering
# is load-bearing at untracked-only vs absent: both are "not on the default
# branch", but only the first says the file is already composed.
#
# `committed` is evaluated against the tree of `branch` (the remote-tracking
# ref when available -- see the comment below). branch-only / untracked-only /
# absent are evaluated against whatever is CURRENTLY CHECKED OUT in `path`,
# via `git ls-files` and `file.exists()`, not against the tree of `branch`
# itself. That is intended: "branch-only" means "tracked on the branch the
# developer happens to have checked out right now", which is exactly the
# half-committed state this tool exists to surface. It does mean a row can
# read differently depending on what a human left checked out on their
# machine when this ran.
artifact_git_state <- function(path, branch) {
  if (!dir.exists(path)) return("no-clone")

  inside <- git_run(path, c("rev-parse", "--is-inside-work-tree"))
  if (!inside$ok) return("not-a-repo")

  if (is.na(branch)) return("unknown-branch")

  # Prefer the remote-tracking ref when it exists: it is the closest thing on
  # disk to what the repo's CI actually checks out. Neither ref is fetched by
  # this tool, so both can be stale -- this narrows the false-alarm window
  # (a file committed and pushed reading as absent because the local branch
  # was never updated here) rather than closing it.
  remote_ref <- paste0("refs/remotes/origin/", branch)
  has_remote <- git_run(path, c("rev-parse", "--verify", "--quiet", remote_ref))
  rev <- if (has_remote$ok) paste0("origin/", branch) else branch

  on_branch <- git_run(path, c("cat-file", "-e", paste0(rev, ":", ARTIFACT_REL)))
  if (on_branch$ok) return("committed")

  tracked <- git_run(path, c("ls-files", "--error-unmatch", ARTIFACT_REL))
  if (tracked$ok) return("branch-only")

  if (file.exists(file.path(path, ARTIFACT_REL))) return("untracked-only")

  "absent"
}

# Fetches by default so `behind` means the same thing here as it does in
# bin/move-tag.sh, which fetches before its ancestry check. A fetch that fails
# (offline, no remote) is not an error: it degrades to the local ref with
# fetched = FALSE, which format_status() labels "[as of last fetch]".
tag_lag <- function(repo_root, fetch = TRUE,
                    tag = "house-style-v1", remote_ref = "origin/main") {
  fetched <- FALSE
  if (isTRUE(fetch)) {
    fetched <- git_run(repo_root, c("fetch", "--quiet", "origin", "main"))$ok
  }

  first <- function(res) if (res$ok && length(res$out)) res$out[1] else NA_character_

  tag_sha  <- first(git_run(repo_root, c("rev-parse", "--short", tag)))
  main_sha <- first(git_run(repo_root, c("rev-parse", "--short", remote_ref)))
  count    <- first(git_run(repo_root,
                            c("rev-list", "--count", paste0(tag, "..", remote_ref))))

  list(behind   = if (is.na(count)) NA_integer_ else as.integer(count),
       tag_sha  = tag_sha,
       main_sha = main_sha,
       fetched  = fetched)
}

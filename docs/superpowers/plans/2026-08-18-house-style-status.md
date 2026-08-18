# House Style Status View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `tools/status.R`, a read-only portfolio view reporting per-repo content drift, whether each artifact is committed on the branch its CI reads, and how far `house-style-v1` trails `origin/main`.

**Architecture:** One new library file `R/status.R` holding five units split on the pure/impure line — three thin `git` wrappers and two pure functions carrying all the logic. One entry point `tools/status.R` sources `R/compose.R` and `R/status.R`, wires them, prints and exits. No new drift detection: content drift comes from the existing `check_repo()`.

**Tech Stack:** R (base only in `R/status.R`), `yaml` + `digest` (already required by the composer), `testthat` + `withr` for tests. `git` invoked via `system2()`.

**Spec:** `docs/superpowers/specs/2026-08-18-house-style-status-design.md`

## Global Constraints

- No new package dependencies. `R/status.R` uses base R only.
- Tests must run unskipped in CI: no network, no vault, no reliance on the developer's clones.
- Exit codes follow the composer: `0` clean, `1` environment failure, `2` one or more repos need attention.
- Tag lag never affects the exit code.
- The artifact path is `.claude/house-style.md` relative to each repo.
- Repo layout convention: `R/` = library, `tools/` = R entry points, `bin/` = shell. Do not add shell.
- Output is ASCII only (`->`, not an arrow glyph).

---

## File Structure

| Path | Responsibility |
|---|---|
| `R/status.R` | create — `git_run`, `default_branch`, `artifact_git_state`, `tag_lag`, `status_exit_code`, `format_status` |
| `tools/status.R` | create — CLI parsing, wiring, printing, exit |
| `tests/testthat/test-status.R` | create — unit tests for all six |
| `docs/superpowers/specs/2026-08-18-house-style-status-design.md` | modify — one line, arrow glyph to ASCII |

---

### Task 1: Pure units — `status_exit_code()` and `format_status()`

These carry all the logic and need no git, so they are built first and in isolation.

**Files:**
- Create: `R/status.R`
- Test: `tests/testthat/test-status.R`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `FAULT_STATES` — character vector of git states that count as faults.
  - `needs_attention(rows)` → logical vector, one element per row; `logical(0)` for an empty registry. The single definition of "faulted", shared by the two functions below so they cannot disagree.
  - `status_exit_code(rows)` → integer `0L` or `2L`.
  - `format_status(rows, lag, sources)` → character vector, one element per output line.
  - A **row** is `list(name = <chr>, content_ok = <lgl>, content_reason = <chr>, git_state = <chr>)`. `content_reason` is `""` when `content_ok` is `TRUE`, else `"stale"` or `"missing"`.
  - A **lag** is `list(behind = <int>, tag_sha = <chr>, main_sha = <chr>, fetched = <lgl>)`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-status.R`:

```r
row <- function(name, content_ok = TRUE, content_reason = "", git_state = "committed") {
  list(name = name, content_ok = content_ok,
       content_reason = content_reason, git_state = git_state)
}

lag_clean <- list(behind = 0L, tag_sha = "abc1234",
                  main_sha = "abc1234", fetched = TRUE)
lag_behind <- list(behind = 7L, tag_sha = "345fae8",
                   main_sha = "75a68c3", fetched = TRUE)

test_that("a clean portfolio exits 0", {
  expect_identical(status_exit_code(list(row("a"), row("b"))), 0L)
})

test_that("an empty registry exits 0", {
  expect_identical(status_exit_code(list()), 0L)
})

test_that("content drift alone exits 2", {
  rows <- list(row("a"), row("b", content_ok = FALSE, content_reason = "stale"))
  expect_identical(status_exit_code(rows), 2L)
})

test_that("every git fault state exits 2", {
  for (state in FAULT_STATES) {
    expect_identical(status_exit_code(list(row("a", git_state = state))), 2L,
                     info = state)
  }
})

test_that("tag lag is not a fault", {
  # status_exit_code() has no lag parameter, so lag cannot structurally reach
  # it -- asserting on it there would prove nothing. The place lag and rows do
  # meet is format_status(), and the observable property is that a behind tag
  # with clean rows still prints no summary line. This fails if anyone later
  # makes lag contribute to "needs attention".
  out <- format_status(list(row("a"), row("b")), lag_behind, "/vault/memory")
  expect_false(any(grepl("need attention", out, fixed = TRUE)))
  expect_true(grepl("7 behind", out[1], fixed = TRUE))
  expect_identical(status_exit_code(list(row("a"), row("b"))), 0L)
})

test_that("format_status renders a clean portfolio without a summary line", {
  out <- format_status(list(row("hvtiPlotR"), row("hvti_graphics")),
                       lag_clean, "/vault/memory")
  expect_identical(out[1], "house-style-v1  abc1234  ->  up to date with origin/main")
  expect_identical(out[2], "sources: /vault/memory")
  expect_identical(out[3], "")
  expect_identical(out[4], "REPO           CONTENT          COMMITTED")
  expect_identical(out[5], "hvtiPlotR      OK               yes")
  expect_identical(out[6], "hvti_graphics  OK               yes")
  expect_length(out, 6L)
})

test_that("format_status reports lag in the header without failing", {
  out <- format_status(list(row("a")), lag_behind, "/vault/memory")
  expect_identical(out[1],
    "house-style-v1  345fae8  ->  7 behind origin/main (75a68c3)")
})

test_that("format_status labels each git state distinctly", {
  rows <- list(
    row("a", git_state = "committed"),
    row("b", git_state = "branch-only"),
    row("c", git_state = "untracked-only"),
    row("d", git_state = "absent"),
    row("e", git_state = "no-clone"),
    row("f", git_state = "not-a-repo"),
    row("g", git_state = "unknown-branch")
  )
  out <- format_status(rows, lag_clean, "/vault/memory")
  labels <- trimws(substring(out[5:11], 22))
  expect_identical(labels, c("yes", "NO (branch only)", "NO (untracked)",
                             "NO (absent)", "NO (no clone)",
                             "NO (not a repo)", "NO (branch?)"))
})

test_that("format_status shows the drift reason and names repos needing attention", {
  rows <- list(
    row("a"),
    row("b", content_ok = FALSE, content_reason = "stale"),
    row("c", git_state = "untracked-only")
  )
  out <- format_status(rows, lag_clean, "/vault/memory")
  expect_true(any(grepl("DRIFT (stale)", out, fixed = TRUE)))
  expect_identical(out[length(out)], "2 repo(s) need attention: b, c")
})

test_that("format_status pluralises a single problem correctly", {
  rows <- list(row("a"), row("b", git_state = "absent"))
  out <- format_status(rows, lag_clean, "/vault/memory")
  expect_identical(out[length(out)], "1 repo(s) need attention: b")
})

test_that("format_status labels an unfetched lag as possibly stale", {
  lag <- list(behind = 3L, tag_sha = "aaa1111",
              main_sha = "bbb2222", fetched = FALSE)
  out <- format_status(list(row("a")), lag, "/vault/memory")
  expect_identical(out[1],
    "house-style-v1  aaa1111  ->  3 behind origin/main (bbb2222) [as of last fetch]")
})

test_that("format_status survives an empty registry", {
  out <- format_status(list(), lag_clean, "/vault/memory")
  expect_identical(out[4], "REPO  CONTENT          COMMITTED")
  expect_length(out, 4L)
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'testthat::test_local(filter = "status")'`
Expected: FAIL — `could not find function "status_exit_code"`.

- [ ] **Step 3: Write the minimal implementation**

Create `R/status.R`:

```r
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'testthat::test_local(filter = "status")'`
Expected: PASS, 12 tests.

If the summary-line assertions fail on an off-by-one index, note that a blank line precedes the summary; adjust the test's `out[length(out)]` expectations only if the blank line is genuinely intended (it is).

- [ ] **Step 5: Commit**

```bash
git add R/status.R tests/testthat/test-status.R
git commit -m "feat: add pure status formatting and exit-code rules"
```

---

### Task 2: Git-backed units — `git_run()`, `default_branch()`, `artifact_git_state()`

**Files:**
- Modify: `R/status.R` (append)
- Modify: `tests/testthat/test-status.R` (append)

**Interfaces:**
- Consumes: `ARTIFACT_REL` from Task 1.
- Produces:
  - `git_run(dir, args)` → `list(ok = <lgl>, out = <chr>)`. Never signals an error.
  - `default_branch(path)` → `"main"` / `"master"` / other branch name / `NA_character_`.
  - `artifact_git_state(path, branch)` → one of `committed`, `branch-only`, `untracked-only`, `absent`, `no-clone`, `not-a-repo`, `unknown-branch`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-status.R`:

```r
# Builds a real git repo in a temp dir. Real git is used rather than mocks
# because the states being distinguished ARE git states -- a mock would only
# re-assert this file's own assumptions about how git answers.
new_repo <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  run <- function(...) system2("git", c("-C", dir, ...), stdout = FALSE, stderr = FALSE)
  run("init", "--quiet")
  run("symbolic-ref", "HEAD", "refs/heads/main")
  run("config", "user.email", "test@example.com")
  run("config", "user.name", "Test")
  run("config", "commit.gpgsign", "false")
  dir
}

write_artifact <- function(dir, text = "artifact") {
  dest <- file.path(dir, ARTIFACT_REL)
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  writeLines(text, dest)
  dest
}

git_in <- function(dir, ...) {
  system2("git", c("-C", dir, ...), stdout = FALSE, stderr = FALSE)
}

test_that("git_run reports failure as data, not an error", {
  dir <- new_repo()
  res <- git_run(dir, c("rev-parse", "--verify", "--quiet", "no-such-ref"))
  expect_false(res$ok)
  expect_silent(git_run(dir, c("rev-parse", "--verify", "--quiet", "nope")))
})

test_that("default_branch falls back to an existing branch when origin/HEAD is unset", {
  dir <- new_repo()
  write_artifact(dir)
  git_in(dir, "add", "-A")
  git_in(dir, "commit", "--quiet", "-m", "init")
  expect_identical(default_branch(dir), "main")
})

test_that("default_branch does not assume main", {
  dir <- new_repo()
  git_in(dir, "symbolic-ref", "HEAD", "refs/heads/master")
  write_artifact(dir)
  git_in(dir, "add", "-A")
  git_in(dir, "commit", "--quiet", "-m", "init")
  expect_identical(default_branch(dir), "master")
})

test_that("artifact_git_state returns committed when the artifact is on the branch", {
  dir <- new_repo()
  write_artifact(dir)
  git_in(dir, "add", "-A")
  git_in(dir, "commit", "--quiet", "-m", "init")
  expect_identical(artifact_git_state(dir, "main"), "committed")
})

test_that("artifact_git_state returns branch-only when it is committed elsewhere", {
  dir <- new_repo()
  writeLines("seed", file.path(dir, "seed.txt"))
  git_in(dir, "add", "-A")
  git_in(dir, "commit", "--quiet", "-m", "seed")
  git_in(dir, "checkout", "--quiet", "-b", "feature")
  write_artifact(dir)
  git_in(dir, "add", "-A")
  git_in(dir, "commit", "--quiet", "-m", "artifact on feature")
  expect_identical(artifact_git_state(dir, "main"), "branch-only")
})

test_that("artifact_git_state returns untracked-only when it is on disk but unadded", {
  dir <- new_repo()
  writeLines("seed", file.path(dir, "seed.txt"))
  git_in(dir, "add", "-A")
  git_in(dir, "commit", "--quiet", "-m", "seed")
  write_artifact(dir)
  expect_identical(artifact_git_state(dir, "main"), "untracked-only")
})

test_that("untracked-only wins over absent -- the precedence that matters", {
  # Both conditions hold at once: the artifact is absent from main AND present
  # untracked on disk. Reporting `absent` would be true but useless; it would
  # send someone to recompose a file that is already composed and merely
  # uncommitted. This is hvtiRbootstrap's exact state.
  dir <- new_repo()
  writeLines("seed", file.path(dir, "seed.txt"))
  git_in(dir, "add", "-A")
  git_in(dir, "commit", "--quiet", "-m", "seed")
  write_artifact(dir)
  expect_false(artifact_git_state(dir, "main") == "absent")
  expect_identical(artifact_git_state(dir, "main"), "untracked-only")
})

test_that("artifact_git_state returns absent when it is nowhere", {
  dir <- new_repo()
  writeLines("seed", file.path(dir, "seed.txt"))
  git_in(dir, "add", "-A")
  git_in(dir, "commit", "--quiet", "-m", "seed")
  expect_identical(artifact_git_state(dir, "main"), "absent")
})

test_that("artifact_git_state reports a missing clone and a non-repo", {
  missing <- file.path(withr::local_tempdir(), "does-not-exist")
  expect_identical(artifact_git_state(missing, "main"), "no-clone")

  plain <- withr::local_tempdir()
  expect_identical(artifact_git_state(plain, "main"), "not-a-repo")
})

test_that("artifact_git_state reports unknown-branch when the branch is NA", {
  dir <- new_repo()
  expect_identical(artifact_git_state(dir, NA_character_), "unknown-branch")
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'testthat::test_local(filter = "status")'`
Expected: FAIL — `could not find function "git_run"`.

- [ ] **Step 3: Write the minimal implementation**

Append to `R/status.R`:

```r
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

# Evaluated in the order given by the spec; first match wins. The ordering is
# load-bearing at untracked-only vs absent: both are "not on the default
# branch", but only the first says the file is already composed.
artifact_git_state <- function(path, branch) {
  if (!dir.exists(path)) return("no-clone")

  inside <- git_run(path, c("rev-parse", "--is-inside-work-tree"))
  if (!inside$ok) return("not-a-repo")

  if (is.na(branch)) return("unknown-branch")

  on_branch <- git_run(path, c("cat-file", "-e", paste0(branch, ":", ARTIFACT_REL)))
  if (on_branch$ok) return("committed")

  tracked <- git_run(path, c("ls-files", "--error-unmatch", ARTIFACT_REL))
  if (tracked$ok) return("branch-only")

  if (file.exists(file.path(path, ARTIFACT_REL))) return("untracked-only")

  "absent"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'testthat::test_local(filter = "status")'`
Expected: PASS, 22 tests.

- [ ] **Step 5: Commit**

```bash
git add R/status.R tests/testthat/test-status.R
git commit -m "feat: add git-backed artifact state detection"
```

---

### Task 3: `tag_lag()`

**Files:**
- Modify: `R/status.R` (append)
- Modify: `tests/testthat/test-status.R` (append)

**Interfaces:**
- Consumes: `git_run()` from Task 2.
- Produces: `tag_lag(repo_root, fetch = TRUE, tag = "house-style-v1", remote_ref = "origin/main")` → `list(behind = <int>, tag_sha = <chr>, main_sha = <chr>, fetched = <lgl>)`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-status.R`:

```r
test_that("tag_lag counts commits between the tag and the ref", {
  dir <- new_repo()
  writeLines("one", file.path(dir, "a.txt"))
  git_in(dir, "add", "-A"); git_in(dir, "commit", "--quiet", "-m", "one")
  git_in(dir, "tag", "house-style-v1")
  writeLines("two", file.path(dir, "b.txt"))
  git_in(dir, "add", "-A"); git_in(dir, "commit", "--quiet", "-m", "two")

  # No remote in a temp repo, so compare against the local branch instead.
  lag <- tag_lag(dir, fetch = FALSE, remote_ref = "main")
  expect_identical(lag$behind, 1L)
  expect_false(lag$fetched)
  expect_true(nzchar(lag$tag_sha))
})

test_that("tag_lag reports zero when the tag is current", {
  dir <- new_repo()
  writeLines("one", file.path(dir, "a.txt"))
  git_in(dir, "add", "-A"); git_in(dir, "commit", "--quiet", "-m", "one")
  git_in(dir, "tag", "house-style-v1")

  lag <- tag_lag(dir, fetch = FALSE, remote_ref = "main")
  expect_identical(lag$behind, 0L)
})

test_that("tag_lag returns NA rather than failing when the tag is absent", {
  dir <- new_repo()
  writeLines("one", file.path(dir, "a.txt"))
  git_in(dir, "add", "-A"); git_in(dir, "commit", "--quiet", "-m", "one")

  lag <- tag_lag(dir, fetch = FALSE, remote_ref = "main")
  expect_true(is.na(lag$behind))
  expect_true(is.na(lag$tag_sha))
})

test_that("a failed fetch degrades to fetched = FALSE without erroring", {
  # No remote configured, so the fetch cannot succeed. It must not signal.
  dir <- new_repo()
  writeLines("one", file.path(dir, "a.txt"))
  git_in(dir, "add", "-A"); git_in(dir, "commit", "--quiet", "-m", "one")
  git_in(dir, "tag", "house-style-v1")

  lag <- expect_silent(tag_lag(dir, fetch = TRUE, remote_ref = "main"))
  expect_false(lag$fetched)
  expect_identical(lag$behind, 0L)
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'testthat::test_local(filter = "status")'`
Expected: FAIL — `could not find function "tag_lag"`.

- [ ] **Step 3: Write the minimal implementation**

Append to `R/status.R`:

```r
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'testthat::test_local(filter = "status")'`
Expected: PASS, 26 tests.

- [ ] **Step 5: Commit**

```bash
git add R/status.R tests/testthat/test-status.R
git commit -m "feat: add tag lag reporting with graceful offline fallback"
```

---

### Task 4: Entry point `tools/status.R`

**Files:**
- Create: `tools/status.R`
- Modify: `docs/superpowers/specs/2026-08-18-house-style-status-design.md` (arrow glyph → ASCII)

**Interfaces:**
- Consumes: everything from Tasks 1–3, plus `load_registry(path)`, `read_sources(vault_dir)` and `check_repo(sources, entry)` from `R/compose.R` (confirmed at `R/compose.R:48`, `:147`, `:308`). `check_repo()` returns `list(ok, reason)` with `reason` one of `"missing"` or `"stale"`.
- Produces: an executable script. No R functions consumed by later tasks.

Read `tools/gate.R` before writing this — it is the existing precedent for an R entry point in this repo, and this file should match its shape for sourcing `R/compose.R` and resolving the repo root.

- [ ] **Step 1: Write the entry point**

Create `tools/status.R`:

```r
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
  if (length(file_arg)) return(dirname(normalizePath(sub("^--file=", "", file_arg[1]))))
  getwd()
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
```

- [ ] **Step 2: Make it executable and run it**

```bash
chmod +x tools/status.R
./tools/status.R --no-fetch; echo "[exit: $?]"
```

Expected: a header line, a `sources:` line, a blank line, a `REPO / CONTENT / COMMITTED` table with ten rows, and a summary naming `hvtiRbootstrap`. Exit `2`, because hvtiRbootstrap's artifact is untracked.

- [ ] **Step 3: Verify the success criteria**

```bash
./tools/status.R --no-fetch | grep hvtiRbootstrap
```

Expected: the row shows `NO (untracked)` — the case `compose-house-style.R --check --all` reports as `OK`.

```bash
./compose-house-style.R --check --all | grep hvtiRbootstrap
```

Expected: `OK    hvtiRbootstrap`. The two disagreeing is the entire point of this tool.

- [ ] **Step 4: Fix the spec's arrow glyph**

The spec's output example uses `→`; the implementation emits `->`. Make the spec match:

```bash
sed -i '' 's/345fae8  →  7 behind/345fae8  ->  7 behind/' \
  docs/superpowers/specs/2026-08-18-house-style-status-design.md
grep -n 'behind origin/main' docs/superpowers/specs/2026-08-18-house-style-status-design.md
```

- [ ] **Step 5: Run the full suite**

Run: `Rscript tests/testthat.R`
Expected: every file passes; `status: ..........................` appears; the two `mirror` tests skip in CI and run locally.

- [ ] **Step 6: Commit**

```bash
git add tools/status.R docs/superpowers/specs/2026-08-18-house-style-status-design.md
git commit -m "feat: add tools/status.R portfolio status entry point"
```

---

### Task 5: Document the tool in the README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read the surrounding section**

```bash
grep -n 'compose-house-style.R --check' README.md
```

Place the new text in whichever section documents the composer's commands, matching its existing prose voice — full sentences, explaining why rather than restating the flag.

- [ ] **Step 2: Add the paragraph**

Insert after the existing `--check --all` description:

```markdown
`tools/status.R` answers a wider question than `--check --all` does. The check
compares each artifact against the vault, reading the working tree; it cannot
see whether that artifact is committed on the branch the repo's CI actually
reads, so a composed-but-uncommitted file passes locally and fails in CI. The
status view adds that column, plus a header line showing how far
`house-style-v1` trails `origin/main`. It exits 2 when a repo needs attention
and 0 otherwise — a lagging tag is reported but never counted as a failure,
since the tag is meant to lag between a merge and a deliberate move.
```

- [ ] **Step 3: Verify no count claims were introduced**

```bash
grep -niE '\bnine\b|\bten\b' README.md
```

Expected: only the pre-existing "ten" instances. Do not add a new hard-coded repository count.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: describe tools/status.R in the README"
```

---

## Verification

Before opening the PR:

```bash
Rscript tests/testthat.R
./tools/status.R --no-fetch; echo "[exit: $?]"
./tools/status.R; echo "[exit: $?]"
```

Expected: suite green; both runs print the table; the fetching run's header lacks the `[as of last fetch]` suffix; both exit 2 while hvtiRbootstrap's artifact stays uncommitted.

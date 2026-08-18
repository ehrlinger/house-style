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

test_that("artifact_git_state prefers origin/<branch> over the local branch", {
  # Simulates the case Fix 2 exists for: the artifact is committed and pushed
  # to origin/main, but the local main was never fetched forward. Checking
  # the bare `branch` rev alone would find it absent -- a false alarm telling
  # someone to commit a file that is already on origin.
  dir <- new_repo()
  writeLines("seed", file.path(dir, "seed.txt"))
  git_in(dir, "add", "-A")
  git_in(dir, "commit", "--quiet", "-m", "seed")

  # Commit the artifact on a side branch, then point refs/remotes/origin/main
  # at that commit directly -- standing in for "pushed to origin, not yet
  # fetched into the local main" without a real remote or a second clone.
  git_in(dir, "checkout", "--quiet", "-b", "pushed")
  write_artifact(dir)
  git_in(dir, "add", "-A")
  git_in(dir, "commit", "--quiet", "-m", "artifact")
  sha <- system2("git", c("-C", dir, "rev-parse", "pushed"),
                 stdout = TRUE, stderr = FALSE)
  git_in(dir, "update-ref", "refs/remotes/origin/main", sha)
  git_in(dir, "checkout", "--quiet", "main")

  expect_false(file.exists(file.path(dir, ARTIFACT_REL)))
  expect_identical(artifact_git_state(dir, "main"), "committed")
})

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
  # remote_ref = "main" does not match ^origin/(.+)$, so tag_lag() does not
  # even attempt a fetch here -- fetched = FALSE for that reason now, not
  # because a fetch was attempted and failed.
  dir <- new_repo()
  writeLines("one", file.path(dir, "a.txt"))
  git_in(dir, "add", "-A"); git_in(dir, "commit", "--quiet", "-m", "one")
  git_in(dir, "tag", "house-style-v1")

  lag <- expect_silent(tag_lag(dir, fetch = TRUE, remote_ref = "main"))
  expect_false(lag$fetched)
  expect_identical(lag$behind, 0L)
})

test_that("tag_lag derives the fetch from remote_ref -- origin/main with no remote configured", {
  # remote_ref = "origin/main" DOES match ^origin/(.+)$, so tag_lag() now
  # attempts `git fetch origin main`. With no remote configured that attempt
  # fails, and must still degrade to fetched = FALSE without erroring, the
  # same as any other offline/no-remote case.
  dir <- new_repo()
  writeLines("one", file.path(dir, "a.txt"))
  git_in(dir, "add", "-A"); git_in(dir, "commit", "--quiet", "-m", "one")
  git_in(dir, "tag", "house-style-v1")

  lag <- expect_silent(tag_lag(dir, fetch = TRUE, remote_ref = "origin/main"))
  expect_false(lag$fetched)
})

test_that("git_run does not signal when the git binary cannot be launched", {
  # Making PATH empty is what actually makes git unfindable in this
  # environment -- verified separately that Sys.which("git") returns "" and
  # that system2() raises an R error (not a warning) when the binary is
  # missing, which suppressWarnings() alone cannot catch. This is exactly the
  # failure mode Fix 1's tryCatch exists for.
  withr::with_path(new = character(0), action = "replace", {
    expect_identical(Sys.which("git"), c(git = ""))
    res <- expect_silent(git_run(".", c("status")))
    expect_false(res$ok)
    expect_identical(res$out, character(0))
  })
})

test_that("an unknown git_state errors loudly from needs_attention and format_status", {
  rows <- list(row("a", git_state = "quantum-superposition"))
  expect_error(needs_attention(rows), "quantum-superposition")
  expect_error(needs_attention(rows), "a")
  expect_error(format_status(rows, lag_clean, "/vault/memory"), "quantum-superposition")
})

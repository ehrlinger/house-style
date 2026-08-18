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

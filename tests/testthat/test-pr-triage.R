# bin/pr-triage.jq decides which pull requests get merged first on a day the
# queue is buried. pr-triage.sh only fetches and prints; this filter is where a
# wrong answer would send a PR to merge with a failed check, or leave a green
# one waiting. It is a pure function of the GraphQL response, so it runs here
# against a fixture, with no network and no token.

triage <- function(fixture = "response.json") {
  testthat::skip_if(Sys.which("jq") == "", "jq is not installed")
  filter <- testthat::test_path("..", "..", "bin", "pr-triage.jq")
  input <- testthat::test_path("fixtures", "pr-triage", fixture)
  # Flatten to TSV in jq itself, so the suite needs no JSON package.
  program <- paste(
    paste(readLines(filter), collapse = "\n"),
    '| .[] | ["\\(.repo)#\\(.number)", .state, .detail, .review] | @tsv'
  )
  out <- system2(
    "jq", c("-r", shQuote(program), shQuote(normalizePath(input))),
    stdout = TRUE
  )
  utils::read.delim(
    text = out, header = FALSE, quote = "", na.strings = NULL,
    col.names = c("pr", "state", "detail", "review"),
    colClasses = "character"
  )
}

test_that("each pull request gets the state its checks imply", {
  rows <- triage()
  state <- setNames(rows$state, rows$pr)
  expect_identical(state[["pkgA#1"]], "READY")
  expect_identical(state[["pkgA#2"]], "RED")
  expect_identical(state[["pkgA#3"]], "WAITING")
  expect_identical(state[["pkgA#4"]], "CONFLICT")
  expect_identical(state[["pkgB#9"]], "NO-CHECKS")
  expect_identical(state[["pkgB#7"]], "DRAFT")
})

test_that("a skipped check counts as passing", {
  # A required job skipped by its `if:` satisfies the ruleset, so it must not
  # hold a pull request out of READY.
  rows <- triage()
  expect_identical(rows$state[rows$pr == "pkgA#1"], "READY")
})

test_that("a failure outranks checks still waiting", {
  # One red check already decides the PR; waiting on the rest wastes the wait.
  rows <- triage()
  expect_identical(
    rows$detail[rows$pr == "pkgA#2"], "failed: lint, ci/legacy"
  )
})

test_that("queued and running checks are counted apart", {
  # The difference matters: queued means the account's runners are full,
  # running means the PR is merely slow.
  rows <- triage()
  expect_identical(rows$detail[rows$pr == "pkgA#3"], "3 queued, 1 running")
})

test_that("rows come out in the order to act on them", {
  rows <- triage()
  expect_identical(
    rows$pr,
    c("pkgA#1", "pkgA#2", "pkgA#4", "pkgA#3", "pkgB#9", "pkgB#7")
  )
})

test_that("a missing review decision is reported, not treated as a block", {
  rows <- triage()
  expect_identical(rows$review[rows$pr == "pkgA#1"], "NONE")
  expect_identical(rows$state[rows$pr == "pkgA#1"], "READY")
})

test_that("a repository with no open pull requests contributes nothing", {
  rows <- triage()
  expect_false(any(startsWith(rows$pr, "pkgC#")))
})

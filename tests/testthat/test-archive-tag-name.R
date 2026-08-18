# bin/archive-tag-name.sh is the only piece of the tag-move path with logic in
# it. The rest of move-tag.sh talks to a remote and needs a mounted vault, so it
# cannot run here; this part was split out precisely so it can.
#
# What it must guarantee: the name it prints is not already a tag. An archive
# tag that collides would be force-moved by a later run, and a tag that moves is
# not an archive.

archive_tag_name <- function(date, existing = character(0)) {
  script <- testthat::test_path("..", "..", "bin", "archive-tag-name.sh")
  out <- suppressWarnings(system2(
    "bash", c(normalizePath(script), shQuote(date)),
    input = existing, stdout = TRUE, stderr = TRUE
  ))
  structure(out, status = attr(out, "status"))
}

test_that("an unused date yields the plain name", {
  expect_identical(archive_tag_name("2026-08-17"), "standard-2026-08-17")
})

test_that("a taken name gets a numeric suffix", {
  expect_identical(
    archive_tag_name("2026-08-17", "standard-2026-08-17"),
    "standard-2026-08-17-2"
  )
})

test_that("suffixes keep climbing until one is free", {
  expect_identical(
    archive_tag_name(
      "2026-08-17",
      c("standard-2026-08-17", "standard-2026-08-17-2", "standard-2026-08-17-3")
    ),
    "standard-2026-08-17-4"
  )
})

test_that("unrelated tags are ignored", {
  expect_identical(
    archive_tag_name("2026-08-17", c("house-style-v1", "standard-2026-01-01", "v2")),
    "standard-2026-08-17"
  )
})

test_that("a partial match is not a match", {
  # standard-2026-08-1 is a different date and must not push 2026-08-17 to a
  # suffix. grep -x rather than a substring search is what makes this hold.
  expect_identical(
    archive_tag_name("2026-08-17", c("standard-2026-08-1", "standard-2026-08-170")),
    "standard-2026-08-17"
  )
})

test_that("a malformed date is refused rather than guessed at", {
  res <- archive_tag_name("17-08-2026")
  expect_identical(attr(res, "status"), 1L)
  expect_match(paste(res, collapse = " "), "not YYYY-MM-DD")
})

test_that("a missing date is refused", {
  res <- archive_tag_name("")
  expect_identical(attr(res, "status"), 1L)
  expect_match(paste(res, collapse = " "), "usage")
})

test_that("source_hashes returns one sha256 per source file", {
  h <- source_hashes(testthat::test_path("fixtures", "vault"))

  expect_named(h, unname(SOURCE_FILES))
  expect_true(all(grepl("^[0-9a-f]{64}$", h)))
})

test_that("source_hashes changes when a byte changes", {
  tmp <- withr::local_tempdir()
  for (f in SOURCE_FILES) writeLines("placeholder", file.path(tmp, f))
  before <- source_hashes(tmp)

  writeLines("placeholder edited", file.path(tmp, "writing-voice.md"))
  after <- source_hashes(tmp)

  expect_false(identical(before[["writing-voice.md"]], after[["writing-voice.md"]]))
  expect_identical(
    before[setdiff(SOURCE_FILES, "writing-voice.md")],
    after[setdiff(SOURCE_FILES, "writing-voice.md")]
  )
})

test_that("source_hashes fails loudly on a missing source", {
  tmp <- withr::local_tempdir()
  writeLines("placeholder", file.path(tmp, "writing-voice.md"))

  expect_error(source_hashes(tmp), "writing-reader-profile\\.md")
})

test_that("a formatted manifest parses back to the same hashes", {
  h <- source_hashes(testthat::test_path("fixtures", "vault"))

  expect_identical(parse_manifest(format_manifest(h)), h)
})

test_that("format_manifest is deterministic and order-independent", {
  h <- source_hashes(testthat::test_path("fixtures", "vault"))

  expect_identical(format_manifest(h), format_manifest(rev(h)))
})

test_that("parse_manifest rejects a manifest naming the wrong files", {
  h <- source_hashes(testthat::test_path("fixtures", "vault"))
  lines <- format_manifest(h)
  lines <- sub("writing-voice\\.md", "writing-voise.md", lines)

  expect_error(parse_manifest(lines), "writing-voise\\.md")
})

test_that("parse_manifest rejects a manifest naming a source twice", {
  # A duplicate is the shape a hand edit leaves behind, and subsetting by
  # name would silently keep the first and drop the rest -- an unnoticed
  # line in the file whose whole job is to notice unnoticed edits.
  h <- source_hashes(testthat::test_path("fixtures", "vault"))
  lines <- c(format_manifest(h), sprintf("%-30s %s", "writing-voice.md", strrep("0", 64)))

  expect_error(parse_manifest(lines), "twice|duplicate|exactly once")
})

test_that("parse_manifest rejects a malformed hash", {
  h <- source_hashes(testthat::test_path("fixtures", "vault"))
  lines <- sub("[0-9a-f]{64}", "notahash", format_manifest(h))

  expect_error(parse_manifest(lines), "Malformed")
})

test_that("the committed MANIFEST matches the committed sources", {
  mirror <- testthat::test_path("..", "..", "sources")

  expect_identical(
    parse_manifest(readLines(file.path(mirror, "MANIFEST"), warn = FALSE)),
    source_hashes(mirror)
  )
})

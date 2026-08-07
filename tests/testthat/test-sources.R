fixture_vault <- function() testthat::test_path("fixtures", "vault")

test_that("read_sources returns all four documents", {
  src <- read_sources(fixture_vault())

  expect_named(src, c("voice", "personas", "context", "structure"))
  expect_true(all(vapply(src, is.character, logical(1))))
  expect_true(all(vapply(src, length, integer(1)) == 1L))
  expect_match(src$voice, "Two registers")
  expect_match(src$personas, "Persona a body")
  expect_match(src$structure, "README canonical order")
})

test_that("read_sources fails loudly on a missing source", {
  tmp <- withr::local_tempdir()
  file.create(file.path(tmp, "writing-voice.md"))

  expect_error(
    read_sources(tmp),
    "writing-reader-profile\\.md"
  )
})

test_that("read_sources fails loudly on an empty source", {
  tmp <- withr::local_tempdir()
  for (f in SOURCE_FILES) file.create(file.path(tmp, f))
  writeLines("placeholder", file.path(tmp, "writing-reader-profile.md"))
  writeLines("placeholder", file.path(tmp, "writing-context.md"))
  writeLines("placeholder", file.path(tmp, "r-package-structure.md"))
  # writing-voice.md is left zero-length by file.create() above.

  expect_error(
    read_sources(tmp),
    "writing-voice\\.md"
  )
})

test_that("read_sources fails loudly on a whitespace-only source", {
  tmp <- withr::local_tempdir()
  for (f in SOURCE_FILES) writeLines("placeholder", file.path(tmp, f))
  writeLines(c("", "   ", "\t"), file.path(tmp, "writing-context.md"))

  expect_error(
    read_sources(tmp),
    "writing-context\\.md"
  )
})

test_that("read_sources preserves non-ASCII characters", {
  tmp <- withr::local_tempdir()
  for (f in SOURCE_FILES) {
    writeLines("placeholder", file.path(tmp, f), useBytes = TRUE)
  }
  # An em-dash and a curly quote, as the real vault sources contain.
  writeLines(
    c("# Voice", "", "Em-dash — and a curly quote ’ here."),
    file.path(tmp, "writing-voice.md"),
    useBytes = TRUE
  )

  src <- read_sources(tmp)

  expect_true(validUTF8(src$voice))
  expect_match(src$voice, "—", fixed = TRUE)
  expect_match(src$voice, "’", fixed = TRUE)
})

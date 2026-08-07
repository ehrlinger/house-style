tmp_entry <- function(dir) list(
  name = "hvtiPlotR", path = dir,
  profile = "package-internal", default_persona = "a", secondary_personas = "c"
)

test_that("write then check round-trips clean", {
  dir <- withr::local_tempdir()
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  entry <- tmp_entry(dir)

  path <- write_house_style(src, entry)

  expect_true(file.exists(path))
  expect_equal(basename(path), "house-style.md")
  expect_equal(basename(dirname(path)), ".claude")

  expect_true(check_repo(src, entry)$ok)
})

test_that("check reports a missing artifact", {
  dir <- withr::local_tempdir()
  src <- read_sources(testthat::test_path("fixtures", "vault"))

  res <- check_repo(src, tmp_entry(dir))
  expect_false(res$ok)
  expect_equal(res$reason, "missing")
})

test_that("check detects a hand-edited artifact", {
  dir <- withr::local_tempdir()
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  entry <- tmp_entry(dir)

  path <- write_house_style(src, entry)
  cat("\nsomeone edited this by hand\n", file = path, append = TRUE)

  res <- check_repo(src, entry)
  expect_false(res$ok)
  expect_equal(res$reason, "stale")
})

test_that("check tolerates trailing whitespace", {
  dir <- withr::local_tempdir()
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  entry <- tmp_entry(dir)

  path <- write_house_style(src, entry)
  cat("\n   \n", file = path, append = TRUE)

  res <- check_repo(src, entry)
  expect_true(res$ok)
})

test_that("check catches leading drift", {
  dir <- withr::local_tempdir()
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  entry <- tmp_entry(dir)

  path <- write_house_style(src, entry)
  original <- readBin(path, "raw", n = file.size(path))
  writeBin(c(charToRaw("\n\n"), original), path)

  res <- check_repo(src, entry)
  expect_false(res$ok)
  expect_equal(res$reason, "stale")
})

test_that("check detects a changed source", {
  dir <- withr::local_tempdir()
  vault <- withr::local_tempdir()
  file.copy(
    list.files(testthat::test_path("fixtures", "vault"), full.names = TRUE),
    vault
  )
  entry <- tmp_entry(dir)

  write_house_style(read_sources(vault), entry)

  # Change a source, as editing the vault would.
  cat("\nA new voice rule.\n", file = file.path(vault, "writing-voice.md"), append = TRUE)

  res <- check_repo(read_sources(vault), entry)
  expect_false(res$ok)
  expect_equal(res$reason, "stale")
})

test_that("the written artifact is valid UTF-8 regardless of string encoding", {
  dir <- withr::local_tempdir()
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  entry <- tmp_entry(dir)

  path <- write_house_style(src, entry)
  raw_bytes <- readBin(path, "raw", n = file.size(path))

  # rawToChar() + validUTF8() fails loudly if any non-UTF-8 byte was written.
  expect_true(validUTF8(rawToChar(raw_bytes)))

  # And the bytes are exactly the composed document, nothing added.
  expect_identical(raw_bytes, charToRaw(enc2utf8(compose_house_style(src, entry))))
})

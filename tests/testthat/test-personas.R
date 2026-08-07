test_that("filter_personas keeps only the requested personas", {
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  out <- filter_personas(src$personas, keep = c("a", "c"))

  expect_match(out, "Persona a body")
  expect_match(out, "Persona c body")
  expect_false(grepl("Persona b body", out, fixed = TRUE))
  expect_false(grepl("Persona d body", out, fixed = TRUE))
})

test_that("filter_personas retains the preamble", {
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  out <- filter_personas(src$personas, keep = "d")

  expect_match(out, "Preamble line that must survive filtering")
  expect_match(out, "Persona d body")
  expect_false(grepl("Persona a body", out, fixed = TRUE))
})

test_that("filter_personas preserves document order regardless of keep order", {
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  out <- filter_personas(src$personas, keep = c("c", "a"))

  expect_lt(
    regexpr("Persona a body", out, fixed = TRUE),
    regexpr("Persona c body", out, fixed = TRUE)
  )
})

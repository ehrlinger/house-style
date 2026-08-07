test_that("registry loads and validates every entry", {
  reg <- load_registry(testthat::test_path("..", "..", "repos.yml"))

  expect_length(reg, 9L)
  expect_equal(reg[[1]]$name, "hvtiPlotR")
  expect_equal(reg[[1]]$profile, "package-internal")
  expect_equal(reg[[1]]$default_persona, "a")
  expect_equal(reg[[1]]$secondary_personas, "c")

  profiles <- vapply(reg, function(e) e$profile, character(1))
  expect_true(all(profiles %in% c("package-internal", "package-cran", "book")))

  # Paths are expanded, not left with a literal tilde.
  expect_false(any(grepl("^~", vapply(reg, function(e) e$path, character(1)))))
})

test_that("registry rejects an unknown profile", {
  tmp <- withr::local_tempfile(fileext = ".yml")
  writeLines(c(
    "repos:",
    "  - name: bogus",
    "    path: /tmp/bogus",
    "    profile: not-a-profile",
    "    default_persona: a",
    "    secondary_personas: []"
  ), tmp)

  expect_error(load_registry(tmp), "unknown profile")
})

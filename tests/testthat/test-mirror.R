test_that("the CI source mirror matches the vault when the vault is present", {
  vault <- path.expand("~/Documents/ObsidianVault/memory")
  skip_if_not(dir.exists(vault), "vault not present (CI)")

  mirror <- testthat::test_path("..", "..", "sources")
  for (f in SOURCE_FILES) {
    expect_identical(
      readLines(file.path(mirror, f), warn = FALSE),
      readLines(file.path(vault, f), warn = FALSE),
      info = paste("mirror out of date:", f)
    )
  }
})

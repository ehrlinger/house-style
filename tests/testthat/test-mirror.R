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

test_that("the committed MANIFEST pins the vault's bytes, not just the mirror's", {
  vault <- path.expand("~/Documents/ObsidianVault/memory")
  skip_if_not(dir.exists(vault), "vault not present (CI)")

  # test-manifest.R already proves MANIFEST agrees with sources/. That pair
  # can be consistent and still stale -- a sync that updates both together
  # is exactly how the drift in #8 stayed green. Anchoring the manifest to
  # the vault is what makes it mean "current" rather than "self-consistent".
  mirror <- testthat::test_path("..", "..", "sources")

  expect_identical(
    parse_manifest(readLines(file.path(mirror, MANIFEST_FILE), warn = FALSE)),
    source_hashes(vault)
  )
})

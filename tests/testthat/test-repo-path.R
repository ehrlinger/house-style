# A registry entry whose `path:` is not a directory on disk is a configuration
# error, not drift. Before this was split out, both CLI modes got it wrong in
# opposite directions: --check folded it into the "out of date with the vault
# sources / Recompose with:" bucket (exit 2, wrong remedy), and composition
# printed SKIP and exited 0 (silent success, nothing written). Three entries
# went stale at once during the Wave 2 clone renames and every one of them
# reported as drift.
#
# The classifier and its message are unit-tested here; the CLI's use of them is
# tested end-to-end below, because the bucketing and the exit code ARE the bug
# and no test of a helper can prove they changed. The subprocess cost buys
# detection power the in-process tests cannot (cf. the rejected cross-process
# determinism test in test-compose.R, which bought none).

entry_at <- function(path, name = "hvtiRpropensity") list(
  name = name, path = path,
  profile = "package-internal", default_persona = "a", secondary_personas = "c"
)

test_that("an existing directory is not a problem", {
  expect_null(repo_path_problem(entry_at(withr::local_tempdir())))
})

test_that("a path that is not on disk at all is absent", {
  gone <- file.path(withr::local_tempdir(), "hvtiPropensityScores")
  expect_identical(repo_path_problem(entry_at(gone)), "absent")
})

test_that("a path that exists but is a file is not-a-directory", {
  file <- file.path(withr::local_tempdir(), "hvtiRpropensity")
  writeLines("not a clone", file)
  expect_identical(repo_path_problem(entry_at(file)), "not-a-directory")
})

test_that("the message names the repo, the path, and the absent directory", {
  gone <- "/nowhere/hvtiPropensityScores"
  msg <- format_path_problem(entry_at(gone), "absent")

  expect_match(msg, "hvtiRpropensity", fixed = TRUE)
  expect_match(msg, gone, fixed = TRUE)
  expect_match(msg, "no directory", ignore.case = TRUE)

  # The whole point: it must not read as drift, and must not send the reader
  # to the remedy that cannot fix it.
  expect_no_match(msg, "out of date", ignore.case = TRUE)
  expect_no_match(msg, "[Rr]ecompose")
})

test_that("the message distinguishes a non-directory from an absent one", {
  msg <- format_path_problem(entry_at("/tmp/afile"), "not-a-directory")
  expect_match(msg, "not a directory", ignore.case = TRUE)
})

# --- CLI ------------------------------------------------------------------
#
# Runs the real script, with a registry written for the test. The script
# resolves repos.yml relative to its own --file= directory, so it is copied
# alongside R/ into a temp tree rather than parameterised: the fix must hold
# for the CLI as it actually ships, not for a test-only entry point.

composer_dir <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  root <- testthat::test_path("..", "..")
  file.copy(file.path(root, "compose-house-style.R"), dir)
  file.copy(file.path(root, "R"), dir, recursive = TRUE)
  dir
}

write_registry <- function(dir, entries) {
  writeLines(
    c("repos:", unlist(lapply(entries, function(e) c(
      sprintf("  - name: %s", e$name),
      sprintf("    path: %s", e$path),
      "    profile: package-internal",
      "    default_persona: a",
      "    secondary_personas: [c]"
    )))),
    file.path(dir, "repos.yml")
  )
}

run_composer <- function(dir, args) {
  out <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"),
    c(file.path(dir, "compose-house-style.R"), args,
      "--vault", normalizePath(testthat::test_path("fixtures", "vault"))),
    stdout = TRUE, stderr = TRUE
  ))
  list(status = attr(out, "status") %||% 0L, text = paste(out, collapse = "\n"))
}

test_that("--check on a moved clone fails as a config error, not as drift", {
  dir <- composer_dir()
  gone <- file.path(dir, "hvtiPropensityScores")
  write_registry(dir, list(list(name = "hvtiRpropensity", path = gone)))

  res <- run_composer(dir, c("--check", "--repo", "hvtiRpropensity"))

  expect_identical(res$status, 1L)
  expect_match(res$text, "hvtiRpropensity", fixed = TRUE)
  expect_match(res$text, gone, fixed = TRUE)
  expect_no_match(res$text, "out of date")
  expect_no_match(res$text, "DRIFT")
})

test_that("composing a moved clone fails loudly rather than skipping", {
  dir <- composer_dir()
  gone <- file.path(dir, "hvtiPropensityScores")
  write_registry(dir, list(list(name = "hvtiRpropensity", path = gone)))

  res <- run_composer(dir, c("--repo", "hvtiRpropensity"))

  expect_identical(res$status, 1L)
  expect_match(res$text, gone, fixed = TRUE)
  expect_no_match(res$text, "SKIP")
})

test_that("--check --all names every stale path, and stats before composing", {
  dir <- composer_dir()
  present <- file.path(dir, "hvtiPlotR")
  dir.create(present)
  gone_a <- file.path(dir, "hvtiPropensityScores")
  gone_b <- file.path(dir, "hvti_graphics")
  write_registry(dir, list(
    list(name = "hvtiRpropensity", path = gone_a),
    list(name = "hvtiPlotR",       path = present),
    list(name = "hvtiGraphics",    path = gone_b)
  ))

  res <- run_composer(dir, c("--check", "--all"))

  expect_identical(res$status, 1L)
  expect_match(res$text, gone_a, fixed = TRUE)
  expect_match(res$text, gone_b, fixed = TRUE)
  expect_no_match(res$text, "out of date")

  # Stat first: the run stops before any artifact is checked, so a broken
  # registry never produces a per-repo verdict that a reader could act on.
  expect_no_match(res$text, "OK    hvtiPlotR")
})

test_that("real drift still reports as drift", {
  dir <- composer_dir()
  repo <- file.path(dir, "hvtiPlotR")
  dir.create(repo)
  write_registry(dir, list(list(name = "hvtiPlotR", path = repo)))

  res <- run_composer(dir, c("--check", "--repo", "hvtiPlotR"))

  expect_identical(res$status, 2L)
  expect_match(res$text, "out of date", fixed = TRUE)
})

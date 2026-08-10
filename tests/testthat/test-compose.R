entry_internal <- function() list(
  name = "hvtiPlotR", path = "/tmp/hvtiPlotR",
  profile = "package-internal", default_persona = "a", secondary_personas = "c"
)

entry_book <- function() list(
  name = "hvti_graphics", path = "/tmp/hvti_graphics",
  profile = "book", default_persona = "a", secondary_personas = "b"
)

test_that("a package profile's header names all four sources, with no timestamp", {
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  hdr <- provenance_header(src, entry_internal())

  expect_match(hdr, "GENERATED FILE")
  for (f in SOURCE_FILES) expect_match(hdr, f, fixed = TRUE)
  expect_match(hdr, "sha256:[0-9a-f]{12}")
  expect_match(hdr, "package-internal", fixed = TRUE)

  # Determinism: no date anywhere in the header.
  expect_false(grepl("\\d{4}-\\d{2}-\\d{2}", hdr))
})

test_that("the header names the repository that actually composes it", {
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  hdr <- provenance_header(src, entry_internal())

  # This text is the artifact's only instruction for regenerating itself.
  # It went stale when the composer moved out of ehrlinger-personal into
  # its own repo, and stayed stale through every compose since, because
  # nothing asserted it -- a reviewer caught it, not CI. A generated file
  # that misnames its own source is precisely the provenance failure this
  # header exists to prevent, so the claim is now pinned.
  expect_match(hdr, "ehrlinger/house-style", fixed = TRUE)
  expect_match(hdr, "compose-house-style.R", fixed = TRUE)
  expect_false(grepl("ehrlinger-personal", hdr, fixed = TRUE))
  expect_false(grepl("tools/house-style", hdr, fixed = TRUE))
})

test_that("the book profile's header omits the source it never composes", {
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  hdr <- provenance_header(src, entry_book())

  expect_match(hdr, "writing-voice.md", fixed = TRUE)
  expect_match(hdr, "writing-reader-profile.md", fixed = TRUE)
  expect_match(hdr, "writing-context.md", fixed = TRUE)

  # `book` never composes the structural rules, so an edit to them cannot
  # change a byte of this artifact's body. Recording their hash here would
  # make check_repo() report drift for a change that provably cannot affect
  # the file -- a red check that does not mean what a red check should mean.
  expect_false(grepl("r-package-structure.md", hdr, fixed = TRUE))
  expect_length(gregexpr("sha256:", hdr, fixed = TRUE)[[1]], 3L)
})

# The regression this guards is not "the header is wrong" but "the two
# functions disagree". provenance_header() decides what the artifact claims
# went into it; compose_house_style() decides what actually did. Editing
# either alone reintroduces the defect in the opposite direction -- an
# unrecorded source would be worse, since real drift would then go
# undetected. Deriving both from PROFILE_SOURCES is what keeps them honest;
# this asserts the property rather than the mechanism.
test_that("every profile's header names exactly the sources whose bodies it composes", {
  src <- read_sources(testthat::test_path("fixtures", "vault"))

  # Each fixture carries a unique H1, so body presence is detectable
  # independently of whatever the header claims.
  markers <- c(
    voice     = "# Voice fixture",
    personas  = "# Reader Profiles fixture",
    context   = "# Context fixture",
    structure = "# Structure fixture"
  )

  for (profile in VALID_PROFILES) {
    entry <- list(
      name = "fixture", path = "/tmp/fixture", profile = profile,
      default_persona = "a", secondary_personas = character(0)
    )
    hdr <- provenance_header(src, entry)
    out <- compose_house_style(src, entry)

    named <- names(SOURCE_FILES)[
      vapply(SOURCE_FILES, function(f) grepl(f, hdr, fixed = TRUE), logical(1))
    ]
    composed <- names(markers)[
      vapply(markers, function(m) grepl(m, out, fixed = TRUE), logical(1))
    ]

    expect_setequal(named, composed)
  }
})

test_that("an unknown profile is refused rather than silently composing nothing", {
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  bogus <- list(
    name = "nope", path = "/tmp/nope", profile = "not-a-profile",
    default_persona = "a", secondary_personas = character(0)
  )

  # load_registry() already rejects these, but both functions are callable
  # directly. Without a guard, PROFILE_SOURCES[["not-a-profile"]] is NULL:
  # the header would list no sources at all and the structure section would
  # vanish, silently, from a document that still looked plausible.
  expect_error(provenance_header(src, bogus), "unknown profile")
  expect_error(compose_house_style(src, bogus), "unknown profile")
})

test_that("PROFILE_SOURCES is the single source of truth for profiles", {
  expect_identical(VALID_PROFILES, names(PROFILE_SOURCES))

  for (p in names(PROFILE_SOURCES)) {
    keys <- PROFILE_SOURCES[[p]]
    expect_true(all(keys %in% names(SOURCE_FILES)))
    expect_identical(anyDuplicated(keys), 0L)

    # Canonical order, so header lines never churn on a table edit.
    expect_identical(keys, intersect(names(SOURCE_FILES), keys))
  }
})

test_that("composition is byte-deterministic", {
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  expect_identical(
    compose_house_style(src, entry_internal()),
    compose_house_style(src, entry_internal())
  )
})

# The pair-compose test above runs both calls in one process. If a clock
# read were reintroduced into provenance_header() or compose_house_style(),
# both calls would almost always land in the same second and the test
# above would keep passing right through the regression it exists to
# catch.
#
# A cross-process variant (compose once in-process, once in a fresh
# Rscript subprocess, compare bytes) was tried here and removed: when a
# Sys.time() read was deliberately reintroduced into provenance_header()
# to test the guard, this comparison did NOT fail — both processes landed
# in the same wall-clock second. It paid subprocess-spawn cost on every
# run for zero detection power against the exact regression it existed to
# guard, so it was deleted rather than patched to force a clock-second
# boundary (which would only trade slowness for flakiness).
#
# The static check below is what actually closes the gap: it inspects
# the deparsed function body for known non-deterministic primitives and
# fails the instant such a call is written, independent of timing.
#
# Scope note: this is a DIRECT-BODY check only. It deparses the body of
# each guarded function and greps that text for forbidden calls. It does
# NOT walk into helpers that a guarded function calls. compose_house_style()
# calls filter_personas(), so filter_personas() is guarded directly below
# alongside provenance_header() and compose_house_style() — a helper is
# not covered merely by being called from a guarded function. read_sources()
# and load_registry() are guarded too: a stray Sys.getenv() in either would
# be just as fatal to determinism and costs nothing to check. If any
# guarded function grows a call to a further, unguarded helper, that helper
# must be added here as well.
test_that("composition functions call no non-deterministic primitive directly", {
  # Each entry is matched against the deparsed function body. Most are
  # fixed substrings, chosen because they're already unambiguous (namespaced
  # like `Sys.time(`, or full call names like `set.seed(`). A couple are
  # short, generic English words that would otherwise false-positive on
  # unrelated future identifiers (e.g. fixed "date(" would also fire on
  # `validate(`, `invalidate(`, `format_date(`; fixed "sample(" would fire
  # on `resample(`) — those use a call-boundary regex instead.
  forbidden <- list(
    list(label = "Sys.time(",    pattern = "Sys.time(",        fixed = TRUE),
    list(label = "Sys.Date(",    pattern = "Sys.Date(",        fixed = TRUE),
    list(label = "Sys.getenv(",  pattern = "Sys.getenv(",      fixed = TRUE),
    list(label = "date(",        pattern = "\\bdate\\s*\\(",   fixed = FALSE),
    list(label = "format(Sys",   pattern = "format(Sys",       fixed = TRUE),
    list(label = "runif(",       pattern = "runif(",           fixed = TRUE),
    list(label = "sample(",      pattern = "\\bsample\\s*\\(", fixed = FALSE),
    list(label = "set.seed(",    pattern = "set.seed(",        fixed = TRUE),
    list(label = "tempfile(",    pattern = "tempfile(",        fixed = TRUE),
    list(label = "Sys.getpid(",  pattern = "Sys.getpid(",      fixed = TRUE)
  )

  check_fn <- function(fn, fn_name) {
    body_text <- paste(deparse(body(fn)), collapse = "\n")
    for (rule in forbidden) {
      expect_false(
        grepl(rule$pattern, body_text, fixed = rule$fixed),
        info = sprintf(
          "%s() must not call non-deterministic primitive '%s' — composition must stay byte-deterministic.",
          fn_name, rule$label
        )
      )
    }
  }

  check_fn(provenance_header, "provenance_header")
  check_fn(compose_house_style, "compose_house_style")
  check_fn(filter_personas, "filter_personas")
  check_fn(read_sources, "read_sources")
  check_fn(load_registry, "load_registry")
})

test_that("package profile composes all four sources in order", {
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  out <- compose_house_style(src, entry_internal())

  expect_match(out, "Two registers")              # voice
  expect_match(out, "Persona a body")             # personas, filtered
  expect_match(out, "Ecosystem and constraints")  # context
  expect_match(out, "README canonical order")     # structure

  expect_lt(regexpr("Two registers", out, fixed = TRUE),
            regexpr("Persona a body", out, fixed = TRUE))
  expect_lt(regexpr("Persona a body", out, fixed = TRUE),
            regexpr("README canonical order", out, fixed = TRUE))
})

test_that("book profile omits the package structure rules", {
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  out <- compose_house_style(src, entry_book())

  expect_match(out, "Two registers")
  expect_false(grepl("README canonical order", out, fixed = TRUE))
})

test_that("the composed document names the repo's default persona", {
  src <- read_sources(testthat::test_path("fixtures", "vault"))
  out <- compose_house_style(src, entry_internal())

  expect_match(out, "House Style . hvtiPlotR")
  expect_match(out, "default reader persona.*\\(a\\)", ignore.case = TRUE)
})

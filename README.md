# house-style

The documentation and CI standard for the HVTI CORR R package portfolio, plus
the composer that distributes it.

Nine repositories share an author, an institution and a documentation
philosophy. This repo holds the rules they share and the tool that keeps each
one's copy current.

## What is here

| Path | What it is |
|---|---|
| `sources/` | The four source documents: voice, reader personas, project context, and the structural rules |
| `sources/MANIFEST` | sha256 of each mirrored source, so CI can detect a hand edit without the vault |
| `compose-house-style.R` | CLI that composes those into one self-contained `.claude/house-style.md` per repository |
| `R/compose.R` | The composition functions |
| `repos.yml` | The registry — the only place the governed repositories are enumerated |
| `bin/move-tag.sh` | The only supported way to advance `house-style-v1` — gates on a verified mirror |
| `tools/gate.R` | Runs the suite in gate mode, where a skipped test counts as a failure |
| `tools/write-manifest.R` | Regenerates `sources/MANIFEST` after a vault sync |
| `tests/` | 148 expectations covering composition, drift detection and mirror freshness |

## Why a composer rather than a copied file

The convention this replaces was "keep a synced copy in each repo." Both
repositories that adopted it ended up with a stale document, neither noticed:
one was missing two whole sections, another was three weeks behind and had lost
an entire reader persona. A hand-maintained copy in nine places is nine chances
to drift silently.

So the artifact is generated. Each repo commits a `.claude/house-style.md` with
a provenance header carrying a SHA-256 prefix per source, and a CI job
recomposes and compares. Drift becomes a red check rather than something nobody
sees for months.

## Usage

```bash
# Write one repository's artifact
Rscript compose-house-style.R --repo hvtiPlotR

# Verify every registered repository matches its sources
Rscript compose-house-style.R --check --all
```

Exit codes: **0** clean, **1** usage error or missing source, **2** drift.

Sources are read from `~/Documents/ObsidianVault/memory/` when that exists, and
otherwise from `sources/` in this repo — which is what CI uses, since a runner
has no vault. Every run prints which directory it read.

## Profiles

A repository composes only the parts that apply to it.

| Profile | Personas | Structure rules |
|---|---|---|
| `package-internal` | (a) biostatistician, plus (c) for SAS ports | full |
| `package-cran` | (d) public CRAN user, plus (c) for SAS ports | full, plus the release gate |
| `book` | (a), with (b) as a constraint | none — a book has no README canonical order |

`R/compose.R` holds that table as `PROFILE_SOURCES`, and both the composed body
and the provenance header are read from it. **A header records only the sources
its profile actually composes** — so a `book` artifact names three, not four.

This matters more than it sounds. The header is not just documentation: the
drift check recomposes and compares bytes, so every line in it is load-bearing.
Hashing a source a profile excludes makes the check strictly more sensitive than
the artifact it guards, and `hvti_graphics` went red twice in one afternoon for
edits to structural rules its profile omits entirely — a byte-identical body,
reported as drift. A red check that does not mean what a red check should mean
is the exact failure this repository argues against, so it does not get to live
inside the mechanism that enforces it.

## The `house-style-v1` tag

Consumer repositories pin their drift-check job to the tag `house-style-v1`
rather than to `main`.

Not `main`, because an in-progress commit here would redden nine repositories at
once. Not a commit SHA either, because this repo carries the *reference sources*
as well as the tool — a frozen ref would freeze what the check compares against,
and the check could never detect drift again.

The tag moves, deliberately, when the standard changes:

```bash
bin/move-tag.sh -m 'what changed'
```

Advancing it is what makes every repository report drift until it recomposes.
That is the intended signal, not a failure.

Use the script rather than `git tag -f` directly. Moving the tag is the moment
stale sources propagate to nine repositories, and it is the only moment in the
lifecycle guaranteed to happen on a machine with the vault — so it is where the
mirror check is both possible and worth blocking on. The script refuses on a
dirty tree, on a commit that is not an ancestor of `origin/main`, on any test
failure, and on any test *skip*.

## What checks the mirror, and when

`sources/` is a copy of the vault, and a copy can go stale. Three checks cover
different halves of that, because no single one can cover all of it:

| Check | Runs | Catches | Cannot catch |
|---|---|---|---|
| `sources/MANIFEST` vs `sources/` | CI, every push | a hand edit to `sources/` | a stale sync |
| `sources/` vs the vault | locally, vault present | a stale mirror | anything, on a runner |
| `bin/move-tag.sh` | before the tag moves | both, and refuses to propagate | — |

A runner has no vault, so CI genuinely cannot know whether `sources/` is
current — that is a limit, not an oversight. What CI can do is pin the bytes
and say plainly that it did not check the rest: the test job emits a warning
annotation and a job-summary note whenever the vault was absent. Previously it
printed a skip, which reads like a pass. See #8 for what that cost.

A run is therefore reproducible only until the tag next moves — weaker than a
SHA, stronger than a branch. The trade holds because moves are deliberate and
rare rather than incidental to every push. `house-style-v2` is reserved for an
incompatible change to the composer's CLI, so repositories could migrate on
their own schedule.

## Determinism

Composition is byte-deterministic given the same sources. There is no timestamp
in the provenance header — a date would make `--check` fail the day after every
composition and turn CI permanently red. The source hashes carry the identity;
git records when the file changed.

A test asserts that the composition functions call no non-deterministic
primitive directly. It is a direct-body check: a clock read reached through a
helper would not be caught, which is why the two functions are written without
shared helpers between them.

`PROFILE_SOURCES` is shared between them, and is deliberately a literal list
rather than a lookup function. Indexing data is not a call, so both function
bodies stay fully covered by that check while still reading the profile rule
from one place. A second test closes the other half: for every profile, the
sources the header names must be exactly the sources whose bodies were
composed. Editing one function alone fails it — including in the direction that
would otherwise be silent, where a source composes but goes unrecorded and real
drift stops being detected.

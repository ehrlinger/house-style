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
| `compose-house-style.R` | CLI that composes those into one self-contained `.claude/house-style.md` per repository |
| `R/compose.R` | The composition functions |
| `repos.yml` | The registry — the only place the governed repositories are enumerated |
| `tests/` | 116 expectations covering composition, drift detection and mirror freshness |

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

## The `house-style-v1` tag

Consumer repositories pin their drift-check job to the tag `house-style-v1`
rather than to `main`.

Not `main`, because an in-progress commit here would redden nine repositories at
once. Not a commit SHA either, because this repo carries the *reference sources*
as well as the tool — a frozen ref would freeze what the check compares against,
and the check could never detect drift again.

The tag moves, deliberately, when the standard changes:

```bash
git tag -f -a house-style-v1 <commit> -m 'what changed'
git push -f origin house-style-v1
```

Advancing it is what makes every repository report drift until it recomposes.
That is the intended signal, not a failure.

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

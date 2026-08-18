# Design: a portfolio status view for the house style

**Date:** 2026-08-18
**Status:** implemented
**Scope:** one new R entry point, one new R source file, one new test file

## Problem

`compose-house-style.R --check --all` already answers "does each governed
repo's artifact match the vault?" for all ten repos, one line each. That is
the visibility the portfolio needs, and it has been present since the
composer was written.

It has two blind spots, both of which cost real time on 2026-08-18:

1. **It cannot see git.** `check_repo()` calls `file.exists()` and
   `readLines()` on the working tree. An artifact that exists on disk but is
   uncommitted reads as `OK`. hvtiRbootstrap is in exactly this state: its
   `.claude/house-style.md` is untracked and its drift workflow lives only on
   an unmerged branch, so a laptop check reports clean while its CI, once
   wired, would report `DRIFT (missing)`.

2. **It cannot see the tag.** Consumers pin `house-style-v1`. Whether that
   tag trails `origin/main` is invisible to a content check, so "how much is
   staged but not propagated" has to be derived by hand from a tag diff.

This design adds those two signals. It adds no new drift detection: content
drift continues to come from the existing `check_repo()`.

## Non-goals

- **Not a scheduler.** Consumer drift jobs trigger on `push` and
  `pull_request` only, so a dormant repo does not re-check after a tag move.
  That is a real latency gap and is explicitly out of scope; this work
  addresses visibility.
- **Not an aggregator of CI results.** Querying each repo's last job
  conclusion would report what CI last happened to run, which is staler than
  recomputing locally against the vault.
- **Not wired into anything.** No caller invokes `tools/status.R`: not
  `bin/move-tag.sh`, not the pre-tag gate, not a CI workflow. Its units are
  unit-tested like any other code in `R/`, but nothing gates on running the
  tool itself. Wiring it into the pre-tag gate is a plausible follow-on, to
  be decided after use.

## Placement

| Path | Role |
|---|---|
| `tools/status.R` | entry point; sources `R/compose.R` and `R/status.R`, prints, exits |
| `R/status.R` | new; the four units below |
| `tests/testthat/test-status.R` | new |

`tools/` already holds R entry points (`gate.R`, `write-manifest.R`); `bin/`
holds shell (`move-tag.sh`, `archive-tag-name.sh`). This needs the registry
with expanded paths and `check_repo()`, both in `R/compose.R`, so it is R and
belongs in `tools/`. It is a separate file from `R/compose.R` — that file is
323 lines and is the composer; status is a reporting concern that consumes
it.

## Signals

| Signal | Source | Answers |
|---|---|---|
| Content | existing `check_repo()` | does the artifact match the vault? |
| Committed | `git show <default-branch>:.claude/house-style.md` | is that artifact in git, on the branch CI reads? |
| Tag lag | `git rev-list --count house-style-v1..origin/main` | is the pin behind main? |

Content and Committed stay separate columns rather than one verdict. They
fail independently and have different remedies — recompose vs. commit — and
collapsing them would report that something is wrong without indicating
which of two unrelated actions to take.

Tag lag is a property of this repo, not of the ten, so it is a header line
rather than a column.

**Committed is evaluated against the repo's default branch**, not its working
tree. The purpose of the column is to catch divergence between "green on my
laptop" and "green in CI", and only the default branch sees that. A repo
mid-onboarding will therefore report a problem, which is correct signal.
This tool never fetches the governed repos, only this one (see Fetch
behaviour, below), so the column reflects each clone's last-fetched state --
a repo not fetched recently can still report a false alarm.

## Units

Split on the pure/impure line. The impure units are thin wrappers over one or
two `git` calls returning a small tagged value; all branching, alignment,
pluralisation and summary logic lives in the pure formatter.

| Unit | Purity | Contract |
|---|---|---|
| `default_branch(path)` | impure | resolve `origin/HEAD` → `main`/`master`; `NA` if undeterminable |
| `artifact_git_state(path, branch)` | impure | one of `committed`, `branch-only`, `untracked-only`, `absent`, `no-clone`, `not-a-repo`, `unknown-branch` |
| `tag_lag(repo_root, fetch)` | impure | list(behind, tag_sha, main_sha, fetched) |
| `format_status(rows, lag, sources)` | pure | rows + lag → character vector to print |
| `status_exit_code(rows)` | pure | rows → `0` or `2` |

`artifact_git_state()` returns a tagged state rather than a boolean because
the ways of not being on the default branch are different situations with
different remedies, and a boolean would flatten them. This mirrors
`check_repo()`'s existing `missing` vs `stale`.

The states are evaluated in this order, first match wins:

| Order | State | Condition | Remedy |
|---|---|---|---|
| 1 | `no-clone` | registry path does not exist | clone it |
| 2 | `not-a-repo` | path exists, no `.git` | investigate |
| 3 | `unknown-branch` | default branch could not be determined | investigate |
| 4 | `committed` | `git show <branch>:<artifact>` succeeds | none |
| 5 | `branch-only` | absent from `<branch>`, but tracked on the current branch | merge the branch |
| 6 | `untracked-only` | absent from `<branch>`, present in the worktree, untracked | commit it |
| 7 | `absent` | absent from `<branch>` and from the worktree | compose, then commit |

Order matters for the case this column exists to catch. hvtiRbootstrap has an
artifact on disk that is absent from `main` and untracked, so it must report
`untracked-only` (rank 6) rather than `absent` (rank 7) — both are "not on
main", but only the first tells you the file is already composed and merely
needs committing. `branch-only` is ranked above both because a tracked file
that is simply on an unmerged branch is a third, distinct situation.

`status_exit_code()` is a separate pure unit so the rule for what counts as a
fault is unit-tested directly rather than inferred from a process exit.

## Output

```
house-style-v1  345fae8  ->  7 behind origin/main (75a68c3)
sources: /Users/ehrlinj/Documents/ObsidianVault/memory

REPO                    CONTENT          COMMITTED
hvtiPlotR               OK               yes
hvtiRutilities          OK               yes
hvtiRbootstrap          OK               NO (untracked)
hvti_graphics           OK               yes

1 repo(s) need attention: hvtiRbootstrap
```

When every repo is clean the summary line is omitted and the table stands
alone.

## CLI and exit codes

`tools/status.R [--no-fetch]`. No `--repo` (that is
`compose-house-style.R --check --repo <name>`), no `--json`.

| Code | Meaning |
|---|---|
| 0 | every repo clean on both axes |
| 1 | environment failure — `git` not on PATH, registry unreadable |
| 2 | one or more repos need attention |

**Tag lag never affects the exit code.** A lagging tag is the normal state:
true after every merge, and true until the tag is deliberately moved. If lag
set exit 2 the command would be red almost always, and a status tool that is
always red stops being read. Only per-repo faults set 2. Lag is a condition
to manage; an uncommitted artifact is a fault to fix.

## Fetch behaviour

`tag_lag()` compares against `origin/main`, which is only as fresh as the
last fetch. It therefore fetches by default (`git fetch --quiet origin main`),
matching `bin/move-tag.sh:53`, so both commands agree about what "behind"
means.

`--no-fetch` skips it. A fetch that fails (offline) does not warn: it sets
`fetched = FALSE` and falls back to the local ref, and the header gains the
"[as of last fetch]" suffix — it does not crash and does not change the exit
code. Fetch-by-default is only safe if failing to fetch degrades to a
labelled answer.

## Failure modes

| Situation | Behaviour |
|---|---|
| Clone missing at the registry path | row `no-clone`, counts toward exit 2 |
| Path exists, not a git repo | row `not-a-repo`, counts toward exit 2 |
| Default branch undeterminable | row `unknown-branch`, counts toward exit 2 |
| `fetch` fails | sets `fetched = FALSE`, uses local ref, labels header "[as of last fetch]", exit code unaffected |
| Vault absent | composer falls back to the CI mirror; status reprints that warning prominently, because checking against the mirror answers a different question |
| `git` not on PATH | exit 1 immediately |

No situation crashes with a stack trace; every one has a defined row state or
a deliberate exit.

## Testing

New `tests/testthat/test-status.R`. No network; runs unskipped in CI.

- **`format_status()`** — the bulk. Fabricated rows covering: all clean;
  content drift only; committed failure only; both on one repo; a `no-clone`
  row; empty registry. Asserts exact output lines, pinning column alignment
  and the summary line.
- **`status_exit_code()`** — clean rows → 0; each fault state → 2; tag lag
  present with clean rows → 0 (the rule that lag is not a fault).
- **`artifact_git_state()`** — real git in `withr::local_tempdir()`, as
  `test-registry.R` already does. One case per state: commit an artifact on
  the default branch → `committed`; commit it only on a second branch →
  `branch-only`; write without adding → `untracked-only`; neither on the
  branch nor on disk → `absent`; empty dir → `no-clone`; non-repo dir →
  `not-a-repo`. Plus a precedence case: absent from the default branch **and**
  present-untracked on disk must return `untracked-only`, not `absent`.
- **`tag_lag()`** — temp repo, two commits, tag the first, assert
  `behind == 1`.
- **`default_branch()`** — temp repo with `origin/HEAD` set to `master`,
  assert it resolves rather than assuming `main`.

## Success criteria

1. `tools/status.R` prints one row per registered repo plus a tag-lag header.
2. It reports hvtiRbootstrap's untracked artifact as a problem, which
   `compose-house-style.R --check --all` currently reports as `OK`.
3. It exits 0 on the current tree despite the tag being behind.
4. The full suite stays green, with `test-status.R` running unskipped in CI.

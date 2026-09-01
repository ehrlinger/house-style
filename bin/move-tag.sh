#!/usr/bin/env bash
#
# move-tag.sh — advance house-style-v1, but only from a verified state.
#
# Moving this tag is the propagation event: every governed repository pins it,
# and the
# next push in each recomposes against whatever sources/ holds at the new
# commit. It is therefore the last point where stale sources are cheap to
# catch, and the only one that is guaranteed to run on a machine with the
# vault mounted. CI cannot do this check -- a runner has no vault (see #8).
#
# Usage:
#   bin/move-tag.sh -m "what changed" [commit]      # defaults to HEAD
#   bin/move-tag.sh -m "..." --yes                  # skip the confirmation
#
# Exit codes: 0 = tag moved, 1 = refused.

set -euo pipefail

TAG="house-style-v1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

message=""
target="HEAD"
assume_yes=0

while [ $# -gt 0 ]; do
  case "$1" in
    -m) message="${2-}"; [ -n "$message" ] || { echo "ERROR: -m needs a message." >&2; exit 1; }; shift 2 ;;
    --yes) assume_yes=1; shift ;;
    -*) echo "ERROR: unknown flag '$1'." >&2; exit 1 ;;
    *)  target="$1"; shift ;;
  esac
done

if [ -z "$message" ]; then
  echo "Usage: bin/move-tag.sh -m \"what changed\" [commit] [--yes]" >&2
  echo "The message is not optional: it is the only record of why the governed repositories went red." >&2
  exit 1
fi

fail() { echo "" >&2; echo "REFUSED: $*" >&2; exit 1; }

# --- Preconditions ---------------------------------------------------------

git diff --quiet && git diff --cached --quiet \
  || fail "the working tree is dirty. The tag must name a committed state, not
         whatever happens to be on disk right now."

sha="$(git rev-parse --verify "${target}^{commit}")" \
  || fail "'$target' is not a commit."

git fetch --quiet origin main
git merge-base --is-ancestor "$sha" origin/main \
  || fail "$(git rev-parse --short "$sha") is not an ancestor of origin/main.
         Tagging an unpushed commit points every governed repository at a
         commit it cannot fetch. Merge to main first."

# The gate must see the tree being tagged, not the tree you happen to have
# checked out. Verifying HEAD and then tagging something else would be the
# same false-assurance shape this script exists to prevent.
head_sha="$(git rev-parse --verify HEAD)"
[ "$sha" = "$head_sha" ] \
  || fail "$(git rev-parse --short "$sha") is not HEAD. Check it out first, so the
         suite runs against the tree that is about to be tagged."

# --- The gate --------------------------------------------------------------

echo "Verifying $(git rev-parse --short "$sha") before moving $TAG ..."
echo ""

Rscript tools/gate.R \
  || fail "the gate did not pass. $TAG stays where it is.
         Nothing propagates until sources/ is verified against the vault."

# --- Confirm ---------------------------------------------------------------

echo ""
echo "About to move $TAG:"
echo "    from  $(git rev-parse --short "$TAG" 2>/dev/null || echo '(does not exist)')"
echo "    to    $(git rev-parse --short "$sha")  $(git log -1 --format=%s "$sha")"
echo "    note  $message"
echo ""
echo "This makes every governed repository report drift until it recomposes."

if [ "$assume_yes" -ne 1 ]; then
  printf 'Proceed? [y/N] '
  read -r reply
  case "$reply" in
    y|Y|yes|Yes) ;;
    *) echo "Aborted; $TAG unchanged."; exit 1 ;;
  esac
fi

# --- The immutable record, BEFORE the moving pin ---------------------------
#
# $TAG is force-moved, which discards the previous tag object and with it the
# note explaining why the standard last changed. main keeps the content history,
# but nothing keeps the answer to "when did this propagate, and why", and that
# is the moment this script exists to mark.
#
# So cut a dated tag that is never moved. It costs one ref, it makes any past
# check reproducible by pinning ref: standard-YYYY-MM-DD, and it leaves the
# drift-detection argument for a moving $TAG untouched, because $TAG still
# moves.
#
# Created first on purpose. If the archive fails we have not propagated yet; if
# it were created after, a failure would lose the record of a move that had
# already happened.
existing_archive="$(git tag --points-at "$sha" | grep '^standard-' | head -1 || true)"
if [ -n "$existing_archive" ]; then
  echo ""
  echo "Archive tag $existing_archive already points at $(git rev-parse --short "$sha"); reusing it."
  archive="$existing_archive"
else
  archive="$(git tag -l | "$REPO_ROOT/bin/archive-tag-name.sh" "$(git log -1 --format=%cs "$sha")")"
  git tag -a "$archive" "$sha" -m "$message"
  git push origin "$archive"
  echo ""
  echo "Archived this state as $archive (immutable; never moved)."
fi

# --- Move it ---------------------------------------------------------------

git tag -f -a "$TAG" "$sha" -m "$message"
git push -f origin "$TAG"

echo ""
echo "$TAG now at $(git rev-parse --short "$sha"), archived as $archive."
echo "Governed repositories will report drift on their next run until they recompose."

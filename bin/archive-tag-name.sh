#!/usr/bin/env bash
#
# archive-tag-name.sh -- print the next free immutable archive tag name.
#
# Split out of move-tag.sh so it can be tested without a git remote, a vault or
# a push. It is a pure function: given a date and the set of existing tag names
# on stdin, it prints a name that is not among them.
#
# Usage:
#   git tag -l | bin/archive-tag-name.sh 2026-08-17
#
# Prints standard-2026-08-17, or standard-2026-08-17-2 and so on when the plain
# name is taken. The suffix exists because the standard can move twice against
# commits sharing a date, and an archive tag that gets overwritten is not an
# archive.

set -euo pipefail

date="${1:-}"
if [ -z "$date" ]; then
  echo "usage: git tag -l | archive-tag-name.sh YYYY-MM-DD" >&2
  exit 1
fi

case "$date" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) echo "ERROR: '$date' is not YYYY-MM-DD." >&2; exit 1 ;;
esac

existing="$(cat)"
base="standard-$date"

if ! printf '%s\n' "$existing" | grep -qx -- "$base"; then
  printf '%s\n' "$base"
  exit 0
fi

n=2
while printf '%s\n' "$existing" | grep -qx -- "$base-$n"; do
  n=$((n + 1))
done
printf '%s\n' "$base-$n"

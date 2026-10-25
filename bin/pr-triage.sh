#!/usr/bin/env bash
#
# pr-triage.sh -- every open pull request across the registered repositories,
# sorted by what to do with it.
#
# Built for the day the queue is buried: one GraphQL call covers every repo in
# repos.yml, and the ones ready to merge come first. The classification lives
# in pr-triage.jq, which says what each state means.
#
# Usage:
#   bin/pr-triage.sh            a table
#   bin/pr-triage.sh --json     the classified rows, for scripting
#
# Needs gh (authenticated) and jq. Repositories are assumed to be under the
# owner below; repos.yml names them, it does not say who owns them.

set -euo pipefail

owner="ehrlinger"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
registry="$here/../repos.yml"

json=false
case "${1:-}" in
  "") ;;
  --json) json=true ;;
  *) echo "usage: pr-triage.sh [--json]" >&2; exit 1 ;;
esac

for tool in gh jq; do
  command -v "$tool" >/dev/null || { echo "ERROR: $tool not found." >&2; exit 1; }
done

names="$(sed -n 's/^  - name: *//p' "$registry")"
if [ -z "$names" ]; then
  echo "ERROR: no '  - name:' entries in $registry; the registry format changed." >&2
  exit 1
fi

# One alias per repository, so the whole registry costs a single request.
# first: 50 covers any queue seen so far; a repo past it is flagged below
# rather than silently truncated.
fields='name pullRequests(states: OPEN, first: 50) { totalCount nodes {
  number title isDraft mergeable reviewDecision updatedAt
  commits(last: 1) { nodes { commit { statusCheckRollup { contexts(first: 100) {
    nodes {
      __typename
      ... on CheckRun { name status conclusion }
      ... on StatusContext { context state }
    } } } } } } } }'
query="query {"
i=0
while IFS= read -r name; do
  query="$query r$i: repository(owner: \"$owner\", name: \"$name\") { $fields }"
  i=$((i + 1))
done <<< "$names"
query="$query }"

response="$(gh api graphql -f query="$query")"

echo "$response" | jq -r '.data | to_entries[] | .value
  | select(.pullRequests.totalCount > 50)
  | "WARNING: \(.name) has \(.pullRequests.totalCount) open PRs; only 50 shown."' >&2

rows="$(echo "$response" | jq -f "$here/pr-triage.jq")"

if $json; then
  echo "$rows"
  exit 0
fi

if [ "$(echo "$rows" | jq 'length')" -eq 0 ]; then
  echo "No open pull requests in the $i registered repositories."
  exit 0
fi

{
  printf 'STATE\tPR\tREVIEW\tAGE\tDETAIL\tTITLE\n'
  echo "$rows" | jq -r '.[] | [
      .state,
      "\(.repo)#\(.number)",
      (.review | ascii_downcase),
      (((now - (.updated | fromdateiso8601)) / 3600 | floor) as $h
        | if $h < 48 then "\($h)h" else "\($h / 24 | floor)d" end),
      (if .detail == "" then "-" else .detail end),
      (.title | if length > 50 then .[:47] + "..." else . end)
    ] | @tsv'
} | column -t -s "$(printf '\t')"

echo
echo "$rows" | jq -r 'group_by(.state) | map("\(.[0].state) \(length)")
  | join(", ")'

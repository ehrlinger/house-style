# pr-triage.jq -- classify every open pull request in a GraphQL response.
#
# Split out of pr-triage.sh so it can be tested against a fixture, with no
# network and no token. It is a pure function of its input: the response to
# the aliased query pr-triage.sh builds, one alias per registered repository.
#
# Emits one object per pull request, sorted so the ones to act on come first:
#
#   READY      checks green and no conflict: merge it
#   RED        a check failed: read it, or look for a shared cause on main
#   CONFLICT   needs main merged in; do that only when it is next to merge
#   WAITING    checks queued or running: leave it alone
#   NO-CHECKS  nothing reported; a required check that never starts waits
#              forever, so this is worth a look, not patience
#   DRAFT      not ready by the author's own say
#
# Review state is reported, not gated on. The maintainer merges as the admin
# bypass actor, so a missing approval does not stop the merges this tool is for.

def check_state:
  if .__typename == "CheckRun" then
    if .status == "COMPLETED" then
      if (.conclusion | IN("SUCCESS", "NEUTRAL", "SKIPPED")) then "pass"
      else "fail" end
    elif .status == "IN_PROGRESS" then "running"
    else "queued" end
  else
    if .state == "SUCCESS" then "pass"
    elif (.state | IN("FAILURE", "ERROR")) then "fail"
    else "queued" end
  end;

def check_name: if .__typename == "CheckRun" then .name else .context end;

def rank:
  {"READY": 0, "RED": 1, "CONFLICT": 2, "WAITING": 3, "NO-CHECKS": 4,
   "DRAFT": 5}[.];

[ .data | to_entries[] | .value as $repo
  | $repo.pullRequests.nodes[]
  | (.commits.nodes[0].commit.statusCheckRollup.contexts.nodes // []
     | map({name: check_name, s: check_state})) as $checks
  | ($checks | map(select(.s == "fail") | .name)) as $failed
  | ($checks | map(select(.s == "queued")) | length) as $queued
  | ($checks | map(select(.s == "running")) | length) as $running
  | {
      repo: $repo.name,
      number: .number,
      title: .title,
      updated: .updatedAt,
      review: (.reviewDecision // "NONE"),
      state: (
        if .isDraft then "DRAFT"
        elif .mergeable == "CONFLICTING" then "CONFLICT"
        elif ($failed | length) > 0 then "RED"
        elif $queued + $running > 0 then "WAITING"
        elif ($checks | length) == 0 then "NO-CHECKS"
        else "READY" end
      ),
      detail: (
        if ($failed | length) > 0 then "failed: " + ($failed | join(", "))
        elif $queued + $running > 0
        then "\($queued) queued, \($running) running"
        else "" end
      )
    }
]
| sort_by((.state | rank), .repo, .number)

#!/bin/bash
# The runner's job-started hook (ACTIONS_RUNNER_HOOK_JOB_STARTED): it runs on
# the host before a job's first step, and a non-zero exit fails the job. A
# public repository's workflow files are pull-request controlled, so the fork
# guard must live here, outside them. The bootstrap writes ./policy beside
# this script (root-owned):
#   ALLOWED_SCOPE  owner/repository, or an organization (any of its repositories)
#   ALLOWED_REFS   space-separated refs; empty for any ref
# A job runs only when it comes from that scope, by push, workflow_dispatch,
# schedule or merge_group, or from a pull request whose head is in the same
# repository, and (with ALLOWED_REFS) on one of those refs. Everything else is
# refused: a fork's pull request, pull_request_target, workflow_run,
# issue_comment, ... GITHUB_* values and the event payload come from GitHub.
set -uo pipefail

refuse() {
  echo "::error::Refused by this self-hosted runner pool: $*"
  exit 1
}

policy="$(dirname "$0")/policy"
[ -r "$policy" ] || refuse "no policy at $policy"
ALLOWED_SCOPE="" ALLOWED_REFS=""
# shellcheck source=/dev/null
. "$policy"
[ -n "$ALLOWED_SCOPE" ] || refuse "empty ALLOWED_SCOPE"

repository="${GITHUB_REPOSITORY:-}"
case "$ALLOWED_SCOPE" in
  */*) [ "$repository" = "$ALLOWED_SCOPE" ] || refuse "repository '$repository' is not $ALLOWED_SCOPE" ;;
  *) [ "${repository%%/*}" = "$ALLOWED_SCOPE" ] && [ "${repository#*/}" != "$repository" ] ||
       refuse "repository '$repository' is not in $ALLOWED_SCOPE" ;;
esac

event="${GITHUB_EVENT_NAME:-}"
case "$event" in
  push | workflow_dispatch | schedule | merge_group) ;;
  pull_request)
    [ -r "${GITHUB_EVENT_PATH:-}" ] || refuse "no event payload"
    head="$(jq -r '.pull_request.head.repo.full_name // empty' "$GITHUB_EVENT_PATH")" ||
      refuse "unreadable event payload"
    [ "$head" = "$repository" ] || refuse "a pull request from '$head' (not $repository)"
    ;;
  *) refuse "event '$event'" ;;
esac

if [ -n "$ALLOWED_REFS" ]; then
  for ref in $ALLOWED_REFS; do
    [ "${GITHUB_REF:-}" = "$ref" ] && exit 0
  done
  refuse "ref '${GITHUB_REF:-}' (this pool serves only $ALLOWED_REFS)"
fi
exit 0

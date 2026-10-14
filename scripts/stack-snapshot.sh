#!/usr/bin/env bash
# stack-snapshot.sh - prove that a stack refactor changes no resolved config.
#
# A snapshot is every stack as Atmos resolves it offline, keys sorted:
#   atmos describe stacks --process-functions=false --include-empty-stacks --format json | jq -S .
# with TFSTATE_SOURCE/TFSTATE_ACCESS (and ATMOS_BASE_PATH/ATMOS_CLI_CONFIG_PATH)
# unset, so the shell cannot change the result, and ATMOS_AUTH_REALM fixed:
# Atmos otherwise derives auth.realm from the checkout's path. --raw adds
# --process-templates=false, for a change that must not even move a template.
#
# compare snapshots <base-ref> (checked out in a temporary git worktree, always
# removed) and the working tree, prints IDENTICAL or a bounded diff
# (SNAPSHOT_DIFF_LINES, default 200) and exits 1 on a difference. Wave C1
# moves instance wiring into stacks/catalog/ and must be identical to its
# merge-base: scripts/stack-snapshot.sh compare "$(git merge-base origin/master HEAD)"
#
# Usage:
#   scripts/stack-snapshot.sh [--raw] <out.json>
#   scripts/stack-snapshot.sh compare [--raw] <base-ref>
# Needs atmos, jq and (compare) git, cmp and diff.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    echo "usage: $0 [--raw] <out.json> | $0 compare [--raw] <base-ref>" >&2
    exit 2
}

# snapshot <tree> <out> [extra describe flags...]
snapshot() {
    local tree="$1" out="$2"
    shift 2
    (cd "$tree" && env -u TFSTATE_SOURCE -u TFSTATE_ACCESS -u ATMOS_BASE_PATH -u ATMOS_CLI_CONFIG_PATH \
        ATMOS_AUTH_REALM=stack-snapshot nice -n 19 atmos describe stacks --process-functions=false --include-empty-stacks --format json "$@") \
        | jq -S . > "$out"
}

mode="snapshot"
if [[ "${1:-}" == "compare" ]]; then
    mode="compare"
    shift
fi
flags=()
label=""
if [[ "${1:-}" == "--raw" ]]; then
    flags+=(--process-templates=false)
    label=", --raw"
    shift
fi
[[ $# -eq 1 && -n "$1" ]] || usage

if [[ "$mode" == "snapshot" ]]; then
    out="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    snapshot "$REPO_ROOT" "$out" ${flags[@]+"${flags[@]}"}
    echo "snapshot: $out ($(wc -c < "$out" | tr -d ' ') bytes)"
    exit 0
fi

base_ref="$1"
work="$(mktemp -d)"
# Removed however the run ends; prune drops the registration if remove failed.
trap 'git -C "$REPO_ROOT" worktree remove --force "$work/base" > /dev/null 2>&1 || true
      rm -rf "$work"; git -C "$REPO_ROOT" worktree prune' EXIT

git -C "$REPO_ROOT" worktree add --quiet --detach "$work/base" "$base_ref"
snapshot "$work/base" "$work/base.json" ${flags[@]+"${flags[@]}"}
snapshot "$REPO_ROOT" "$work/head.json" ${flags[@]+"${flags[@]}"}

if cmp -s "$work/base.json" "$work/head.json"; then
    echo "IDENTICAL: $(git -C "$REPO_ROOT" rev-parse --short "$base_ref") vs working tree" \
        "(cksum $(cksum < "$work/head.json" | cut -d' ' -f1)$label)"
    exit 0
fi
echo "DIFFERENT: $base_ref vs working tree$label"
jq -rn --slurpfile a "$work/base.json" --slurpfile b "$work/head.json" \
    '"stacks that differ: " + ([($a[0] + $b[0]) | keys[] | select($a[0][.] != $b[0][.])] | join(" "))'
diff -u --label "$base_ref" --label "working tree" "$work/base.json" "$work/head.json" \
    | head -n "${SNAPSHOT_DIFF_LINES:-200}" || true
exit 1

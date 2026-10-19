#!/usr/bin/env bash
# stack-snapshot.sh - prove that a stack refactor changes no resolved config.
#
# A snapshot is every stack as Atmos resolves it offline, keys sorted:
#   atmos describe stacks --process-functions=false --include-empty-stacks --format json | jq -S .
# with TFSTATE_SOURCE/TFSTATE_ACCESS and every ATMOS_* variable
# unset, so the shell cannot change the result, and ATMOS_AUTH_REALM fixed:
# Atmos otherwise derives auth.realm from the checkout's path. --raw adds
# --process-templates=false, for a change that must not even move a template.
#
# compare snapshots <base-ref> (checked out in a temporary git worktree, always
# removed) and the working tree, prints IDENTICAL or a bounded diff
# (SNAPSHOT_DIFF_LINES, default 200) and exits 1 on a difference. A refactor
# of stack wiring must be identical to its merge-base:
# scripts/stack-snapshot.sh compare "$(git merge-base origin/master HEAD)"
#
# The result line names the repository (the git top level of the current
# directory, not of this script), its HEAD short SHA, "+dirty" when stacks/,
# atmos.yaml or schemas/ have uncommitted changes, and the stack count (16).
#
# A local proof tool, run by hand for each such PR; it is not wired into CI.
#
# Usage:
#   scripts/stack-snapshot.sh [--raw] <out.json>
#   scripts/stack-snapshot.sh compare [--raw] <base-ref>
# Needs atmos, jq (CI's toolchain pin: jqlang/jq "1.8.2") and git; compare also cmp and diff.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

usage() {
    echo "usage: $0 [--raw] <out.json> | $0 compare [--raw] <base-ref>" >&2
    exit 2
}

# snapshot <tree> <out> [extra describe flags...]
snapshot() {
    local tree="$1" out="$2"
    shift 2
    # Every ATMOS_* variable is cleared (ATMOS_STACKS_BASE_PATH alone would
    # point both snapshots at one tree), then the realm is pinned.
    (
        cd "$tree" || exit 1
        for var in $(compgen -v ATMOS_); do unset "$var"; done
        unset TFSTATE_SOURCE TFSTATE_ACCESS
        export ATMOS_AUTH_REALM=stack-snapshot
        nice -n 19 atmos describe stacks --process-functions=false --include-empty-stacks --format json "$@"
    ) | jq -S . > "$out"
    # A stub or broken atmos that prints nothing or {} must not pass as IDENTICAL.
    if ! jq -e 'type == "object" and length > 0' "$out" > /dev/null 2>&1; then
        echo "stack-snapshot: empty or invalid snapshot of $tree (atmos printed no stacks)" >&2
        exit 1
    fi
}

# "<repo> @ <short sha>[+dirty]" for the result line.
head_label() {
    local dirty=""
    [[ -z "$(git -C "$REPO_ROOT" status --porcelain -- stacks atmos.yaml schemas)" ]] || dirty="+dirty"
    echo "$REPO_ROOT @ $(git -C "$REPO_ROOT" rev-parse --short HEAD)$dirty"
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
    echo "snapshot: $out of $(head_label), $(jq length "$out") stacks ($(wc -c < "$out" | tr -d ' ') bytes$label)"
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
    echo "IDENTICAL: $base_ref ($(git -C "$REPO_ROOT" rev-parse --short "$base_ref")) vs $(head_label)," \
        "$(jq length "$work/head.json") stacks (cksum $(cksum < "$work/head.json" | cut -d' ' -f1)$label)"
    exit 0
fi
echo "DIFFERENT: $base_ref ($(git -C "$REPO_ROOT" rev-parse --short "$base_ref")) vs $(head_label)," \
    "$(jq length "$work/base.json") vs $(jq length "$work/head.json") stacks$label"
jq -rn --slurpfile a "$work/base.json" --slurpfile b "$work/head.json" \
    '"stacks that differ: " + ([($a[0] + $b[0]) | keys[] | select($a[0][.] != $b[0][.])] | join(" "))'
diff -u --label "$base_ref" --label "working tree" "$work/base.json" "$work/head.json" \
    | head -n "${SNAPSHOT_DIFF_LINES:-200}" || true
exit 1

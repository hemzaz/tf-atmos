#!/usr/bin/env bash
#
# check-stack-scaffold.sh - prove the stack scaffold (scaffolds/stack) still
# regenerates every reference stack it was copied from, so it cannot rot unseen.
#
# Each scaffolds/stack-golden/<stack>.env holds the answers (key=value per line,
# # comments) that regenerate <stack>'s file. In a scratch copy of the
# repository, for each golden:
#   - snapshot the committed stack as Atmos resolves it, normally and with
#     --process-templates=false (raw: every {{ }} the template must emit
#     verbatim);
#   - `atmos scaffold generate stack . --force --defaults --set ...` with the
#     stack file still there must fail (the guard hook) and leave it unchanged;
#   - delete the stack file, generate it again with the hooks (guard, then
#     verify: atmos validate stacks), yamllint it, and snapshot it again: both
#     snapshots must be identical to the committed stack's.
# The regenerated file sits at the committed file's path, so no normalising
# is needed (atmos_manifest and atmos_stack_file are equal by construction).
#
# A residue edit to a reference stack must update its template or .env in the
# same PR, or this fails.
#
# Usage: scripts/check-stack-scaffold.sh
# Needs atmos, python3 and yamllint. Exit 0 when every golden regenerates
# identically, 1 otherwise.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# The working tree minus ignored files (as check-stack-samples.sh); outside a
# usable git work tree (the CI container's unsafe owner), every file but .git
# and .terraform.
cd "$REPO_ROOT"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -z -co --exclude-standard | tar --null -cf - -T - | tar -xf - -C "$scratch"
else
    tar --exclude=.git --exclude=.terraform -cf - . | tar -xf - -C "$scratch"
fi
cd "$scratch"
out="$(mktemp -d "$scratch/.check-stack-scaffold.XXXXXX")"
atmos scaffold validate scaffolds/stack/scaffold.yaml

# snapshot <stack> <out.json> [describe flags...]: the stack, keys sorted.
snapshot() {
    local stack="$1" json="$2"
    shift 2
    atmos describe stacks -s "$stack" --process-functions=false --format json "$@" \
        | python3 -c 'import json, sys; d = json.load(sys.stdin); assert d, "no stacks"; json.dump(d, sys.stdout, sort_keys=True, indent=1)' \
        > "$json"
}

# Every file in the scratch copy but the scaffold's answers record and ours.
files_list() {
    find . -type f ! -path './.atmos/*' ! -path "./${out##*/}/*" | LC_ALL=C sort
}

failed=""
goldens=0
for env in scaffolds/stack-golden/*.env; do
    stack="$(basename "$env" .env)"
    goldens=$((goldens + 1))
    sets=()
    tenant="" stage="" region="" code=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in ''|'#'*) continue ;; esac
        sets+=(--set "$line")
        case "$line" in
            tenant=*) tenant="${line#*=}" ;;
            stage=*) stage="${line#*=}" ;;
            region=*) region="${line#*=}" ;;
            region_code=*) code="${line#*=}" ;;
        esac
    done < "$env"
    if [[ "$tenant-$code-$stage" != "$stack" ]]; then
        echo "ERROR $env: its answers name $tenant-$code-$stage, not $stack" >&2
        failed="$failed $stack"
        continue
    fi
    file="stacks/orgs/$tenant/$stage/$region.yaml"
    if [[ ! -f "$file" ]]; then
        echo "ERROR $env: $file does not exist" >&2
        failed="$failed $stack"
        continue
    fi
    echo "== $stack ($file)"
    snapshot "$stack" "$out/$stack.before.json"
    snapshot "$stack" "$out/$stack.before.raw.json" --process-templates=false
    cp "$file" "$out/$stack.committed.yaml"

    # The guard: an existing stack file is never overwritten.
    if atmos scaffold generate stack . --force --defaults "${sets[@]}" > "$out/$stack.guard.log" 2>&1; then
        echo "ERROR $stack: the scaffold overwrote an existing $file (guard hook did not refuse)" >&2
        cat "$out/$stack.guard.log" >&2
        failed="$failed $stack"
        cp "$out/$stack.committed.yaml" "$file"
        continue
    fi
    if ! grep -q "exists; remove it first" "$out/$stack.guard.log" \
        || ! cmp -s "$file" "$out/$stack.committed.yaml"; then
        echo "ERROR $stack: the run over an existing $file failed, but not by the guard, or changed it:" >&2
        cat "$out/$stack.guard.log" >&2
        failed="$failed $stack"
        cp "$out/$stack.committed.yaml" "$file"
        continue
    fi
    echo "guard: refused to overwrite $file"

    rm "$file"
    files_list > "$out/$stack.files.before"
    if ! atmos scaffold generate stack . --force --defaults "${sets[@]}"; then
        echo "ERROR $stack: atmos scaffold generate stack failed" >&2
        failed="$failed $stack"
        cp "$out/$stack.committed.yaml" "$file"
        continue
    fi
    # The run writes the stack file and nothing else (bar its .atmos record).
    files_list > "$out/$stack.files.after"
    if ! diff <(echo "./$file") <(LC_ALL=C comm -13 "$out/$stack.files.before" "$out/$stack.files.after") > /dev/null; then
        echo "ERROR $stack: the scaffold wrote more or less than $file:" >&2
        LC_ALL=C comm -3 "$out/$stack.files.before" "$out/$stack.files.after" >&2
        failed="$failed $stack"
    fi
    yamllint -d relaxed "$file"
    snapshot "$stack" "$out/$stack.after.json"
    snapshot "$stack" "$out/$stack.after.raw.json" --process-templates=false
    for kind in "" .raw; do
        if ! cmp -s "$out/$stack.before$kind.json" "$out/$stack.after$kind.json"; then
            echo "DIFFERENT $stack${kind:+ (raw)}: the scaffold no longer regenerates $file from $env" >&2
            diff -u --label "committed $file" --label "generated from $env" \
                "$out/$stack.before$kind.json" "$out/$stack.after$kind.json" | head -n 100 >&2 || true
            failed="$failed $stack"
        fi
    done
    # Leave the committed file for the next golden.
    cp "$out/$stack.committed.yaml" "$file"
done

if [[ "$goldens" -eq 0 ]]; then
    echo "ERROR no scaffolds/stack-golden/*.env" >&2
    exit 1
fi
if [[ -n "$failed" ]]; then
    echo "stack scaffold check failed for: $(echo "$failed" | tr ' ' '\n' | sed '/^$/d' | sort -u | paste -sd ' ' -)" >&2
    exit 1
fi
echo "IDENTICAL: the stack scaffold regenerates all $goldens golden stacks (normal and raw)"

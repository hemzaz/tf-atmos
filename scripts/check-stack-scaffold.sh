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
#     verify: atmos validate stacks), check the run wrote that file and nothing
#     else, yamllint it (relaxed, the lint gate's config) and snapshot it again:
#     both snapshots must be identical to the committed stack's.
# The regenerated file sits at the committed file's path, so no normalising
# is needed (atmos_manifest and atmos_stack_file are equal by construction).
# Then each REFUSALS case (a golden with some answers changed) must be refused
# by the guard with its message, writing nothing. Last, a us-west-2 stack of
# each nonprod flavor with account_singletons=no is generated beside its
# account's committed stack, and check-lane-names over every stack must pass.
#
# A residue edit to a reference stack must update its template or .env in the
# same PR, or this fails.
#
# Usage: scripts/check-stack-scaffold.sh
# Needs atmos, python3 and yamllint. Exit 0 when every golden regenerates
# identically and every refusal is refused, 1 otherwise.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# A critical_alerts answer that runs a command if any hook interpolates it
# into shell unchecked (literal: the $( ) is the point).
# shellcheck disable=SC2016
INJECTION='a@example.com,x$(touch${IFS}INJECTED)@example.com'
# shellcheck disable=SC2016
DR_INJECTION='ec1$(touch${IFS}INJECTED)'
# Guard refusals: <golden>|<expected guard message>|<answer overrides...>.
REFUSALS=(
    "fnx-ue2-prod|at least two critical_alerts|critical_alerts=oncall@example.com"
    "fnx-ue2-prod|primary must be in us-east-1|primary_region=us-west-2 standby_of=fnx-uw2-prod"
    "fnx-ue2-prod|must both be EU (GDPR) or both not|primary_region=eu-west-1 standby_of=fnx-ew1-prod"
    "fnx-ec1-prod|the EU regions are exactly the prod-eu account's|account=prod"
    "fnx-ue2-prod|must differ from its primary's|primary_region=us-east-2 standby_of=fnx-ue2-prod"
    "fnx-ec1-prod|is itself a standby|region=eu-west-1 region_code=ew1 primary_region=eu-central-1 standby_of=fnx-ec1-prod"
    "fnx-ue2-prod|does not belong to stage prod|account=dev"
    "fnx-ue1-dev|a nonprod stack is a dev or staging stack|stage=prod account=prod"
    "fnx-ue1-dev|vpc_cidr_services and vpc_cidr_main must differ|vpc_cidr_services=10.0.0.0/16"
    "fnx-ue1-staging|the EU regions are exactly the prod-eu account's|region=eu-west-1 region_code=ew1"
    "fnx-ue1-dev|account_singletons=yes, but the dev account already has a stack|region=us-west-2 region_code=uw2 az_ids=usw2-az1,usw2-az2,usw2-az3"
    "fnx-ue1-staging|account_singletons=no, but the staging account has no other stack|account_singletons=no"
    "fnx-ew1-prod|a prod primary is a prod stack|stage=staging account=staging region=us-east-1 region_code=ue1 dr_region=us-east-2 dr_region_code=ue2"
    "fnx-ew1-prod|data_plane=yes (fnx-ue1-prod's data plane) is not in the template yet|data_plane=yes"
    "fnx-ew1-prod|a non-EU prod primary (account prod) is not in the template yet|account=prod region=us-east-1 region_code=ue1 dr_region=us-east-2 dr_region_code=ue2"
    "fnx-ew1-prod|dr_region must differ from region|dr_region=eu-west-1 dr_region_code=ew1"
    "fnx-ew1-prod|dr_region us-east-2 and region eu-west-1 must both be EU (GDPR) or both not|dr_region=us-east-2 dr_region_code=ue2"
    "fnx-ew1-prod|dr_region_code ew1 is not|dr_region_code=ew1"
    "fnx-ew1-prod|the prod-eu account already has its prod primary (eu-west-1.yaml)|region=eu-central-1 region_code=ec1 az_ids=euc1-az1,euc1-az2,euc1-az3 dr_region=eu-west-1 dr_region_code=ew1"
    # Shell injection through an answer: refused by the field pattern, and the
    # command substitution never runs (no INJECTED file anywhere).
    "fnx-ue2-prod|One or more email addresses|critical_alerts=$INJECTION"
    "fnx-ew1-prod|\"dr_region_code\":|dr_region_code=$DR_INJECTION"
)

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
# The INJECTION refusal pins critical_alerts' field pattern; this pins the
# guard's second defence, the urlquery encoding of the answer it reads.
if ! grep -qF 'case "{{ urlquery .Answers.critical_alerts }}" in' scaffolds/stack/scaffold.yaml; then
    echo "ERROR scaffolds/stack/scaffold.yaml: the guard no longer reads critical_alerts through urlquery" >&2
    exit 1
fi

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

# load <env> [key=value...]: the golden's answers with the overrides applied,
# as the --set array `sets`, plus tenant, stage, region, code and file.
load() {
    local env="$1" line key override
    shift
    sets=()
    tenant="" stage="" region="" code=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in ''|'#'*) continue ;; esac
        key="${line%%=*}"
        for override in "$@"; do
            [[ "${override%%=*}" == "$key" ]] && line="$override"
        done
        sets+=(--set "$line")
        case "$key" in
            tenant) tenant="${line#*=}" ;;
            stage) stage="${line#*=}" ;;
            region) region="${line#*=}" ;;
            region_code) code="${line#*=}" ;;
        esac
    done < "$env"
    file="stacks/orgs/$tenant/$stage/$region.yaml"
}

generate() {
    atmos scaffold generate stack . --force --defaults "${sets[@]}"
}

# golden <env>: regenerate its stack; returns 1 on any difference.
golden() {
    local env="$1" stack kind rc=0
    stack="$(basename "$env" .env)"
    load "$env"
    if [[ "$tenant-$code-$stage" != "$stack" ]]; then
        echo "ERROR $env: its answers name $tenant-$code-$stage, not $stack" >&2
        return 1
    fi
    if [[ ! -f "$file" ]]; then
        echo "ERROR $env: $file does not exist" >&2
        return 1
    fi
    echo "== $stack ($file)"
    snapshot "$stack" "$out/$stack.before.json" || return 1
    snapshot "$stack" "$out/$stack.before.raw.json" --process-templates=false || return 1
    cp "$file" "$out/$stack.committed.yaml"

    # The guard: an existing stack file is never overwritten.
    if generate > "$out/$stack.guard.log" 2>&1; then
        echo "ERROR $stack: the scaffold overwrote an existing $file (guard hook did not refuse)" >&2
        cat "$out/$stack.guard.log" >&2
        return 1
    fi
    if ! grep -q "exists; remove it first" "$out/$stack.guard.log" \
        || ! cmp -s "$file" "$out/$stack.committed.yaml"; then
        echo "ERROR $stack: the run over an existing $file failed, but not by the guard, or changed it:" >&2
        cat "$out/$stack.guard.log" >&2
        return 1
    fi
    echo "guard: refused to overwrite $file"

    rm "$file"
    files_list > "$out/$stack.files.before"
    if ! generate; then
        echo "ERROR $stack: atmos scaffold generate stack failed" >&2
        return 1
    fi
    # The run writes the stack file and nothing else (bar its .atmos record).
    files_list > "$out/$stack.files.after"
    if ! diff <(echo "./$file") <(LC_ALL=C comm -13 "$out/$stack.files.before" "$out/$stack.files.after") > /dev/null; then
        echo "ERROR $stack: the scaffold wrote more or less than $file:" >&2
        LC_ALL=C comm -3 "$out/$stack.files.before" "$out/$stack.files.after" >&2
        rc=1
    fi
    yamllint -d relaxed "$file" || rc=1
    snapshot "$stack" "$out/$stack.after.json" || return 1
    snapshot "$stack" "$out/$stack.after.raw.json" --process-templates=false || return 1
    for kind in "" .raw; do
        if ! cmp -s "$out/$stack.before$kind.json" "$out/$stack.after$kind.json"; then
            echo "DIFFERENT $stack${kind:+ (raw)}: the scaffold no longer regenerates $file from $env" >&2
            diff -u --label "committed $file" --label "generated from $env" \
                "$out/$stack.before$kind.json" "$out/$stack.after$kind.json" | head -n 100 >&2 || true
            rc=1
        fi
    done
    return "$rc"
}

# refusal <golden> <message> <overrides>: the guard refuses, writing nothing.
refusal() {
    local stack="$1" message="$2" overrides log rc
    read -r -a overrides <<< "$3"
    load "scaffolds/stack-golden/$stack.env" "${overrides[@]}"
    log="$out/refusal.log"
    # The target may be a real stack; remove it so only the case's own
    # answers can be refused.
    [[ ! -f "$file" ]] || mv "$file" "$out/refusal.target"
    files_list > "$out/refusal.before"
    if generate > "$log" 2>&1; then
        echo "ERROR refusal ($stack with $3): generated, but the guard should refuse: $message" >&2
        rc=1
    elif ! grep -qF "$message" "$log"; then
        echo "ERROR refusal ($stack with $3): failed, but not with the guard's \"$message\":" >&2
        cat "$log" >&2
        rc=1
    else
        rc=0
    fi
    if [[ -n "$(find . -name INJECTED)" ]] || [[ -e "$REPO_ROOT/INJECTED" ]]; then
        echo "ERROR refusal ($stack with $3): an answer was executed by the shell (INJECTED exists)" >&2
        rc=1
    fi
    files_list > "$out/refusal.after"
    if ! cmp -s "$out/refusal.before" "$out/refusal.after"; then
        echo "ERROR refusal ($stack with $3): the refused run wrote files:" >&2
        LC_ALL=C comm -3 "$out/refusal.before" "$out/refusal.after" >&2
        rc=1
    fi
    [[ "$rc" -ne 0 ]] || echo "guard: refused $stack with $3 ($message)"
    # Undo whatever the case did.
    LC_ALL=C comm -13 "$out/refusal.before" "$out/refusal.after" | while IFS= read -r f; do rm -f "$f"; done
    [[ ! -f "$out/refusal.target" ]] || mv "$out/refusal.target" "$file"
    return "$rc"
}

failed=""
goldens=0
for env in scaffolds/stack-golden/*.env; do
    goldens=$((goldens + 1))
    stack="$(basename "$env" .env)"
    files_list > "$out/files.before"
    golden "$env" || failed="$failed $stack"
    # Leave the committed file, and nothing a run wrote, for the next golden.
    [[ ! -f "$out/$stack.committed.yaml" ]] || cp "$out/$stack.committed.yaml" "$file"
    files_list > "$out/files.after"
    LC_ALL=C comm -13 "$out/files.before" "$out/files.after" | while IFS= read -r f; do rm -f "$f"; done
done
if [[ "$goldens" -eq 0 ]]; then
    echo "ERROR no scaffolds/stack-golden/*.env" >&2
    exit 1
fi

echo "== guard refusals"
for case in "${REFUSALS[@]}"; do
    IFS='|' read -r stack message overrides <<< "$case"
    refusal "$stack" "$message" "$overrides" || failed="$failed refusal:$stack"
done

# A second-region stack of each nonprod flavor (account_singletons=no, the
# branch no golden renders), generated with the hooks beside the account's
# committed stack: check-lane-names over every stack must pass, so the
# singletons it leaves to that stack (GitHub OIDC provider, Auto Scaling SLR,
# multi-region trail, Config global recording) are really left.
echo "== second-region stacks (account_singletons=no)"
SECOND_REGION=(
    "fnx-ue1-dev|stacks/orgs/fnx/dev/us-west-2.yaml"
    "fnx-ue1-staging|stacks/orgs/fnx/staging/us-west-2.yaml"
)
files_list > "$out/second.before"
second_ok=1
for case in "${SECOND_REGION[@]}"; do
    IFS='|' read -r stack expected <<< "$case"
    load "scaffolds/stack-golden/$stack.env" account_singletons=no region=us-west-2 region_code=uw2 \
        az_ids=usw2-az1,usw2-az2,usw2-az3 vpc_cidr_main=10.2.0.0/16 vpc_cidr_services=10.3.0.0/16
    if [[ "$file" != "$expected" ]] || ! generate > "$out/second.log" 2>&1; then
        echo "ERROR second region ($stack, account_singletons=no): generating $expected failed:" >&2
        cat "$out/second.log" >&2
        second_ok=0
    fi
done
if [[ "$second_ok" -eq 1 ]]; then
    atmos describe stacks --process-functions=false --format json > "$out/second.json"
    if python3 workflows/scripts/common/check-lane-names.py < "$out/second.json" > "$out/second.lanes" 2>&1; then
        echo "lane names: OK with fnx-uw2-dev and fnx-uw2-staging beside their accounts' ue1 stacks"
    else
        echo "ERROR second region: a stack generated with account_singletons=no collides with its account's other stack:" >&2
        cat "$out/second.lanes" >&2
        second_ok=0
    fi
fi
[[ "$second_ok" -eq 1 ]] || failed="$failed second-region"
files_list > "$out/second.after"
LC_ALL=C comm -13 "$out/second.before" "$out/second.after" | while IFS= read -r f; do rm -f "$f"; done

if [[ -n "$failed" ]]; then
    echo "stack scaffold check failed for:$(echo "$failed" | tr ' ' '\n' | sed '/^$/d' | sort -u | paste -sd ' ' -)" >&2
    exit 1
fi
echo "IDENTICAL: the stack scaffold regenerates all $goldens golden stacks (normal and raw); the guard refuses all ${#REFUSALS[@]} bad answer sets; the ${#SECOND_REGION[@]} second-region stacks leave the account singletons"

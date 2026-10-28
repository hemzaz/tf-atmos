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
#     verify: atmos validate stacks, then wire: scripts/stack-wiring.py),
#     check the run wrote that file and nothing else, left the root backend
#     files as they were (the reference stack is already wired), yamllint it
#     (relaxed, the lint gate's config) and snapshot it again: both snapshots
#     must be identical to the committed stack's, and its import: list must
#     be the committed one in the same order (today's resolved config does
#     not depend on the order, no two imports setting the same key, so the
#     snapshots cannot pin it).
# The regenerated file sits at the committed file's path, so no normalising
# is needed (atmos_manifest and atmos_stack_file are equal by construction).
# Then each REFUSALS case (a golden with some answers changed) must be refused
# by the guard with its message, writing nothing; so must a second prod-eu
# primary with eu-west-1.yaml's account: line quoted, a second prod primary
# beside a hand-written one whose account: line is plain or quoted, and, with
# the hooks skipped, a prod primary whose data_plane does not match its
# account (the template's own fail). A hostile value in a field the profile
# hides must generate the golden unchanged, running nothing. A generate into a
# target other than the root must be refused (by the verify hook on 1.229, the
# guard on 1.233), changing nothing outside the target.
# Last, the fresh-stack end to end: brand-new stacks generated with the hooks
# (a us-west-2 stack of each nonprod flavor with account_singletons=no beside
# its account's committed stack, a us-west-2 core stack, and a prod primary +
# standby pair,
# fnx-ue1-prod with its DR in us-west-2 and the new standby fnx-uw2-prod, in
# place of the committed ue1/ue2 pair: no other prod primary is generatable,
# one per account), so the wire hook adds each but the core stack to the root
# backend. The root file may differ only by the added lines, a second wiring run must add
# nothing, and every stack check (as check-stack-samples.sh runs them, plus
# dr-pair --lint) must pass over the result.
#
# The hooks edit the copy they run in (git's top level, else the working
# directory): the scratch copy is checked not to sit inside a git work tree,
# and the real repository's root backend files must be unchanged at the end.
#
# A residue edit to a reference stack must update its template or .env in the
# same PR, or this fails.
#
# Usage: scripts/check-stack-scaffold.sh [--sweep]
# --sweep (atmos sweep --scaffold) runs only the fresh-stack end to end, then
# scripts/plan-sweep.sh on the fresh stacks its default would select (ci-stacks.py
# --plan-sweep: a CI-disabled stack with nothing to plan is skipped with a
# ::notice::); lint runs the rest.
# Needs atmos, python3 and yamllint (and, for --sweep, plan-sweep's tools).
# Exit 0 when every golden regenerates identically, every refusal is refused
# and the fresh stacks pass, 1 otherwise.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWEEP="false"
[[ "${1:-}" == "--sweep" ]] && SWEEP="true"
# The backends the wire hook edits; the real ones must never change.
ROOT_FILES=(stacks/orgs/fnx/root/us-east-1.yaml stacks/orgs/fnx/root/eu-west-1.yaml)

# A critical_alerts answer that runs a command if any hook interpolates it
# into shell unchecked (literal: the $( ) is the point).
# shellcheck disable=SC2016
INJECTION='a@example.com,x$(touch${IFS}INJECTED)@example.com'
# shellcheck disable=SC2016
DR_INJECTION='ec1$(touch${IFS}INJECTED)'
# shellcheck disable=SC2016
CIDR_INJECTION='10.21.0.0/16$(touch${IFS}INJECTED)'
# shellcheck disable=SC2016
TENANT_INJECTION='fnx$(touch${IFS}INJECTED)'
# shellcheck disable=SC2016
ACCOUNT_INJECTION='dev";touch${IFS}INJECTED;"'
# shellcheck disable=SC2016
CODE_INJECTION='ue1`touch${IFS}INJECTED`'
# shellcheck disable=SC2016
STAGE_INJECTION='dev$(touch${IFS}INJECTED)'
# shellcheck disable=SC2016
REGION_INJECTION='us-east-1;touch${IFS}INJECTED'
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
    "fnx-ew1-prod|data_plane=yes in the prod-eu account: the EU primary has no data plane|data_plane=yes vpc_cidr_services=10.31.0.0/16"
    "fnx-ue1-prod|data_plane=no in account prod: only the prod-eu account's EU primary has no data plane|data_plane=no"
    "fnx-ue1-prod|a data-plane prod primary must be in us-east-1|region=us-west-2 region_code=uw2 az_ids=usw2-az1,usw2-az2,usw2-az3"
    "fnx-ue1-prod|vpc_cidr_services and vpc_cidr_main must differ|vpc_cidr_services=10.20.0.0/16"
    "fnx-ew1-prod|dr_region must differ from region|dr_region=eu-west-1 dr_region_code=ew1"
    "fnx-ew1-prod|dr_region us-east-2 and region eu-west-1 must both be EU (GDPR) or both not|dr_region=us-east-2 dr_region_code=ue2"
    "fnx-ew1-prod|dr_region_code ew1 is not|dr_region_code=ew1"
    "fnx-ew1-prod|the prod-eu account already has its prod primary (eu-west-1.yaml)|region=eu-central-1 region_code=ec1 az_ids=euc1-az1,euc1-az2,euc1-az3 dr_region=eu-west-1 dr_region_code=ew1"
    # Core stacks: profile core takes exactly the core accounts' stages, each
    # in its own account, outside the EU.
    "fnx-ue1-security|a core stack is a core account's stack|stage=dev account=dev"
    "fnx-ue1-dev|stage security is a core account's: its stack takes profile core|stage=security account=security"
    "fnx-ue1-security|account audit does not belong to stage security|account=audit"
    "fnx-ue1-security|the EU regions are exactly the prod-eu account's|region=eu-west-1 region_code=ew1"
    "fnx-ue1-security|region_code ue2 is not|region_code=ue2"
    # Shell injection through an answer: refused by the field pattern, and the
    # command substitution never runs (no INJECTED file anywhere).
    "fnx-ue2-prod|One or more email addresses|critical_alerts=$INJECTION"
    "fnx-ew1-prod|\"dr_region_code\":|dr_region_code=$DR_INJECTION"
    "fnx-ue1-prod|\"vpc_cidr_services\":|vpc_cidr_services=$CIDR_INJECTION"
    # Every answer the wire hook passes to scripts/stack-wiring.py is refused
    # before any hook runs: the inputs by their patterns, the selects by their
    # options.
    "fnx-ue1-dev|\"tenant\":|tenant=$TENANT_INJECTION"
    "fnx-ue1-dev|\"account\":|account=$ACCOUNT_INJECTION"
    "fnx-ue1-dev|\"region_code\":|region_code=$CODE_INJECTION"
    "fnx-ue1-dev|(valid values: dev, staging, prod, audit, security, network, identity, artifacts)|stage=$STAGE_INJECTION"
    "fnx-ue1-dev|(valid values: us-east-1, us-east-2, us-west-2, eu-west-1, eu-central-1)|region=$REGION_INJECTION"
)

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
real_roots="$(cd "$REPO_ROOT" && cksum "${ROOT_FILES[@]}")"

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
# The hooks use the working directory when it holds the tenant's stacks, so a
# nested copy is safe; the check still refuses to run inside a work tree.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR the scratch copy $scratch is inside a git work tree; the scaffold hooks would edit $(git rev-parse --show-toplevel)" >&2
    exit 1
fi
mkdir "$out/roots"
for root_file in "${ROOT_FILES[@]}"; do
    cp "$root_file" "$out/roots/${root_file##*/}"
done
# roots_unchanged <what>: the scratch copy's root backend files are as copied.
roots_unchanged() {
    local root_file rc=0
    for root_file in "${ROOT_FILES[@]}"; do
        if ! cmp -s "$root_file" "$out/roots/${root_file##*/}"; then
            echo "ERROR $1: $root_file changed:" >&2
            diff -u "$out/roots/${root_file##*/}" "$root_file" >&2 || true
            # Restore it, so later cases do not report this one's change again.
            cp "$out/roots/${root_file##*/}" "$root_file"
            rc=1
        fi
    done
    return "$rc"
}
python3 -m unittest workflows/scripts/common/test_stack_wiring.py
atmos scaffold validate scaffolds/stack/scaffold.yaml
# scaffold_code: scaffold.yaml without its comment lines, so a comment quoting
# a pinned line cannot satisfy its pin. The pins are anchored whole lines in
# bracket expressions (no backslash escapes), the same for GNU and BSD grep.
scaffold_code() {
    grep -v '^[[:space:]]*#' scaffolds/stack/scaffold.yaml
}
# The INJECTION refusal pins critical_alerts' field pattern; this pins the
# guard's second defence, the urlquery encoding of the answer it reads.
if ! scaffold_code | grep -E '^[[:space:]]*case "[{][{] urlquery [.]Answers[.]critical_alerts [}][}]" in$' >/dev/null; then
    echo "ERROR scaffolds/stack/scaffold.yaml: the guard no longer reads critical_alerts through urlquery" >&2
    exit 1
fi
# The wire hook's backstop: a target that is not the repository root has no
# stack file, so the hook refuses to wire it (scripts/test-scaffold-stack.sh
# runs the hook body itself).
if ! scaffold_code | grep -E '^[[:space:]]*[[] -f "[$]stack_file" []] [|][|] [{]$' >/dev/null; then
    echo "ERROR scaffolds/stack/scaffold.yaml: the wire hook no longer checks that the stack file exists" >&2
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

# load <env> [key=value...]: the golden's answers with the overrides applied
# (an override of a key the golden lacks is added), as the --set array
# `sets`, plus tenant, stage, region, code and file.
load() {
    local env="$1" line key override seen=" "
    shift
    sets=()
    tenant="" stage="" region="" code="" profile=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in ''|'#'*) continue ;; esac
        key="${line%%=*}"
        seen="$seen$key "
        for override in "$@"; do
            [[ "${override%%=*}" == "$key" ]] && line="$override"
        done
        sets+=(--set "$line")
        case "$key" in
            tenant) tenant="${line#*=}" ;;
            stage) stage="${line#*=}" ;;
            region) region="${line#*=}" ;;
            region_code) code="${line#*=}" ;;
            profile) profile="${line#*=}" ;;
        esac
    done < "$env"
    for override in "$@"; do
        [[ "$seen" == *" ${override%%=*} "* ]] || sets+=(--set "$override")
    done
    file="stacks/orgs/$tenant/$stage/$region.yaml"
}

# GEN_FLAGS: extra flags for the next generate calls (--skip-hooks).
GEN_FLAGS=()
generate() {
    atmos scaffold generate stack . --force --defaults ${GEN_FLAGS[@]+"${GEN_FLAGS[@]}"} "${sets[@]}"
}

# logged <log> <message>: the log says message. Atmos renders its errors for a
# terminal, wrapped and (in CI) coloured mid-word, so compare both with the
# ANSI escapes removed and every whitespace run, newlines included, as one
# space.
flatten() {
    sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g' | tr -s '[:space:]' ' '
}
logged() {
    local text message
    text="$(flatten < "$1")"
    message="$(printf '%s' "$2" | flatten)"
    # An empty (or all-space) message would match any log.
    [[ -n "${message// /}" ]] || return 1
    [[ "$text" == *"$message"* ]]
}
if logged "$REPO_ROOT/scripts/check-stack-scaffold.sh" "" || logged "$REPO_ROOT/scripts/check-stack-scaffold.sh" "   "; then
    echo "ERROR logged: an empty message matches any log, so a refusal case without one would pass" >&2
    exit 1
fi

# imports <file>: its import: list, one entry per line, in file order. The
# goldens compare resolved config, which today does not depend on import order
# (Atmos merges imports in order, later wins, but no two of a reference
# stack's imports set the same key), so this pins the order (a reordered list
# resolves identically today but may not after a catalog edit).
imports() {
    awk '/^import:/ { f = 1; next }
        f && /^[^ #-]/ { exit }
        f && /^ *- / { sub(/^ *- */, ""); sub(/ *#.*$/, ""); gsub(/["\047]/, ""); print }' "$1"
}

# golden <env>: regenerate its stack; returns 1 on any difference.
golden() {
    local env="$1" stack kind wired rc=0
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
    if ! logged "$out/$stack.guard.log" "exists; remove it first" \
        || ! cmp -s "$file" "$out/$stack.committed.yaml"; then
        echo "ERROR $stack: the run over an existing $file failed, but not by the guard, or changed it:" >&2
        cat "$out/$stack.guard.log" >&2
        return 1
    fi
    echo "guard: refused to overwrite $file"

    rm "$file"
    files_list > "$out/$stack.files.before"
    if ! generate > "$out/$stack.generate.log" 2>&1; then
        echo "ERROR $stack: atmos scaffold generate stack failed:" >&2
        cat "$out/$stack.generate.log" >&2
        return 1
    fi
    # The wire hook ran (it found the reference stack already wired, or a
    # core stack, which it leaves unwired).
    wired="is already wired"
    [[ "$profile" != "core" ]] || wired="is a core-account stack: nothing to wire"
    if ! logged "$out/$stack.generate.log" "$stack $wired"; then
        echo "ERROR $stack: the wire hook did not report \"$stack $wired\":" >&2
        cat "$out/$stack.generate.log" >&2
        rc=1
    fi
    # The run writes the stack file and nothing else (bar its .atmos record).
    files_list > "$out/$stack.files.after"
    if ! diff <(echo "./$file") <(LC_ALL=C comm -13 "$out/$stack.files.before" "$out/$stack.files.after") > /dev/null; then
        echo "ERROR $stack: the scaffold wrote more or less than $file:" >&2
        LC_ALL=C comm -3 "$out/$stack.files.before" "$out/$stack.files.after" >&2
        rc=1
    fi
    roots_unchanged "$stack (wire hook on an already wired stack)" || rc=1
    yamllint -d relaxed "$file" || rc=1
    imports "$out/$stack.committed.yaml" > "$out/$stack.imports.committed"
    imports "$file" > "$out/$stack.imports.generated"
    if [[ ! -s "$out/$stack.imports.committed" ]] \
        || ! cmp -s "$out/$stack.imports.committed" "$out/$stack.imports.generated"; then
        echo "DIFFERENT $stack (import order): the generated import: list is not the committed one, in order" >&2
        diff -u --label "committed $file" --label "generated from $env" \
            "$out/$stack.imports.committed" "$out/$stack.imports.generated" >&2 || true
        rc=1
    else
        echo "import order: $(wc -l < "$out/$stack.imports.committed" | tr -d ' ') imports, as committed"
    fi
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
    load "scaffolds/stack-golden/$stack.env" ${overrides[@]+"${overrides[@]}"}
    log="$out/refusal.log"
    # The target may be a real stack; remove it so only the case's own
    # answers can be refused.
    [[ ! -f "$file" ]] || mv "$file" "$out/refusal.target"
    files_list > "$out/refusal.before"
    if generate > "$log" 2>&1; then
        echo "ERROR refusal ($stack with $3): generated, but the guard should refuse: $message" >&2
        rc=1
    elif ! logged "$log" "$message"; then
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
    roots_unchanged "refusal ($stack with $3)" || rc=1
    [[ "$rc" -ne 0 ]] || echo "guard: refused $stack with $3 ($message)"
    # Undo whatever the case did.
    LC_ALL=C comm -13 "$out/refusal.before" "$out/refusal.after" | while IFS= read -r f; do rm -f "$f"; done
    [[ ! -f "$out/refusal.target" ]] || mv "$out/refusal.target" "$file"
    return "$rc"
}

failed=""
goldens=0
refused=0

# clean_since <before list>: remove every file a case wrote since the listing.
clean_since() {
    files_list > "$out/clean.after"
    LC_ALL=C comm -13 "$1" "$out/clean.after" | while IFS= read -r f; do rm -f "$f"; done
}

if [[ "$SWEEP" == "false" ]]; then
for env in scaffolds/stack-golden/*.env; do
    goldens=$((goldens + 1))
    stack="$(basename "$env" .env)"
    files_list > "$out/files.before"
    golden "$env" || failed="$failed $stack"
    # Leave the committed file, and nothing a run wrote, for the next golden.
    [[ ! -f "$out/$stack.committed.yaml" ]] || cp "$out/$stack.committed.yaml" "$file"
    clean_since "$out/files.before"
done
if [[ "$goldens" -eq 0 ]]; then
    echo "ERROR no scaffolds/stack-golden/*.env" >&2
    exit 1
fi

echo "== guard refusals"
for case in "${REFUSALS[@]}"; do
    IFS='|' read -r stack message overrides <<< "$case"
    refused=$((refused + 1))
    refusal "$stack" "$message" "$overrides" || failed="$failed refusal:$stack"
done

# The one-primary-per-account loop reads an account: line plain or quoted:
# with eu-west-1.yaml's written `account: "prod-eu"`, a second prod-eu
# primary is still refused.
echo "== quoted account (one primary per account)"
ew1="stacks/orgs/fnx/prod/eu-west-1.yaml"
cp "$ew1" "$out/quoted.committed.yaml"
sed 's/^\( *account: *\)prod-eu *$/\1"prod-eu"/' "$out/quoted.committed.yaml" > "$ew1"
if ! grep -q '^ *account: *"prod-eu"$' "$ew1"; then
    echo "ERROR quoted account: could not quote $ew1's account: line" >&2
    failed="$failed quoted-account"
else
    refused=$((refused + 1))
    refusal fnx-ew1-prod "the prod-eu account already has its prod primary (eu-west-1.yaml)" \
        "region=eu-central-1 region_code=ec1 az_ids=euc1-az1,euc1-az2,euc1-az3 dr_region=eu-west-1 dr_region_code=ew1" \
        || failed="$failed quoted-account"
fi
cp "$out/quoted.committed.yaml" "$ew1"

# The same loop for the prod account, which no generatable tree reaches (its
# only primary is us-east-1's data plane): a hand-written us-west-2 primary,
# a copy of fnx-ue1-prod with its account: line plain, "quoted" and 'quoted',
# refuses regenerating fnx-ue1-prod (refusal moves the committed file away).
echo "== hand-written prod primary (one primary per account)"
uw2="stacks/orgs/fnx/prod/us-west-2.yaml"
for quote in "" '"' "'"; do
    sed "s/^\( *account: *\)prod *\$/\1${quote}prod${quote}/" stacks/orgs/fnx/prod/us-east-1.yaml > "$uw2"
    if ! grep -q "^ *account: *${quote}prod${quote}\$" "$uw2"; then
        echo "ERROR hand-written primary: could not write $uw2's account: line as ${quote}prod${quote}" >&2
        failed="$failed hand-written-primary"
    else
        refused=$((refused + 1))
        refusal fnx-ue1-prod "the prod account already has its prod primary (us-west-2.yaml)" "" \
            || failed="$failed hand-written-primary"
    fi
    rm -f "$uw2"
done

# With every hook skipped (no guard), the prod primary template still refuses
# a data_plane its account does not run: its own fail, writing nothing. Atmos
# 1.229 and 1.233 both report only that the template failed, hiding the fail's
# own text, so the generic "Failed to generate files" message is matched.
echo "== template refusals (--skip-hooks)"
GEN_FLAGS=(--skip-hooks)
for case in \
    "fnx-ue1-prod|data_plane=no" \
    "fnx-ew1-prod|data_plane=yes vpc_cidr_services=10.31.0.0/16"; do
    IFS='|' read -r stack overrides <<< "$case"
    refused=$((refused + 1))
    refusal "$stack" "Failed to generate files: stack/prod-primary.yaml.tmpl" "$overrides" \
        || failed="$failed template-refusal:$stack"
done
GEN_FLAGS=()

# A hostile value in a field the profile's `when` hides (vpc_cidr_services
# without the data plane) is never interpolated: the stack generates as its
# golden does, and nothing runs.
echo "== hidden-field injection (fnx-ew1-prod, vpc_cidr_services)"
load scaffolds/stack-golden/fnx-ew1-prod.env "vpc_cidr_services=$CIDR_INJECTION"
cp "$file" "$out/hidden.committed.yaml"
snapshot fnx-ew1-prod "$out/hidden.before.json"
rm "$file"
files_list > "$out/hidden.before"
# The golden has no vpc_cidr_services: load must have added the override, or
# this case tests nothing.
if [[ " ${sets[*]} " != *" vpc_cidr_services=$CIDR_INJECTION "* ]]; then
    echo "ERROR hidden-field injection: the hostile vpc_cidr_services was not passed (sets: ${sets[*]})" >&2
    failed="$failed hidden-injection"
elif ! generate > "$out/hidden.log" 2>&1; then
    echo "ERROR hidden-field injection: generating fnx-ew1-prod with a hidden hostile vpc_cidr_services failed:" >&2
    cat "$out/hidden.log" >&2
    failed="$failed hidden-injection"
elif [[ -n "$(find . -name INJECTED)" ]] || [[ -e "$REPO_ROOT/INJECTED" ]]; then
    echo "ERROR hidden-field injection: the hidden answer was executed by the shell (INJECTED exists)" >&2
    failed="$failed hidden-injection"
elif ! snapshot fnx-ew1-prod "$out/hidden.after.json" || ! cmp -s "$out/hidden.before.json" "$out/hidden.after.json"; then
    echo "ERROR hidden-field injection: the hidden answer changed fnx-ew1-prod" >&2
    failed="$failed hidden-injection"
else
    echo "hidden field: vpc_cidr_services=$CIDR_INJECTION ignored, nothing executed, fnx-ew1-prod unchanged"
fi
clean_since "$out/hidden.before"
find . -name INJECTED -exec rm -f {} +
cp "$out/hidden.committed.yaml" "$file"
roots_unchanged "hidden-field injection" || failed="$failed hidden-injection"

# A target other than the repository root. On 1.229 the guard runs in the
# invocation directory (the root) and passes and the file lands in the target;
# then verify, the first after-generate hook, must refuse (the wire hook's own
# check stays a second defence: Atmos runs no hook after a failed one), and
# nothing may claim the stack resolves or wire it. On 1.233 the hooks run in
# the target, where the guard finds no stage defaults. Either way nothing
# outside the target changes. Not counted among the bad answer sets.
echo "== non-root target (fnx-uw2-dev into $out/nonroot)"
load scaffolds/stack-golden/fnx-ue1-dev.env account_singletons=no region=us-west-2 region_code=uw2 \
    az_ids=usw2-az1,usw2-az2,usw2-az3 vpc_cidr_main=10.2.0.0/16 vpc_cidr_services=10.3.0.0/16
atmos_version="$(atmos version 2>&1 | flatten)"
files_list > "$out/nonroot.before"
if atmos scaffold generate stack "$out/nonroot" --force --defaults "${sets[@]}" > "$out/nonroot.log" 2>&1; then
    echo "ERROR non-root target: generated, but a target other than the root must be refused" >&2
    cat "$out/nonroot.log" >&2
    failed="$failed non-root-target"
elif logged "$out/nonroot.log" "resolves" || logged "$out/nonroot.log" "stack-wiring:"; then
    echo "ERROR non-root target: a hook verified or wired a stack the root does not have:" >&2
    cat "$out/nonroot.log" >&2
    failed="$failed non-root-target"
elif logged "$out/nonroot.log" "scaffold stack: not verifying:" \
    && logged "$out/nonroot.log" "/$file does not exist, so the target is not the repository root"; then
    echo "non-root target: refused by the verify hook"
elif [[ "$atmos_version" != *"Atmos 1.229."* ]] \
    && logged "$out/nonroot.log" "no stacks/orgs/$tenant/$stage/_defaults.yaml: a new tenant or stage is out of scope"; then
    echo "non-root target: refused by the guard (the hooks run in the target)"
else
    echo "ERROR non-root target: failed, but not by the verify hook (or, after 1.229, the guard; this is $atmos_version):" >&2
    cat "$out/nonroot.log" >&2
    failed="$failed non-root-target"
fi
files_list > "$out/nonroot.after"
if ! cmp -s "$out/nonroot.before" "$out/nonroot.after"; then
    echo "ERROR non-root target: files outside the target changed:" >&2
    LC_ALL=C comm -3 "$out/nonroot.before" "$out/nonroot.after" >&2
    failed="$failed non-root-target"
fi
roots_unchanged "non-root target" || failed="$failed non-root-target"
rm -rf "$out/nonroot"
fi

# The fresh-stack end to end. Scratch-only setup for the prod pair: the
# committed ue1/ue2 pair's files and their root backend lines go, so the pair
# below is wired from an empty prod family. Each FRESH entry is
# <golden>|<stack>|<answer overrides>, generated in order with the hooks.
echo "== fresh stacks (generated and wired by the hooks)"
FRESH=(
    "fnx-ue1-dev|fnx-uw2-dev|account_singletons=no region=us-west-2 region_code=uw2 az_ids=usw2-az1,usw2-az2,usw2-az3 vpc_cidr_main=10.2.0.0/16 vpc_cidr_services=10.3.0.0/16"
    "fnx-ue1-staging|fnx-uw2-staging|account_singletons=no region=us-west-2 region_code=uw2 az_ids=usw2-az1,usw2-az2,usw2-az3 vpc_cidr_main=10.2.0.0/16 vpc_cidr_services=10.3.0.0/16"
    "fnx-ue1-prod|fnx-ue1-prod|dr_region=us-west-2 dr_region_code=uw2"
    "fnx-ue2-prod|fnx-uw2-prod|region=us-west-2 region_code=uw2 az_ids=usw2-az1,usw2-az2,usw2-az3 vpc_cidr_main=10.26.0.0/16"
    # The EU backend: the prod-eu standby is wired into eu-west-1.yaml.
    "fnx-ec1-prod|fnx-ec1-prod|"
    # A core account's second region: validated, left unwired (no line added).
    "fnx-ue1-security|fnx-uw2-security|region=us-west-2 region_code=uw2"
)
us_root="${ROOT_FILES[0]}"
eu_root="${ROOT_FILES[1]}"
files_list > "$out/fresh.before"
cp "$us_root" "$out/fresh.us.committed"
cp "$eu_root" "$out/fresh.eu.committed"
fresh_ok=1
rm stacks/orgs/fnx/prod/us-east-1.yaml stacks/orgs/fnx/prod/us-east-2.yaml stacks/orgs/fnx/prod/eu-central-1.yaml
# Only the pair's list items go; the comments naming them stay.
grep -v -E '^ *- .*(fnx-ue1-prod|fnx-ue2-prod)' "$out/fresh.us.committed" > "$us_root"
grep -v -E '^ *- .*fnx-ec1-prod' "$out/fresh.eu.committed" > "$eu_root"
cp "$us_root" "$out/fresh.us.base"
cp "$eu_root" "$out/fresh.eu.base"
fresh=()
wired_fresh=0
for case in "${FRESH[@]}"; do
    IFS='|' read -r golden_stack stack overrides <<< "$case"
    read -r -a override_list <<< "$overrides"
    load "scaffolds/stack-golden/$golden_stack.env" ${override_list[@]+"${override_list[@]}"}
    if [[ "$tenant-$code-$stage" != "$stack" ]] || ! generate > "$out/fresh.$stack.log" 2>&1; then
        echo "ERROR fresh $stack: generating it failed:" >&2
        cat "$out/fresh.$stack.log" >&2
        fresh_ok=0
    elif [[ "$profile" == "core" ]]; then
        if ! logged "$out/fresh.$stack.log" "$stack is a core-account stack: nothing to wire" \
            || logged "$out/fresh.$stack.log" "stack-wiring: added"; then
            echo "ERROR fresh $stack: the wire hook did not leave the core stack unwired:" >&2
            cat "$out/fresh.$stack.log" >&2
            fresh_ok=0
        fi
    elif ! logged "$out/fresh.$stack.log" "stack-wiring: added"; then
        echo "ERROR fresh $stack: the wire hook added nothing for it:" >&2
        cat "$out/fresh.$stack.log" >&2
        fresh_ok=0
    else
        wired_fresh=$((wired_fresh + 1))
    fi
    fresh+=("$stack")
done
if [[ "$fresh_ok" -eq 1 ]]; then
    # The hook only adds lines: four per wired stack (its pattern pair, its
    # plan and apply role ARNs; none for a core stack), everything else byte
    # for byte.
    diff "$out/fresh.us.base" "$us_root" > "$out/fresh.root.diff" || true
    diff "$out/fresh.eu.base" "$eu_root" >> "$out/fresh.root.diff" || true
    if grep -v -e '^> ' -e '^[0-9,]*a[0-9,]*$' "$out/fresh.root.diff" > /dev/null \
        || [[ "$(grep -c '^> ' "$out/fresh.root.diff")" -ne $((4 * wired_fresh)) ]]; then
        echo "ERROR fresh: $us_root and $eu_root changed by more than the $((4 * wired_fresh)) added lines:" >&2
        cat "$out/fresh.root.diff" >&2
        fresh_ok=0
    fi
    # Re-running the wiring adds nothing.
    cp "$us_root" "$out/fresh.us.wired"
    cp "$eu_root" "$out/fresh.eu.wired"
    for case in "${FRESH[@]}"; do
        IFS='|' read -r golden_stack stack overrides <<< "$case"
        read -r -a override_list <<< "$overrides"
        load "scaffolds/stack-golden/$golden_stack.env" ${override_list[@]+"${override_list[@]}"}
        account="$(sed -n 's/^account=//p' "scaffolds/stack-golden/$golden_stack.env")"
        python3 scripts/stack-wiring.py "$tenant" "$stage" "$account" "$region" "$stack" > "$out/fresh.rewire.log" 2>&1 \
            || { cat "$out/fresh.rewire.log" >&2; fresh_ok=0; }
    done
    if ! cmp -s "$out/fresh.us.wired" "$us_root" || ! cmp -s "$out/fresh.eu.wired" "$eu_root"; then
        echo "ERROR fresh: a second wiring run changed $us_root or $eu_root:" >&2
        diff -u "$out/fresh.us.wired" "$us_root" >&2 || true
        diff -u "$out/fresh.eu.wired" "$eu_root" >&2 || true
        fresh_ok=0
    fi
fi
if [[ "$fresh_ok" -eq 1 ]]; then
    atmos describe stacks --process-functions=false --format json > "$out/fresh.json"
    atmos describe workflows --output all --format json > "$out/fresh.workflows.json"
    for stack in "${fresh[@]}"; do
        python3 -c 'import json,sys; sys.exit(sys.argv[2] not in json.load(open(sys.argv[1])))' "$out/fresh.json" "$stack" \
            || { echo "ERROR fresh $stack: not among the resolved stacks" >&2; fresh_ok=0; }
    done
    # The stack checks check-stack-samples.sh runs, plus the DR pairing.
    for check in \
        "workflows/scripts/common/check-dependencies.py components/terraform" \
        "workflows/scripts/common/check-lane-names.py" \
        "workflows/scripts/common/check-prod-protection.py components/terraform" \
        "workflows/scripts/common/check-cluster-api-ci.py components/terraform" \
        "workflows/scripts/common/check-state-keys.py" \
        "workflows/scripts/common/check-ci-state-roles.py" \
        "workflows/scripts/common/check-data-residency.py" \
        "workflows/scripts/common/dr-pair.py --lint" \
        "scripts/check-inherited-state-reads.py"; do
        read -r -a argv <<< "$check"
        if ! python3 "${argv[@]}" < "$out/fresh.json" > "$out/fresh.check.log" 2>&1; then
            echo "ERROR fresh: ${argv[0]##*/} fails with ${fresh[*]}:" >&2
            cat "$out/fresh.check.log" >&2
            fresh_ok=0
        fi
    done
    if ! python3 workflows/scripts/common/check-deploy-layers.py "$out/fresh.json" "$out/fresh.workflows.json" \
        > "$out/fresh.check.log" 2>&1; then
        echo "ERROR fresh: check-deploy-layers.py fails with ${fresh[*]}:" >&2
        cat "$out/fresh.check.log" >&2
        fresh_ok=0
    fi
fi
if [[ "$fresh_ok" -eq 1 ]]; then
    echo "fresh: ${fresh[*]} generated, wired ($((4 * wired_fresh)) lines added to the root backends, a second run adds none) and pass every stack check"
fi
if [[ "$fresh_ok" -eq 1 && "$SWEEP" == "true" ]]; then
    # plan-sweep mirrors components/terraform with git ls-files.
    git init -q .
    # The fresh stacks plan-sweep's default would select (ci-stacks.py
    # --plan-sweep's rule, over every resolved stack): a hosted-CI-disabled
    # stack with nothing to plan (the fresh core stack) is skipped with its
    # ::notice::; anything else it refuses fails here, as it fails the sweep.
    if ! swept="$(python3 -B - "$out/fresh.json" "${fresh[@]}" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("ci_stacks", "workflows/scripts/common/ci-stacks.py")
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)
stacks = json.load(open(sys.argv[1]))
try:
    selected = set(ci.plan_sweep_stacks(stacks))
except ValueError as error:
    sys.exit(f"::error::{error}")
print(" ".join(name for name in sys.argv[2:] if name in selected))
PY
)"; then
        echo "ERROR fresh: ci-stacks.py's plan-sweep selection failed" >&2
        fresh_ok=0
    elif [[ -z "$swept" ]]; then
        echo "ERROR fresh: plan-sweep would select none of ${fresh[*]}" >&2
        fresh_ok=0
    else
        read -r -a swept_list <<< "$swept"
        bash scripts/plan-sweep.sh "${swept_list[@]}" || fresh_ok=0
    fi
fi
[[ "$fresh_ok" -eq 1 ]] || failed="$failed fresh"
clean_since "$out/fresh.before"

# Nothing above may touch the real repository's root backend files.
if [[ "$(cd "$REPO_ROOT" && cksum "${ROOT_FILES[@]}")" != "$real_roots" ]]; then
    echo "ERROR the real repository's root backend files changed during the check:" >&2
    (cd "$REPO_ROOT" && git diff -- "${ROOT_FILES[@]}" >&2) || true
    failed="$failed real-root-files"
fi

if [[ -n "$failed" ]]; then
    echo "stack scaffold check failed for:$(echo "$failed" | tr ' ' '\n' | sed '/^$/d' | sort -u | paste -sd ' ' -)" >&2
    exit 1
fi
if [[ "$SWEEP" == "true" ]]; then
    echo "OK: the ${#fresh[@]} fresh stacks pass the stack checks, and plan-sweep passes the ${#swept_list[@]} it selects (${swept_list[*]})"
else
    echo "IDENTICAL: the stack scaffold regenerates all $goldens golden stacks (normal and raw, imports in their committed order, the root backends untouched); $refused bad answer sets are refused; the ${#fresh[@]} fresh stacks (${fresh[*]}) are wired by the hook (a core stack left unwired) and pass every stack check"
fi

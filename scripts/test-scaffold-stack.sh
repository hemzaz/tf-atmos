#!/usr/bin/env bash
#
# test-scaffold-stack.sh - tests for scripts/scaffold-stack.sh, the one answers
# reader behind make onboard/onboard-custom, and for the Makefile's quoting
# (lint step scaffold-stack-reader). A stub `atmos` first on PATH records its
# argv, one word per line, so no real scaffold or plan runs. Checked:
#   - good answers (a golden file plus --set before and after it) reach Atmos
#     as the exact argv, in order, and no arguments mean the interactive run;
#   - hostile lines (', ;, $( ), backticks, CR, spaces, an `export ` prefix,
#     an unknown field, a bad key) fail loudly, naming the line, without
#     running Atmos or any command in them (no PWNED marker anywhere);
#   - make onboard with a hostile ANSWERS file runs nothing either;
#   - make help, plan, plan-component, setup-aws-backend-dry-run and
#     bootstrap-environment with a hostile STACK, TENANT, STAGE, ENVIRONMENT,
#     NAME, REGION, COMPONENT or BACKEND_STACK echo and pass the value as one
#     literal word and run nothing in it, as shell or as make syntax.
# Exit 0 when every case passes, 1 otherwise.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
READER="$REPO_ROOT/scripts/scaffold-stack.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/work"
cat > "$tmp/bin/atmos" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "$tmp/argv"
EOF
chmod +x "$tmp/bin/atmos"
PATH="$tmp/bin:$PATH"
export PATH
failures=0

pass() { echo "ok: $*"; }
bad() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

# expect_argv <name> <expected argv file> <reader args...>
expect_argv() {
    local name="$1" want="$2"
    shift 2
    rm -f "$tmp/argv"
    if ! (cd "$tmp/work" && bash "$READER" "$@") > "$tmp/out" 2>&1; then
        bad "$name: reader failed: $(cat "$tmp/out")"
    elif ! diff -u "$want" "$tmp/argv" > "$tmp/diff" 2>&1; then
        bad "$name: argv differs:"; cat "$tmp/diff" >&2
    else
        pass "$name"
    fi
}

# expect_refused <name> <message> <file contents>
expect_refused() {
    local name="$1" message="$2" contents="$3"
    rm -f "$tmp/argv"
    printf '%s\n' "$contents" > "$tmp/work/hostile.env"
    if (cd "$tmp/work" && bash "$READER" --answers hostile.env) > "$tmp/out" 2>&1; then
        bad "$name: accepted"
    elif [[ -e "$tmp/argv" ]]; then
        bad "$name: atmos ran"
    elif ! grep -qF -- "$message" "$tmp/out"; then
        bad "$name: no '$message' in: $(cat "$tmp/out")"
    else
        pass "$name refused: $(cat "$tmp/out")"
    fi
}

# Good: --set, then the golden file, then --set; comments skipped, order kept.
golden="$REPO_ROOT/scaffolds/stack-golden/fnx-ue1-dev.env"
{
    printf '%s\n' scaffold generate stack . --force --defaults --set tenant=fnx
    grep -v '^#' "$golden" | grep -v '^$' | while IFS= read -r l; do printf '%s\n%s\n' --set "$l"; done
    printf '%s\n' --set vpc_cidr_main=10.22.0.0/16
} > "$tmp/want-golden"
expect_argv "golden answers in order" "$tmp/want-golden" \
    --set tenant=fnx --answers "$golden" --set vpc_cidr_main=10.22.0.0/16
printf '%s\n' scaffold generate stack . --force > "$tmp/want-interactive"
expect_argv "no arguments is interactive" "$tmp/want-interactive"
# An empty value (account=) and blank/whitespace-only lines are fine; a path
# with spaces is read whole.
mkdir "$tmp/work/a dir"
printf '# c\n\naccount=\n   \nstage=dev' > "$tmp/work/a dir/ok.env"
printf '%s\n' scaffold generate stack . --force --defaults --set account= --set stage=dev > "$tmp/want-empty"
expect_argv "empty value, blank lines, no final newline, spaced path" "$tmp/want-empty" --answers "a dir/ok.env"
# A comment-only file is an empty answer set: interactive.
printf '# only\n' > "$tmp/work/comments.env"
expect_argv "comment-only file" "$tmp/want-interactive" --answers comments.env

# Hostile lines: refused loudly, nothing runs.
# shellcheck disable=SC2016
{
    expect_refused "quote breakout" "hostile.env:1" "tenant=fnx';touch\${IFS}PWNED1;'"
    expect_refused "semicolon" "hostile.env:2" "$(printf 'stage=dev\ntenant=fnx;touch${IFS}PWNED2')"
    expect_refused "command substitution" "hostile.env:1" 'critical_alerts=a'"'"'$(touch PWNED3)'"'"'@example.com'
    expect_refused "backticks" "hostile.env:1" 'region_code=ue1`touch PWNED4`'
    expect_refused "CR (CRLF file)" "hostile.env:1" "$(printf 'stage=dev\r')"
    expect_refused "trailing space" "hostile.env:1" "vpc_cidr_main=10.22.0.0/16 "
    expect_refused "spaces around =" "hostile.env:1" "vpc_cidr_main = 10.22.0.0/16"
    expect_refused "export prefix" "hostile.env:1" "export stage=dev"
    expect_refused "unknown field" "unknown field nope" "nope=1"
    expect_refused "bad key" "hostile.env:1" "Stage=dev"
}
rm -f "$tmp/argv"
if (cd "$tmp/work" && bash "$READER" --answers missing.env) > "$tmp/out" 2>&1 \
    || [[ -e "$tmp/argv" ]] || ! grep -q 'answers file not found' "$tmp/out"; then
    bad "missing file"
else
    pass "missing file refused"
fi
rm -f "$tmp/argv"
if (cd "$tmp/work" && bash "$READER" --set 'stage=dev;touch PWNED5') > "$tmp/out" 2>&1 || [[ -e "$tmp/argv" ]]; then
    bad "hostile --set accepted"
else
    pass "hostile --set refused"
fi

# The Makefile recipes (onboard, onboard-custom): a hostile ANSWERS file or
# make variable never runs as shell. Each payload would create a marker under
# $M if a recipe pasted it into the shell unquoted (x;touch), with its quotes
# unescaped (x';touch;'), or let $(...) expand; the reader refuses it instead
# (REGION never gets that far: no region code, make stops). CI must run this
# (lint installs make), so a missing make fails there and skips only locally.
M="$tmp/m"
mkdir "$M"
golden_q="$tmp/work/it's a golden.env"
cp "$golden" "$golden_q"

# make_case <name> refused|ok|ran <make args...>
# ran: make must succeed; what reached the atmos stub is checked by the caller.
make_case() {
    local name="$1" want="$2"
    shift 2
    rm -f "$tmp/argv"
    if (cd "$tmp/work" && make -s -C "$REPO_ROOT" "$@") > "$tmp/out" 2>&1; then
        if [[ "$want" == "refused" ]]; then bad "make $name: accepted"; return; fi
        if [[ "$want" == "ok" ]] && ! grep -qx 'budget_monthly_limit=500' "$tmp/argv"; then bad "make $name: the answers did not reach atmos"; return; fi
    else
        if [[ "$want" != "refused" ]]; then bad "make $name: failed: $(tail -2 "$tmp/out")"; return; fi
        if [[ -e "$tmp/argv" ]]; then bad "make $name: atmos ran"; return; fi
    fi
    pass "make $name ($want)"
}

if ! command -v make > /dev/null 2>&1; then
    if [[ "${CI:-}" == "true" ]]; then
        bad "no make on PATH in CI: the Makefile recipes go untested (lint installs make)"
    else
        echo "skip: no make on PATH (the Makefile recipe cases)"
    fi
else
    # shellcheck disable=SC2016
    printf '%s\n' "tenant=fnx';touch\${IFS}$M/file;'" > "$tmp/work/hostile.env"
    make_case "onboard, hostile ANSWERS file" refused onboard ANSWERS="$tmp/work/hostile.env"
    make_case "onboard, ANSWERS path with ' and spaces" ok onboard ANSWERS="$golden_q"
    make_case "onboard-custom, ANSWERS path with ' and spaces" ok onboard-custom ANSWERS="$golden_q" VPC_CIDR=10.22.0.0/16
    n=0
    for var in TENANT STAGE ANSWERS VPC_CIDR VPC_CIDR_SERVICES REGION; do
        for payload in "x;touch $M/$var-semi" "x';touch $M/$var-quote;'" "x\$\$(touch $M/$var-subst)" "x \$\$(touch $M/$var-space)"; do
            n=$((n + 1))
            case "$var" in
                ANSWERS) args=(onboard "ANSWERS=$tmp/work/$payload") ;;
                VPC_CIDR) args=(onboard-custom "ANSWERS=$golden" "VPC_CIDR=$payload") ;;
                VPC_CIDR_SERVICES) args=(onboard-custom "ANSWERS=$golden" VPC_CIDR=10.22.0.0/16 "VPC_CIDR_SERVICES=$payload") ;;
                *) args=(onboard "ANSWERS=$golden" "$var=$payload") ;;
            esac
            make_case "hostile $var #$n" refused "${args[@]}"
        done
    done
    # The other recipes echo and pass STACK (also derived from TENANT, STAGE,
    # ENVIRONMENT and NAME), REGION (STACK= set, so make does not stop on its
    # missing region code), COMPONENT and BACKEND_STACK. help is the default
    # goal, plan an -s recipe, and bootstrap-environment runs three atmos
    # workflows: each must succeed, run nothing, and hand atmos the value
    # whole. The $$(shell ...) payload is make syntax: it runs only if a recipe
    # hands the value to a second make (STACK=... on a $(MAKE) line).
    for tc in "help STACK" "help TENANT" "help STAGE" "help ENVIRONMENT" "help NAME" "help REGION" \
        "plan STACK" "plan TENANT" "plan STAGE" "plan ENVIRONMENT" "plan NAME" "plan REGION" \
        "plan-component COMPONENT" "setup-aws-backend-dry-run BACKEND_STACK" \
        "bootstrap-environment STACK"; do
        target="${tc% *}" var="${tc#* }"
        for payload in "x;touch $M/$target-$var-semi" "x';touch $M/$target-$var-quote;'" \
            "x\$\$(touch $M/$target-$var-subst)" "x \$\$(touch $M/$target-$var-space)" \
            "x\`touch $M/$target-$var-tick\`" "x\"; touch $M/$target-$var-dquote; \"" \
            "x\$\$(shell touch $M/$target-$var-make)"; do
            n=$((n + 1))
            args=("$target" "$var=$payload")
            [[ "$var" != "REGION" ]] || args+=(STACK=fnx-ue1-dev)
            make_case "$target, hostile $var #$n" ran "${args[@]}"
            # make turns $$ into $: atmos gets the value as the shell would
            # have seen it, but as one word that never ran.
            literal="${payload//\$\$/\$}"
            case "$var" in
                STACK | COMPONENT | BACKEND_STACK) want_word="$literal" ;;
                TENANT) want_word="$literal-ue1-dev" ;;
                STAGE) want_word="fnx-ue1-$literal" ;;
                ENVIRONMENT) want_word="fnx-$literal-dev" ;;
                NAME) want_word="fnx-ue1-dev-$literal" ;;
                REGION) want_word="fnx-ue1-dev" ;;
            esac
            if [[ "$target" != "help" ]] && ! grep -qxF -- "$want_word" "$tmp/argv"; then
                bad "make $target, hostile $var #$n: atmos did not get '$want_word' as one word"
            fi
        done
    done
fi

for marker in "$M"/*; do
    [[ ! -e "$marker" ]] || bad "a hostile value ran: $marker exists"
done
for dir in "$tmp/work" "$tmp/work/a dir" "$REPO_ROOT"; do
    for marker in "$dir"/PWNED*; do
        [[ ! -e "$marker" ]] || bad "a PWNED marker exists: $marker"
    done
done

if [[ $failures -gt 0 ]]; then
    echo "test-scaffold-stack: $failures failure(s)" >&2
    exit 1
fi
echo "test-scaffold-stack: all cases pass, no PWNED marker"

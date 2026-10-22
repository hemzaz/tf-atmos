#!/usr/bin/env bash
#
# test-scaffold-stack.sh - tests for scripts/scaffold-stack.sh, the one answers
# reader behind make onboard, quickstart.sh and manifest-generator.sh (lint step
# scaffold-stack-reader). A stub `atmos` first on PATH records its argv, one
# word per line, so no real scaffold runs. Checked:
#   - good answers (a golden file plus --set before and after it) reach Atmos
#     as the exact argv, in order, and no arguments mean the interactive run;
#   - hostile lines (', ;, $( ), backticks, CR, spaces, an `export ` prefix,
#     an unknown field, a bad key) fail loudly, naming the line, without
#     running Atmos or any command in them (no PWNED marker anywhere);
#   - make onboard with a hostile ANSWERS file runs nothing either.
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

# make onboard with a hostile ANSWERS file: the reader refuses it, no shell
# ever sees the line.
# shellcheck disable=SC2016
printf '%s\n' "tenant=fnx';touch\${IFS}PWNED6;'" > "$tmp/work/hostile.env"
rm -f "$tmp/argv"
if ! command -v make > /dev/null 2>&1; then
    echo "skip: no make on PATH (the make onboard case)"
elif (cd "$tmp/work" && make -s -C "$REPO_ROOT" onboard ANSWERS="$tmp/work/hostile.env") > "$tmp/out" 2>&1; then
    bad "make onboard accepted a hostile ANSWERS file"
elif [[ -e "$tmp/argv" ]]; then
    bad "make onboard ran atmos on a hostile ANSWERS file"
else
    pass "make onboard refused a hostile ANSWERS file"
fi

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

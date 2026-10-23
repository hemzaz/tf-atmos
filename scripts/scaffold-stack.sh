#!/usr/bin/env bash
#
# scaffold-stack.sh - run the stack scaffold (scaffolds/stack) from the
# repository root with target `.`, as its hooks expect (docs/OPERATIONS.md,
# Adding a stack). make onboard/onboard-custom generate stacks through this
# one reader.
#
# Usage: scripts/scaffold-stack.sh [--set key=value | --answers FILE]...
#   No arguments: the scaffold prompts for every answer.
#   Otherwise it runs non-interactively (--defaults) with the answers in
#   argument order, a later answer for the same key winning.
#
# An answers file holds one key=value per line (a scaffolds/stack-golden/*.env
# is one); blank lines and lines starting with # are skipped. Every other line,
# and every --set, must be <field>=<value>, <field> one of
# scaffolds/stack/scaffold.yaml's fields and <value> only the characters its
# answers use (names, CIDRs, AZ ids, domains, emails, comma lists:
# A-Z a-z 0-9 . _ % + @ , / : -). So whitespace (a CR from a CRLF file, a
# trailing space, spaces around =, an `export ` prefix) and shell syntax
# (' " ; $ ` ( ) ...) are refused, not dropped: anything else fails before
# Atmos runs, naming the line.
#
# Each answer reaches Atmos as one argv word (--set "key=value") and is never
# evaluated by a shell; the scaffold's own field validation then checks the
# value. Exit: Atmos's status, or 1 for a refused answer or a missing file.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAFFOLD="$REPO_ROOT/scaffolds/stack/scaffold.yaml"

fail() {
    echo "scaffold-stack: $*" >&2
    exit 1
}

[[ -f "$SCAFFOLD" ]] || fail "no $SCAFFOLD"
# The scaffold's field names, space-delimited: " profile data_plane ... ".
FIELDS=" $(sed -n 's/^    - name: \([a-z_][a-z0-9_]*\)$/\1/p' "$SCAFFOLD" | tr '\n' ' ')"
[[ "$FIELDS" != " " ]] || fail "no fields found in $SCAFFOLD"

sets=()

# add <where> <key=value>: validate one answer and append it to `sets`.
add() {
    local where="$1" answer="$2"
    if [[ ! "$answer" =~ ^[a-z_][a-z0-9_]*=[A-Za-z0-9._%+@,/:-]*$ ]]; then
        fail "$where: $(printf '%q' "$answer") is not <field>=<value> (value characters: A-Z a-z 0-9 . _ % + @ , / : -; no whitespace)"
    fi
    [[ "$FIELDS" == *" ${answer%%=*} "* ]] \
        || fail "$where: unknown field ${answer%%=*} (scaffolds/stack fields:$FIELDS)"
    sets+=(--set "$answer")
}

# read_answers <file>: add every answer line of the file.
read_answers() {
    local file="$1" line n=0
    [[ -f "$file" ]] || fail "answers file not found: $(printf '%q' "$file")"
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        case "$line" in '#'*) continue ;; esac
        [[ "$line" =~ ^[[:space:]]*$ && "$line" != *$'\r'* ]] && continue
        add "$file:$n" "$line"
    done < "$file"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --set)
            [[ $# -ge 2 ]] || fail "--set needs key=value"
            add "--set" "$2"
            shift 2
            ;;
        --answers)
            [[ $# -ge 2 ]] || fail "--answers needs a file"
            read_answers "$2"
            shift 2
            ;;
        *)
            fail "unknown argument $(printf '%q' "$1") (usage: scaffold-stack.sh [--set key=value | --answers FILE]...)"
            ;;
    esac
done

cd "$REPO_ROOT"
if [[ ${#sets[@]} -eq 0 ]]; then
    exec atmos scaffold generate stack . --force
fi
exec atmos scaffold generate stack . --force --defaults "${sets[@]}"

#!/usr/bin/env bash
#
# check-stack-samples.sh - put the copy-in stack samples (templates/stacks/*.yaml)
# under the same checks as the real stacks, so they cannot rot unseen.
#
# A sample is not a stack until someone copies it in, so nothing else resolves
# it. This copies the repository to a scratch directory, drops every sample at
# the path its own Usage header names (`#   cp templates/stacks/<file> <path>`),
# all at once (each is a lane, so they must also coexist with the stage stacks),
# and runs:
#   - atmos validate stacks, and every sample stack its header names (`-s <stack>`)
#     must resolve;
#   - check-dependencies.py, check-deploy-layers.py, check-lane-names.py,
#     check-prod-protection.py and check-cluster-api-ci.py over the result;
#   - with --sweep, scripts/plan-sweep.sh on the sample stacks.
# The checks that need deploy-time inputs a copied-in lane must still add
# (its state pattern pair and CI role ARNs on backend/main) are left out:
# check-state-keys and check-ci-state-roles.
#
# Usage: scripts/check-stack-samples.sh [--sweep]
# Exit 0 when every sample passes, 1 otherwise.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWEEP="false"
[[ "${1:-}" == "--sweep" ]] && SWEEP="true"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# The working tree minus ignored files, as plan-sweep mirrors it; outside a
# usable git work tree (the CI container's unsafe owner), every file but .git
# and .terraform.
cd "$REPO_ROOT"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -z -co --exclude-standard | tar --null -cf - -T - | tar -xf - -C "$scratch"
else
    tar --exclude=.git --exclude=.terraform -cf - . | tar -xf - -C "$scratch"
fi

stacks=()
for sample in templates/stacks/*.yaml; do
    file="$(basename "$sample")"
    dest="$(sed -n "s|^#   cp templates/stacks/${file} \(stacks/[^ ]*\)\$|\1|p" "$sample")"
    stack="$(sed -n 's|^#   atmos .* -s \([a-z0-9-]*\)$|\1|p' "$sample" | head -1)"
    if [[ -z "$dest" || -z "$stack" ]]; then
        echo "ERROR $sample: its Usage header names no '#   cp templates/stacks/${file} stacks/...' path or '-s <stack>'" >&2
        exit 1
    fi
    if [[ -e "$scratch/$dest" ]]; then
        echo "ERROR $sample: $dest already exists; a sample must be a new stack" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$scratch/$dest")"
    cp "$sample" "$scratch/$dest"
    stacks+=("$stack")
    echo "$sample -> $dest ($stack)"
done

cd "$scratch"
atmos validate stacks
atmos describe stacks --process-functions=false --format json > stacks.json
atmos describe workflows --output all --format json > workflows.json
missing=0
for stack in "${stacks[@]}"; do
    if ! python3 -c 'import json,sys; sys.exit(sys.argv[2] not in json.load(open(sys.argv[1])))' stacks.json "$stack"; then
        echo "ERROR $stack: not among the resolved stacks (its sample's name or path is wrong)" >&2
        missing=1
    fi
done
[[ "$missing" -eq 0 ]]

python3 workflows/scripts/common/check-dependencies.py components/terraform < stacks.json
python3 workflows/scripts/common/check-deploy-layers.py stacks.json workflows.json
python3 workflows/scripts/common/check-lane-names.py < stacks.json
python3 workflows/scripts/common/check-prod-protection.py components/terraform < stacks.json
python3 workflows/scripts/common/check-cluster-api-ci.py components/terraform < stacks.json

if [[ "$SWEEP" == "true" ]]; then
    # plan-sweep mirrors components/terraform with git ls-files.
    git init -q .
    bash scripts/plan-sweep.sh "${stacks[@]}"
fi
echo "every templates/stacks sample resolves as ${stacks[*]} and passes the stack checks"

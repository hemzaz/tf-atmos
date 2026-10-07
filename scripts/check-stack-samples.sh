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
#   - ci-apply-role-arn.py --kind plan/apply for each sample stack, as
#     terraform-ci.yml and terraform-cd.yml resolve its CI roles (a sample with
#     no iam/ci fails here, as it would in CI);
#   - the one manual step a deployed lane needs, done in the scratch copy:
#     its plan/apply role ARNs added to backend/main's access roles for its
#     stage (read/write; prod_read/prod_write for stage prod). No state pattern
#     pair: the stage stack's "*/<stack>-*" pattern already covers a lane;
#   - check-dependencies.py, check-deploy-layers.py, check-lane-names.py,
#     check-prod-protection.py, check-cluster-api-ci.py, check-state-keys.py and
#     check-ci-state-roles.py over the result;
#   - with --sweep, scripts/plan-sweep.sh on the sample stacks.
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

# The CI preflight: each sample stack's CI role ARNs, as CI resolves them.
: > roles.tsv
for stack in "${stacks[@]}"; do
    for kind in plan apply; do
        arn="$(STACK="$stack" python3 workflows/scripts/common/ci-apply-role-arn.py --kind "$kind")"
        printf '%s\t%s\t%s\n' "$stack" "$kind" "${arn##*: }" >> roles.tsv
    done
done
# The manual step: the roles on backend/main's access roles for each lane's stage.
python3 - stacks.json roles.tsv <<'ROLES'
import json, pathlib, sys

stacks = json.load(open(sys.argv[1]))
backend = next(
    (i["atmos_stack_file"] for s in stacks.values()
     for i in (s.get("components") or {}).get("terraform", {}).values()
     if i.get("component") == "backend" and (i.get("metadata") or {}).get("type") != "abstract"),
    None,
)
if backend is None:
    sys.exit("ERROR no deployable backend instance to add the sample lanes' CI roles to")
path = pathlib.Path("stacks") / f"{backend}.yaml"
lines = path.read_text().splitlines()
for row in open(sys.argv[2]):
    stack, kind, arn = row.rstrip("\n").split("\t")
    stage = next(i["settings"]["context"]["stage"] for i in stacks[stack]["components"]["terraform"].values()
                 if ((i.get("settings") or {}).get("context") or {}).get("stage"))
    role = ("prod_" if stage == "prod" else "") + ("read" if kind == "plan" else "write")
    start = lines.index(f"          {role}:")
    at = next(n for n in range(start, len(lines)) if lines[n].strip() == "allowed_principal_arns:")
    lines.insert(at + 1, f'              - "{arn}"')
    print(f"{stack}: {kind} role {arn} -> backend/main access_roles.{role}")
path.write_text("\n".join(lines) + "\n")
ROLES
atmos describe stacks --process-functions=false --format json > stacks.json

python3 workflows/scripts/common/check-dependencies.py components/terraform < stacks.json
python3 workflows/scripts/common/check-deploy-layers.py stacks.json workflows.json
python3 workflows/scripts/common/check-lane-names.py < stacks.json
python3 workflows/scripts/common/check-prod-protection.py components/terraform < stacks.json
python3 workflows/scripts/common/check-cluster-api-ci.py components/terraform < stacks.json
python3 workflows/scripts/common/check-state-keys.py < stacks.json
python3 workflows/scripts/common/check-ci-state-roles.py < stacks.json

if [[ "$SWEEP" == "true" ]]; then
    # plan-sweep mirrors components/terraform with git ls-files.
    git init -q .
    bash scripts/plan-sweep.sh "${stacks[@]}"
fi
echo "every templates/stacks sample resolves as ${stacks[*]} and passes the stack checks"

#!/usr/bin/env bash
#
# plan-sweep.sh - bind each stack's RESOLVED variables to its component and plan.
#
# This is the middle rung between `terraform validate` and an emulator apply.
# `terraform validate` exits 0 on a component whose variable validations all
# fail, because it never binds values; tflint does not read them either. The
# emulator lane does bind them, but covers 5 of 28 components and needs a
# running emulator.
#
# No AWS account is required. Terraform evaluates variable validations BEFORE
# the provider authenticates, so `InvalidClientTokenId` is expected and ignored.
#
# WHAT THIS CAN AND CANNOT SEE -- the same fact cuts both ways.
#
# Because the provider never authenticates, execution stops there. Variable
# validations run before that point and ARE checked. Resource-level
# expressions, lifecycle preconditions and anything the AWS API decides run
# after it and are NOT. So:
#
#   caught here   #145 iam RE2 repetition, #149 environment/stage mix-up,
#                 #150 rds prod gates, #152 ec2 prefix-list default,
#                 #153 iam/ci role prefix, #154 acm domain pattern
#   NOT caught    #144 monitoring's null api_gateway_name -- a templatefile()
#                 failure inside a resource, reached only after auth. Verified:
#                 reintroducing that null still reports PASS here.
#                 #142 rds overlapping backup/maintenance windows -- AWS
#                 rejects those at apply; no local check can know.
#
# Both of those were caught by the emulator lane, which is why that lane is not
# redundant with this one. A PASS here means "its variable validations accept
# these values", never "this component works".
#
# Usage:
#   bash scripts/plan-sweep.sh                       # the three real stacks
#   bash scripts/plan-sweep.sh fnx-prod-production   # only these stacks
#
# Exit status: 1 if any pair FAILs, else 0. INCONCLUSIVE does not fail the run,
# but it is never reported as a pass.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${PLAN_SWEEP_WORKDIR:-$(mktemp -d)}"
STACKS="${*:-fnx-dev-testenv-01 fnx-staging-staging-01 fnx-prod-production}"

cd "$REPO" || exit 1
mkdir -p "$WORK"

# Three outcomes, never two. The distinction is the point of this script:
#
#   FAIL          at least one "Invalid value for variable"
#   INCONCLUSIVE  "No value for required variable" -- Terraform aborts BEFORE
#                 evaluating validations, so zero errors here proves NOTHING.
#                 Reporting it as PASS would be the same class of bug as can()
#                 swallowing a regex error: it looks green and checked nothing.
#                 These are components whose inputs come from another
#                 component's state via !terraform.state, which cannot be
#                 resolved without real state.
#   PASS          zero validation errors AND no missing required variables.
fail=0
pass=0
inconclusive=0
skip=0

printf '%-24s %-26s %s\n' STACK COMPONENT RESULT
printf '%s\n' "-------------------------------------------------------------------"

for d in components/terraform/*/; do
  [ -f "${d}main.tf" ] || continue
  (cd "$d" && terraform init -backend=false -input=false >/dev/null 2>&1)
done

for s in $STACKS; do
  # `atmos list components` emits TAB-separated "<component>\t<type>\t<count>".
  # Splitting on whitespace yields three tokens per line and invents components.
  for c in $(atmos list components -s "$s" 2>/dev/null | cut -f1); do
    dir="components/terraform/${c%%/*}"
    if [ ! -d "$dir" ]; then
      printf '%-24s %-26s %s\n' "$s" "$c" "SKIP no component dir"
      skip=$((skip + 1))
      continue
    fi

    tag="${s}__$(printf '%s' "$c" | tr / _)"
    vf="$WORK/$tag.json"

    if ! atmos describe component "$c" -s "$s" --process-functions=false --format json 2>/dev/null |
      python3 -c "
import sys, json
d = json.load(sys.stdin)
v = d.get('vars') or {}
# Drop unresolved !terraform.state references: they need another component's
# state. The resulting 'No value for required variable' is what makes a pair
# INCONCLUSIVE rather than passing.
v = {k: x for k, x in v.items()
     if not (isinstance(x, str) and x.startswith('!terraform.state'))}
json.dump(v, open('$vf', 'w'))
" 2>/dev/null; then
      printf '%-24s %-26s %s\n' "$s" "$c" "SKIP describe failed"
      skip=$((skip + 1))
      continue
    fi

    out="$WORK/$tag.txt"
    (cd "$dir" && terraform plan -input=false -var-file="$vf" >"$out" 2>&1)

    clean=$(sed 's/\x1b\[[0-9;]*m//g' "$out")
    invalid=$(printf '%s' "$clean" | grep -c 'Invalid value for variable')
    missing=$(printf '%s' "$clean" | grep -c 'No value for required variable')

    if [ "$invalid" -gt 0 ]; then
      printf '%-24s %-26s FAIL %s validation error(s)\n' "$s" "$c" "$invalid"
      # The error_message sits two lines above "This was checked", separated by
      # a blank "| " line, so -B2 with the blanks filtered is what surfaces it.
      printf '%s' "$clean" | grep -B2 'This was checked by the validation rule' |
        grep -vE 'This was checked|^--$|^[│|] *$' |
        sed 's/^[│|] */        /' | head -6
      fail=$((fail + 1))
    elif [ "$missing" -gt 0 ]; then
      printf '%-24s %-26s INCONCLUSIVE %s missing required var(s)\n' "$s" "$c" "$missing"
      inconclusive=$((inconclusive + 1))
    else
      printf '%-24s %-26s PASS\n' "$s" "$c"
      pass=$((pass + 1))
    fi
  done
done

printf '%s\n' "-------------------------------------------------------------------"
printf 'PASS %s   FAIL %s   INCONCLUSIVE %s   SKIP %s\n' \
  "$pass" "$fail" "$inconclusive" "$skip"
if [ -n "${PLAN_SWEEP_WORKDIR:-}" ]; then
  printf 'varfiles and plan logs: %s\n' "$WORK"
fi

if [ "$fail" -gt 0 ]; then
  printf '\n%s\n' "FAILING pairs cannot plan in their own stack."
  exit 1
fi
exit 0

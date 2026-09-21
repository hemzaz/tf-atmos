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
# WHAT THIS CAN AND CANNOT SEE
#
# Variable validations are evaluated before the provider authenticates, so they
# are ALWAYS checked. Past that point it depends on the component: one that
# needs no provider data during plan (secretsmanager, for one) plans all the
# way through, and its lifecycle preconditions are checked too. One that reads
# a data source stops at InvalidClientTokenId, and anything after that point is
# invisible.
#
#   caught          #145 iam RE2 repetition, #149 environment/stage mix-up,
#                   #150 rds prod gates, #152 ec2 prefix-list default,
#                   #153 iam/ci role prefix, #154 acm domain pattern, and
#                   secretsmanager's missing KMS key (a precondition)
#   NOT caught      #144 monitoring's null api_gateway_name -- a templatefile()
#                   failure in a component that does stop at auth. Verified:
#                   reintroducing that null still reports PASS here.
#                   #142 rds overlapping backup/maintenance windows -- AWS
#                   rejects those at apply; no local check can know.
#
# Both of those were caught by the emulator lane, which is why that lane is not
# redundant with this one. A PASS here means "nothing checkable without
# credentials objected", never "this component works".
#
# Usage:
#   bash scripts/plan-sweep.sh                       # the three real stacks
#   bash scripts/plan-sweep.sh fnx-prod-production   # only these stacks
#
# Exit status: 1 if any pair FAILs or ERRORs, else 0. INCONCLUSIVE does not
# fail the run, but it is never reported as a pass.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${PLAN_SWEEP_WORKDIR:-$(mktemp -d)}"
STACKS="${*:-fnx-dev-testenv-01 fnx-staging-staging-01 fnx-prod-production}"

cd "$REPO" || exit 1
mkdir -p "$WORK"

# Four outcomes, and the distinctions are the point of this script:
#
#   FAIL          at least one "Invalid value for variable"
#   ERROR         an error that is none of the above and is not the expected
#                 credential failure. Without this bucket an unrecognised
#                 error class falls through to PASS, which is how a green
#                 result can mean nothing at all.
#   INCONCLUSIVE  "No value for required variable" -- Terraform aborts BEFORE
#                 evaluating validations, so zero errors here proves NOTHING.
#                 Reporting it as PASS would be the same class of bug as can()
#                 swallowing a regex error: it looks green and checked nothing.
#                 What remains here is a !terraform.state reference this script
#                 has no synthetic value for (see SYNTH below); unmatched ones
#                 are dropped on purpose rather than guessed at.
#   PASS          zero validation errors, nothing missing, nothing unexpected.
fail=0
pass=0
inconclusive=0
errored=0
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

    if ! ndropped=$(atmos describe component "$c" -s "$s" --process-functions=false --format json 2>/dev/null |
      python3 -c "
import sys, json, re
d = json.load(sys.stdin)
v = d.get('vars') or {}

# --process-functions=false leaves Atmos's YAML functions as literal strings:
# '!terraform.state vpc/main .vpc_id' needs another component's state, and
# '!env PROD_ELASTICACHE_AUTH_TOKEN' needs an environment variable. Neither is
# available here. Rather than drop them all and report INCONCLUSIVE, substitute
# a SYNTHETIC value wherever the variable's type is known, so the component's
# own validations are actually exercised.
#
# Passing an unresolved '!env ...' string THROUGH is the worst option: it is a
# plausible-looking value that fails validations real input would pass. That is
# a false positive, and a gate that cries wolf gets ignored.
#
# The values are deliberately WELL-FORMED -- vpc-0123456789abcdef0 is real hex,
# so rds's ^vpc-[a-f0-9]+\$ still tests something.
#
# Matched on the VARIABLE name, not the referenced output, because the variable
# is what the component validates. Anything unmatched is dropped and the pair
# stays INCONCLUSIVE: a wrong guess is worse than an honest 'not checked'.
SYNTH = [
    (r'(^|_)vpc_id\$',                 'vpc-0123456789abcdef0'),
    (r'subnet_ids\$',                  ['subnet-0123456789abcdef0', 'subnet-0123456789abcdef1']),
    (r'(kms_key_id|kms_key_arn)\$',    'arn:aws:kms:eu-west-2:123456789012:key/12345678-1234-1234-1234-123456789012'),
    (r'^zone_id\$',                    'Z1234567890ABCDEFGHIJ'),
    (r'^certificate_arn\$',            'arn:aws:acm:eu-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012'),
    (r'^certificate_arns\$',           ['arn:aws:acm:eu-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012']),
    (r'^certificate_names\$',          ['main_wildcard']),
    (r'^certificate_domains\$',        ['example.com']),
    (r'^host\$',                       'https://EXAMPLE0123456789.gr7.eu-west-2.eks.amazonaws.com'),
    (r'^cluster_name\$',               'example-cluster'),
    (r'^oidc_provider_url\$',          'oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E'),
    (r'^oidc_provider_arn\$',          'arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E'),
    (r'^ci_state_bucket_name\$',       'example-terraform-state'),
    (r'(^|_)auth_token\$',            'SyntheticAuthToken0123456789abcd'),
    (r'route_table_ids\$',            ['rtb-0123456789abcdef0']),
]

def synth(name):
    for pat, val in SYNTH:
        if re.search(pat, name):
            return val
    return None

# Match an ACTUAL Atmos function, not merely a leading '!'. secretsmanager sets
# random_password_override_special to the literal '!#\$%&*()-_=+[]{}<>:?', and
# treating that as an unresolved function suppressed a REAL defect: the guard
# below downgraded its genuine precondition failure to INCONCLUSIVE.
ATMOS_FN = re.compile(r'^!(terraform\.state|terraform\.output|env|exec|include|template|store)\b')

SENTINEL = object()
dropped = []

def walk(key, node):
    # Atmos functions are not only top-level: network/vpc-peering hides one in
    # route_table_ids INSIDE a list of route objects. Missing those leaves the
    # literal '!terraform.state ...' string in a typed structure, which fails as
    # a type error and looks like a component defect. Recurse.
    if isinstance(node, str) and ATMOS_FN.match(node):
        got = synth(key)
        if got is None:
            dropped.append(key)
            return SENTINEL
        return got
    if isinstance(node, dict):
        out = {}
        for k, x in node.items():
            r = walk(k, x)
            if r is not SENTINEL:
                out[k] = r
        return out
    if isinstance(node, list):
        out = []
        for x in node:
            r = walk(key, x)   # keep the owning key: list items are unnamed
            if r is not SENTINEL:
                out.append(r)
        return out
    return node

top = {}
for k, x in v.items():
    r = walk(k, x)
    if r is not SENTINEL:
        top[k] = r
json.dump(top, open('$vf', 'w'))
# Report how many functions had no synthetic. Dropping one can invalidate the
# structure AROUND it -- apigateway's AWS_PROXY integration needs its uri, and
# removing it trips the component's own 'must set uri' rule. A failure we may
# have manufactured must not be reported as the component's.
print(len(dropped))
"); then
      printf '%-24s %-26s %s\n' "$s" "$c" "SKIP describe failed"
      skip=$((skip + 1))
      continue
    fi

    out="$WORK/$tag.txt"
    (cd "$dir" && terraform plan -input=false -var-file="$vf" >"$out" 2>&1)

    clean=$(sed 's/\x1b\[[0-9;]*m//g' "$out")
    invalid=$(printf '%s' "$clean" | grep -c 'Invalid value for variable')
    missing=$(printf '%s' "$clean" | grep -c 'No value for required variable')

    # Any error that is NOT a validation failure, a missing variable, or the
    # expected credential failure. Without this, an unrecognised error class
    # falls through to PASS -- which is how a green result can mean nothing.
    errors=$(printf '%s' "$clean" | grep -c 'Error: ')
    expected=$(printf '%s' "$clean" |
      grep -c 'InvalidClientTokenId\|Invalid value for variable\|No value for required variable\|no valid credential sources\|AuthFailure\|ExpiredToken')
    other=$((errors - expected))
    [ "$other" -lt 0 ] && other=0

    # An unsynthesizable Atmos function was dropped, so any failure here may be
    # ours rather than the component's -- we cannot tell the two apart. PASS
    # still stands (nothing objected); anything else downgrades to INCONCLUSIVE.
    if [ "${ndropped:-0}" -gt 0 ] &&
      { [ "$invalid" -gt 0 ] || [ "$missing" -gt 0 ] || [ "$other" -gt 0 ]; }; then
      printf '%-24s %-26s INCONCLUSIVE %s unresolved function(s)\n' "$s" "$c" "$ndropped"
      inconclusive=$((inconclusive + 1))
    elif [ "$invalid" -gt 0 ]; then
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
    elif [ "$other" -gt 0 ]; then
      printf '%-24s %-26s ERROR %s unexpected error(s)\n' "$s" "$c" "$other"
      printf '%s' "$clean" | grep 'Error: ' |
        grep -vE 'InvalidClientTokenId|Invalid value for variable|No value for required variable' |
        sed 's/^[│|] */        /' | head -3
      errored=$((errored + 1))
    else
      printf '%-24s %-26s PASS\n' "$s" "$c"
      pass=$((pass + 1))
    fi
  done
done

printf '%s\n' "-------------------------------------------------------------------"
printf 'PASS %s   FAIL %s   ERROR %s   INCONCLUSIVE %s   SKIP %s\n' \
  "$pass" "$fail" "$errored" "$inconclusive" "$skip"
if [ -n "${PLAN_SWEEP_WORKDIR:-}" ]; then
  printf 'varfiles and plan logs: %s\n' "$WORK"
fi

if [ "$fail" -gt 0 ] || [ "$errored" -gt 0 ]; then
  printf '\n%s\n' "FAILING pairs cannot plan in their own stack."
  exit 1
fi
exit 0

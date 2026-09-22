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
# Exit status: 1 if any pair FAILs or ERRORs, else 0. INCONCLUSIVE and
# UNATTRIBUTABLE do not fail the run, but neither is ever reported as a pass.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACKS="${*:-fnx-dev-testenv-01 fnx-staging-staging-01 fnx-prod-production}"

cd "$REPO" || exit 1

fail=0
pass=0
inconclusive=0
unattributable=0
errored=0
skip=0

# A caller-supplied workdir is the caller's to keep. One we made ourselves is
# removed on exit ONLY if the run was completely clean -- if anything needs
# looking at, the varfile and the plan log are the only way to look at it, and
# deleting them is how a reproducible failure becomes an unreproducible one.
#
# Absolute, because every plan runs from inside the component's directory and a
# relative workdir would resolve against that instead.
if [ -n "${PLAN_SWEEP_WORKDIR:-}" ]; then
  mkdir -p "$PLAN_SWEEP_WORKDIR" || exit 1
  WORK="$(cd "$PLAN_SWEEP_WORKDIR" && pwd)" || exit 1
  KEEP_WORK=1
else
  WORK="$(mktemp -d)" || exit 1
  KEEP_WORK=0
fi

cleanup() {
  [ "$KEEP_WORK" = 1 ] && return 0
  [ "$fail" = 0 ] && [ "$errored" = 0 ] && [ "$unattributable" = 0 ] &&
    [ "$inconclusive" = 0 ] && [ "$skip" = 0 ] && rm -rf "$WORK"
  return 0
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Synthetic CA certificate, generated fresh per run.
#
# The kubernetes provider PEM-decodes cluster_ca_certificate when it configures
# itself, so a hand-written placeholder is rejected outright and turns every
# external-secrets pair into a provider error of this script's own making. It
# has to be a real certificate.
#
# It is NOT committed. A certificate checked into a repository is a standing
# invitation to trust it, has a fixed expiry that will one day break the sweep
# for a reason unrelated to any component, and cannot be told apart from a
# credential committed by accident. Generating it live costs one subprocess per
# run and leaves nothing behind.
#
# mkcert is used when present because it produces a correctly-shaped CA without
# an openssl incantation. CAROOT points at this run's throwaway directory and
# TRUST_STORES=none keeps it out of the system and browser trust stores;
# `mkcert -install` is never called. Nothing on this machine trusts what a
# sweep generates, and the private keys are deleted the moment the certificate
# is encoded.
# ---------------------------------------------------------------------------
gen_ca_cert() {
  local d="$WORK/synth-ca"
  mkdir -p "$d" || return 1

  if command -v mkcert >/dev/null 2>&1; then
    if CAROOT="$d" TRUST_STORES=none mkcert \
      -cert-file "$d/leaf.pem" -key-file "$d/leaf-key.pem" \
      plan-sweep-synthetic.invalid >/dev/null 2>&1 && [ -s "$d/rootCA.pem" ]; then
      rm -f "$d/rootCA-key.pem" "$d/leaf-key.pem"
      base64 <"$d/rootCA.pem" | tr -d '\n'
      return 0
    fi
  fi

  if command -v openssl >/dev/null 2>&1; then
    if openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
      -keyout /dev/null -out "$d/rootCA.pem" -days 3650 \
      -subj /CN=plan-sweep-synthetic >/dev/null 2>&1 && [ -s "$d/rootCA.pem" ]; then
      base64 <"$d/rootCA.pem" | tr -d '\n'
      return 0
    fi
  fi

  return 1
}

SYNTH_CA_CERT="$(gen_ca_cert)" || SYNTH_CA_CERT=""
if [ -z "$SYNTH_CA_CERT" ]; then
  # Better to drop the variable and report INCONCLUSIVE than to substitute
  # something the kubernetes provider will reject: that would be this script
  # manufacturing a failure and reporting it as the component's.
  printf '%s\n' "warning: could not generate a synthetic CA (no usable mkcert or openssl)." >&2
  printf '%s\n' "         cluster_ca_certificate will be dropped rather than guessed." >&2
fi
export PLAN_SWEEP_CA_CERT="$SYNTH_CA_CERT"

# ---------------------------------------------------------------------------
# The varfile builder. Kept in its own file, and fed its inputs through the
# environment and argv, because it used to be a `python3 -c "..."` inside a
# DOUBLE-quoted shell string: every regex needed its '$' escaped, and the
# certificate and the output path were spliced into the program text.
# ---------------------------------------------------------------------------
SYNTH_PY="$WORK/build-varfile.py"
cat >"$SYNTH_PY" <<'PYEOF'
import sys, json, os, re

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
# so rds's ^vpc-[a-f0-9]+$ still tests something.
#
# Matched on the VARIABLE name, not the referenced output, because the variable
# is what the component validates. Anything unmatched is dropped and the pair
# stays INCONCLUSIVE: a wrong guess is worse than an honest 'not checked'.
SYNTH = [
    (r'(^|_)vpc_id$',                 'vpc-0123456789abcdef0'),
    (r'subnet_ids$',                  ['subnet-0123456789abcdef0', 'subnet-0123456789abcdef1']),
    (r'(kms_key_id|kms_key_arn)$',    'arn:aws:kms:eu-west-2:123456789012:key/12345678-1234-1234-1234-123456789012'),
    (r'^zone_id$',                    'Z1234567890ABCDEFGHIJ'),
    (r'^certificate_arn$',            'arn:aws:acm:eu-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012'),
    (r'^certificate_arns$',           ['arn:aws:acm:eu-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012']),
    (r'^certificate_names$',          ['main_wildcard']),
    (r'^certificate_domains$',        ['example.com']),
    (r'^host$',                       'https://EXAMPLE0123456789.gr7.eu-west-2.eks.amazonaws.com'),
    (r'^cluster_name$',               'example-cluster'),
    (r'^oidc_provider_url$',          'oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E'),
    (r'^oidc_provider_arn$',          'arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E'),
    (r'^ci_state_bucket_name$',       'example-terraform-state'),
    (r'(^|_)auth_token$',             'SyntheticAuthToken0123456789abcd'),
    (r'route_table_ids$',             ['rtb-0123456789abcdef0']),
    # apigateway's api_integrations[] carries the Lambda wiring. Without these
    # two the whole integration object was dropped, which tripped the
    # component's own "AWS_PROXY requires uri" validation and reported six
    # pairs as UNATTRIBUTABLE -- a script artefact, not a stack defect.
    (r'^uri$',                        'arn:aws:apigateway:eu-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-2:123456789012:function:example-function/invocations'),
    (r'^lambda_function_name$',       'example-function'),
    (r'^cognito_user_pool_arns$',     ['arn:aws:cognito-idp:eu-west-2:123456789012:userpool/eu-west-2_EXAMPLE1']),
    # Singular: ec2's instances[].subnet_id. The plural pattern above is
    # anchored, so it never matched this one.
    (r'^subnet_id$',                  'subnet-0123456789abcdef0'),
    (r'^key_name$',                   'example-keypair'),
    # ec2's allowed_ingress_rules[].security_groups -- source SG ids, not the
    # instance's own attachments.
    (r'^security_groups$',            ['sg-0123456789abcdef0']),
    (r'^vpc_associations$',           ['vpc-0123456789abcdef0']),
    # dns records[].records: a CNAME target, so it must be a hostname rather
    # than one of the id shapes above.
    (r'^records$',                    ['synthetic.example.com']),
]

# Only offered when the caller actually managed to generate one. An empty entry
# here would substitute '' and trip the kubernetes provider's PEM decode, which
# is exactly the self-inflicted failure the real certificate exists to avoid.
CA_CERT = os.environ.get('PLAN_SWEEP_CA_CERT') or ''
if CA_CERT:
    SYNTH.append((r'^cluster_ca_certificate$', CA_CERT))


def synth(name):
    for pat, val in SYNTH:
        if re.search(pat, name):
            return val
    return None


# Match an ACTUAL Atmos function, not merely a leading '!'. secretsmanager sets
# random_password_override_special to the literal '!#$%&*()-_=+[]{}<>:?', and
# treating that as an unresolved function suppressed a REAL defect: the guard
# in the caller downgraded its genuine precondition failure to INCONCLUSIVE.
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
            if r is SENTINEL:
                continue
            if isinstance(x, str) and isinstance(r, list):
                # x was an Atmos function replaced by a LIST-valued synthetic.
                # Appending it would nest -- list(list(string)) where the
                # component declares list(string) -- and the type error that
                # follows is this script's, not the component's. Splice it,
                # keeping order and dropping values already present.
                for item in r:
                    if item not in out:
                        out.append(item)
            else:
                out.append(r)
        return out
    return node


top = {}
for k, x in v.items():
    r = walk(k, x)
    if r is not SENTINEL:
        top[k] = r

with open(sys.argv[1], 'w') as fh:
    json.dump(top, fh)

# Line 1: the TERRAFORM component, which is not the instance name. network/main
# and network/services both set metadata.component: dns, and deriving the
# directory from the instance name instead planned components/terraform/network
# with dns's variables while never sweeping dns at all.
#
# Line 2: WHICH functions had no synthetic, not merely how many. Dropping one
# can invalidate the structure AROUND it -- apigateway's AWS_PROXY integration
# needs its uri, and removing it trips the component's own 'must set uri' rule.
# A failure this script may have manufactured must not be reported as the
# component's, and the names are what let a reader decide which one it was.
print(d.get('component') or (d.get('metadata') or {}).get('component') or '')
print(','.join(sorted(set(dropped))))
PYEOF

# ---------------------------------------------------------------------------
# Terraform boxes every diagnostic between U+2577 and U+2575. The SUMMARY line
# is never wrapped, but the DETAIL body wraps at ~72 columns even when stdout
# is a file, and a bad -var-file value makes Terraform echo the entire varfile
# JSON into the diagnostic as source context. Counting matching LINES therefore
# counts wrap artefacts and variable values, not diagnostics -- which is how
# subtracting one line count from another could go negative and, once clamped
# to zero, silently absorb a real error.
#
# Fold each box back into a single "<summary>TAB<detail>" record instead, and
# make every later decision per diagnostic.
# ---------------------------------------------------------------------------
fold_diags() {
  sed 's/\x1b\[[0-9;]*m//g' "$1" | awk '
    /^╷/ { s=""; ctx=""; b=""; inblk=1; next }
    /^╵/ { if (inblk && s != "") print s "\t" ctx "\t" b; inblk=0; s=""; ctx=""; b=""; next }
    inblk {
      l = $0
      sub(/^[│|]/, "", l)
      sub(/^[ \t]+/, "", l)
      sub(/[ \t]+$/, "", l)
      if (l == "") next
      # Inside a failed condition Terraform draws a SECOND box listing the
      # values behind it. The rule line is pure border and carries nothing;
      # the inner bar prefixes the values, which do matter. Drop the first,
      # unwrap the second, or both end up in the one-line detail ahead of the
      # sentence that says what is wrong.
      if (l ~ /^├─*$/) next
      sub(/^│[ ]?/, "", l)
      sub(/^[ \t]+/, "", l)
      if (l == "") next
      if (s == "")                  { s = l; next }
      if (l ~ /^on .+ line [0-9]+/) { if (ctx == "") ctx = l; next }
      # An echoed source line. For a -var-file diagnostic that is the ENTIRE
      # varfile on one line, which would bury the sentence that says what is
      # actually wrong.
      if (l ~ /^[0-9]+:/)           { next }
      b = (b == "" ? l : b " " l)
      next
    }
    END { if (inblk && s != "") print s "\t" ctx "\t" b }
  '
}

# A credential stop does not always name itself in the summary: a data source
# that cannot read caller identity summarises as 'reading STS Caller Identity'
# and carries the token only in the detail, so matching the summary alone
# reported prod's kms/main as an unexpected ERROR.
#
# Matching the detail is safe because fold_diags drops echoed source lines, so
# a varfile whose own values happen to mention one of these words can no longer
# reach the detail and launder a genuine defect into expected noise. It is also
# why the two real-defect rules below are decided first.
EXPECTED_RE='InvalidClientTokenId|no valid credential sources|AuthFailure|ExpiredToken'

# "Invalid value for variable" is a failed validation block; "Invalid value for
# INPUT variable" is a failed type constraint. Both are the component rejecting
# its own stack's values and both belong in FAIL, but only the first was ever
# matched -- which is how eks/main's non-uniform clusters.main.node_groups map
# was reported as an unexpected ERROR under a summary line reading FAIL 0.
#
# Order matters and is not arbitrary. A validation or type failure is decided
# FIRST, so that nothing in the detail can demote it to noise; only what is left
# over is tested against the credential noise; and whatever survives both is an
# error this script does not recognise, which is why the ERROR bucket exists.
classify_diags() {
  awk -F'\t' -v noise_re="$EXPECTED_RE" '
    $1 !~ /^Error: / { next }
    $1 ~ /^Error: Invalid value for (input )?variable/ { print "INVALID\t" $0;  next }
    $1 ~ /^Error: No value for required variable/      { print "MISSING\t" $0;  next }
    $1 ~ noise_re || $3 ~ noise_re                     { print "EXPECTED\t" $0; next }
                                                       { print "OTHER\t" $0 }
  '
}

show_diags() {
  awk -F'\t' -v b="$2" '
    $1 == b {
      # Message first, source location last: the location is the long part and
      # the truncation below should eat it rather than the explanation.
      msg = $2
      if ($4 != "") msg = msg " -- " $4
      if ($3 != "") msg = msg "  [" $3 "]"
      print msg
    }' "$1" |
    cut -c1-160 | sed 's/^/        /' | head -"$3"
}

printf '%-24s %-26s %s\n' STACK COMPONENT RESULT
printf '%s\n' "-------------------------------------------------------------------"

# Components split their configuration across several .tf files -- backend, iam
# and vpc have no main.tf at all -- so requiring one skipped initialising three
# of the largest components here. They only planned because a previous run had
# left .terraform/ behind; on a clean checkout each would have failed with a
# missing provider and been reported as the component's own ERROR.
#
# A failure is recorded rather than discarded for the same reason: a component
# that cannot init cannot plan, and calling that ERROR blames the component for
# this script's broken setup.
init_failed=""
for d in components/terraform/*/; do
  comp="$(basename "$d")"
  case "$comp" in _*) continue ;; esac
  ls "$d"*.tf >/dev/null 2>&1 || continue
  if ! (cd "$d" && terraform init -backend=false -input=false) \
    >"$WORK/init__$comp.log" 2>&1; then
    init_failed="$init_failed $comp"
  fi
done

for s in $STACKS; do
  # `atmos list components` emits TAB-separated "<component>\t<type>\t<count>".
  # Splitting on whitespace yields three tokens per line and invents components.
  for c in $(atmos list components -s "$s" 2>/dev/null | cut -f1); do
    tag="${s}__$(printf '%s' "$c" | tr / _)"
    vf="$WORK/$tag.json"

    # The describe has to happen BEFORE the directory is resolved: it is the
    # only thing that knows which terraform component this instance maps to.
    if ! meta=$(atmos describe component "$c" -s "$s" --process-functions=false --format json 2>/dev/null |
      python3 "$SYNTH_PY" "$vf"); then
      printf '%-24s %-26s %s\n' "$s" "$c" "SKIP describe failed"
      skip=$((skip + 1))
      continue
    fi

    comp=$(printf '%s\n' "$meta" | sed -n 1p)
    dropped=$(printf '%s\n' "$meta" | sed -n 2p)
    [ -n "$comp" ] || comp="${c%%/*}"
    dir="components/terraform/$comp"

    if [ ! -d "$dir" ]; then
      printf '%-24s %-26s %s\n' "$s" "$c" "SKIP no component dir ($comp)"
      skip=$((skip + 1))
      continue
    fi

    case " $init_failed " in
      *" $comp "*)
        printf '%-24s %-26s %s\n' "$s" "$c" "SKIP init failed ($comp)"
        skip=$((skip + 1))
        continue
        ;;
    esac

    ndropped=0
    [ -n "$dropped" ] && ndropped=$(printf '%s\n' "$dropped" | tr ',' '\n' | grep -c .)

    out="$WORK/$tag.txt"
    cls="$WORK/$tag.diag"
    (cd "$dir" && terraform plan -input=false -var-file="$vf" >"$out" 2>&1)
    fold_diags "$out" | classify_diags >"$cls"

    invalid=$(grep -c '^INVALID' "$cls")
    missing=$(grep -c '^MISSING' "$cls")
    other=$(grep -c '^OTHER' "$cls")

    # An unsynthesizable Atmos function was dropped, so any failure here may be
    # ours rather than the component's -- this script cannot tell the two apart.
    # Anything other than a clean plan is UNATTRIBUTABLE and is printed in full,
    # dropped variables first: the drop is usually in a variable the error never
    # names, so a bare count left the reader unable to rule our own damage in or
    # out, and a real defect could hide behind it.
    if [ "$ndropped" -gt 0 ] &&
      { [ "$invalid" -gt 0 ] || [ "$missing" -gt 0 ] || [ "$other" -gt 0 ]; }; then
      printf '%-24s %-26s UNATTRIBUTABLE dropped: %s\n' "$s" "$c" "$dropped"
      for b in INVALID MISSING OTHER; do show_diags "$cls" "$b" 4; done
      unattributable=$((unattributable + 1))
    elif [ "$invalid" -gt 0 ]; then
      printf '%-24s %-26s FAIL %s validation error(s)\n' "$s" "$c" "$invalid"
      show_diags "$cls" INVALID 6
      fail=$((fail + 1))
    elif [ "$missing" -gt 0 ]; then
      printf '%-24s %-26s INCONCLUSIVE %s missing required var(s)\n' "$s" "$c" "$missing"
      show_diags "$cls" MISSING 4
      inconclusive=$((inconclusive + 1))
    elif [ "$other" -gt 0 ]; then
      printf '%-24s %-26s ERROR %s unexpected error(s)\n' "$s" "$c" "$other"
      show_diags "$cls" OTHER 3
      errored=$((errored + 1))
    elif [ "$ndropped" -gt 0 ]; then
      # Nothing objected, but this script removed values the component may have
      # needed, so the plan it just proved clean is not quite the stack's plan.
      # An unqualified PASS here read as more coverage than there was.
      printf '%-24s %-26s PASS (dropped: %s)\n' "$s" "$c" "$dropped"
      pass=$((pass + 1))
    else
      printf '%-24s %-26s PASS\n' "$s" "$c"
      pass=$((pass + 1))
    fi
  done
done

printf '%s\n' "-------------------------------------------------------------------"
printf 'PASS %s   FAIL %s   ERROR %s   UNATTRIBUTABLE %s   INCONCLUSIVE %s   SKIP %s\n' \
  "$pass" "$fail" "$errored" "$unattributable" "$inconclusive" "$skip"

if [ "$KEEP_WORK" = 0 ] && [ "$fail" = 0 ] && [ "$errored" = 0 ] &&
  [ "$unattributable" = 0 ] && [ "$inconclusive" = 0 ] && [ "$skip" = 0 ]; then
  printf 'varfiles and plan logs: %s (removed: nothing to inspect)\n' "$WORK"
else
  printf 'varfiles and plan logs: %s\n' "$WORK"
fi

if [ "$fail" -gt 0 ] || [ "$errored" -gt 0 ]; then
  printf '\n%s\n' "FAILING pairs cannot plan in their own stack."
  exit 1
fi
exit 0

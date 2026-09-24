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
# No AWS account is required, and none is used: the script pins its own
# unissued credentials (see below), so a plan that gets as far as the provider
# stops at `InvalidClientTokenId`, which is expected and ignored. Terraform
# evaluates variable validations BEFORE the provider authenticates.
#
# WHAT THIS CAN AND CANNOT SEE
#
# Variable validations are evaluated before the provider authenticates, so they
# are ALWAYS checked. The provider's own credential check is switched off (see
# the mirror, below), so past that point it depends on the component: one that
# needs no provider data during plan (secretsmanager, for one) plans all the
# way through, and its lifecycle preconditions are checked too. One that reads
# a data source stops at its first one, refused for the unissued key, and
# anything after that point is invisible.
#
#   caught          #145 iam RE2 repetition, #149 environment/stage mix-up,
#                   #150 rds prod gates, #152 ec2 prefix-list default,
#                   #153 iam/ci role prefix, #154 acm domain pattern,
#                   secretsmanager's missing KMS key (a precondition), and
#                   #166 acm's certificate_arns MAP passed to monitoring's
#                   list(string), including its first fix: Atmos prepends
#                   '.' to `[.certificate_arns // {} | .[]]`, making it an
#                   index that yields the string "null null". Caught since
#                   references are evaluated as Atmos evaluates them, over
#                   outputs shaped like the target's (see the builder).
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
# Exit status: 1 if any pair FAILs, ERRORs or is SKIPped, or if nothing was
# planned at all; 2 if a required tool is missing (yq must be mikefarah v4) or
# the diagnostic parser or the varfile builder fails its self-test; else 0.
# A broken !terraform reference is a FAIL: a stack, instance or output that is
# not there, arguments Atmos cannot parse, an expression yq rejects. An output
# that is not there BEHIND a '//' default is not broken -- Atmos succeeds with
# the default -- but it is stale: a STALE line, counted, never failing.
# INCONCLUSIVE and UNATTRIBUTABLE do not fail the run, but neither is ever
# reported as a pass. A PASS says how the plan ended:
# "full plan", or "stopped at an expected refusal" once everything before it
# held -- the unissued key refused by AWS, or the synthetic EKS host that does
# not resolve.
set -u

# Varfiles hold every resolved stack variable. Keep everything this run
# writes private to the user running it, a caller-supplied workdir included.
umask 077

# Pin the credentials instead of inheriting them. Through the default chain a
# developer's live profile would have every plan read a real account, while CI
# has none at all and ends somewhere else again -- and the same commit has to
# reach the same verdicts everywhere. STS rejects an unissued key with
# InvalidClientTokenId, the stop EXPECTED_RE recognises; the metadata endpoint
# is disabled so the provider never waits on one that is not there. The key
# deliberately does not look like a real one, so secret scanners stay quiet.
unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_SESSION_TOKEN AWS_SECURITY_TOKEN \
  AWS_ROLE_ARN AWS_WEB_IDENTITY_TOKEN_FILE AWS_CONTAINER_CREDENTIALS_FULL_URI \
  AWS_CONTAINER_CREDENTIALS_RELATIVE_URI AWS_CONTAINER_AUTHORIZATION_TOKEN
export AWS_ACCESS_KEY_ID=PLANSWEEPSYNTHETIC
export AWS_SECRET_ACCESS_KEY=plan-sweep-synthetic-not-a-credential
export AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true

# The rest of what a shell can hand a plan: an endpoint override sends it to an
# emulator that accepts any key; TF_CLI_ARGS* add arguments to every command;
# TF_VAR_* fills a variable the varfile lacks and hides a MISSING; a kubeconfig
# hands an unconfigured kubernetes provider a real cluster.
for v in $(compgen -e); do
  case "$v" in
    AWS_ENDPOINT_URL* | TF_CLI_ARGS* | TF_VAR_* | KUBECONFIG | KUBE_*) unset "$v" ;;
  esac
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACKS="${*:-fnx-dev-testenv-01 fnx-staging-staging-01 fnx-prod-production}"

cd "$REPO" || exit 1

# A missing tool is this script's failure, not ninety SKIPs to be read as one.
for tool in atmos terraform python3 git tar yq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'error: %s not found on PATH; nothing can be planned without it.\n' "$tool" >&2
    exit 2
  fi
done

# yq evaluates each !terraform.state expression the way Atmos does, and it has
# to be the SAME yq: mikefarah's v4, the library Atmos embeds. The Python yq
# (a jq wrapper) and mikefarah v3 share the name and disagree on the syntax, so
# a wrong one would turn every reference into a "yq error" FAIL -- or, worse,
# evaluate some differently and pass what Atmos would reject. No fallback.
yq_version=$(yq --version 2>&1)
if ! printf '%s\n' "$yq_version" | grep -Eq 'mikefarah/yq.* version v?4\.'; then
  printf '%s\n' "error: yq on PATH is not mikefarah yq v4 (got: $yq_version)." \
    "       The sweep evaluates !terraform.state expressions with it, as Atmos does." >&2
  exit 2
fi

fail=0
pass=0
inconclusive=0
unattributable=0
errored=0
skip=0
swept=0
refs_shaped=0
refs_fallback=0
refs_dropped=0
refs_stale=0
other_guessed=0
other_dropped=0
pass_full=0
interrupted=0

# A caller-supplied workdir is the caller's to keep. One we made ourselves is
# removed on exit ONLY if the run was completely clean -- if anything needs
# looking at, the varfile and the plan log are the only way to look at it, and
# deleting them is how a reproducible failure becomes an unreproducible one.
#
# Absolute, because every plan runs from inside the component's directory and a
# relative workdir would resolve against that instead.
#
# The sweep deletes and rebuilds its mirror inside the workdir, so it has to
# know the workdir is its own: PLAN_SWEEP_WORKDIR=$HOME, or a project directory
# that happens to have a mirror/ subdirectory, would otherwise lose it. A
# workdir the sweep has used carries a marker file. An empty directory is
# claimed and marked; a non-empty one without the marker is refused.
WORK_MARKER=.plan-sweep-workdir
if [ -n "${PLAN_SWEEP_WORKDIR:-}" ]; then
  mkdir -p "$PLAN_SWEEP_WORKDIR" || exit 1
  WORK="$(cd "$PLAN_SWEEP_WORKDIR" && pwd)" || exit 1
  KEEP_WORK=1
  if [ ! -e "$WORK/$WORK_MARKER" ] && [ -n "$(ls -A "$WORK")" ]; then
    printf '%s\n' "error: PLAN_SWEEP_WORKDIR=$WORK is not empty and was not created by" \
      "       plan-sweep (no $WORK_MARKER in it). The sweep deletes and rebuilds" \
      "       files there, so it will not use a directory it does not own. Point it" \
      "       at an empty or new directory." >&2
    exit 2
  fi
else
  WORK="$(mktemp -d)" || exit 1
  KEEP_WORK=0
fi
: >"$WORK/$WORK_MARKER" || exit 2

cleanup() {
  [ "$KEEP_WORK" = 1 ] && return 0
  [ "$interrupted" = 0 ] && [ "$fail" = 0 ] && [ "$errored" = 0 ] &&
    [ "$unattributable" = 0 ] && [ "$inconclusive" = 0 ] && [ "$skip" = 0 ] &&
    rm -rf "$WORK"
  return 0
}

# A signal handler that returns resumes the script: Ctrl-C used to stop only
# the plan in flight, the loop moved on to the next pair, and the interrupted
# pair -- which never printed a diagnostic -- read as a pass. Exit instead. The
# EXIT trap still runs, and keeps the workdir because the run is incomplete.
on_signal() {
  interrupted=1
  printf '\ninterrupted; varfiles and plan logs kept in %s\n' "$WORK" >&2
  exit "$1"
}
trap cleanup EXIT
trap 'on_signal 130' INT
trap 'on_signal 143' TERM

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

# ---------------------------------------------------------------------------
# A private copy of the components, planned instead of the working tree.
#
# The working tree carries files git ignores and Atmos generates --
# backend.tf.json, *.tfvars.json and, from the emulator lanes,
# providers_override.tf.json with test keys and skip_credentials_validation.
# Terraform merges every *_override.tf.json it finds, so on a developer's
# machine those leftovers quietly turned credential stops into full plans:
# the same commit reached six more PASSes and six more ERRORs there than in
# CI's fresh checkout. And a sweep has no business writing .terraform/ into
# the repository.
#
# `git ls-files -co --exclude-standard` is the working tree minus what git
# ignores: uncommitted edits are swept, generated files never are. Tracked
# files deleted in the working tree are left out rather than failing the copy.
#
# The mirror is rebuilt from nothing on every run. A caller-supplied workdir
# outlives the run, and tar only ever adds: a file deleted from the repository,
# a .terraform/ directory and its lock file would all survive into the next
# sweep and be planned as if they were still the working tree. Deleting it is
# safe because the workdir is marked as the sweep's own (see above).
# ---------------------------------------------------------------------------
MIRROR="$WORK/mirror"
[ -e "$WORK/$WORK_MARKER" ] || exit 2
rm -rf "$MIRROR" || exit 2
mkdir -p "$MIRROR" || exit 2
git ls-files -z -co --exclude-standard -- components/terraform |
  while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done |
  tar --null -T - -cf - | tar -xf - -C "$MIRROR"
# Every stage but the filter has to succeed. The filter's status is that of its
# last test, which is 1 whenever the last file listed was deleted in the
# working tree, so it says nothing. A git or tar that failed half way leaves a
# mirror with components missing, and the check below only notices one that is
# missing all of them.
mirror_rc=("${PIPESTATUS[@]}")
if [ "${mirror_rc[0]}" -ne 0 ] || [ "${mirror_rc[2]}" -ne 0 ] || [ "${mirror_rc[3]}" -ne 0 ]; then
  printf '%s\n' "error: copying components/terraform into $MIRROR failed" \
    "       (git ls-files, tar create, tar extract exited ${mirror_rc[0]}, ${mirror_rc[2]}, ${mirror_rc[3]})." >&2
  exit 2
fi
if ! ls -d "$MIRROR"/components/terraform/*/ >/dev/null 2>&1; then
  printf '%s\n' "error: could not copy components/terraform into $MIRROR" >&2
  exit 2
fi

# Untracked files are swept on purpose, so that uncommitted work is checked
# before it is committed. An untracked override file, though, is exactly the
# contamination the mirror exists to keep out: Terraform merges it into every
# plan of that component, and it is usually a leftover rather than a change
# anyone means to commit. It stays in -- it may be deliberate -- but it is
# named, so that a verdict it changed is not mistaken for the committed code's.
stray_overrides=$(git ls-files -o --exclude-standard -- components/terraform |
  grep -E '(^|/)([^/]*_)?override\.tf(\.json)?$')
if [ -n "$stray_overrides" ]; then
  printf '%s\n' "warning: untracked override files are included in the sweep, and Terraform" \
    "         merges each into every plan of its component:" >&2
  printf '%s\n' "$stray_overrides" | sed 's/^/           /' >&2
fi

# In the mirror only, let each plan past the AWS provider's own credential
# check. Without this the provider validates the pinned key when it is
# configured, STS refuses it, and Terraform stops before planning a single
# resource -- so lifecycle preconditions (secretsmanager's KMS rule, for one)
# were never evaluated in CI. These are the flags the emulator lanes already
# set. Every API call still carries the unissued key and is refused, so a
# component that reads a data source stops at its first one, as before.
#
# Which components get it is decided by what they use, not by parsing their
# provider blocks: Terraform 1.16 accepts a default provider "aws" override
# even where the configuration declares only an aliased block, or none at all.
# It is still left out of a component that never touches AWS
# (eks-backend-services): there it would not break init, but it would make
# Terraform download the AWS provider for nothing.
#
# An override never reaches an ALIASED provider, so each alias gets its own
# block; without one, backup's replica and dns's dns_account would still
# validate the unissued key. Aliases are read one file at a time, from the
# files as arguments rather than concatenated: several lack a final newline,
# and cat would glue one file's closing brace onto the next file's provider line.
for d in "$MIRROR"/components/terraform/*/; do
  ls "$d"*.tf >/dev/null 2>&1 || continue
  grep -Eqs 'hashicorp/aws|^[[:space:]]*(resource|data|ephemeral)[[:space:]]+"aws_' "$d"*.tf || continue
  aliases=$(awk '
    FNR == 1                                  { inb = 0 }
    /^provider[[:space:]]+"aws"[[:space:]]*[{]/ { inb = 1; next }
    inb && /^[}]/                             { inb = 0; next }
    inb && /^[[:space:]]*alias[[:space:]]*=/  {
      a = $0
      sub(/^[^"]*"/, "", a)
      sub(/".*$/, "", a)
      if (a != "" && !seen[a]++) print a
    }
  ' "$d"*.tf)
  {
    for a in "" $aliases; do
      printf '%s\n' 'provider "aws" {'
      [ -n "$a" ] && printf '  alias                       = "%s"\n' "$a"
      printf '%s\n' '  skip_credentials_validation = true' \
        '  skip_requesting_account_id  = true' \
        '  skip_metadata_api_check     = true' '}'
    done
  } >"${d}plan_sweep_override.tf"
done

# A fresh mirror means a fresh `terraform init` in every component on every
# run; without a shared cache that is one AWS provider download apiece.
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/plan-sweep/terraform-plugins}"
mkdir -p "$TF_PLUGIN_CACHE_DIR" || exit 2

# ---------------------------------------------------------------------------
# A stand-in for the aws CLI, on PATH for the plans only.
#
# external-secrets' kubernetes and helm providers authenticate with an exec
# plugin that runs `aws eks get-token`, and so do eks-addons' (provider.tf), so
# this covers both components. A developer's machine has the aws CLI
# and CI's atmos image does not, so the same pair used to stop at "executable
# aws not found" in CI and at the synthetic host's DNS failure on a laptop --
# two different verdicts for one commit. With this first on PATH both get the
# same static token and both stop at the DNS failure, which EXPECTED_RE knows.
#
# It answers `eks get-token` and nothing else. Anything more would mean some
# plan wants the real CLI, and the real CLI must never run here: it would read
# whatever credentials the machine has, which is what pinning them above exists
# to prevent. The apiVersion is echoed from the request client-go sends in
# KUBERNETES_EXEC_INFO, so it matches whichever version the exec block names;
# v1beta1, external-secrets' version, is only the fallback.
# ---------------------------------------------------------------------------
AWS_SHIM_DIR="$WORK/aws-shim"
mkdir -p "$AWS_SHIM_DIR" || exit 2
#
# The subcommand is looked for anywhere in the arguments, not at $1, because
# global options may come first (Cloud Posse's provider-helm.tf passes
# `--profile NAME eks get-token ...`). --cluster-name is required, as the real
# CLI requires it, so that a malformed exec block still fails here instead of
# being handed a token it would never get.
cat >"$AWS_SHIM_DIR/aws" <<'EOF'
#!/bin/sh
prev="" get_token=0 cluster=""
for a in "$@"; do
  [ "$prev" = eks ] && [ "$a" = get-token ] && get_token=1
  [ "$prev" = --cluster-name ] && cluster=$a
  case "$a" in --cluster-name=*) cluster=${a#--cluster-name=} ;; esac
  prev=$a
done
if [ "$get_token" = 1 ]; then
  if [ -z "$cluster" ]; then
    echo "aws: error: the following arguments are required: --cluster-name" >&2
    exit 252
  fi
  api=$(printf '%s' "${KUBERNETES_EXEC_INFO:-}" |
    sed -n 's/.*"apiVersion":"\(client\.authentication\.k8s\.io\/v[0-9a-z]*\)".*/\1/p')
  printf '{"kind":"ExecCredential","apiVersion":"%s","spec":{},"status":{"expirationTimestamp":"2099-01-01T00:00:00Z","token":"k8s-aws-v1.plan-sweep-synthetic"}}\n' \
    "${api:-client.authentication.k8s.io/v1beta1}"
  exit 0
fi
echo "plan-sweep: the aws CLI stand-in only answers 'eks get-token'; refusing 'aws $*'." >&2
exit 1
EOF
chmod 755 "$AWS_SHIM_DIR/aws" || exit 2

SYNTH_CA_CERT="$(gen_ca_cert)" || SYNTH_CA_CERT=""
if [ -z "$SYNTH_CA_CERT" ]; then
  # Better to drop the variable and report INCONCLUSIVE than to substitute
  # something the kubernetes provider will reject: that would be this script
  # manufacturing a failure and reporting it as the component's.
  printf '%s\n' "warning: could not generate a synthetic CA (no usable mkcert or openssl)." >&2
  printf '%s\n' "         cluster_ca_certificate will be dropped rather than guessed." >&2
fi
export PLAN_SWEEP_CA_CERT="$SYNTH_CA_CERT"

# The EKS endpoint the varfile builder hands out for `host`. Defined once,
# because the classifier below has to recognise it: a kubernetes provider that
# needs the API server at plan time (kubernetes_manifest does) can never reach
# a host this script invented, and that failure is ours, not the component's.
SYNTH_EKS_HOST=EXAMPLE0123456789.gr7.eu-west-2.eks.amazonaws.com
export PLAN_SWEEP_EKS_HOST="$SYNTH_EKS_HOST"

# ---------------------------------------------------------------------------
# The varfile builder, scripts/plan_sweep_varfile.py. It used to be a
# heredoc here, and before that a `python3 -c "..."` inside a DOUBLE-quoted
# shell string where every regex needed its '$' escaped. It moved out when it
# grew an HCL reader (scripts/plan_sweep_hcl.py) and a self-test of its own;
# its header says what it does.
#
# The short version: an Atmos !terraform.state reference is the target's
# OUTPUTS run through a yq expression, with a '.' prepended and several
# results joined into one string. The builder synthesizes those outputs in
# the shapes the target component declares and runs the reference through
# the same steps. Before, it guessed a value from the consuming variable's
# name and never looked at the expression -- which is how #166, a map output
# wired into a list(string) variable, passed this sweep.
#
# Its self-test checks the evaluation against results recorded from real
# Atmos, and runs against this run's mirror, so an edit to acm, vpc or kms
# that the builder can no longer read fails here, not as ninety fallbacks.
# ---------------------------------------------------------------------------
# Not under scripts/lib/: .gitignore ignores every lib/ directory, and a
# builder that exists only on the machine that wrote it is a CI run that
# cannot start.
SYNTH_PY="$REPO/scripts/plan_sweep_varfile.py"
# -B: the builder imports plan_sweep_hcl.py, and a sweep has no business
# writing __pycache__/ into the repository (see the mirror, above).
if ! python3 -B "$SYNTH_PY" --self-test "$MIRROR/components/terraform" "$WORK/varfile-selftest" \
  2>"$WORK/varfile-selftest.err"; then
  KEEP_WORK=1
  printf '%s\n' "error: the varfile builder failed its self-test, so the values it builds" \
    "       for !terraform.state references cannot be trusted:" >&2
  sed 's/^/         /' "$WORK/varfile-selftest.err" >&2
  exit 2
fi

# One `atmos describe stacks` per stack, for the builder to resolve each
# reference's instance to its component. --process-functions=false, like every
# describe here: without it Atmos resolves the functions itself and needs the
# live state this sweep has no credentials for.
STACKS_DIR="$WORK/stacks"
rm -rf "$STACKS_DIR" && mkdir -p "$STACKS_DIR" || exit 2

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
#
# The box characters are multibyte, and CI's awk is mawk, which matches BYTES.
# To it [│|] was a class of four bytes, so sub() removed the first byte of the
# bar and left two behind; no summary then began with "Error: ", every
# diagnostic was discarded, and every pair in CI reported PASS -- ten real
# defects included, on a commit that reported them on macOS. ├─* likewise
# repeated only the last byte of the dash. Keep multibyte characters out of
# bracket expressions and group them before repeating; the self-test below
# fails the run if a byte-wise and a character-wise awk ever disagree again.
# ---------------------------------------------------------------------------
fold_diags() {
  sed 's/\x1b\[[0-9;]*m//g' "$1" | awk '
    /^╷/ { s=""; ctx=""; b=""; inblk=1; next }
    /^╵/ { if (inblk && s != "") print s "\t" ctx "\t" b; inblk=0; s=""; ctx=""; b=""; next }
    inblk {
      l = $0
      sub(/^(│|[|])/, "", l)
      sub(/^[ \t]+/, "", l)
      sub(/[ \t]+$/, "", l)
      if (l == "") next
      # Inside a failed condition Terraform draws a SECOND box listing the
      # values behind it. The rule line is pure border and carries nothing;
      # the inner bar prefixes the values, which do matter. Drop the first,
      # unwrap the second, or both end up in the one-line detail ahead of the
      # sentence that says what is wrong.
      if (l ~ /^├(─)*$/) next
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
#
# With the credential check off, the refusal comes from whichever service the
# first data source calls, and each words it its own way: STS and IAM say
# InvalidClientTokenId, EC2 AuthFailure, S3 InvalidAccessKeyId, and the JSON
# APIs (KMS, Secrets Manager, Lambda, ...) UnrecognizedClientException.
#
# The last alternative is the synthetic EKS host failing to resolve -- and only
# that host, so a kubernetes error against anything else is still an ERROR.
# Its dots are bracketed rather than escaped: awk -v would eat the backslash.
# Go words the failure per platform: macOS's resolver says "lookup HOST: no
# such host", Linux's names the server it asked, "lookup HOST on
# 192.168.65.7:53: no such host". Matching only the first had CI report ERROR
# for the external-secrets pairs that PASSed on a laptop.
EXPECTED_RE='InvalidClientTokenId|UnrecognizedClientException|InvalidAccessKeyId|no valid credential sources|AuthFailure|ExpiredToken'
EXPECTED_RE="$EXPECTED_RE|lookup ${SYNTH_EKS_HOST//./[.]}( on [^ ]+)?: no such host"

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

# Every plan this script runs -- the self-test's and the sweep's -- takes these
# arguments and no others, so the self-test always reads the same format the
# sweep does. -no-color, for one, drops the diagnostic box entirely.
PLAN_ARGS=(-input=false)

# The parser IS the gate: every verdict is derived from what it extracts, so
# when it silently extracts nothing, every pair reads as PASS. Before trusting
# it with a real plan, feed it one validation failure -- inner value box
# included -- one credential stop, and the synthetic host's DNS failure in
# both Linux's and macOS's wording, and refuse to run unless all four come
# back classified, with the detail intact. Both DNS forms are here because
# each platform only ever produces its own: a regex that only matched the
# Mac's passed every local run and failed only in CI.
selftest="$WORK/parser-selftest.txt"
cat >"$selftest" <<'EOF'
╷
│ Error: Invalid value for variable
│
│   on variables.tf line 3, in variable "x":
│    3:   validation {
│     ├────────────────
│     │ var.x is "bad"
│
│ x must be good.
╵
╷
│ Error: Retrieving AWS account details
│
│ api error InvalidClientTokenId: The security token included in the request is invalid.
╵
EOF
# Unquoted, unlike the one above, so that the host follows the constant. Linux
# first, its detail wrapped mid-message as Terraform wraps it; then macOS's
# shorter form, so that an edit to the regex cannot keep one and lose the other.
cat >>"$selftest" <<EOF
╷
│ Error: Invalid configuration for API client
│
│   with kubernetes_manifest.cluster_secret_store,
│   on main.tf line 20, in resource "kubernetes_manifest" "cluster_secret_store":
│   20: resource "kubernetes_manifest" "cluster_secret_store" {
│
│ Get "https://${SYNTH_EKS_HOST}/apis": dial tcp: lookup ${SYNTH_EKS_HOST} on
│ 192.168.65.7:53: no such host
╵
╷
│ Error: Invalid configuration for API client
│
│   with kubernetes_manifest.certificate_secret_store,
│   on main.tf line 40, in resource "kubernetes_manifest" "certificate_secret_store":
│   40: resource "kubernetes_manifest" "certificate_secret_store" {
│
│ Get "https://${SYNTH_EKS_HOST}/apis": dial tcp: lookup ${SYNTH_EKS_HOST}: no
│ such host
╵
EOF
selftest_want='INVALID|var.x is "bad" x must be good.
EXPECTED|api error InvalidClientTokenId: The security token included in the request is invalid.
EXPECTED|with kubernetes_manifest.cluster_secret_store, Get "https://'"$SYNTH_EKS_HOST"'/apis": dial tcp: lookup '"$SYNTH_EKS_HOST"' on 192.168.65.7:53: no such host
EXPECTED|with kubernetes_manifest.certificate_secret_store, Get "https://'"$SYNTH_EKS_HOST"'/apis": dial tcp: lookup '"$SYNTH_EKS_HOST"': no such host'
selftest_got=$(fold_diags "$selftest" | classify_diags | awk -F'\t' '{ print $1 "|" $4 }')
if [ "$selftest_got" != "$selftest_want" ]; then
  KEEP_WORK=1
  printf '%s\n' "error: the diagnostic parser failed its self-test, so every verdict would be" >&2
  printf '%s\n' "       wrong. Expected:" "$selftest_want" "       Got:" "$selftest_got" >&2
  exit 2
fi

# The canned sample proves the regexes, not the format: that belongs to
# Terraform and to the flags this script passes, and a change to either once
# turned every pair into an ERROR while the sample above still passed. So also
# run a real plan, with the sweep's own PLAN_ARGS, on a module that breaks one
# validation rule and one type constraint -- no providers, so no init -- and
# require both to come back INVALID.
st_mod="$WORK/parser-selftest-module"
mkdir -p "$st_mod"
cat >"$st_mod/main.tf" <<'EOF'
variable "x" {
  type = string
  validation {
    condition     = var.x == "good"
    error_message = "x must be good."
  }
}

variable "y" {
  type = map(object({ p = number }))
}
EOF
printf '%s\n' '{"x":"bad","y":{"a":{"p":1},"b":{"q":2}}}' >"$st_mod/vars.json"
(cd "$st_mod" && terraform plan "${PLAN_ARGS[@]}" -var-file=vars.json >plan.txt 2>&1)
st_rc=$?
st_got=$(fold_diags "$st_mod/plan.txt" | classify_diags | cut -f1 | tr '\n' ' ')
if [ "$st_rc" -eq 0 ] || [ "$st_got" != "INVALID INVALID " ]; then
  KEEP_WORK=1
  printf '%s\n' "error: the parser cannot read this terraform's own plan output (exit $st_rc," >&2
  printf '%s\n' "       classified as '${st_got}', expected 'INVALID INVALID '), so every" >&2
  printf '%s\n' "       verdict would be wrong. See $st_mod/plan.txt" >&2
  exit 2
fi

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
#
# No .terraform.lock.hcl is committed, and since Terraform 1.4 init will not
# install a provider from TF_PLUGIN_CACHE_DIR without a lock entry to check it
# against -- so every fresh mirror downloaded every provider again. Letting the
# cache through is safe here and only here: the lock files these inits write
# live in the mirror and are thrown away with it, never committed, so there is
# no lock file for a cached provider to break.
init_failed=""
for d in "$MIRROR"/components/terraform/*/; do
  comp="$(basename "$d")"
  case "$comp" in _*) continue ;; esac
  ls "$d"*.tf >/dev/null 2>&1 || continue
  if ! (cd "$d" && TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true \
    terraform init -backend=false -input=false) \
    >"$WORK/init__$comp.log" 2>&1; then
    init_failed="$init_failed $comp"
  fi
done

for s in $STACKS; do
  # `atmos list components` emits TAB-separated "<component>\t<type>\t<count>".
  # Splitting on whitespace yields three tokens per line and invents components.
  #
  # Its failure used to be discarded along with its stderr: a mistyped stack
  # listed nothing, the loop never ran, and the run exited 0 having planned
  # nothing. A stack with no terraform components is an error -- and so is a
  # column layout this script no longer recognises, which filters to the same
  # empty list.
  listed=$(atmos list components -s "$s" 2>"$WORK/list__$s.err")
  comps=$(printf '%s\n' "$listed" | awk -F'\t' '$2 == "terraform" { print $1 }')
  if [ -z "$comps" ]; then
    printf '%-24s %-26s %s\n' "$s" "-" "ERROR no terraform components listed"
    head -3 "$WORK/list__$s.err" | cut -c1-160 | sed 's/^/        /'
    errored=$((errored + 1))
    continue
  fi

  # Without the stack's map the builder cannot resolve a single reference, and
  # guessing all of them by variable name is the blind spot this map exists to
  # close. Better one loud ERROR than a stack of quietly weaker PASSes.
  if ! atmos describe stacks --process-functions=false --format json -s "$s" \
    >"$STACKS_DIR/$s.json" 2>"$STACKS_DIR/$s.json.err"; then
    rm -f "$STACKS_DIR/$s.json"
    printf '%-24s %-26s %s\n' "$s" "-" "ERROR describe stacks failed"
    head -3 "$STACKS_DIR/$s.json.err" | cut -c1-160 | sed 's/^/        /'
    errored=$((errored + 1))
    continue
  fi

  for c in $comps; do
    tag="${s}__$(printf '%s' "$c" | tr / _)"
    vf="$WORK/$tag.json"
    desc="$WORK/$tag.describe.json"

    # The describe has to happen BEFORE the directory is resolved: it is the
    # only thing that knows which terraform component this instance maps to.
    #
    # Two steps, each keeping its own stderr. They used to share one pipe whose
    # only message was "describe failed" -- even when it was the varfile
    # builder that failed, printing its traceback into the middle of the table.
    if ! atmos describe component "$c" -s "$s" --process-functions=false --format json \
      >"$desc" 2>"$WORK/$tag.describe.err"; then
      printf '%-24s %-26s %s\n' "$s" "$c" "SKIP describe failed"
      head -2 "$WORK/$tag.describe.err" | cut -c1-160 | sed 's/^/        /'
      skip=$((skip + 1))
      continue
    fi
    if ! meta=$(python3 -B "$SYNTH_PY" "$vf" "$s" "$STACKS_DIR" "$MIRROR/components/terraform" \
      <"$desc" 2>"$WORK/$tag.build.err"); then
      printf '%-24s %-26s %s\n' "$s" "$c" "SKIP varfile build failed"
      tail -2 "$WORK/$tag.build.err" | cut -c1-160 | sed 's/^/        /'
      skip=$((skip + 1))
      continue
    fi

    comp=$(printf '%s\n' "$meta" | sed -n 1p)
    dropped=$(printf '%s\n' "$meta" | sed -n 2p)
    ref_defects=$(printf '%s\n' "$meta" | sed -n 3p)
    ref_stale=$(printf '%s\n' "$meta" | sed -n 5p)
    read -r n_shaped n_fallback n_dropped n_oguess n_odrop <<<"$(printf '%s\n' "$meta" | sed -n 4p)"
    refs_shaped=$((refs_shaped + ${n_shaped:-0}))
    refs_fallback=$((refs_fallback + ${n_fallback:-0}))
    refs_dropped=$((refs_dropped + ${n_dropped:-0}))
    other_guessed=$((other_guessed + ${n_oguess:-0}))
    other_dropped=$((other_dropped + ${n_odrop:-0}))
    [ -n "$comp" ] || comp="${c%%/*}"

    # An output the target does not declare, read behind a '//' default:
    # Atmos returns the default, so the pair is planned with it, but the
    # reference points at nothing and the owner wants it seen. Listed, counted
    # in the summary, never failing the run; the pair's own verdict follows.
    if [ -n "$ref_stale" ]; then
      n=$(printf '%s\n' "$ref_stale" | tr '\t' '\n' | grep -c .)
      refs_stale=$((refs_stale + n))
      printf '%-24s %-26s STALE %s !terraform reference(s) whose // default always applies (warning)\n' \
        "$s" "$c" "$n"
      printf '%s\n' "$ref_stale" | tr '\t' '\n' | cut -c1-220 | sed 's/^/        /'
    fi

    # A reference that is broken whatever the state holds: a stack or
    # instance that is not there, arguments Atmos cannot parse, an expression
    # yq rejects -- Atmos stops -- or an output the component does not declare,
    # read with no '//' default, which reads null from S3.
    # The stack's defect, found before any plan. Not planned: the varfile
    # lacks the broken values, and whatever the plan said about that would be
    # this script's damage, reported on top of the real finding.
    if [ -n "$ref_defects" ]; then
      n=$(printf '%s\n' "$ref_defects" | tr '\t' '\n' | grep -c .)
      printf '%-24s %-26s FAIL %s broken !terraform reference(s), not planned\n' "$s" "$c" "$n"
      printf '%s\n' "$ref_defects" | tr '\t' '\n' | cut -c1-220 | sed 's/^/        /'
      fail=$((fail + 1))
      continue
    fi
    dir="$MIRROR/components/terraform/$comp"

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
    swept=$((swept + 1))
    (cd "$dir" && PATH="$AWS_SHIM_DIR:$PATH" \
      terraform plan "${PLAN_ARGS[@]}" -var-file="$vf" >"$out" 2>&1)
    rc=$?
    fold_diags "$out" | classify_diags >"$cls"

    invalid=$(grep -c '^INVALID' "$cls")
    missing=$(grep -c '^MISSING' "$cls")
    other=$(grep -c '^OTHER' "$cls")
    expected=$(grep -c '^EXPECTED' "$cls")

    how="stopped at an expected refusal"
    [ "$rc" -eq 0 ] && how="full plan"

    # Every verdict below is derived from diagnostics, so a plan that failed
    # without one this script could read -- a crash, a kill, a parser that no
    # longer understands the output -- used to fall through all of them to
    # PASS. An exit status that no diagnostic accounts for is an ERROR.
    if [ "$rc" -ne 0 ] && [ $((invalid + missing + other + expected)) -eq 0 ]; then
      printf '%-24s %-26s ERROR plan exited %s with no readable diagnostic\n' "$s" "$c" "$rc"
      grep -v '^[[:space:]]*$' "$out" | tail -3 | cut -c1-160 | sed 's/^/        /'
      errored=$((errored + 1))

    # An unsynthesizable Atmos function was dropped, so any failure here may be
    # ours rather than the component's -- this script cannot tell the two apart.
    # Anything other than a clean plan is UNATTRIBUTABLE and is printed in full,
    # dropped variables first: the drop is usually in a variable the error never
    # names, so a bare count left the reader unable to rule our own damage in or
    # out, and a real defect could hide behind it.
    elif [ "$ndropped" -gt 0 ] &&
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
      printf '%-24s %-26s PASS (%s; dropped: %s)\n' "$s" "$c" "$how" "$dropped"
      pass=$((pass + 1))
      [ "$rc" -eq 0 ] && pass_full=$((pass_full + 1))
    else
      printf '%-24s %-26s PASS (%s)\n' "$s" "$c" "$how"
      pass=$((pass + 1))
      [ "$rc" -eq 0 ] && pass_full=$((pass_full + 1))
    fi
  done
done

printf '%s\n' "-------------------------------------------------------------------"
printf 'PASS %s   FAIL %s   ERROR %s   UNATTRIBUTABLE %s   INCONCLUSIVE %s   SKIP %s\n' \
  "$pass" "$fail" "$errored" "$unattributable" "$inconclusive" "$skip"
printf '  of the passes: %s planned in full, %s stopped at an expected refusal\n' \
  "$pass_full" "$((pass - pass_full))"
# How much of the sweep rests on the target's real output shape, and how much
# still on a guess from the variable's name -- the number to watch shrink.
printf '  !terraform references: %s output-shaped, %s guessed by variable name, %s dropped\n' \
  "$refs_shaped" "$refs_fallback" "$refs_dropped"
printf '  stale !terraform references (warning, not failing): %s\n' "$refs_stale"
printf '  other functions (!env, !store, ...): %s guessed by variable name, %s dropped\n' \
  "$other_guessed" "$other_dropped"

if [ "$KEEP_WORK" = 0 ] && [ "$fail" = 0 ] && [ "$errored" = 0 ] &&
  [ "$unattributable" = 0 ] && [ "$inconclusive" = 0 ] && [ "$skip" = 0 ]; then
  printf 'varfiles and plan logs: %s (removed: nothing to inspect)\n' "$WORK"
else
  printf 'varfiles and plan logs: %s\n' "$WORK"
fi

status=0
if [ "$swept" -eq 0 ]; then
  printf '\n%s\n' "NOTHING WAS PLANNED: no stack/component pair reached terraform plan."
  status=1
fi
if [ "$fail" -gt 0 ] || [ "$errored" -gt 0 ]; then
  printf '\n%s\n' "FAILING pairs cannot plan in their own stack."
  status=1
fi
if [ "$skip" -gt 0 ]; then
  printf '\n%s\n' "SKIPPED pairs were never planned, so this run checked nothing about them."
  status=1
fi
exit "$status"

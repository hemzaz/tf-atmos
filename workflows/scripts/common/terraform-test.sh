#!/bin/sh
# Run `terraform test` for every component under components/terraform/ that has
# a tests/ directory, or for the component names given as arguments.
#
# Usage:
#   workflows/scripts/common/terraform-test.sh [component...]
#
#   workflows/scripts/common/terraform-test.sh securitygroup
#   workflows/scripts/common/terraform-test.sh              # every component with a tests/ dir
#
# Used directly by the "Terraform tests" job in
# .github/workflows/terraform-ci.yml, and by `atmos workflow terraform-test`
# (workflows/validate-enhanced.yaml) for a local full run.
#
# A named component with no tests/ directory is skipped, not failed: some
# components (idp-platform) cannot be tested because mock_provider rejects
# their ephemeral resources.
#
# POSIX sh, no bashisms: this runs unmodified inside ghcr.io/cloudposse/atmos,
# whose default awk is mawk (not gawk) -- the summary table below sticks to
# plain printf/awk field splitting, nothing gawk-specific.
#
# terraform must already be on PATH (the CI job installs it from the Atmos
# toolchain; a local run picks up whatever `terraform` resolves to).

set -eu

repo_root=$(cd "$(dirname "$0")/../../.." && pwd)
components_dir="$repo_root/components/terraform"

# Some tests use the real aws provider (see components/terraform/kms/tests)
# with dummy credentials, never real ones -- default them so the script also
# works for a developer who has not exported anything.
: "${AWS_ACCESS_KEY_ID:=test}"
: "${AWS_SECRET_ACCESS_KEY:=test}"
: "${AWS_REGION:=eu-west-2}"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION

if [ -n "${TF_PLUGIN_CACHE_DIR:-}" ]; then
  mkdir -p "$TF_PLUGIN_CACHE_DIR"
  export TF_PLUGIN_CACHE_DIR
fi

if [ "$#" -gt 0 ]; then
  components="$*"
else
  components=""
  for dir in "$components_dir"/*/; do
    component=$(basename "$dir")
    [ "$component" = "_library" ] && continue
    [ -d "${dir}tests" ] || continue
    components="$components $component"
  done
fi

tmp_log=$(mktemp)
trap 'rm -f "$tmp_log"' EXIT

overall_status=0
tested=0
rows=""

for component in $components; do
  dir="$components_dir/$component"

  if [ ! -d "$dir" ]; then
    echo "terraform-test: no such component directory: $component" >&2
    overall_status=1
    continue
  fi

  if [ ! -d "$dir/tests" ]; then
    echo "terraform-test: skipping $component (no tests/ directory)"
    continue
  fi

  tested=$((tested + 1))
  echo "== $component =="

  if ! terraform -chdir="$dir" init -backend=false -input=false >"$tmp_log" 2>&1; then
    cat "$tmp_log"
    echo "terraform-test: init failed for $component" >&2
    rows="$rows
$component	ERROR	ERROR"
    overall_status=1
    continue
  fi

  if terraform -chdir="$dir" test -no-color >"$tmp_log" 2>&1; then
    :
  else
    overall_status=1
  fi
  cat "$tmp_log"

  # terraform test's final line reads "Success! N passed, M failed." or
  # "Failure! N passed, M failed[, K skipped]." -- pull the two counts out of
  # it rather than counting per-run lines, so nested for_each runs never throw
  # the tally off.
  summary_line=$(grep -E '^(Success|Failure)! [0-9]+ passed, [0-9]+ failed' "$tmp_log" | tail -1)
  passed=$(printf '%s\n' "$summary_line" | sed -n 's/^[A-Za-z]*! \([0-9]*\) passed.*/\1/p')
  failed=$(printf '%s\n' "$summary_line" | sed -n 's/.*passed, \([0-9]*\) failed.*/\1/p')
  passed=${passed:-0}
  failed=${failed:-0}
  rows="$rows
$component	$passed	$failed"
done

echo
echo "Terraform test summary:"
{
  printf 'COMPONENT\tPASSED\tFAILED\n'
  printf '%s\n' "$rows" | sed '/^$/d'
} | awk -F'\t' '{printf "%-24s %8s %8s\n", $1, $2, $3}'

if [ "$tested" -eq 0 ]; then
  echo "terraform-test: no components with a tests/ directory were run"
fi

exit "$overall_status"

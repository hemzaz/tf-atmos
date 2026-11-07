#!/bin/sh
# `terraform init -backend=false -lockfile=readonly` + `terraform validate` for
# every root module under components/terraform/ (a directory with *.tf files),
# $TF_VALIDATE_JOBS modules at a time (default: CPU count, at most 4 in CI and
# 2 elsewhere, so a laptop stays usable).
#
# Usage (validate-all's validate-root-modules step, terraform on PATH):
#   workflows/scripts/common/validate-root-modules.sh
#   TF_VALIDATE_JOBS=1 workflows/scripts/common/validate-root-modules.sh   # serial
#
# Every module runs even after another fails; each module's output is printed
# whole, in module order, after all have finished; the failed ones are listed
# and the script exits 1.
#
# TF_PLUGIN_CACHE_DIR: Terraform's plugin cache is not safe for concurrent
# installs ("not guaranteed to be concurrency safe", CLI config docs). So the
# first module that locks each provider@version not yet seen is initialised
# serially, which installs every locked provider into the cache; the parallel
# inits after it only link from the cache into their own .terraform/. If a
# locked provider is still not cached after that, the run drops to one module
# at a time rather than install it concurrently.
#
# POSIX sh and BSD/GNU-common xargs flags: runs in the Atmos image (Linux) and
# on macOS.

set -eu

repo_root=$(cd "$(dirname "$0")/../../.." && pwd)
self="$repo_root/workflows/scripts/common/validate-root-modules.sh"

# Worker: validate-root-modules.sh --module <log dir> <module dir>
if [ "${1:-}" = "--module" ]; then
  log_dir=$2
  dir=$3
  name=$(basename "$dir")
  log="$log_dir/$name.log"
  if ! terraform -chdir="$dir" init -backend=false -input=false -lockfile=readonly >"$log" 2>&1; then
    echo "terraform init failed" >>"$log"
  elif terraform -chdir="$dir" validate -no-color >"$log" 2>&1; then
    # Success is recorded, so a worker killed midway counts as failed.
    : >"$log_dir/$name.ok"
    echo "ok      $name"
    exit 0
  fi
  echo "FAILED  $name"
  exit 0
fi

jobs=${TF_VALIDATE_JOBS:-}
if [ -z "$jobs" ]; then
  cap=2
  [ -z "${CI:-}" ] || cap=4
  jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
  [ "$jobs" -gt "$cap" ] && jobs=$cap
fi
case "$jobs" in
  '' | *[!0-9]* | 0)
    echo "TF_VALIDATE_JOBS must be a positive integer, got '$jobs'" >&2
    exit 2
    ;;
esac

log_dir=$(mktemp -d)
trap 'rm -rf "$log_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cd "$repo_root"
modules=""
for dir in components/terraform/*/; do
  [ -n "$(find "$dir" -maxdepth 1 -name '*.tf' -print -quit)" ] || continue
  modules="$modules ${dir%/}"
done

if [ -n "${TF_PLUGIN_CACHE_DIR:-}" ]; then
  mkdir -p "$TF_PLUGIN_CACHE_DIR"
  export TF_PLUGIN_CACHE_DIR
  seen="$log_dir/seen"
  : >"$seen"
  for dir in $modules; do
    lock="$dir/.terraform.lock.hcl"
    [ -f "$lock" ] || continue
    locked=$(awk '/^provider "/ { p = $2; gsub(/"/, "", p) }
      /^  version *=/ { v = $3; gsub(/"/, "", v); print p "@" v }' "$lock")
    new=$(printf '%s\n' "$locked" | grep -vxF -f "$seen" || [ $? -eq 1 ])
    [ -n "$new" ] || continue
    echo "warming the plugin cache: $dir"
    # A failed init is reported by the parallel run below; its providers stay
    # unseen, so the next module locking them warms the cache instead.
    if terraform -chdir="$dir" init -backend=false -input=false -lockfile=readonly >/dev/null 2>&1; then
      printf '%s\n' "$locked" >>"$seen"
    fi
  done
  # Every locked provider@version must be cached now; parallel inits must not
  # install one concurrently into the shared cache.
  missing=$(for dir in $modules; do
    [ -f "$dir/.terraform.lock.hcl" ] || continue
    awk '/^provider "/ { p = $2; gsub(/"/, "", p) }
      /^  version *=/ { v = $3; gsub(/"/, "", v); print p "@" v }' "$dir/.terraform.lock.hcl"
  done | sort -u | grep -vxF -f "$seen" || [ $? -eq 1 ])
  if [ -n "$missing" ]; then
    echo "WARNING not cached after warm-up, validating one module at a time: $(printf '%s' "$missing" | tr '\n' ' ')" >&2
    jobs=1
  fi
fi

echo "validating root modules, $jobs at a time"
xargs_status=0
# $modules unquoted: one argument per module (directory names have no spaces).
# shellcheck disable=SC2086
printf '%s\n' $modules | xargs -n 1 -P "$jobs" sh "$self" --module "$log_dir" || xargs_status=$?

failed=""
for dir in $modules; do
  name=$(basename "$dir")
  echo "== $dir"
  cat "$log_dir/$name.log" 2>/dev/null || echo "(no output: the worker did not run)"
  if [ ! -e "$log_dir/$name.ok" ]; then
    failed="$failed $name"
  fi
done

if [ -n "$failed" ]; then
  echo "root modules failed validation:$failed"
  exit 1
fi
if [ "$xargs_status" -ne 0 ]; then
  echo "xargs exited $xargs_status" >&2
  exit 1
fi

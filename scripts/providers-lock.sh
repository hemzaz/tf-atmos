#!/usr/bin/env bash
#
# providers-lock.sh - regenerate the committed .terraform.lock.hcl of every
# Terraform root module (components/terraform/*, not _library/) for every
# platform that runs this repository.
#
# Usage (normally through the toolchain-pinned terraform):
#   atmos workflow providers-lock -f providers               # every root module
#   bash scripts/providers-lock.sh [component...]            # terraform on PATH
#
#   UPGRADE=false bash scripts/providers-lock.sh   # keep the locked versions,
#                                                  # only (re)write the hashes
#
# Environment:
#   UPGRADE   true | false. Whether to take the newest provider versions the
#             constraints allow (true) or keep each root's locked version and only
#             rewrite hashes (false). Default: true for a run over every root
#             module, false when component names are given, so a subset run never
#             upgrades providers. UPGRADE=true with components opts back in.
#   TF_PLUGIN_CACHE_DIR   provider cache (default ~/.cache/terraform-plugins).
#
# CI runs `terraform init` with -lockfile=readonly, so a provider, version or
# platform that is not in a committed lock fails init instead of floating.
# Run this after changing a required_providers block, to take newer provider
# releases within the constraints, or to add a platform, and commit the result.
#
# Why not `terraform providers lock` in every root module: it downloads every
# provider package for every platform to hash it, per module -- about 43 x 4
# AWS provider archives. Instead:
#   1. init each root from scratch (lock moved aside; local platform only,
#      through the plugin cache) to learn the newest versions its constraints
#      select and the constraints string Terraform records for it. With
#      UPGRADE=false, the previously locked version of each provider is kept;
#   2. lock ONE throwaway module that pins exactly that union, against the
#      registry, for every platform (each package downloaded once): this writes
#      the registry's zh: hashes and the h1: hashes;
#   3. write each root's lock: the union's version and hashes for each provider
#      the root uses, with the constraints string step 1's init recorded for
#      that root. (Copying the union lock and letting init prune it is not
#      enough: init keeps a satisfied entry as is, constraints included, so
#      every root would record the union's `= <version>` pin.);
#   4. prove each root: `init -lockfile=readonly` passes, and a plain `init`
#      leaves the file byte-for-byte unchanged (Terraform's own formatting).
#
# The roots must agree on one version per provider (they do: the constraints
# are the house-wide `~> 6.65`, `~> 3.9` ...). If two roots ever select
# different versions of one provider the script stops and names them.

set -euo pipefail

PLATFORMS=(linux_amd64 linux_arm64 darwin_arm64 darwin_amd64)

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO/components/terraform"

command -v terraform >/dev/null || { echo "providers-lock: terraform not on PATH" >&2; exit 2; }
command -v python3 >/dev/null || { echo "providers-lock: python3 not on PATH" >&2; exit 2; }

# The lock must be written as the CLI arguments say, never as a caller's
# TF_CLI_ARGS_init=-lockfile=readonly (CI) or an extra -upgrade says.
for v in $(compgen -e); do
  case "$v" in TF_CLI_ARGS*) unset "$v" ;; esac
done

if [ "$#" -gt 0 ]; then
  roots=("$@")
  UPGRADE="${UPGRADE:-false}"
else
  UPGRADE="${UPGRADE:-true}"
  roots=()
  for d in "$TF_DIR"/*/; do
    c="$(basename "$d")"
    [ "$c" = "_library" ] && continue
    ls "$d"*.tf >/dev/null 2>&1 || continue
    roots+=("$c")
  done
fi

WORK="$(mktemp -d)"
# A run that fails puts back every lock it had moved aside, so a failure never
# leaves a root with a half-written (local-platform-only) lock. A root that had
# no lock yet (a new component) gets a discovery lock from step 1's init; it is
# marked with $WORK/new-<root> and removed on failure rather than left behind.
cleanup() {
  local rc=$? restored=0 removed=0
  if [ "$rc" -ne 0 ]; then
    for c in "${roots[@]}"; do
      if [ -f "$WORK/prev-$c.lock.hcl" ]; then
        mv -f "$WORK/prev-$c.lock.hcl" "$TF_DIR/$c/.terraform.lock.hcl"
        restored=$((restored + 1))
      elif [ -f "$WORK/new-$c" ]; then
        rm -f "$TF_DIR/$c/.terraform.lock.hcl"
        removed=$((removed + 1))
      fi
    done
    if [ "$restored" -gt 0 ] && [ "$removed" -gt 0 ]; then
      echo "providers-lock: failed; $restored previous lock file(s) restored, $removed new lock file(s) removed" >&2
    elif [ "$restored" -gt 0 ]; then
      echo "providers-lock: failed; the previous lock files are restored" >&2
    elif [ "$removed" -gt 0 ]; then
      echo "providers-lock: failed; the new lock file(s) it had created were removed (no previous lock to restore)" >&2
    else
      echo "providers-lock: failed; no lock file had been changed" >&2
    fi
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/terraform-plugins}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

# --- 1. what each root selects ------------------------------------------------
# Discovery only, and its locks are overwritten in step 3, so letting the cache
# through without a lock entry is safe here (otherwise every root would
# download its providers again).
echo "== 1/4 selecting provider versions (${#roots[@]} roots)"
for c in "${roots[@]}"; do
  dir="$TF_DIR/$c"
  [ -d "$dir" ] || { echo "providers-lock: no such component: $c" >&2; exit 2; }
  if [ -f "$dir/.terraform.lock.hcl" ]; then
    mv "$dir/.terraform.lock.hcl" "$WORK/prev-$c.lock.hcl"
  else
    : >"$WORK/new-$c"
  fi
  if ! TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true \
    terraform -chdir="$dir" init -backend=false -input=false >"$WORK/select-$c.log" 2>&1; then
    cat "$WORK/select-$c.log" >&2
    echo "providers-lock: init failed in $c" >&2
    exit 1
  fi
  cp "$dir/.terraform.lock.hcl" "$WORK/select-$c.lock.hcl"
done

# Lock-file reading shared by steps 2 and 3: provider blocks keyed by address.
cat >"$WORK/lockfile.py" <<'PY'
import re

BLOCK = re.compile(r'^provider "([^"]+)" \{\n(.*?)^\}\n', re.S | re.M)
ATTR = re.compile(r'^  (version|constraints)\s*=\s*"([^"]*)"$', re.M)
HASHES = re.compile(r'^  hashes = \[\n(.*?)^  \]\n', re.S | re.M)
HEADER = ('# This file is maintained automatically by "terraform init".\n'
          '# Manual edits may be lost in future updates.\n')


def read(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    out = {}
    for addr, body in BLOCK.findall(text):
        attrs = dict(ATTR.findall(body))
        hashes = HASHES.search(body)
        out[addr] = {
            "version": attrs["version"],
            "constraints": attrs.get("constraints"),
            "hashes": re.findall(r'"([^"]+)"', hashes.group(1)) if hashes else [],
        }
    return out


def chosen_version(work, root, addr, selected, upgrade):
    """The newest version step 1 selected, or with UPGRADE=false the version
    the root's previous lock held (when it locked that provider at all)."""
    import os
    prev = f"{work}/prev-{root}.lock.hcl"
    if upgrade != "true" and os.path.exists(prev):
        old = read(prev).get(addr)
        if old:
            return old["version"]
    return selected


def render(blocks):
    parts = [HEADER]
    for addr in sorted(blocks):
        b = blocks[addr]
        lines = [f'provider "{addr}" {{', f'  version     = "{b["version"]}"']
        if b["constraints"] is not None:
            lines.append(f'  constraints = "{b["constraints"]}"')
        lines.append("  hashes = [")
        lines += [f'    "{h}",' for h in b["hashes"]]
        lines += ["  ]", "}"]
        parts.append("\n" + "\n".join(lines) + "\n")
    return "".join(parts)
PY

# --- 2. one registry lock for the union ---------------------------------------
echo "== 2/4 locking the union for: ${PLATFORMS[*]}"
mkdir -p "$WORK/union"
python3 - "$WORK" "$UPGRADE" "${roots[@]}" >"$WORK/union/versions.tf" <<'PY'
import sys
work, upgrade, roots = sys.argv[1], sys.argv[2], sys.argv[3:]
sys.path.insert(0, work)
import lockfile
chosen = {}
for root in roots:
    for addr, block in lockfile.read(f"{work}/select-{root}.lock.hcl").items():
        version = lockfile.chosen_version(work, root, addr, block["version"], upgrade)
        chosen.setdefault(addr, {}).setdefault(version, []).append(root)
split = {a: v for a, v in chosen.items() if len(v) > 1}
if split:
    for addr, versions in split.items():
        print(f"providers-lock: roots disagree on {addr}: "
              + "; ".join(f"{v} <- {', '.join(r)}" for v, r in versions.items()),
              file=sys.stderr)
    sys.exit(1)
print("terraform {\n  required_providers {")
for i, (addr, versions) in enumerate(sorted(chosen.items())):
    print(f'    p{i} = {{\n      source  = "{addr}"\n      version = "= {next(iter(versions))}"\n    }}')
print("  }\n}")
PY
platform_args=()
for p in "${PLATFORMS[@]}"; do platform_args+=("-platform=$p"); done
terraform -chdir="$WORK/union" providers lock "${platform_args[@]}"

# --- 3. per-root locks from the union -----------------------------------------
echo "== 3/4 writing each root's lock"
python3 - "$WORK" "$TF_DIR" "${roots[@]}" <<'PY'
import sys
work, tf_dir, roots = sys.argv[1], sys.argv[2], sys.argv[3:]
sys.path.insert(0, work)
import lockfile
union = lockfile.read(f"{work}/union/.terraform.lock.hcl")
for root in roots:
    blocks = {}
    for addr, own in lockfile.read(f"{work}/select-{root}.lock.hcl").items():
        blocks[addr] = dict(union[addr], constraints=own["constraints"])
    with open(f"{tf_dir}/{root}/.terraform.lock.hcl", "w", encoding="utf-8") as fh:
        fh.write(lockfile.render(blocks))
PY

# --- 4. prove them -------------------------------------------------------------
echo "== 4/4 checking every lock (init -lockfile=readonly, then init leaves it unchanged)"
for c in "${roots[@]}"; do
  dir="$TF_DIR/$c"
  if ! terraform -chdir="$dir" init -backend=false -input=false -lockfile=readonly \
    >"$WORK/check-$c.log" 2>&1; then
    cat "$WORK/check-$c.log" >&2
    echo "providers-lock: $c does not init with -lockfile=readonly" >&2
    exit 1
  fi
  cp "$dir/.terraform.lock.hcl" "$WORK/written-$c.lock.hcl"
  if ! terraform -chdir="$dir" init -backend=false -input=false >"$WORK/stable-$c.log" 2>&1 ||
    ! cmp -s "$dir/.terraform.lock.hcl" "$WORK/written-$c.lock.hcl"; then
    diff -u "$WORK/written-$c.lock.hcl" "$dir/.terraform.lock.hcl" >&2 || true
    echo "providers-lock: a plain init rewrites the lock of $c" >&2
    exit 1
  fi
  printf '  %-30s ok\n' "$c"
done
echo "providers-lock: ${#roots[@]} lock files written; review and commit them."

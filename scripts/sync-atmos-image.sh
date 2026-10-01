#!/usr/bin/env bash
#
# sync-atmos-image.sh - keep every workflow's Atmos container on the one pinned
# reference in .github/atmos-image/Dockerfile (tag@sha256:digest).
#
# Usage:
#   bash scripts/sync-atmos-image.sh           # rewrite the workflows to match
#   bash scripts/sync-atmos-image.sh --check   # CI: exit 1 listing any mismatch
#
# Rewrites `image: ghcr.io/cloudposse/atmos:...` in .github/workflows/*.yml and
# the `atmos-version:` input of cloudposse/github-action-setup-atmos (the tag).
# Dependabot bumps the Dockerfile; this carries the bump to the workflows.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-write}"
case "$MODE" in write | --check) ;; *) echo "usage: $0 [--check]" >&2; exit 2 ;; esac

python3 - "$REPO" "$MODE" <<'PY'
import glob, os, re, sys

repo, mode = sys.argv[1], sys.argv[2]
dockerfile = os.path.join(repo, ".github", "atmos-image", "Dockerfile")
with open(dockerfile, encoding="utf-8") as fh:
    m = re.search(r"^FROM\s+(ghcr\.io/cloudposse/atmos:([^@\s]+)@sha256:[0-9a-f]{64})\s*$", fh.read(), re.M)
if not m:
    sys.exit(f"sync-atmos-image: no `FROM ghcr.io/cloudposse/atmos:<tag>@sha256:<digest>` in {dockerfile}")
ref, tag = m.group(1), m.group(2)

image_re = re.compile(r"^(\s*image:\s*)ghcr\.io/cloudposse/atmos:\S+[ \t]*$", re.M)
version_re = re.compile(r'^(\s*atmos-version:[ \t]*)\S+[ \t]*$', re.M)
stale = []
for path in sorted(glob.glob(os.path.join(repo, ".github", "workflows", "*.yml"))):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    new = image_re.sub(lambda mm: f"{mm.group(1)}{ref}", text)
    new = version_re.sub(lambda mm: f'{mm.group(1)}"{tag}"', new)
    if new != text:
        stale.append(os.path.relpath(path, repo))
        if mode == "write":
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(new)

if mode == "--check" and stale:
    print(f"::error title=Atmos image not synced::{', '.join(stale)} do not use {ref}. "
          "Run: bash scripts/sync-atmos-image.sh")
    sys.exit(1)
print(f"sync-atmos-image: {ref} ({'updated ' + ', '.join(stale) if stale else 'all workflows match'})")
PY

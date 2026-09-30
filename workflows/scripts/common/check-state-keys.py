#!/usr/bin/env python3
"""Check that every S3-backend instance's state key stays inside its stage's prefix.

Reads `atmos describe stacks --process-functions=false --format json` on stdin.
The state backend's access roles are split by stage within one bucket with S3
object-key patterns "*/<tenant>-<stage>-*" (stacks/catalog/backend/defaults.yaml).
A state key is "<workspace_key_prefix>/<workspace>/<backend.key>", and the "*"
in those patterns spans "/", so they match exactly one stage only while, for
every instance with backend_type s3:
  - the workspace starts with its own stack's "<tenant>-<stage>-"
    (settings.context), and contains no "/";
  - backend.workspace_key_prefix contains no "/";
  - backend.key is exactly "terraform.tfstate" (every instance uses it; a key
    like "fnx-dev-x/terraform.tfstate" would put prod state under "*/fnx-dev-*").
An instance breaking any of these lands its state where another stage's role can read
or write it (or where its own cannot). Exits 1 on any violation.
"""
import json
import sys
from typing import Optional

STATE_KEY = "terraform.tfstate"


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def stage_prefix(instance: dict) -> Optional[str]:
    context = (instance.get("settings") or {}).get("context") or {}
    tenant, stage = context.get("tenant"), context.get("stage")
    return f"{tenant}-{stage}-" if tenant and stage else None


def check(stacks: dict) -> list[str]:
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        instances = (stack.get("components") or {}).get("terraform") or {}
        for name, instance in sorted(instances.items()):
            if not is_deployable(instance) or instance.get("backend_type") != "s3":
                continue
            where = f"{stack_name}: {name}"
            prefix = stage_prefix(instance)
            workspace = instance.get("workspace") or ""
            key_prefix = (instance.get("backend") or {}).get("workspace_key_prefix") or ""
            key = (instance.get("backend") or {}).get("key")
            if prefix is None:
                errors.append(f"{where} has no settings.context tenant/stage to derive its state prefix from")
            elif not workspace.startswith(prefix):
                errors.append(f"{where} workspace {workspace!r} does not start with its stage prefix {prefix!r}")
            if "/" in workspace:
                errors.append(f"{where} workspace {workspace!r} contains '/'")
            if not key_prefix:
                errors.append(f"{where} has no backend.workspace_key_prefix")
            elif "/" in key_prefix:
                errors.append(f"{where} workspace_key_prefix {key_prefix!r} contains '/'")
            if key != STATE_KEY:
                slash = " (contains '/')" if isinstance(key, str) and "/" in key else ""
                errors.append(f"{where} backend.key {key!r} is not {STATE_KEY!r}{slash}")
    return errors


def main() -> int:
    errors = check(json.load(sys.stdin))
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} state key problem(s)")
        return 1
    print(
        "every s3-backend instance's workspace starts with its stack's <tenant>-<stage>- "
        "and its workspace_key_prefix has no '/' and its backend.key is terraform.tfstate"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

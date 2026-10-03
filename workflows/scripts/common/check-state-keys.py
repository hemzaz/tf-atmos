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
or write it (or where its own cannot).

Every s3 backend also points at the one bucket's region: backend.region must equal the
region of the stack that deploys the "backend" component (backend/main, fnx-core-root),
not the stack's own, or init of a DR/EU stack fails against a region with no bucket.
Exits 1 on any violation.
"""
import json
import re
import sys
from typing import Optional

STATE_KEY = "terraform.tfstate"
BACKEND_COMPONENT = "backend"
# A template over an unset setting renders "<no value>" for both sides, which would compare equal.
AWS_REGION = re.compile(r"^[a-z]{2}(-[a-z]+)+-\d$")


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def stage_prefix(instance: dict) -> Optional[str]:
    context = (instance.get("settings") or {}).get("context") or {}
    tenant, stage = context.get("tenant"), context.get("stage")
    return f"{tenant}-{stage}-" if tenant and stage else None


def bucket_regions(stacks: dict) -> set:
    """Regions of the stacks that deploy the state bucket (the "backend" component)."""
    regions = set()
    for stack in stacks.values():
        for instance in ((stack.get("components") or {}).get("terraform") or {}).values():
            if is_deployable(instance) and instance.get("component") == BACKEND_COMPONENT:
                regions.add((instance.get("vars") or {}).get("region"))
    return regions


def check(stacks: dict) -> list[str]:
    errors = []
    regions = bucket_regions(stacks)
    if len(regions) != 1 or None in regions:
        errors.append(f"expected exactly one deployed '{BACKEND_COMPONENT}' region, found {sorted(map(str, regions))}")
    bucket_region = next(iter(regions)) if len(regions) == 1 else None
    if bucket_region is not None and not AWS_REGION.match(str(bucket_region)):
        errors.append(f"the state bucket's region {bucket_region!r} is not an AWS region (settings.tfstate.region unset?)")
        bucket_region = None
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
            region = (instance.get("backend") or {}).get("region")
            if not AWS_REGION.match(str(region)):
                errors.append(f"{where} backend.region {region!r} is not an AWS region (settings.tfstate.region unset?)")
            elif bucket_region is not None and region != bucket_region:
                errors.append(f"{where} backend.region {region!r} is not the state bucket's region {bucket_region!r}")
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
        "and its workspace_key_prefix has no '/' and its backend.key is terraform.tfstate "
        "and its backend.region is the state bucket's"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

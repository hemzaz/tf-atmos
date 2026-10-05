#!/usr/bin/env python3
"""Check that the state backend's access roles split every state key by stage.

Reads `atmos describe stacks --process-functions=false --format json` on stdin.
The state backend's access roles are split by stage within one bucket with S3
object-key patterns, an exact pair per stack, "*/<stack>/*" and "*/<stack>-*"
(stacks/catalog/backend/defaults.yaml). A state key is
"<workspace_key_prefix>/<workspace>/<backend.key>" (+ ".tflock"). This evaluates
the deployed backend component's access_roles patterns against every key, with
S3's semantics ("*" spans "/"), and requires, for every instance with
backend_type s3:
  - each of its state objects matches some role, including the role its
    backend assumes (backend.assume_role.role_arn);
  - every role that matches one of its stage's state objects matches all of them;
  - stages whose backends assume the same role (dev and staging) are matched by
    the same roles, and stages that assume different roles share no role;
  - every role matches some state object (a role reaching nothing has lost its stage).
This holds whatever the stack names look like, so it does not depend on where
the stage sits in name_template. Stage fixtures is skipped: its stacks are
never deployed and have no access role. Layout checks stay for every instance:
  - the workspace and backend.workspace_key_prefix contain no "/";
  - backend.key is exactly "terraform.tfstate" (every instance uses it).

Every s3 backend also points at the one bucket's region: backend.region must equal the
region of the stack that deploys the "backend" component (backend/main, fnx-core-root),
not the stack's own, or init of a DR/EU stack fails against a region with no bucket.
Exits 1 on any violation.
"""
import json
import os
import re
import sys
from typing import Optional

# The sibling module, also when this file is loaded by path (tests).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fixtures  # noqa: E402

STATE_KEY = "terraform.tfstate"
LOCK_SUFFIX = ".tflock"
BACKEND_COMPONENT = "backend"
# A template over an unset setting renders "<no value>" for both sides, which would compare equal.
AWS_REGION = re.compile(r"^[a-z]{2}(-[a-z]+)+-\d$")


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def stage_of(instance: dict) -> Optional[str]:
    return ((instance.get("settings") or {}).get("context") or {}).get("stage") or None


def backend_instances(stacks: dict) -> list[dict]:
    """The deployed instances of the "backend" component (the state bucket)."""
    return [
        instance
        for stack in stacks.values()
        for instance in ((stack.get("components") or {}).get("terraform") or {}).values()
        if is_deployable(instance) and instance.get("component") == BACKEND_COMPONENT
    ]


def pattern_matches(pattern: str, key: str) -> bool:
    """S3 object-key pattern match: "*" matches any run of characters, "/" included."""
    return re.fullmatch(".*".join(map(re.escape, pattern.split("*"))), key, re.DOTALL) is not None


def assumed_role_name(instance: dict) -> Optional[str]:
    arn = ((instance.get("backend") or {}).get("assume_role") or {}).get("role_arn") or ""
    return arn.rsplit(":role/", 1)[1].rsplit("/", 1)[-1] if ":role/" in arn else None


def check_layout(where: str, instance: dict, bucket_region: Optional[str]) -> list[str]:
    errors = []
    workspace = instance.get("workspace") or ""
    backend = instance.get("backend") or {}
    key_prefix = backend.get("workspace_key_prefix") or ""
    key = backend.get("key")
    if "/" in workspace:
        errors.append(f"{where} workspace {workspace!r} contains '/'")
    if not key_prefix:
        errors.append(f"{where} has no backend.workspace_key_prefix")
    elif "/" in key_prefix:
        errors.append(f"{where} workspace_key_prefix {key_prefix!r} contains '/'")
    region = backend.get("region")
    if not AWS_REGION.match(str(region)):
        errors.append(f"{where} backend.region {region!r} is not an AWS region (settings.tfstate.region unset?)")
    elif bucket_region is not None and region != bucket_region:
        errors.append(f"{where} backend.region {region!r} is not the state bucket's region {bucket_region!r}")
    if key != STATE_KEY:
        slash = " (contains '/')" if isinstance(key, str) and "/" in key else ""
        errors.append(f"{where} backend.key {key!r} is not {STATE_KEY!r}{slash}")
    return errors


def check_roles(objects: list[tuple], roles: dict) -> list[str]:
    """objects: (stage, where, object key, assumed role name). roles: access_roles by key."""
    errors = []
    names = {role.get("role_name"): name for name, role in roles.items()}
    matched_by_stage: dict = {}  # stage -> every role matching one of its objects
    assumed_by_stage: dict = {}  # stage -> the roles its backends assume (its tier)
    matched = []
    for stage, where, obj, role_name in objects:
        hits = frozenset(
            name for name, role in roles.items()
            if any(pattern_matches(p, obj) for p in role.get("object_key_patterns") or [])
        )
        matched.append((stage, where, obj, hits))
        matched_by_stage.setdefault(stage, set()).update(hits)
        assumed_by_stage.setdefault(stage, set()).add(names.get(role_name, role_name))
        if not hits:
            errors.append(f"{where} state object {obj!r} matches no access role's object_key_patterns")
        if role_name not in names:
            errors.append(f"{where} assumes role {role_name!r}, which the backend's access_roles do not define")
        elif hits and names[role_name] not in hits:
            errors.append(f"{where} state object {obj!r} is outside its own role {names[role_name]!r}'s patterns")
    for stage, where, obj, hits in matched:
        missing = matched_by_stage[stage] - hits
        if hits and missing:
            errors.append(
                f"{where} state object {obj!r} is not matched by {sorted(missing)}, "
                f"which match other stage {stage!r} state objects"
            )
    # Stages that assume the same role (dev and staging share the non-prod
    # roles) must be matched by the same roles; stages that assume different
    # roles must share none.
    stages = sorted(matched_by_stage)
    for i, a in enumerate(stages):
        for b in stages[i + 1:]:
            if assumed_by_stage[a] == assumed_by_stage[b]:
                if matched_by_stage[a] != matched_by_stage[b]:
                    errors.append(
                        f"stages {a!r} and {b!r} assume the same role but their state is matched by "
                        f"{sorted(matched_by_stage[a])} and {sorted(matched_by_stage[b])}"
                    )
            elif matched_by_stage[a] & matched_by_stage[b]:
                errors.append(
                    f"access roles {sorted(matched_by_stage[a] & matched_by_stage[b])} match state of stages "
                    f"{a!r} and {b!r}, which assume different roles"
                )
    for name in sorted(roles):
        if not any(name in hits for hits in matched_by_stage.values()):
            errors.append(f"access role {name!r} matches no state object")
    # The state object and its lock repeat the per-instance role error.
    return list(dict.fromkeys(errors))


def check(stacks: dict) -> list[str]:
    errors = []
    backends = backend_instances(stacks)
    regions = {(instance.get("vars") or {}).get("region") for instance in backends}
    if len(regions) != 1 or None in regions:
        errors.append(f"expected exactly one deployed '{BACKEND_COMPONENT}' region, found {sorted(map(str, regions))}")
    bucket_region = next(iter(regions)) if len(regions) == 1 else None
    if bucket_region is not None and not AWS_REGION.match(str(bucket_region)):
        errors.append(f"the state bucket's region {bucket_region!r} is not an AWS region (settings.tfstate.region unset?)")
        bucket_region = None
    roles = {}
    if len(backends) == 1:
        roles = (backends[0].get("vars") or {}).get("access_roles") or {}
        if not roles:
            errors.append(f"the deployed '{BACKEND_COMPONENT}' instance has no access_roles")
    objects = []
    for stack_name, stack in sorted(stacks.items()):
        instances = (stack.get("components") or {}).get("terraform") or {}
        for name, instance in sorted(instances.items()):
            if not is_deployable(instance) or instance.get("backend_type") != "s3":
                continue
            where = f"{stack_name}: {name}"
            errors += check_layout(where, instance, bucket_region)
            stage = stage_of(instance)
            if stage is None:
                errors.append(f"{where} has no settings.context stage to split its state by")
                continue
            if stage == fixtures.FIXTURE_STAGE:
                continue
            backend = instance.get("backend") or {}
            state = f"{backend.get('workspace_key_prefix')}/{instance.get('workspace')}/{backend.get('key')}"
            for obj in (state, state + LOCK_SUFFIX):
                objects.append((stage, where, obj, assumed_role_name(instance)))
    if roles:
        errors += check_roles(objects, roles)
    return errors


def main() -> int:
    errors = check(json.load(sys.stdin))
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} state key problem(s)")
        return 1
    print(
        "every s3-backend state object is matched by exactly its stage's access roles, including "
        "the role it assumes; its workspace_key_prefix has no '/', its backend.key is terraform.tfstate "
        "and its backend.region is the state bucket's"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

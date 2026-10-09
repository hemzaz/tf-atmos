#!/usr/bin/env python3
"""Check that each state backend's access roles split every state key in its bucket by stage.

Reads `atmos describe stacks --process-functions=false --format json` on stdin.
Each deployed "backend" instance (backends.py) owns one bucket, vars.bucket_name,
and its access roles split the stages of that bucket with S3 object-key
patterns, an exact pair per stack, "*/<stack>/*" and "*/<stack>-*"
(stacks/orgs/fnx/root/us-east-1.yaml). Every instance's backend.bucket must be
owned by exactly one backend instance; the rules below hold per bucket, against
its owner's access roles only (US prod and EU prod are separate stages). A state key is
"<workspace_key_prefix>/<workspace>/<backend.key>" (+ ".tflock"). This evaluates
each owning backend's access_roles patterns against every key in its bucket, with
IAM's resource-ARN wildcards ("*" any run of characters, "/" included; "?" any
one character), and requires, for every instance with backend_type s3:
  - each of its state objects matches some role, including the role its
    backend assumes (backend.assume_role.role_arn);
  - every role that matches one of its stage's state objects matches all of them;
  - stages whose backends assume the same role (dev and staging) are matched by
    the same roles, and stages that assume different roles share no role;
  - every role matches some state object (a role reaching nothing has lost its stage);
  - every pattern matches some state object, so a pair left behind by a rename or
    a removed stack fails. A "*/<stack>-*" pattern (a stack's derived
    instances) may match nothing while its "*/<stack>/*" companion on the same
    role matches: most stacks have no derived instance.
This holds whatever the stack names look like, so it does not depend on where
the stage sits in name_template. Stage fixtures is skipped: its stacks are
never deployed and have no access role. Layout checks stay for every instance:
  - the workspace and backend.workspace_key_prefix contain no "/";
  - backend.key is exactly "terraform.tfstate" (every instance uses it);
  - no two stacks share a state key in one bucket. Atmos names an instance's workspace
    <stack>-<instance suffix> (fnx-ue1-dev-main for vpc/main), so a lane named
    like a suffix (fnx-ue1-dev-main's vpc) would read and write its parent's state.

Every s3 backend also points at its bucket's region: backend.region must equal the
region of the backend instance that owns backend.bucket (backend/main in fnx-ue1-root
for fnx-terraform-state), not the stack's own, or init of a DR/EU stack fails against
a region with no bucket. Exits 1 on any violation.
"""
import json
import os
import re
import sys
from typing import Optional

# The sibling modules, also when this file is loaded by path (tests).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import backends  # noqa: E402
import fixtures  # noqa: E402

STATE_KEY = "terraform.tfstate"
LOCK_SUFFIX = ".tflock"
AWS_REGION = backends.AWS_REGION


def stage_of(instance: dict) -> Optional[str]:
    return ((instance.get("settings") or {}).get("context") or {}).get("stage") or None


WILDCARDS = {"*": ".*", "?": "."}


def pattern_matches(pattern: str, key: str) -> bool:
    """IAM resource-ARN wildcard match: "*" any run of characters ("/" included), "?" any one."""
    regex = "".join(WILDCARDS.get(char) or re.escape(char) for char in pattern)
    return re.fullmatch(regex, key, re.DOTALL) is not None


def dead_patterns(roles: dict, live: set) -> list[str]:
    """Patterns that match no state object, except a live stack's "-*" companion."""
    errors = []
    for name in sorted(roles):
        patterns = roles[name].get("object_key_patterns") or []
        for pattern in patterns:
            if (name, pattern) in live:
                continue
            companion = pattern[:-2] + "/*" if pattern.endswith("-*") else None
            if companion in patterns and (name, companion) in live:
                continue
            errors.append(
                f"access role {name!r} pattern {pattern!r} matches no state object "
                "(a stack renamed or removed?)"
            )
    return errors


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
    live: set = set()  # (role, pattern) pairs that match some state object
    for stage, where, obj, role_name in objects:
        pairs = {
            (name, p) for name, role in roles.items()
            for p in role.get("object_key_patterns") or [] if pattern_matches(p, obj)
        }
        live |= pairs
        hits = frozenset(name for name, _ in pairs)
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
    errors += dead_patterns(roles, live)
    # The state object and its lock repeat the per-instance role error.
    return list(dict.fromkeys(errors))


def check(stacks: dict) -> list[str]:
    owned, errors = backends.owned(stacks)
    created = set(backends.owners(stacks))  # a bucket created twice is created, but has no owner
    objects: dict = {}  # bucket -> (stage, where, object key, assumed role name)
    keys = {}  # (bucket, state key) -> (stack, where)
    for stack_name, stack in sorted(stacks.items()):
        for name, instance in sorted(backends.instances(stack).items()):
            if not backends.is_deployable(instance) or instance.get("backend_type") != "s3":
                continue
            where = f"{stack_name}: {name}"
            bucket = backends.bucket_of(instance)
            owner = backends.owner_of(owned, instance)
            if bucket not in created:
                errors.append(f"{where} backend.bucket {bucket!r} is created by no deployed backend instance")
            region = owner.region if owner and AWS_REGION.match(str(owner.region)) else None
            errors += check_layout(where, instance, region)
            backend = instance.get("backend") or {}
            state = f"{backend.get('workspace_key_prefix')}/{instance.get('workspace')}/{backend.get('key')}"
            first = keys.setdefault((bucket, state), (stack_name, where))
            if first[0] != stack_name:
                errors.append(
                    f"{where} and {first[1]} share the state key {state!r}: rename the lane "
                    "(settings.context.name) so it is no instance's workspace suffix"
                )
            stage = stage_of(instance)
            if stage is None:
                errors.append(f"{where} has no settings.context stage to split its state by")
                continue
            if stage == fixtures.FIXTURE_STAGE or owner is None:
                continue
            for obj in (state, state + LOCK_SUFFIX):
                objects.setdefault(bucket, []).append((stage, where, obj, backends.assumed_role_name(instance)))
    for bucket, owner in sorted(owned.items()):
        if owner.access_roles:
            label = f"bucket {bucket!r} ({owner.where})"
            errors += [f"{label}: {error}" for error in check_roles(objects.get(bucket, []), owner.access_roles)]
    return errors


def main() -> int:
    errors = check(json.load(sys.stdin))
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} state key problem(s)")
        return 1
    print(
        "every s3-backend state object is in a bucket one backend instance owns and is matched by exactly "
        "its stage's access roles of that owner, including the role it assumes; its workspace_key_prefix "
        "has no '/', its backend.key is terraform.tfstate, its backend.region is its bucket's and no other "
        "instance shares its key"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

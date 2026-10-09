#!/usr/bin/env python3
"""Check that every stack's CI roles are trusted by its stage's state access roles.

Reads `atmos describe stacks --process-functions=false --format json` on stdin.
Each deployable iam/ci instance creates <ci_role_name_prefix>-plan (github_oidc_enabled)
and <ci_role_name_prefix>-apply (also ci_apply_role_enabled) in its stack's account;
ci-apply-role-arn.py derives the ARNs CI assumes the same way. The backend
instance owning the iam/ci instance's state bucket (backends.owner_of: backend/main
for fnx-terraform-state, its EU twin for the EU bucket) trusts them in its
access_roles as literal ARNs (stacks/orgs/fnx/root/us-east-1.yaml, an
aws:PrincipalArn condition), so nothing else ties the two together: the plan
role must be in that backend's stage read role's allowed_principal_arns (read for
dev/staging, prod_read for prod) and the apply role in its write role's (write /
prod_write). Another backend's roles do not count. A renamed ci_role_name_prefix
or a new stack missing there leaves its CI unable to assume a state role. An
iam/ci instance whose bucket has no one owning backend is an error. Stage
fixtures is skipped: never deployed.

The stages' roles are the explicit STAGE_ROLES map: a stage missing from it is an
error, so a new tier never falls into the non-prod roles silently. Each CI
instance's own backend must assume one of its stage's two roles of that owner
(backend.assume_role.role_arn, the role_arn template in stacks/orgs/fnx/_defaults.yaml).
The other side of the trust: the plan role may assume only that owner's stage read
role (every ci_backend_read_role_arns entry names it, at least one) and the apply
role only its write role (ci_backend_write_role_arn), so an EU CI role pointed at
the US backend's roles fails.

The reverse holds too, per backend: an allowed_principal_arns entry shaped like a
CI role (":role/...-ci-plan" / "-ci-apply") must be the plan or apply ARN of an
iam/ci instance whose state that backend owns, in a stage that access role
serves, of the matching kind. That fails a dev apply role trusted on prod_write,
a stale ARN left behind by a rename, and a US CI role trusted by the EU backend.
OPERATOR_ROLE_ARNS lists any non-CI role that happens to have that shape.
Exits 1 on any error.
"""
import importlib.util
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import backends  # noqa: E402
import fixtures  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "ci_apply_role_arn", pathlib.Path(__file__).with_name("ci-apply-role-arn.py")
)
ci_apply_role_arn = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ci_apply_role_arn)

CI_COMPONENT = "iam"
# stage -> (plan role's access_roles key, apply role's). Explicit on purpose.
STAGE_ROLES = {
    "dev": ("read", "write"),
    "staging": ("read", "write"),
    "prod": ("prod_read", "prod_write"),
}
KINDS = ("plan", "apply")
# The iam/ci variables naming the state roles each CI role may assume (sts:AssumeRole).
GRANT_VARS = {"plan": "ci_backend_read_role_arns", "apply": "ci_backend_write_role_arn"}
CI_ROLE_ARN = re.compile(r"^arn:aws:iam::[^:]*:role/(?:.*/)?[^/]+-ci-(plan|apply)$")
# Non-CI principals with a CI-role-shaped name, exempt from the reverse check. None today.
OPERATOR_ROLE_ARNS: frozenset = frozenset()


def instances(stacks: dict):
    for stack_name, stack in sorted(stacks.items()):
        for name, instance in sorted(backends.instances(stack).items()):
            if backends.is_deployable(instance):
                yield stack_name, name, instance


def stage_kind(key: str) -> str:
    """'plan' or 'apply': the CI role kind an access_roles key trusts."""
    for plan_key, apply_key in STAGE_ROLES.values():
        if key == plan_key:
            return "plan"
        if key == apply_key:
            return "apply"
    return "CI"


def check_grant(where: str, instance: dict, kind: str, owner: backends.Backend, key: str) -> list[str]:
    """The state roles the CI role may assume (GRANT_VARS[kind]) must be exactly the owner's access_roles.key."""
    variable = GRANT_VARS[kind]
    value = (instance.get("vars") or {}).get(variable)
    granted = (value or []) if kind == "plan" else ([value] if value else [])
    want = (owner.access_roles.get(key) or {}).get("role_name")
    if granted and all(backends.role_name_of(arn) == want for arn in granted):
        return []
    return [f"{where} {kind} role may assume {granted} ({variable}), not {owner.where} access_roles.{key} "
            f"({want}), so its CI cannot assume the state role of the backend owning its state"]


def check_ci(where: str, instance: dict, stage: str, owner: backends.Backend, expected: dict) -> list[str]:
    """One iam/ci instance against the access_roles of the backend owning its state; records the
    ARNs each (bucket, key) must trust in expected."""
    errors = []
    assumed = backends.assumed_role_key(instance, owner)
    if assumed not in STAGE_ROLES[stage]:
        errors.append(
            f"{where} backend assumes access_roles.{assumed} (backend.assume_role.role_arn), "
            f"not one of stage {stage!r}'s {list(STAGE_ROLES[stage])} of {owner.where}"
        )
    kinds = ["plan"] + (["apply"] if (instance.get("vars") or {}).get("ci_apply_role_enabled") else [])
    for kind in kinds:
        try:
            arn = ci_apply_role_arn.role_arn(instance, kind)
        except (KeyError, ValueError) as error:
            errors.append(f"{where} {kind} role: {error}")
            continue
        key = STAGE_ROLES[stage][KINDS.index(kind)]
        expected.setdefault((owner.bucket, key), {})[arn] = kind
        errors += check_grant(where, instance, kind, owner, key)
        trusted = (owner.access_roles.get(key) or {}).get("allowed_principal_arns") or []
        if arn not in trusted:
            errors.append(
                f"{where} {kind} role {arn} is not in backend access_roles.{key} allowed_principal_arns "
                f"of {owner.where}, so its CI cannot assume a state role"
            )
    return errors


def check(stacks: dict) -> list[str]:
    owned, _ = backends.owned(stacks)  # owned()'s own errors are check-state-keys.py's to report
    if not owned:
        return [f"no state bucket has one deployable '{backends.BACKEND_COMPONENT}' instance owning it"]
    errors = []
    expected: dict = {}  # (bucket, access_roles key) -> {CI role ARN: kind} it must trust
    for stack_name, name, instance in instances(stacks):
        if instance.get("component") != CI_COMPONENT or not (instance.get("vars") or {}).get("github_oidc_enabled"):
            continue
        stage = ((instance.get("settings") or {}).get("context") or {}).get("stage")
        if stage == fixtures.FIXTURE_STAGE:
            continue
        where = f"{stack_name}: {name}"
        if stage not in STAGE_ROLES:
            errors.append(f"{where} is in stage {stage!r}, which STAGE_ROLES does not map to backend roles")
            continue
        owner = backends.owner_of(owned, instance)
        if owner is None:
            errors.append(f"{where} state bucket {backends.bucket_of(instance)!r} has no one owning "
                          f"'{backends.BACKEND_COMPONENT}' instance, so its CI roles cannot be checked")
            continue
        errors += check_ci(where, instance, stage, owner, expected)
    for bucket, owner in sorted(owned.items()):
        for key in sorted(owner.access_roles):
            for arn in (owner.access_roles[key] or {}).get("allowed_principal_arns") or []:
                if arn in OPERATOR_ROLE_ARNS or not CI_ROLE_ARN.match(arn):
                    continue
                if arn not in expected.get((bucket, key), {}):
                    errors.append(
                        f"{owner.where}: backend access_roles.{key} trusts {arn}, which is no {stage_kind(key)} "
                        "role of an iam/ci instance in a stage this role serves whose state this backend owns "
                        "(stale, or another stage's or backend's)"
                    )
    return errors


def main() -> int:
    errors = check(json.load(sys.stdin))
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} CI state role problem(s)")
        return 1
    print("every iam/ci plan and apply role is trusted by its stage's read and write role of the backend "
          "owning its state, and every CI-shaped trusted ARN is one of them")
    return 0


if __name__ == "__main__":
    sys.exit(main())

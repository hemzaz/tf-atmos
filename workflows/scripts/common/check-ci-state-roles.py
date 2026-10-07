#!/usr/bin/env python3
"""Check that every stack's CI roles are trusted by its stage's state access roles.

Reads `atmos describe stacks --process-functions=false --format json` on stdin.
Each deployable iam/ci instance creates <ci_role_name_prefix>-plan (github_oidc_enabled)
and <ci_role_name_prefix>-apply (also ci_apply_role_enabled) in its stack's account;
ci-apply-role-arn.py derives the ARNs CI assumes the same way. backend/main's
access_roles trust them as literal ARNs (stacks/orgs/fnx/root/us-east-1.yaml,
an aws:PrincipalArn condition), so nothing else ties the two together: the plan
role must be in its stage's read role's allowed_principal_arns (read for
dev/staging, prod_read for prod) and the apply role in its write role's (write /
prod_write). A renamed ci_role_name_prefix or a new stack missing there leaves
its CI unable to assume a state role. Stage fixtures is skipped: never deployed.

The stages' roles are the explicit STAGE_ROLES map: a stage missing from it is an
error, so a new tier never falls into the non-prod roles silently. Each CI
instance's own backend must assume one of its stage's two roles
(backend.assume_role.role_arn, the role_arn template in stacks/orgs/fnx/_defaults.yaml).

The reverse holds too: an allowed_principal_arns entry shaped like a CI role
(":role/...-ci-plan" / "-ci-apply") must be the plan or apply ARN of an iam/ci
instance in a stage that access role serves, of the matching kind. That fails a
dev apply role trusted on prod_write, and a stale ARN left behind by a rename.
OPERATOR_ROLE_ARNS lists any non-CI role that happens to have that shape.
Exits 1 on any error.
"""
import importlib.util
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import fixtures  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "ci_apply_role_arn", pathlib.Path(__file__).with_name("ci-apply-role-arn.py")
)
ci_apply_role_arn = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ci_apply_role_arn)

BACKEND_COMPONENT = "backend"
CI_COMPONENT = "iam"
# stage -> (plan role's access_roles key, apply role's). Explicit on purpose.
STAGE_ROLES = {
    "dev": ("read", "write"),
    "staging": ("read", "write"),
    "prod": ("prod_read", "prod_write"),
}
KINDS = ("plan", "apply")
CI_ROLE_ARN = re.compile(r"^arn:aws:iam::[^:]*:role/(?:.*/)?[^/]+-ci-(plan|apply)$")
# Non-CI principals with a CI-role-shaped name, exempt from the reverse check. None today.
OPERATOR_ROLE_ARNS: frozenset = frozenset()


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def instances(stacks: dict):
    for stack_name, stack in sorted(stacks.items()):
        for name, instance in sorted(((stack.get("components") or {}).get("terraform") or {}).items()):
            if is_deployable(instance):
                yield stack_name, name, instance


def assumed_role_key(instance: dict, roles: dict) -> "str | None":
    """The access_roles key whose role_name the instance's backend assumes."""
    arn = ((instance.get("backend") or {}).get("assume_role") or {}).get("role_arn") or ""
    name = arn.rsplit("/", 1)[-1] if ":role/" in arn else None
    return next((key for key, role in roles.items() if role.get("role_name") == name), None)


def stage_kind(key: str) -> str:
    """'plan' or 'apply': the CI role kind an access_roles key trusts."""
    for plan_key, apply_key in STAGE_ROLES.values():
        if key == plan_key:
            return "plan"
        if key == apply_key:
            return "apply"
    return "CI"


def check(stacks: dict) -> list[str]:
    backends = [i for _, _, i in instances(stacks) if i.get("component") == BACKEND_COMPONENT]
    if len(backends) != 1:
        return [f"expected exactly one deployable '{BACKEND_COMPONENT}' instance, found {len(backends)}"]
    roles = (backends[0].get("vars") or {}).get("access_roles") or {}
    errors = []
    expected: dict = {}  # access_roles key -> {CI role ARN: kind} it must trust
    for stack_name, name, instance in instances(stacks):
        variables = instance.get("vars") or {}
        if instance.get("component") != CI_COMPONENT or not variables.get("github_oidc_enabled"):
            continue
        stage = ((instance.get("settings") or {}).get("context") or {}).get("stage")
        if stage == fixtures.FIXTURE_STAGE:
            continue
        where = f"{stack_name}: {name}"
        if stage not in STAGE_ROLES:
            errors.append(f"{where} is in stage {stage!r}, which STAGE_ROLES does not map to backend roles")
            continue
        assumed = assumed_role_key(instance, roles)
        if assumed not in STAGE_ROLES[stage]:
            errors.append(
                f"{where} backend assumes access_roles.{assumed} (backend.assume_role.role_arn), "
                f"not one of stage {stage!r}'s {list(STAGE_ROLES[stage])}"
            )
        kinds = ["plan"] + (["apply"] if variables.get("ci_apply_role_enabled") else [])
        for kind in kinds:
            try:
                arn = ci_apply_role_arn.role_arn(instance, kind)
            except (KeyError, ValueError) as error:
                errors.append(f"{where} {kind} role: {error}")
                continue
            key = STAGE_ROLES[stage][KINDS.index(kind)]
            expected.setdefault(key, {})[arn] = kind
            trusted = (roles.get(key) or {}).get("allowed_principal_arns") or []
            if arn not in trusted:
                errors.append(
                    f"{where} {kind} role {arn} is not in backend access_roles.{key} "
                    "allowed_principal_arns, so its CI cannot assume a state role"
                )
    for key in sorted(roles):
        for arn in (roles[key] or {}).get("allowed_principal_arns") or []:
            if arn in OPERATOR_ROLE_ARNS or not CI_ROLE_ARN.match(arn):
                continue
            if arn not in expected.get(key, {}):
                errors.append(
                    f"backend access_roles.{key} trusts {arn}, which is no {stage_kind(key)} role of an "
                    "iam/ci instance in a stage this role serves (stale, or another stage's)"
                )
    return errors


def main() -> int:
    errors = check(json.load(sys.stdin))
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} CI state role problem(s)")
        return 1
    print("every iam/ci plan and apply role is trusted by its stage's backend read and write role, "
          "and every CI-shaped trusted ARN is one of them")
    return 0


if __name__ == "__main__":
    sys.exit(main())

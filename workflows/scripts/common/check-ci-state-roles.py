#!/usr/bin/env python3
"""Check that every stack's CI roles are trusted by its stage's state access roles.

Reads `atmos describe stacks --process-functions=false --format json` on stdin.
Each deployable iam/ci instance creates <ci_role_name_prefix>-plan (github_oidc_enabled)
and <ci_role_name_prefix>-apply (also ci_apply_role_enabled) in its stack's account;
ci-apply-role-arn.py derives the ARNs CI assumes the same way. backend/main's
access_roles trust them as literal ARNs (stacks/orgs/fnx/core/us-east-1/root.yaml,
an aws:PrincipalArn condition), so nothing else ties the two together: the plan
role must be in its stage's read role's allowed_principal_arns (read for
dev/staging, prod_read for prod) and the apply role in its write role's (write /
prod_write). A renamed ci_role_name_prefix or a new stack missing there leaves
its CI unable to assume a state role. Stage fixtures is skipped: never deployed.
Exits 1 on any error.
"""
import importlib.util
import json
import pathlib
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


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def instances(stacks: dict):
    for stack_name, stack in sorted(stacks.items()):
        for name, instance in sorted(((stack.get("components") or {}).get("terraform") or {}).items()):
            if is_deployable(instance):
                yield stack_name, name, instance


def stage_role(stage: str, kind: str) -> str:
    """The access_roles key that must trust a stage's plan or apply role."""
    prefix = "prod_" if stage == "prod" else ""
    return f"{prefix}read" if kind == "plan" else f"{prefix}write"


def check(stacks: dict) -> list[str]:
    backends = [i for _, _, i in instances(stacks) if i.get("component") == BACKEND_COMPONENT]
    if len(backends) != 1:
        return [f"expected exactly one deployable '{BACKEND_COMPONENT}' instance, found {len(backends)}"]
    roles = (backends[0].get("vars") or {}).get("access_roles") or {}
    errors = []
    for stack_name, name, instance in instances(stacks):
        variables = instance.get("vars") or {}
        if instance.get("component") != CI_COMPONENT or not variables.get("github_oidc_enabled"):
            continue
        stage = ((instance.get("settings") or {}).get("context") or {}).get("stage")
        if stage == fixtures.FIXTURE_STAGE:
            continue
        kinds = ["plan"] + (["apply"] if variables.get("ci_apply_role_enabled") else [])
        for kind in kinds:
            try:
                arn = ci_apply_role_arn.role_arn(instance, kind)
            except (KeyError, ValueError) as error:
                errors.append(f"{stack_name}: {name} {kind} role: {error}")
                continue
            key = stage_role(stage, kind)
            trusted = (roles.get(key) or {}).get("allowed_principal_arns") or []
            if arn not in trusted:
                errors.append(
                    f"{stack_name}: {name} {kind} role {arn} is not in backend access_roles.{key} "
                    "allowed_principal_arns, so its CI cannot assume a state role"
                )
    return errors


def main() -> int:
    errors = check(json.load(sys.stdin))
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} CI state role problem(s)")
        return 1
    print("every iam/ci plan and apply role is trusted by its stage's backend read and write role")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Check that every prod rds and elasticache instance keeps its data-loss protections.

Usage: check-prod-protection.py <components/terraform dir> < describe-stacks.json
(`atmos describe stacks --process-functions=false --format json`).

The stack templates (web-application, idp-platform) ship non-prod values and
leave the prod ones to the importing stack (their ENVIRONMENT-SPECIFIC
OVERRIDES). A prod stack that forgets an override would deploy a database
without deletion protection or a cache without failover. For every deployable
instance of rds or elasticache in a stack of stage prod, the effective value of
each setting below (the instance's var, else the variable's default read from
the component's variables.tf) must be safe:

  rds:          environment = "prod" (turns on the component's own prod
                validations), multi_az, deletion_protection and prevent_destroy
                true, skip_final_snapshot false, backup_retention_period >= 7
  elasticache:  automatic_failover_enabled and multi_az_enabled true, at least
                2 nodes (num_cache_nodes) unless cluster_mode_enabled, and
                snapshot_retention_limit >= 7

And every deployable iam instance in a stack of stage prod that creates the
GitHub OIDC CI roles (github_oidc_enabled) must set ci_plan_role_subjects
explicitly, to exactly repo:<github_oidc_repository>:ref:refs/heads/<github_oidc_default_branch>
(both resolved as the component does, var or default), nothing else: no
pull_request, environment, other branch or wildcard subject. The plan role reads
every prod state object through backend/main's prod_read role, and the
component's default trusts repo:<repo>:pull_request, i.e. code from any PR.

Exits 1 on any unsafe value.
"""
import json
import pathlib
import re
import sys
from typing import Any, Callable, Optional

PROD_STAGE = "prod"
MIN_RETENTION_DAYS = 7

# component -> [(variable, is_safe, what safe means)]
RULES: dict[str, list[tuple[str, Callable[[Any, dict], bool], str]]] = {
    "rds": [
        ("environment", lambda v, _: v == "prod", '"prod"'),
        ("multi_az", lambda v, _: v is True, "true"),
        ("deletion_protection", lambda v, _: v is True, "true"),
        ("prevent_destroy", lambda v, _: v is True, "true"),
        ("skip_final_snapshot", lambda v, _: v is False, "false"),
        ("backup_retention_period", lambda v, _: isinstance(v, (int, float)) and v >= MIN_RETENTION_DAYS,
         f">= {MIN_RETENTION_DAYS}"),
    ],
    "elasticache": [
        ("automatic_failover_enabled", lambda v, _: v is True, "true"),
        ("multi_az_enabled", lambda v, _: v is True, "true"),
        ("num_cache_nodes", lambda v, eff: eff("cluster_mode_enabled") is True or (isinstance(v, (int, float)) and v >= 2),
         ">= 2 (or cluster_mode_enabled)"),
        ("snapshot_retention_limit", lambda v, _: isinstance(v, (int, float)) and v >= MIN_RETENTION_DAYS,
         f">= {MIN_RETENTION_DAYS}"),
    ],
}
DEFAULT = re.compile(r'^\s*default\s*=\s*("(?:[^"\\]|\\.)*"|true|false|-?\d+(?:\.\d+)?|null)\s*(?:#.*)?$')


def normalize(value: Any) -> Any:
    """Atmos renders Go templates as strings: "true"/"7" mean true/7."""
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in ("true", "false"):
            return lowered == "true"
        if re.fullmatch(r"-?\d+", lowered):
            return int(lowered)
    return value


def variable_default(components_dir: pathlib.Path, component: str, name: str) -> Any:
    """A scalar default from the component's variables.tf; raises if it has none."""
    text = (components_dir / component / "variables.tf").read_text(encoding="utf-8")
    match = re.search(r'^variable\s+"' + re.escape(name) + r'"\s*\{\n(.*?)^\}', text, re.MULTILINE | re.DOTALL)
    if not match:
        raise KeyError(f"{component}: variable {name!r} is not declared in variables.tf")
    for line in match.group(1).splitlines():
        found = DEFAULT.match(line)
        if found:
            return json.loads(found.group(1))
    raise KeyError(f"{component}: variable {name!r} has no scalar default in variables.tf")


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def check(stacks: dict, components_dir: pathlib.Path) -> list[str]:
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        for name, instance in sorted(((stack.get("components") or {}).get("terraform") or {}).items()):
            component = instance.get("component")
            stage = ((instance.get("settings") or {}).get("context") or {}).get("stage")
            if component not in RULES or stage != PROD_STAGE or not is_deployable(instance):
                continue
            variables = instance.get("vars") or {}

            def effective(var: str, _vars: dict = variables, _component: str = component) -> Optional[Any]:
                if var in _vars and _vars[var] is not None:
                    return normalize(_vars[var])
                return variable_default(components_dir, _component, var)

            for var, is_safe, safe in RULES[component]:
                try:
                    value = effective(var)
                except KeyError as error:
                    errors.append(f"{stack_name}: {name} {error}")
                    continue
                if not is_safe(value, effective):
                    source = "set" if var in variables else "the default"
                    errors.append(
                        f"{stack_name}: {name} ({component}) {var} is {json.dumps(value)} ({source}); "
                        f"a prod instance needs {safe}"
                    )
    return errors


def check_ci_plan_trust(stacks: dict, components_dir: pathlib.Path) -> list[str]:
    """Prod CI plan roles trusting anything but their repository's default-branch ref."""
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        for name, instance in sorted(((stack.get("components") or {}).get("terraform") or {}).items()):
            stage = ((instance.get("settings") or {}).get("context") or {}).get("stage")
            variables = instance.get("vars") or {}
            if (instance.get("component") != "iam" or stage != PROD_STAGE or not is_deployable(instance)
                    or normalize(variables.get("github_oidc_enabled")) is not True):
                continue

            def effective(var: str) -> Any:
                value = variables.get(var)
                return value if value is not None else variable_default(components_dir, "iam", var)

            repository, branch = effective("github_oidc_repository"), effective("github_oidc_default_branch")
            allowed = f"repo:{repository}:ref:refs/heads/{branch}"
            subjects = variables.get("ci_plan_role_subjects")
            if not repository:
                errors.append(f"{stack_name}: {name} (iam) sets no github_oidc_repository")
            elif not subjects:
                errors.append(
                    f"{stack_name}: {name} (iam) leaves ci_plan_role_subjects unset, so its prod plan role "
                    f"trusts repo:{repository}:pull_request (the default): list {allowed!r} only"
                )
            else:
                for subject in subjects:
                    if subject != allowed:
                        errors.append(
                            f"{stack_name}: {name} (iam) ci_plan_role_subjects trusts {subject!r}: a prod plan "
                            f"role trusts its default branch's ref only, {allowed!r}"
                        )
    return errors


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.splitlines()[2], file=sys.stderr)
        return 2
    described = json.load(sys.stdin)
    errors = check(described, pathlib.Path(sys.argv[1])) + check_ci_plan_trust(described, pathlib.Path(sys.argv[1]))
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} prod protection problem(s)")
        return 1
    print(
        "every prod rds instance is environment prod, Multi-AZ, deletion-protected, keeps a final "
        f"snapshot and {MIN_RETENTION_DAYS}+ days of backups; every prod elasticache instance fails over "
        f"across AZs and keeps {MIN_RETENTION_DAYS}+ days of snapshots; every prod CI plan role trusts its "
        "repository's default-branch ref only"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

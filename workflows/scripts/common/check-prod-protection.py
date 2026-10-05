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


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.splitlines()[2], file=sys.stderr)
        return 2
    errors = check(json.load(sys.stdin), pathlib.Path(sys.argv[1]))
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} prod protection problem(s)")
        return 1
    print(
        "every prod rds instance is environment prod, Multi-AZ, deletion-protected, keeps a final "
        f"snapshot and {MIN_RETENTION_DAYS}+ days of backups; every prod elasticache instance fails over "
        f"across AZs and keeps {MIN_RETENTION_DAYS}+ days of snapshots"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Print, in dependency order, the terraform instances of --stack a hosted runner may run.

terraform-cd.yml and drift-detection.yml loop over this list (one
`atmos terraform <cmd> <component> -s <stack>` each) instead of Atmos's own
stack-wide `deploy --affected` / `plan -s <stack>`, because:
  - an instance with settings.github.actions_enabled: false must be skipped
    (the in-cluster components: the EKS API is private, so a GitHub-hosted
    runner cannot reach it; docs/OPERATIONS.md, "In-cluster components"), and
    Atmos 1.229 rejects --query together with --affected;
  - a stack-wide bulk run builds the dependency graph from the filtered set
    alone and fails on any dependency outside it (iam/ci -> fnx-core-root's
    backend/main).
Order: a topological sort of the stack's deployable instances over their
same-stack dependencies.components (the list check-dependencies.py enforces
for every !terraform.state read), ties broken by name. With --base, only the
instances `atmos describe affected --base <sha> -s <stack>` reports.

Skipped instances are reported as ::notice:: lines on stderr. Exits 1 on an
unknown stack or a dependency cycle.
"""
import argparse
import json
import subprocess
import sys
from typing import Optional


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def hosted_ci_enabled(instance: dict) -> bool:
    github = ((instance.get("settings") or {}).get("github")) or {}
    return github.get("actions_enabled") is not False


def dependency_order(instances: dict, stack: str) -> list[str]:
    """Deployable instances of `stack`, each after every same-stack instance it depends on."""
    names = sorted(name for name, instance in instances.items() if is_deployable(instance or {}))
    deps = {}
    for name in names:
        entries = ((instances[name].get("dependencies") or {}).get("components")) or []
        deps[name] = {
            entry["component"]
            for entry in entries
            if isinstance(entry, dict)
            and entry.get("component") in instances
            and entry.get("stack", stack) == stack
            and entry.get("component") != name
        } & set(names)
    ordered, done = [], set()
    while len(ordered) < len(names):
        ready = [name for name in names if name not in done and deps[name] <= done]
        if not ready:
            cycle = sorted(name for name in names if name not in done)
            raise ValueError(f"dependency cycle among {cycle}")
        ordered.extend(ready)
        done.update(ready)
    return ordered


def select(instances: dict, stack: str, affected: Optional[set] = None) -> tuple[list[str], list[str]]:
    """(instances to run in order, instances skipped because actions_enabled is false)."""
    run, skipped = [], []
    for name in dependency_order(instances, stack):
        if affected is not None and name not in affected:
            continue
        (run if hosted_ci_enabled(instances[name]) else skipped).append(name)
    return run, skipped


def atmos_json(*args: str):
    return json.loads(subprocess.check_output(["atmos", *args, "--process-functions=false", "--format", "json"]))


def stack_instances(stack: str, describe=None) -> dict:
    """The stack's terraform instances; LookupError when Atmos does not know the stack.

    `atmos describe stacks -s <unknown>` prints {} on some Atmos versions and
    exits non-zero on others, so both mean an unknown stack.
    """
    try:
        stacks = (describe or atmos_json)("describe", "stacks", "-s", stack, "--sections", "metadata,settings,dependencies")
    except subprocess.CalledProcessError as error:
        raise LookupError(f"Unknown stack '{stack}' (atmos describe stacks exited {error.returncode})") from error
    if stack not in stacks:
        raise LookupError(f"Unknown stack '{stack}'")
    return (stacks[stack].get("components") or {}).get("terraform") or {}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--stack", required=True)
    parser.add_argument("--base", help="only instances affected since this commit")
    args = parser.parse_args()

    try:
        instances = stack_instances(args.stack)
    except LookupError as error:
        print(f"::error::{error}")
        return 1
    affected = None
    if args.base:
        affected = {
            item["component"]
            for item in atmos_json("describe", "affected", "--base", args.base, "-s", args.stack)
            if item.get("stack") == args.stack and item.get("component_type") == "terraform"
        }
    try:
        run, skipped = select(instances, args.stack, affected)
    except ValueError as error:
        print(f"::error::{args.stack}: {error}")
        return 1
    if skipped:
        print(
            f"::notice::{args.stack}: skipping {', '.join(skipped)} (settings.github.actions_enabled: false; "
            "applied from inside the VPC, see docs/OPERATIONS.md)",
            file=sys.stderr,
        )
    for name in run:
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Check that every !terraform.state / !terraform.output target is a declared dependency.

Reads `atmos describe stacks --process-functions=false --format json` on stdin.
For each enabled, non-abstract component instance, every YAML function that reads
another instance's state must name an instance that exists in the target stack and
that is listed in the reader's `dependencies.components`; otherwise deploy ordering
(and `atmos describe affected`) silently misses the edge. Exits 1 on any violation.
"""
import json
import sys
from typing import Any, Iterator, Optional

FUNCTIONS = ("!terraform.state", "!terraform.output")


def references(value: Any) -> Iterator[tuple[str, Optional[str]]]:
    """Yield (component, stack_or_None) for every state-reading YAML function in value."""
    if isinstance(value, dict):
        for item in value.values():
            yield from references(item)
    elif isinstance(value, list):
        for item in value:
            yield from references(item)
    elif isinstance(value, str) and value.startswith(FUNCTIONS):
        tokens = value.split()
        if len(tokens) < 3:
            return
        # `!fn <component> <expr>` or `!fn <component> <stack> <expr>`
        stack = tokens[2] if not tokens[2].startswith((".", "[")) else None
        yield tokens[1], stack


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata", {})
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def check(stacks: dict) -> list[str]:
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        instances = stack.get("components", {}).get("terraform", {})
        for name, instance in sorted(instances.items()):
            if not is_deployable(instance):
                continue
            declared = {
                (dep.get("component"), dep.get("stack") or stack_name)
                for dep in (instance.get("dependencies") or {}).get("components") or []
            }
            for component, ref_stack in sorted(set(references(instance.get("vars", {}))), key=str):
                target_stack = ref_stack or stack_name
                where = f"{stack_name}: {name} reads {component}"
                if target_stack != stack_name:
                    where += f" in {target_stack}"
                target = stacks.get(target_stack, {}).get("components", {}).get("terraform", {}).get(component)
                if target is None:
                    errors.append(f"{where}, which does not exist")
                elif not is_deployable(target):
                    errors.append(f"{where}, which is abstract or disabled")
                elif (component, target_stack) not in declared:
                    errors.append(f"{where} but does not list it in dependencies.components")
    return errors


def main() -> int:
    errors = check(json.load(sys.stdin))
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} dependency problem(s)")
        return 1
    print("dependencies.components covers every !terraform.state/!terraform.output reference")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Check that every !terraform.state / !terraform.output target is a declared dependency.

Reads `atmos describe stacks --process-functions=false --format json` on stdin.
For each enabled, non-abstract component instance, every YAML function that reads
another instance's state must name an instance that exists in the target stack and
that is listed in the reader's `dependencies.components`; otherwise deploy ordering
(and `atmos describe affected`) silently misses the edge. With a components
directory, it must also read an output that the target's root module declares
(outputs.tf): a missing one reads null from the state, or Atmos stops. Exits 1 on
any violation.

Also with a components directory: every var set on an instance must be a
variable its root module declares. Atmos writes every var into the varfile and
Terraform only warns about an undeclared one, so a misspelt or stale var is
silently dropped.
"""
import functools
import json
import os
import re
import sys
from typing import Any, Iterator, Optional

# The sibling module, also when this file is loaded by path (tests, check-domains.py).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fixtures  # noqa: E402

FUNCTIONS = ("!terraform.state", "!terraform.output")
# Characters that open a yq expression rather than a stack name (Atmos 1.229.0 isExpressionStart).
EXPRESSION_STARTS = tuple(".[{|'\"")
COMPONENTS_DIR = "components/terraform"
# The first `.name` / `.["name"]` of a yq expression is the output it reads:
# `.vpc_id`, `.queue_arns.tasks`, `.ids[0]`, `[.a // {} | .[]]`, `'.id | [.]'`.
FIRST_SEGMENT = re.compile(r'\.(?:([A-Za-z_][A-Za-z0-9_]*)|\["([^"]+)"\])')
BARE_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def reads(value: Any) -> Iterator[tuple[str, Optional[str], str]]:
    """Yield (component, stack_or_None, expression) for every state-reading YAML function in value."""
    if isinstance(value, dict):
        for item in value.values():
            yield from reads(item)
    elif isinstance(value, list):
        for item in value:
            yield from reads(item)
    elif isinstance(value, str) and value.startswith(FUNCTIONS):
        tokens = value.split()
        if len(tokens) < 3:
            return
        # `!fn <component> <expr>` or `!fn <component> <stack> <expr>`; the
        # !terraform.output <expr> may be a bare output name (`vpc_id`). A third
        # token that starts an expression is not a stack (Atmos isExpressionStart).
        stack = None if len(tokens) == 3 or tokens[2].startswith(EXPRESSION_STARTS) else tokens[2]
        yield tokens[1], stack, " ".join(tokens[3 if stack else 2:])


def references(value: Any) -> Iterator[tuple[str, Optional[str]]]:
    """Yield (component, stack_or_None) for every state-reading YAML function in value."""
    for component, stack, _ in reads(value):
        yield component, stack


def output_name(expression: str) -> Optional[str]:
    """The output a reference's expression reads, or None when it cannot tell."""
    if "{{" in expression:  # an unrendered Go template: nothing to resolve offline
        return None
    expression = expression.strip().strip("'\"")
    if BARE_NAME.match(expression):  # !terraform.output <component> <output>
        return expression
    match = FIRST_SEGMENT.search(expression)
    return (match.group(1) or match.group(2)) if match else None


@functools.lru_cache(maxsize=None)
def declared(components_dir: str, module: str, kind: str) -> Optional[frozenset]:
    """Names of the module's `output` or `variable` blocks (kind); None when it has no directory."""
    directory = os.path.join(components_dir, module)
    if not os.path.isdir(directory):
        return None
    block = re.compile(rf'^{kind}\s+"([^"]+)"', re.MULTILINE)
    names = set()
    for entry in sorted(os.listdir(directory)):
        if entry.endswith(".tf"):
            with open(os.path.join(directory, entry), encoding="utf-8") as tf:
                names.update(block.findall(tf.read()))
    return frozenset(names)


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata", {})
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def module_name(name: str, instance: dict) -> str:
    """The component directory this instance is built from."""
    return instance.get("component") or instance.get("metadata", {}).get("component") or name


def check(stacks: dict, components_dir: Optional[str] = None) -> list[str]:
    """Check state references, and component directories too when components_dir is given."""
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        instances = stack.get("components", {}).get("terraform", {})
        for name, instance in sorted(instances.items()):
            if not is_deployable(instance):
                continue
            # Nothing else catches this: `atmos validate stacks` and the
            # validate-all workflow both pass when a deployable instance names a
            # component that was never written, because neither maps instances
            # back to directories.
            if components_dir is not None:
                module = module_name(name, instance)
                if not os.path.isdir(os.path.join(components_dir, module)):
                    errors.append(
                        f"{stack_name}: {name} is deployable but {components_dir}/{module} does not exist"
                    )
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
            if components_dir is not None:
                errors += missing_outputs(stacks, stack_name, name, instance, components_dir)
    return errors


def missing_outputs(stacks: dict, stack_name: str, name: str, instance: dict, components_dir: str) -> list[str]:
    """Reads of an output the target's root module does not declare (a missing target is reported by check)."""
    errors = []
    for component, ref_stack, expression in sorted(set(reads(instance.get("vars", {}))), key=str):
        target_stack = ref_stack or stack_name
        target = stacks.get(target_stack, {}).get("components", {}).get("terraform", {}).get(component)
        output = output_name(expression)
        if target is None or not is_deployable(target) or output is None:
            continue
        module = module_name(component, target)
        outputs = declared(components_dir, module, "output")
        if outputs is not None and output not in outputs:
            where = f"{stack_name}: {name} reads {component}"
            if target_stack != stack_name:
                where += f" in {target_stack}"
            errors.append(f"{where} output {output} ({expression}), which {components_dir}/{module} does not declare")
    return errors


def undeclared_vars(stacks: dict, components_dir: str) -> list[str]:
    """Vars set on a deployable instance that its root module does not declare."""
    problems = []
    for stack_name, stack in sorted(stacks.items()):
        for name, instance in sorted(stack.get("components", {}).get("terraform", {}).items()):
            if not is_deployable(instance):
                continue
            module = module_name(name, instance)
            variables = declared(components_dir, module, "variable")
            extra = sorted(set(instance.get("vars") or {}) - variables) if variables is not None else []
            if extra:
                problems.append(
                    f"{stack_name}: {name} sets {', '.join(extra)}, which {components_dir}/{module} does not declare"
                )
    return problems


def main() -> int:
    components_dir = sys.argv[1] if len(sys.argv) > 1 else COMPONENTS_DIR
    stacks = json.load(sys.stdin)
    errors = check(stacks, components_dir) + undeclared_vars(stacks, components_dir)
    errors = fixtures.fatal(errors, "check-dependencies")
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} dependency problem(s)")
        return 1
    print(
        "every deployable instance has a component directory and sets only vars it declares, "
        "dependencies.components covers every !terraform.state/!terraform.output reference, "
        "and every reference reads an output its target declares"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

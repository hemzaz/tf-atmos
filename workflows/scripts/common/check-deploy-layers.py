#!/usr/bin/env python3
"""Check that deploy-full-stack deploys every instance, and in dependency order.

Usage:
  check-deploy-layers.py <describe-stacks.json> <describe-workflows.json>

<describe-stacks.json> is `atmos describe stacks --process-functions=false --format json`;
<describe-workflows.json> is `atmos describe workflows --output all --format json`
(Atmos parses the YAML, so this needs nothing beyond the python3 stdlib).

The layers are the `plan-<layer>` steps of the `deploy` workflow in
deploy-full-stack.yaml, in step order. Each selects instances by Terraform root
module: its query must be a disjunction of `.metadata.component == "<type>"`
terms, which this script can evaluate exactly. Exits 1 when:
  - a layer's query is not of that form, or a type is in two layers;
  - a layer's plan, deploy and deploy-<layer> workflow steps disagree on the query;
  - an enabled, non-abstract instance of any stack is in no layer;
  - an instance's layer comes before the layer of an instance it depends on,
    through dependencies.components or a !terraform.state/!terraform.output read.
Instances in the same layer are ordered by Atmos from dependencies.components.
"""
import importlib.util
import json
import pathlib
import re
import sys
from typing import Optional

WORKFLOW_FILE = "deploy-full-stack.yaml"
ALL_LAYERS_WORKFLOW = "deploy"
PLAN = re.compile(r"^terraform plan --query '(?P<query>[^']*)'$")
DEPLOY = re.compile(r"^terraform deploy --from-plan --query '(?P<query>[^']*)'$")
TERM = re.compile(r'^\.metadata\.component == "(?P<type>[^"]+)"$')

_spec = importlib.util.spec_from_file_location(
    "check_dependencies", pathlib.Path(__file__).with_name("check-dependencies.py")
)
check_dependencies = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_dependencies)


def query_types(query: str) -> Optional[list[str]]:
    """The component types an `a == "x" or a == "y"` query selects; None if it is not of that form."""
    types = []
    for term in query.split(" or "):
        match = TERM.match(term.strip())
        if match is None:
            return None
        types.append(match.group("type"))
    return types


def workflow_steps(workflows: dict, name: str) -> list[dict]:
    return ((workflows.get(name) or {}).get("steps")) or []


def step_query(steps: list[dict], name: str, pattern: re.Pattern) -> Optional[str]:
    for step in steps:
        if step.get("name") == name:
            match = pattern.match(" ".join((step.get("command") or "").split()))
            return match.group("query") if match else None
    return None


def only_query(steps: list[dict], pattern: re.Pattern) -> Optional[str]:
    """The query of the single step matching pattern; None when there is none, or several."""
    matches = [pattern.match(" ".join((step.get("command") or "").split())) for step in steps]
    queries = [match.group("query") for match in matches if match]
    return queries[0] if len(queries) == 1 else None


def layers(workflow_files: dict) -> tuple[list[tuple[str, list[str]]], list[str]]:
    """Ordered (layer, component types) from the `deploy` workflow, plus consistency errors."""
    errors = []
    workflows = (workflow_files.get(WORKFLOW_FILE) or {}).get("workflows") or {}
    steps = workflow_steps(workflows, ALL_LAYERS_WORKFLOW)
    if not steps:
        return [], [f"{WORKFLOW_FILE}: no `{ALL_LAYERS_WORKFLOW}` workflow with steps"]
    result = []
    seen: dict[str, str] = {}
    for step in steps:
        name = step.get("name") or ""
        if not name.startswith("plan-"):
            continue
        layer = name[len("plan-"):]
        where = f"{WORKFLOW_FILE}: layer {layer}"
        query = step_query(steps, name, PLAN)
        if query is None:
            errors.append(f"{where}: step {name} is not `terraform plan --query '<query>'`")
            continue
        types = query_types(query)
        if types is None:
            errors.append(f'{where}: query is not a disjunction of .metadata.component == "<type>": {query}')
            continue
        others = {
            f"step deploy-{layer} of `{ALL_LAYERS_WORKFLOW}`": step_query(steps, f"deploy-{layer}", DEPLOY),
            f"workflow deploy-{layer} (plan)": only_query(workflow_steps(workflows, f"deploy-{layer}"), PLAN),
            f"workflow deploy-{layer} (deploy)": only_query(workflow_steps(workflows, f"deploy-{layer}"), DEPLOY),
        }
        for other, other_query in others.items():
            if other_query != query:
                errors.append(f"{where}: {other} does not use the query of step {name} ({other_query!r} != {query!r})")
        for component_type in types:
            if component_type in seen:
                errors.append(f"{where}: {component_type} is also in layer {seen[component_type]}")
            else:
                seen[component_type] = layer
        result.append((layer, types))
    if not result:
        errors.append(f"{WORKFLOW_FILE}: `{ALL_LAYERS_WORKFLOW}` has no plan-<layer> steps")
    return result, errors


def check(stacks: dict, workflow_files: dict) -> list[str]:
    ordered, errors = layers(workflow_files)
    if errors:
        return errors
    names = [layer for layer, _ in ordered]
    index = {t: i for i, (_, types) in enumerate(ordered) for t in types}
    for stack_name, stack in sorted(stacks.items()):
        instances = stack.get("components", {}).get("terraform", {})

        def layer_of(instance: dict) -> Optional[int]:
            return index.get((instance.get("metadata") or {}).get("component"))

        for name, instance in sorted(instances.items()):
            if not check_dependencies.is_deployable(instance):
                continue
            mine = layer_of(instance)
            if mine is None:
                component_type = (instance.get("metadata") or {}).get("component")
                errors.append(
                    f"{stack_name}: {name} (metadata.component {component_type!r}) is in no layer of {WORKFLOW_FILE}"
                )
                continue
            targets = {
                dep.get("component")
                for dep in (instance.get("dependencies") or {}).get("components") or []
                if (dep.get("stack") or stack_name) == stack_name
            }
            targets |= {c for c, s in check_dependencies.references(instance.get("vars", {})) if s in (None, stack_name)}
            for target in sorted(t for t in targets if t):
                dependency = instances.get(target)
                # A missing or disabled target is check-dependencies.py's error to report.
                if dependency is None or not check_dependencies.is_deployable(dependency):
                    continue
                theirs = layer_of(dependency)
                if theirs is not None and theirs > mine:
                    errors.append(
                        f"{stack_name}: {name} (layer {names[mine]}) depends on {target}, "
                        f"which deploys later (layer {names[theirs]})"
                    )
    return errors


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    with open(sys.argv[1]) as stacks_file, open(sys.argv[2]) as workflows_file:
        errors = check(json.load(stacks_file), json.load(workflows_file))
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} deploy layer problem(s)")
        return 1
    print(f"every deployable instance is in a {WORKFLOW_FILE} layer at or after the layers it depends on")
    return 0


if __name__ == "__main__":
    sys.exit(main())

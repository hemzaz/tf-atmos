#!/usr/bin/env python3
"""Check that the layered deploy workflows deploy every instance, and in dependency order.

Usage:
  check-deploy-layers.py <describe-stacks.json> <describe-workflows.json>

<describe-stacks.json> is `atmos describe stacks --process-functions=false --format json`;
<describe-workflows.json> is `atmos describe workflows --output all --format json`
(Atmos parses the YAML, so this needs nothing beyond the python3 stdlib).

A layered workflow is a run of phases. A `terraform plan --query '<q>'` step
starts a phase (it saves a planfile for every instance <q> selects); the
`terraform deploy --from-plan --query '<q>'` steps after it apply those
planfiles. Queries must be disjunctions (` or `) of conjunctions (` and `) of
`.metadata.component` / `.atmos_component` `==` / `!=` "<value>" terms, which
this script evaluates exactly (yq binds `and` tighter than `or`).
`terraform plan <instance>` and `terraform deploy <instance> --from-plan`
select that one instance.

Checked workflows (LAYERED): `deploy` in deploy-full-stack.yaml, which must
select every deployable instance of every stack (COVERAGE); `deploy-app` in
deploy-application.yaml and `full` in bootstrap.yaml, which deploy a subset
(instances they do not select are assumed deployed already). Exits 1 when:
  - a query is not of that form, or a --from-plan step comes before any plan;
  - an instance is planned by two phases, planned but applied by no step or by
    two, or applied by a step whose phase did not plan it;
  - (COVERAGE) an enabled, non-abstract instance is in no phase;
  - an instance reads (!terraform.state / !terraform.output) a same-stack
    instance planned in the same or a later phase: a phase plans everything
    before it applies anything, so on a first deploy that state does not exist;
  - an instance declares (dependencies.components only) a same-stack instance
    that is applied later: in a later phase, or by a later step of its phase.
    Within one step Atmos applies in dependency order.
For deploy-full-stack.yaml, each plan-<layer> step's query must also be the
query of its deploy-<layer> step and of the deploy-<layer> workflow's plan and
deploy steps, so a single layer run selects what the full run selects.
"""
import importlib.util
import json
import pathlib
import re
import sys
from typing import Optional

FULL_STACK_FILE = "deploy-full-stack.yaml"
ALL_LAYERS_WORKFLOW = "deploy"
# (file, workflow, must select every deployable instance)
LAYERED = (
    (FULL_STACK_FILE, ALL_LAYERS_WORKFLOW, True),
    ("deploy-application.yaml", "deploy-app", False),
    ("bootstrap.yaml", "full", False),
)
PLAN = re.compile(r"^terraform plan (?:--log-order \w+ )?--query '(?P<query>[^']*)'$")
DEPLOY = re.compile(r"^terraform deploy --from-plan --query '(?P<query>[^']*)'$")
# One named instance: `terraform plan <instance>` / `terraform deploy <instance> --from-plan`.
PLAN_ONE = re.compile(r"^terraform plan (?P<instance>[\w./-]+)$")
DEPLOY_ONE = re.compile(r"^terraform deploy (?P<instance>[\w./-]+) --from-plan$")
TERM = re.compile(r'^\.(?P<field>metadata\.component|atmos_component) (?P<op>==|!=) "(?P<value>[^"]+)"$')
# A dependencies.components entry with a `stack` other than its own, or any of
# these context keys, names an instance in another stack: not ordered here.
CROSS_STACK_CONTEXT_KEYS = ("namespace", "tenant", "environment", "stage")

_spec = importlib.util.spec_from_file_location(
    "check_dependencies", pathlib.Path(__file__).with_name("check-dependencies.py")
)
check_dependencies = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_dependencies)

Query = list[list[tuple[str, str, str]]]


def parse_query(query: str) -> Optional[Query]:
    """The query as OR-ed lists of AND-ed (field, op, value) terms; None if it is not of that form."""
    disjuncts = []
    for disjunct in query.split(" or "):
        terms = []
        for term in disjunct.split(" and "):
            match = TERM.match(term.strip())
            if match is None:
                return None
            terms.append((match.group("field"), match.group("op"), match.group("value")))
        disjuncts.append(terms)
    return disjuncts


def selects(query: Query, name: str, instance: dict) -> bool:
    fields = {"metadata.component": (instance.get("metadata") or {}).get("component"), "atmos_component": name}
    return any(
        all((fields[field] == value) == (op == "==") for field, op, value in terms) for terms in query
    )


def command(step: dict) -> str:
    return " ".join((step.get("command") or "").split())


def workflow_steps(workflows: dict, name: str) -> list[dict]:
    return ((workflows.get(name) or {}).get("steps")) or []


def phases(steps: list[dict], where: str) -> tuple[list[dict], list[str]]:
    """[{name, plan, deploys: [(step name, query)]}] in step order, plus parse errors."""
    result, errors = [], []
    for step in steps:
        name = step.get("name") or "(unnamed)"
        for pattern, kind in ((PLAN, "plan"), (DEPLOY, "deploy"), (PLAN_ONE, "plan"), (DEPLOY_ONE, "deploy")):
            match = pattern.match(command(step))
            if match is None:
                continue
            if "instance" in match.groupdict():
                query = [[("atmos_component", "==", match.group("instance"))]]
            else:
                query = parse_query(match.group("query"))
            if query is None:
                errors.append(f"{where}: step {name}: query is not an or/and of .metadata.component/.atmos_component terms")
            elif kind == "plan":
                result.append({"name": name, "plan": query, "deploys": []})
            elif not result:
                errors.append(f"{where}: step {name} applies planfiles before any plan step")
            else:
                result[-1]["deploys"].append((name, query))
    if not result:
        errors.append(f"{where}: no `terraform plan --query` step")
    for phase in result:
        if not phase["deploys"]:
            errors.append(f"{where}: plan step {phase['name']} is followed by no deploy --from-plan step")
    return result, errors


def layer_query_drift(workflows: dict) -> list[str]:
    """deploy-full-stack: every plan-<layer> query must match deploy-<layer> and the deploy-<layer> workflow."""
    errors = []
    steps = workflow_steps(workflows, ALL_LAYERS_WORKFLOW)

    def step_query(name: str, pattern: re.Pattern) -> Optional[str]:
        match = next((pattern.match(command(s)) for s in steps if s.get("name") == name), None)
        return match.group("query") if match else None

    def only_query(layer_steps: list[dict], pattern: re.Pattern) -> Optional[str]:
        queries = [m.group("query") for m in (pattern.match(command(s)) for s in layer_steps) if m]
        return queries[0] if len(queries) == 1 else None

    for step in steps:
        name = step.get("name") or ""
        if not name.startswith("plan-"):
            continue
        layer = name[len("plan-"):]
        query = step_query(name, PLAN)
        layer_steps = workflow_steps(workflows, f"deploy-{layer}")
        others = {
            f"step deploy-{layer} of `{ALL_LAYERS_WORKFLOW}`": step_query(f"deploy-{layer}", DEPLOY),
            f"workflow deploy-{layer} (plan)": only_query(layer_steps, PLAN),
            f"workflow deploy-{layer} (deploy)": only_query(layer_steps, DEPLOY),
        }
        for other, other_query in others.items():
            if other_query != query:
                errors.append(
                    f"{FULL_STACK_FILE}: layer {layer}: {other} does not use the query of step {name} "
                    f"({other_query!r} != {query!r})"
                )
    return errors


def dependencies(stack_name: str, instance: dict) -> dict[str, bool]:
    """Same-stack instances this one depends on -> True when it reads their state."""
    result = {
        dep.get("component"): False
        for dep in (instance.get("dependencies") or {}).get("components") or []
        if (dep.get("stack") or stack_name) == stack_name
        and not any(dep.get(key) is not None for key in CROSS_STACK_CONTEXT_KEYS)
    }
    for component, stack in check_dependencies.references(instance.get("vars", {})):
        if stack in (None, stack_name):
            result[component] = True
    return {target: reads for target, reads in result.items() if target}


def place(instances: dict, where: str, ordered: list[dict], coverage: bool) -> tuple[dict, list[str]]:
    """instance -> (phase index, deploy step index within the phase), plus selection errors."""
    placed: dict[str, tuple[int, int]] = {}
    errors = []
    for name, instance in sorted(instances.items()):
        if not check_dependencies.is_deployable(instance):
            continue
        planned = [i for i, phase in enumerate(ordered) if selects(phase["plan"], name, instance)]
        for i, phase in enumerate(ordered):
            for step, query in phase["deploys"]:
                if i not in planned and selects(query, name, instance):
                    errors.append(f"{where}{name} is applied by step {step}, whose phase did not plan it")
        if not planned:
            if coverage:
                component_type = (instance.get("metadata") or {}).get("component")
                errors.append(f"{where}{name} (metadata.component {component_type!r}) is in no layer")
            continue
        if len(planned) > 1:
            steps = ", ".join(ordered[i]["name"] for i in planned)
            errors.append(f"{where}{name} is planned by more than one step: {steps}")
            continue
        phase = ordered[planned[0]]
        applied = [j for j, (_, query) in enumerate(phase["deploys"]) if selects(query, name, instance)]
        if len(applied) != 1:
            steps = ", ".join(phase["deploys"][j][0] for j in applied) or "no step"
            errors.append(f"{where}{name} is planned by {phase['name']} but applied by {steps}")
            continue
        placed[name] = (planned[0], applied[0])
    return placed, errors


def order_errors(stack_name: str, instances: dict, placed: dict, where: str, ordered: list[dict]) -> list[str]:
    errors = []
    for name, (mine, my_step) in sorted(placed.items()):
        for target, reads in sorted(dependencies(stack_name, instances[name]).items()):
            # Unselected (assumed deployed), missing or disabled: check-dependencies.py reports the latter two.
            if target not in placed:
                continue
            theirs, their_step = placed[target]
            reader = f"{where}{name} (plan step {ordered[mine]['name']})"
            if reads and theirs == mine:
                errors.append(f"{reader} reads {target}, which is planned in the same phase, before it is applied")
            elif reads and theirs > mine:
                errors.append(f"{reader} reads {target}, which deploys later (plan step {ordered[theirs]['name']})")
            elif theirs > mine or (theirs == mine and their_step > my_step):
                step = ordered[theirs]["deploys"][their_step][0]
                errors.append(f"{reader} depends on {target}, which deploys later (step {step})")
    return errors


def check_workflow(stacks: dict, where: str, ordered: list[dict], coverage: bool) -> list[str]:
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        instances = stack.get("components", {}).get("terraform", {})
        prefix = f"{where}: {stack_name}: "
        placed, place_errors = place(instances, prefix, ordered, coverage)
        errors += place_errors + order_errors(stack_name, instances, placed, prefix, ordered)
    return errors


def check(stacks: dict, workflow_files: dict) -> list[str]:
    errors = []
    for file_name, workflow, coverage in LAYERED:
        workflows = (workflow_files.get(file_name) or {}).get("workflows") or {}
        where = f"{file_name} `{workflow}`"
        steps = workflow_steps(workflows, workflow)
        if not steps:
            errors.append(f"{where}: no such workflow with steps")
            continue
        ordered, parse_errors = phases(steps, where)
        if file_name == FULL_STACK_FILE:
            parse_errors += layer_query_drift(workflows)
        errors += parse_errors or check_workflow(stacks, where, ordered, coverage)
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
    print(
        "every deployable instance is in exactly one deploy-full-stack layer, and every layered "
        "workflow plans an instance only after the instances it reads are applied"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

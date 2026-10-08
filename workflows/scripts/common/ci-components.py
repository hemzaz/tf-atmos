#!/usr/bin/env python3
"""Print, in dependency order, the terraform instances of --stack one kind of runner may run.

terraform-cd.yml, drift-detection.yml and terraform-ci.yml loop over this list
(one `atmos terraform <cmd> <component> -s <stack>` each) instead of Atmos's own
stack-wide `deploy --affected` / `plan -s <stack>`, because:
  - instances run on two kinds of runner. GitHub-hosted runners (--runner
    hosted, the default) cannot reach a private EKS API, so the in-cluster
    components (settings.github.runner: in-vpc) run on the stack's self-hosted
    runners in the VPC (--runner in-vpc --label <label>; the github-runners
    component, docs/OPERATIONS.md "In-cluster components"). An instance with
    settings.github.actions_enabled: false runs on neither (an operator
    applies it). Atmos 1.229 rejects --query together with --affected;
  - a stack-wide bulk run builds the dependency graph from the filtered set
    alone and fails on any dependency outside it (iam/ci -> fnx-ue1-root's
    backend/main).
Order: a topological sort of the stack's deployable instances over their
same-stack dependencies.components (the list check-dependencies.py enforces
for every !terraform.state read), ties broken by name. With --base, only the
instances `atmos describe affected --base <sha> -s <stack>` reports.

An in-vpc instance runs on the runners labelled settings.github.runner_label,
by default the stack's full id, its name (as check-cluster-api-ci.py resolves
it, and as the github-runners catalog registers it from {{ .atmos_stack }}). --pools prints, instead of instances,
one JSON object per line for each label the selected in-vpc instances need:
{"label", "pool", "asg", "instances"}, the github-runners instance registering
that label, its Auto Scaling group (<tags.Environment>-<vars.name>), whose
start policy CI executes once per job (start-runner.sh), and the selected
instances of that label, in order.

Skipped instances are reported as a ::notice:: and errors as ::error:: on stderr
(callers capture stdout). Exits 1 on an unknown stack, a dependency cycle, or
(--pools) a label no deployable github-runners instance registers.
"""
import argparse
import json
import subprocess
import sys
from typing import Optional

RUNNERS = ("hosted", "in-vpc")
RUNNER_COMPONENT = "github-runners"
RUNNER_POOL_DEFAULT_NAME = "github-runners"


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def github_settings(instance: dict) -> dict:
    return ((instance.get("settings") or {}).get("github")) or {}


def ci_enabled(instance: dict) -> bool:
    return github_settings(instance).get("actions_enabled") is not False


def runner_of(instance: dict) -> str:
    return "in-vpc" if github_settings(instance).get("runner") == "in-vpc" else "hosted"


def runner_label(stack: str, instance: dict) -> str:
    """settings.github.runner_label, else the stack's full id: its name (check-cluster-api-ci.py's rule)."""
    return github_settings(instance).get("runner_label") or stack


def component_of(instance: dict) -> Optional[str]:
    return instance.get("component") or (instance.get("metadata") or {}).get("component")


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


def select(
    instances: dict,
    stack: str,
    affected: Optional[set] = None,
    runner: str = "hosted",
    label: Optional[str] = None,
) -> tuple[list[str], list[str]]:
    """(instances this runner runs, in order; instances skipped because actions_enabled is false)."""
    run, skipped = [], []
    for name in dependency_order(instances, stack):
        if affected is not None and name not in affected:
            continue
        instance = instances[name]
        if not ci_enabled(instance):
            skipped.append(name)
        elif runner_of(instance) == runner and (label is None or runner_label(stack, instance) == label):
            run.append(name)
    return run, skipped


def pools(instances: dict, stack: str, selected: list[str]) -> list[dict]:
    """{"label", "pool", "asg", "instances"} for each label the selected in-vpc instances need, by label."""
    needed = sorted({runner_label(stack, instances[name]) for name in selected if runner_of(instances[name]) == "in-vpc"})
    result = []
    for label in needed:
        registering = sorted(
            name for name, instance in instances.items()
            if component_of(instance) == RUNNER_COMPONENT and is_deployable(instance)
            and label in ((instance.get("vars") or {}).get("runner_labels") or [])
        )
        if not registering:
            raise LookupError(f"no deployable {RUNNER_COMPONENT} instance registers the label {label!r}")
        pool = registering[0]
        variables = instances[pool].get("vars") or {}
        environment = (variables.get("tags") or {}).get("Environment")
        result.append({
            "label": label,
            "pool": pool,
            "asg": f"{environment}-{variables.get('name') or RUNNER_POOL_DEFAULT_NAME}",
            "instances": [
                name for name in selected
                if runner_of(instances[name]) == "in-vpc" and runner_label(stack, instances[name]) == label
            ],
        })
    return result


def atmos_json(*args: str):
    return json.loads(subprocess.check_output(["atmos", *args, "--process-functions=false", "--format", "json"]))


def stack_instances(stack: str, describe=None) -> dict:
    """The stack's terraform instances; LookupError when Atmos does not know the stack.

    `atmos describe stacks -s <unknown>` prints {} on some Atmos versions and
    exits non-zero on others, so both mean an unknown stack.
    """
    try:
        stacks = (describe or atmos_json)(
            "describe", "stacks", "-s", stack, "--sections", "metadata,settings,dependencies,vars"
        )
    except subprocess.CalledProcessError as error:
        raise LookupError(f"Unknown stack '{stack}' (atmos describe stacks exited {error.returncode})") from error
    if stack not in stacks:
        raise LookupError(f"Unknown stack '{stack}'")
    return (stacks[stack].get("components") or {}).get("terraform") or {}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--stack", required=True)
    parser.add_argument("--base", help="only instances affected since this commit")
    parser.add_argument("--runner", choices=RUNNERS, default="hosted")
    parser.add_argument("--label", help="with --runner in-vpc: only the instances whose runner label is this")
    parser.add_argument("--pools", action="store_true",
                        help="print the runner pools the selected in-vpc instances need (JSON lines)")
    parser.add_argument("--only", help="only this instance (e.g. a workflow_dispatch component)")
    args = parser.parse_args()

    try:
        instances = stack_instances(args.stack)
    except LookupError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    affected = None
    if args.base:
        affected = {
            item["component"]
            for item in atmos_json("describe", "affected", "--base", args.base, "-s", args.stack)
            if item.get("stack") == args.stack and item.get("component_type") == "terraform"
        }
    runner = "in-vpc" if args.pools else args.runner
    try:
        run, skipped = select(instances, args.stack, affected, runner, args.label)
    except ValueError as error:
        print(f"::error::{args.stack}: {error}", file=sys.stderr)
        return 1
    if args.only:
        run = [name for name in run if name == args.only]
    if skipped:
        print(
            f"::notice::{args.stack}: skipping {', '.join(skipped)} (settings.github.actions_enabled: false)",
            file=sys.stderr,
        )
    if args.pools:
        try:
            for pool in pools(instances, args.stack, run):
                print(json.dumps(pool, sort_keys=True))
        except LookupError as error:
            print(f"::error::{args.stack}: {error}", file=sys.stderr)
            return 1
        return 0
    for name in run:
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())

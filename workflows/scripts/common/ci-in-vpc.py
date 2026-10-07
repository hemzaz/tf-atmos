#!/usr/bin/env python3
"""The in-VPC halves of the CI matrices (the in-cluster components, settings.github.runner: in-vpc).

  split            terraform-ci.yml: reads an affected matrix {"include": [{"stack", "component", ...}]}
                   on stdin and prints {"hosted": <matrix>, "in_vpc": <matrix>}: the hosted
                   runners' entries unchanged, and one in-VPC entry per (stack, runner label)
                   {"stack", "label", "asg", "components"} (space-separated, sorted) for
                   in-vpc.yml.
  missing <stack>  terraform-cd.yml's mark-deployed: prints the runner labels of <stack> in
                   $IN_VPC (the in-VPC deploy matrix) whose marker
                   <markers>/in-vpc-<stack>--<label>/sha is missing, space-separated. A stack
                   moves deployed/<stack> only when this prints nothing.

The runner pools come from ci-components.py --pools.
"""
import argparse
import json
import os
import pathlib
import subprocess
import sys
from typing import Callable

CI_COMPONENTS = pathlib.Path(__file__).with_name("ci-components.py")


def stack_pools(stack: str) -> list[dict]:
    """ci-components.py --pools for every in-vpc instance of the stack."""
    out = subprocess.check_output([sys.executable, str(CI_COMPONENTS), "--stack", stack, "--pools"], text=True)
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def split(include: list[dict], pools_of: Callable[[str], list[dict]] = stack_pools) -> tuple[list[dict], list[dict]]:
    """(hosted entries, in-VPC entries grouped per (stack, label))."""
    hosted, groups, by_stack = [], {}, {}
    for item in include:
        stack = item.get("stack")
        if stack not in by_stack:
            by_stack[stack] = {name: pool for pool in pools_of(stack) for name in pool["instances"]}
        pool = by_stack[stack].get(item.get("component"))
        if pool is None:
            hosted.append(item)
            continue
        group = groups.setdefault(
            (stack, pool["label"]), {"stack": stack, "label": pool["label"], "asg": pool["asg"], "components": set()}
        )
        group["components"].add(item["component"])
    in_vpc = [dict(group, components=" ".join(sorted(group["components"]))) for _, group in sorted(groups.items())]
    return hosted, in_vpc


def missing(stack: str, in_vpc: dict, markers: pathlib.Path) -> list[str]:
    """Labels of the stack's in-VPC deploys that left no marker."""
    labels = [entry["label"] for entry in in_vpc.get("include", []) if entry.get("stack") == stack]
    return [label for label in labels if not (markers / f"in-vpc-{stack}--{label}" / "sha").is_file()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("split")
    gate = sub.add_parser("missing")
    gate.add_argument("stack")
    gate.add_argument("--markers", default="in-vpc-markers")
    args = parser.parse_args()

    if args.command == "split":
        hosted, in_vpc = split(json.load(sys.stdin).get("include", []))
        print(json.dumps({"hosted": {"include": hosted}, "in_vpc": {"include": in_vpc}}))
        return 0
    print(" ".join(missing(args.stack, json.loads(os.environ.get("IN_VPC") or "{}"), pathlib.Path(args.markers))))
    return 0


if __name__ == "__main__":
    sys.exit(main())

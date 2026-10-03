#!/usr/bin/env python3
"""Print, one per line in promotion order, the stacks a CI workflow runs against.

Derived from `atmos describe stacks`, so a new stack under stacks/orgs/ flows
through CD, DR and plan-sweep with no workflow edit (Cloud Posse's Atmos
GitHub Actions derive their stack sets from describe affected / describe
stacks the same way):

  (default)        stacks a hosted runner deploys, plans and checks: every stack
                   except those whose terraform instances ALL set
                   settings.github.actions_enabled: false (fnx-core-root,
                   fnx-local-*, fnx-fixtures-*). terraform-cd.yml, and
                   drift-detection.yml's identical inline rule.
  --check STACK    exit 1 with an ::error:: unless STACK is in that list
                   (workflow_dispatch inputs of terraform-cd.yml and
                   disaster-recovery.yml).
  --plan-sweep     scripts/plan-sweep.sh's default: every stack except the
                   stages in PLAN_SWEEP_EXCLUDED_STAGES.

Order: settings.context.stage by STAGE_ORDER (dev, staging, prod), other
stages after them, ties by stack name.
"""
import argparse
import json
import subprocess
import sys

# Promotion order: CD deploys dev before staging before prod.
STAGE_ORDER = ("dev", "staging", "prod")

# Stages plan-sweep deliberately skips (everything else, the template
# fixtures included, is swept):
PLAN_SWEEP_EXCLUDED_STAGES = {
    "core": "fnx-core-root holds only the state backend, bootstrapped by an operator",
    "local": "emulator-only stacks; the sandbox/LocalEmu lanes apply them for real",
}


def instances(config: dict) -> dict:
    return ((config or {}).get("components") or {}).get("terraform") or {}


def stage(config: dict):
    """The stack's settings.context.stage (every instance inherits the same one)."""
    stages = {
        (((spec or {}).get("settings") or {}).get("context") or {}).get("stage")
        for spec in instances(config).values()
    } - {None}
    return stages.pop() if len(stages) == 1 else None


def ci_disabled(config: dict) -> bool:
    """True when EVERY terraform instance opts out of hosted CI."""
    specs = instances(config).values()
    return bool(specs) and all(
        (((spec or {}).get("settings") or {}).get("github") or {}).get("actions_enabled") is False
        for spec in specs
    )


def ordered(stacks: dict, names) -> list:
    def key(name):
        s = stage(stacks[name])
        return (STAGE_ORDER.index(s) if s in STAGE_ORDER else len(STAGE_ORDER), name)

    return sorted(names, key=key)


def ci_stacks(stacks: dict) -> list:
    return ordered(stacks, (name for name, config in stacks.items() if not ci_disabled(config)))


def plan_sweep_stacks(stacks: dict) -> list:
    return ordered(
        stacks, (name for name, config in stacks.items() if stage(config) not in PLAN_SWEEP_EXCLUDED_STAGES)
    )


def check(stacks: dict, name: str) -> str:
    """'' when `name` is a CI stack, else the reason it is not."""
    if name not in stacks:
        return f"Unknown stack {name!r}"
    if ci_disabled(stacks[name]):
        return f"{name!r} has settings.github.actions_enabled: false on every instance; CI does not run against it"
    return ""


def describe_stacks() -> dict:
    return json.loads(subprocess.check_output(
        ["atmos", "describe", "stacks", "--process-functions=false", "--format", "json", "--sections", "settings"]))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", metavar="STACK")
    mode.add_argument("--plan-sweep", action="store_true")
    args = parser.parse_args()

    stacks = describe_stacks()
    if args.check is not None:
        error = check(stacks, args.check)
        if error:
            print(f"::error::{error}")
            return 1
        print(args.check)
        return 0
    names = plan_sweep_stacks(stacks) if args.plan_sweep else ci_stacks(stacks)
    if not names:
        print("::error::no stacks selected", file=sys.stderr)
        return 1
    for name in names:
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())

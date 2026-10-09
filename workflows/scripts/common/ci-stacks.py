#!/usr/bin/env python3
"""Print, one per line in promotion order, the stacks a CI workflow runs against.

Derived from `atmos describe stacks`, so a new stack under stacks/orgs/ flows
through CD, DR and plan-sweep with no workflow edit (Cloud Posse's Atmos
GitHub Actions derive their stack sets from describe affected / describe
stacks the same way):

  (default)        stacks a hosted runner deploys, plans and checks: every stack
                   except those whose terraform instances ALL set
                   settings.github.actions_enabled: false (fnx-ue1-root, fnx-ew1-root,
                   fnx-ue1-local-*, fnx-ue1-fixtures-*). terraform-cd.yml and
                   drift-detection.yml. Every selected stack's stage must be
                   in STAGE_ORDER, or CD could not place it in the promotion.
  --check STACK    exit 1 with an ::error:: unless STACK is in that list
                   (workflow_dispatch inputs of terraform-cd.yml and
                   disaster-recovery.yml).
  --plan-sweep     scripts/plan-sweep.sh's default: every stack except the
                   stages in PLAN_SWEEP_EXCLUDED_STAGES.

stdout carries only stack names; every ::error:: goes to stderr, so a caller
that captures stdout (subprocess.check_output) still shows the reason.

Order: settings.context.stage by STAGE_ORDER (dev, staging, prod), other
stages (plan-sweep's fixtures) after them; within a stage, a DR standby
(settings.dr.standby_of: <primary stack>, fnx-ue2-prod) right after the stack
it stands by for, which it reads through !terraform.state; other ties by stack
name. A selected stack without exactly one stage, or a standby whose primary is
not a selected stack of the same stage, is an error in both list modes.
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
    "root": "fnx-ue1-root and fnx-ew1-root hold only the state backends, bootstrapped by an operator",
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


def standby_of(config: dict):
    """The stack's settings.dr.standby_of (its DR primary), or None."""
    primaries = {
        (((spec or {}).get("settings") or {}).get("dr") or {}).get("standby_of")
        for spec in instances(config).values()
    } - {None}
    return primaries.pop() if len(primaries) == 1 else None


def ci_disabled(config: dict) -> bool:
    """True when EVERY terraform instance opts out of hosted CI."""
    specs = instances(config).values()
    return bool(specs) and all(
        (((spec or {}).get("settings") or {}).get("github") or {}).get("actions_enabled") is False
        for spec in specs
    )


def ordered(stacks: dict, names) -> list:
    """`names` by stage rank, then name; ValueError for a stack without exactly one stage."""
    names = list(names)
    for name in names:
        if stage(stacks[name]) is None:
            raise ValueError(
                f"{name!r} has no single settings.context.stage (no terraform instances, or mixed stages)"
            )

    selected = set(names)
    for name in names:
        primary = standby_of(stacks[name])
        if primary is None:
            continue
        if primary not in selected or stage(stacks[primary]) != stage(stacks[name]):
            raise ValueError(
                f"{name!r} is a DR standby of {primary!r} (settings.dr.standby_of), which is not a selected "
                f"stack of stage {stage(stacks[name])!r}: the standby reads its primary's state, so the "
                "primary must deploy first"
            )
        if standby_of(stacks[primary]) is not None:
            raise ValueError(f"{name!r} is a standby of {primary!r}, which is itself a standby: chains are not supported")

    def key(name):
        s = stage(stacks[name])
        # A standby sorts with its primary, right after it, whatever the names.
        primary = standby_of(stacks[name])
        return (STAGE_ORDER.index(s) if s in STAGE_ORDER else len(STAGE_ORDER), primary or name, primary is not None, name)

    return sorted(names, key=key)


def ci_stacks(stacks: dict) -> list:
    """The CI stacks in promotion order; ValueError for a stage outside STAGE_ORDER."""
    names = ordered(stacks, (name for name, config in stacks.items() if not ci_disabled(config)))
    for name in names:
        if stage(stacks[name]) not in STAGE_ORDER:
            raise ValueError(
                f"{name!r} has stage {stage(stacks[name])!r}, which is not in STAGE_ORDER {STAGE_ORDER}: "
                "add it to STAGE_ORDER in workflows/scripts/common/ci-stacks.py where it belongs in the "
                "promotion, or CD cannot order it"
            )
    return names


def plan_sweep_stacks(stacks: dict) -> list:
    names = [name for name, config in stacks.items() if stage(config) not in PLAN_SWEEP_EXCLUDED_STAGES]
    return ordered(stacks, names)


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
            print(f"::error::{error}", file=sys.stderr)
            return 1
        print(args.check)
        return 0
    try:
        names = plan_sweep_stacks(stacks) if args.plan_sweep else ci_stacks(stacks)
    except ValueError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    if not names:
        print("::error::no stacks selected", file=sys.stderr)
        return 1
    for name in names:
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())

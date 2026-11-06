#!/usr/bin/env python3
"""Split `atmos sweep --all` into the legs of terraform-ci.yml's plan-sweep matrix.

  sweep-shards.py [--chunks N]

Prints one JSON object, {"include": [{"name": ..., "args": ...}, ...]}: N legs of
`-s <stacks>` that together hold exactly the stacks plan-sweep.sh's default sweeps
(ci-stacks.py --plan-sweep), then `--samples` and `--scaffold`, the other two parts
of --all. A leg's args are passed to `atmos sweep` as they are.

Stacks are balanced by the pairs each plans (its deployable terraform instances),
not by stack count: a core stack plans a handful, a workload stack fifty. Greedy
longest-first onto the lightest leg; inside a leg, stacks keep promotion order.

Coverage is the point of the sweep, so the split is checked before it is printed:
the legs' stacks must be exactly the --plan-sweep set, each once, every leg
non-empty, and the template fixtures among them (plan-sweep.sh refuses a default
run without them). Anything else is an ::error:: and exit 1, never a smaller sweep.
"""
import argparse
import importlib.util
import json
import pathlib
import sys

_spec = importlib.util.spec_from_file_location("ci_stacks", pathlib.Path(__file__).with_name("ci-stacks.py"))
ci_stacks = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ci_stacks)

DEFAULT_CHUNKS = 6
FIXTURE_PREFIX = "fnx-ue1-fixtures-"


def weight(config: dict) -> int:
    """The pairs a stack plans: its deployable terraform instances (at least 1)."""
    return max(1, sum(1 for spec in ci_stacks.instances(config).values() if ci_stacks.deployable(spec)))


def balance(names: list, weights: dict, chunks: int) -> list:
    """`names` split into at most `chunks` non-empty lists of near-equal total weight."""
    bins = [[] for _ in range(min(chunks, len(names)))]
    loads = [0] * len(bins)
    for name in sorted(names, key=lambda n: (-weights[n], names.index(n))):
        i = loads.index(min(loads))
        bins[i].append(name)
        loads[i] += weights[name]
    order = {name: i for i, name in enumerate(names)}
    return [sorted(b, key=order.get) for b in bins]


def parity_errors(expected: list, chunks: list) -> list:
    """Why `chunks` does not cover `expected` exactly once each ([] when it does)."""
    errors = []
    flat = [name for chunk in chunks for name in chunk]
    duplicated = sorted({name for name in flat if flat.count(name) > 1})
    missing = sorted(set(expected) - set(flat))
    extra = sorted(set(flat) - set(expected))
    if duplicated:
        errors.append(f"stacks in more than one leg: {', '.join(duplicated)}")
    if missing:
        errors.append(f"stacks in no leg: {', '.join(missing)}")
    if extra:
        errors.append(f"stacks no --plan-sweep run selects: {', '.join(extra)}")
    if any(not chunk for chunk in chunks):
        errors.append("an empty leg")
    if not any(name.startswith(FIXTURE_PREFIX) for name in flat):
        errors.append(f"no {FIXTURE_PREFIX}* stacks; plan-sweep.sh refuses to sweep without them")
    return errors


def matrix(chunks: list) -> dict:
    legs = [{"name": f"stacks {i + 1}/{len(chunks)}", "args": "-s " + ",".join(chunk)} for i, chunk in enumerate(chunks)]
    legs += [{"name": "samples", "args": "--samples"}, {"name": "scaffold", "args": "--scaffold"}]
    return {"include": legs}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--chunks", type=int, default=DEFAULT_CHUNKS)
    args = parser.parse_args()
    if args.chunks < 1:
        parser.error("--chunks must be at least 1")

    stacks = ci_stacks.describe_stacks()
    try:
        names = ci_stacks.plan_sweep_stacks(stacks)
    except ValueError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    weights = {name: weight(stacks[name]) for name in names}
    chunks = balance(names, weights, args.chunks)

    errors = parity_errors(names, chunks)
    if errors:
        for error in errors:
            print(f"::error::sweep shards do not cover the --plan-sweep stacks exactly: {error}", file=sys.stderr)
        return 1
    for chunk in chunks:
        print(f"{sum(weights[n] for n in chunk):4d} pairs: {' '.join(chunk)}", file=sys.stderr)
    print(json.dumps(matrix(chunks)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Fail a CD deploy of a prod instance whose plan deletes or replaces a resource nobody allowed.

Usage (deploy-component.sh, one instance per call):
  atmos terraform show <component> -s <stack> -json <planfile> \\
    | check-plan-destroys.py --stack <stack> --component <component> --base <sha>

Reads `terraform show -json <planfile>` on stdin (lines before the JSON
document, such as Atmos and init output, are skipped) and lists every
resource change whose actions contain "delete": a destroy (["delete"]) or a
replace (["delete", "create"] or ["create", "delete"]).

Protected stacks are stage prod (settings.context.stage) and every DR standby
(settings.dr.standby_of; ci-stacks.py requires a standby to share its
primary's stage, so today these are the prod standbys). There each such
change must be allowed by an `Allow-Destroy:` trailer on a commit in
<base>..<head> (the commits this stack is being deployed for, from its
deployed/<stack> tag), one trailer per address, either
  Allow-Destroy: <resource address>                        (any instance, any stack)
  Allow-Destroy: <component>/<stack>:<resource address>    (that instance only)
with the address exactly as the plan prints it (aws_s3_bucket.this["logs"]).
An unallowed change fails (exit 1), before anything is applied. Other stages
only report: a ::warning:: and a job summary entry per change, never a failure.
Exits 2 when stdin holds no plan JSON (fail closed).
"""
import argparse
import json
import os
import subprocess
import sys

TRAILER = "Allow-Destroy"
PROTECTED_STAGES = ("prod",)


def load_plan(text: str) -> dict:
    """The plan document: the first line that parses as a JSON object, else the whole text."""
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue
    return json.loads(text)


def destroys(plan: dict) -> list[tuple[str, list[str]]]:
    """(address, actions) of every managed resource change that deletes, in plan order."""
    found = []
    for change in plan.get("resource_changes") or []:
        if change.get("mode", "managed") != "managed":
            continue
        actions = (change.get("change") or {}).get("actions") or []
        if "delete" in actions:
            address = change.get("address") or "?"
            if change.get("deposed"):
                address = f"{address} (deposed {change['deposed']})"
            found.append((address, actions))
    return found


def protected(settings: dict) -> bool:
    """True for a prod stage stack or a DR standby."""
    settings = settings or {}
    stage = (settings.get("context") or {}).get("stage")
    return stage in PROTECTED_STAGES or bool((settings.get("dr") or {}).get("standby_of"))


def parse_trailers(text: str) -> set[str]:
    """The Allow-Destroy values, one per non-empty line of `git log --format=%(trailers:...)`."""
    return {line.strip() for line in text.splitlines() if line.strip()}


def is_allowed(address: str, stack: str, component: str, allows: set[str]) -> bool:
    return address in allows or f"{component}/{stack}:{address}" in allows


def check(plan: dict, stack: str, component: str, settings: dict, allows: set[str]) -> tuple[list[str], list[str]]:
    """(errors, notes): errors fail the deploy; notes are reported only."""
    errors, notes = [], []
    enforce = protected(settings)
    for address, actions in destroys(plan):
        what = f"{component} in {stack}: {address} ({'replace' if len(actions) > 1 else 'destroy'}, actions {actions})"
        if not enforce:
            notes.append(what)
        elif is_allowed(address, stack, component, allows):
            notes.append(f"{what}, allowed by an {TRAILER} trailer")
        else:
            errors.append(
                f"{what}: not applied. If intended, merge a commit whose message ends with the trailer "
                f"'{TRAILER}: {address}' (or '{TRAILER}: {component}/{stack}:{address}')"
            )
    return errors, notes


def component_settings(component: str, stack: str) -> dict:
    out = subprocess.check_output(
        ["atmos", "describe", "component", component, "-s", stack,
         "--process-functions=false", "--provenance=false", "--format", "json"])
    return json.loads(out).get("settings") or {}


def trailers(base: str, head: str) -> set[str]:
    """Allow-Destroy values of every commit in base..head (the stack's undeployed commits)."""
    out = subprocess.check_output(
        ["git", "log", f"--format=%(trailers:key={TRAILER},valueonly,unfold)", f"{base}..{head}"], text=True)
    return parse_trailers(out)


def summarize(lines: list[str]) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path and lines:
        with open(path, "a") as out:
            out.write("".join(f"- {line}\n" for line in lines))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--stack", required=True)
    parser.add_argument("--component", required=True)
    parser.add_argument("--base", required=True, help="the stack's last deployed commit (deployed/<stack>)")
    parser.add_argument("--head", default=os.environ.get("GITHUB_SHA", "HEAD"))
    args = parser.parse_args()
    try:
        plan = load_plan(sys.stdin.read())
    except json.JSONDecodeError:
        print(f"::error::{args.component} in {args.stack}: stdin holds no `terraform show -json` plan document")
        return 2
    try:
        settings = component_settings(args.component, args.stack)
        enforce = protected(settings)
        allows = trailers(args.base, args.head) if enforce else set()
    except subprocess.CalledProcessError as error:
        print(f"::error::{args.component} in {args.stack}: {' '.join(error.cmd[:3])} failed; not applying")
        return 1
    errors, notes = check(plan, args.stack, args.component, settings, allows)
    for note in notes:
        print(f"::{'notice' if enforce else 'warning'} title=Plan deletes::{note}")
    for error in errors:
        print(f"::error title=Destroy not allowed::{error}")
    summarize([f"⚠️ {note}" for note in notes] + [f"❌ {error}" for error in errors])
    if errors:
        return 1
    print(f"{args.component} in {args.stack}: {len(notes)} delete(s) in the plan, none blocking")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Decide a CD deploy from its planfile: block unallowed prod deletes, skip a plan without changes.

Usage (deploy-component.sh, one instance per call):
  atmos terraform show <component> -s <stack> -json <planfile> \\
    | check-plan-destroys.py --stack <stack> --component <component> --base <sha>
  atmos terraform show ... -json <planfile> | check-plan-destroys.py --changes-only   (drift)

Reads `terraform show -json <planfile>` on stdin (lines before the plan
document, such as Atmos and init output, are skipped). The decision comes
from the plan JSON, never from `plan -detailed-exitcode`: with ci.enabled
(atmos.yaml) Atmos maps plan's exit code 2 to 0, so the exit code cannot say
whether the plan changes anything.

Every managed resource change whose actions contain "delete" is a destroy
(["delete"]) or a replace (["delete", "create"] or ["create", "delete"]).
Protected stacks are stage prod (settings.context.stage) and every DR standby
(settings.dr.standby_of; ci-stacks.py requires a standby to share its
primary's stage, so today these are the prod standbys). There each such
change must be allowed by a trailer on a commit in <base>..<head> (the
commits this stack is being deployed for, from its deployed/<stack> tag):
  Allow-Destroy: <component>/<stack>:<resource address>
one per change, the address exactly as the plan prints it
(s3-bucket/logs/fnx-ue1-prod:aws_s3_bucket.this["logs"]). Only this scoped
form: a bare address (aws_iam_role.default[0]) repeats across components
and stacks. A deposed object's delete (the leftover of a failed
create_before_destroy) needs no trailer and is reported as a warning. Other
stages only report: a ::warning:: and a job summary entry per change.

Exit codes: 0 apply (or, --changes-only, the plan changes something);
1 an unallowed delete, or a failed describe/git call; 2 stdin holds no plan
document (fail closed); 3 the plan changes nothing (no resource action
outside no-op/read, no output change): nothing to apply.
"""
import argparse
import json
import os
import subprocess
import sys

TRAILER = "Allow-Destroy"
PROTECTED_STAGES = ("prod",)
NO_CHANGE_ACTIONS = {"no-op", "read"}
NO_CHANGES = 3


def is_plan(document) -> bool:
    return isinstance(document, dict) and "format_version" in document and (
        "resource_changes" in document or "planned_values" in document)


def load_plan(text: str) -> dict:
    """The plan document: the first line that parses as one, else the whole text; ValueError if none."""
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                document = json.loads(line)
            except json.JSONDecodeError:
                continue
            if is_plan(document):
                return document
    try:
        document = json.loads(text)
    except json.JSONDecodeError:
        document = None
    if not is_plan(document):
        raise ValueError("no `terraform show -json` plan document")
    return document


def actions_of(change: dict) -> list[str]:
    return (change.get("change") or {}).get("actions") or []


def has_changes(plan: dict) -> bool:
    """True when applying the plan changes something: a resource action outside no-op/read (a moved
    or imported no-op still updates state), or an output change."""
    for change in plan.get("resource_changes") or []:
        if set(actions_of(change)) - NO_CHANGE_ACTIONS:
            return True
        details = change.get("change") or {}
        if change.get("previous_address") or details.get("importing"):
            return True
    return any(set((output or {}).get("actions") or []) - {"no-op"}
               for output in (plan.get("output_changes") or {}).values())


def destroys(plan: dict) -> list[tuple[str, list[str], bool]]:
    """(address, actions, deposed) of every managed resource change that deletes, in plan order."""
    found = []
    for change in plan.get("resource_changes") or []:
        if change.get("mode", "managed") != "managed":
            continue
        actions = actions_of(change)
        if "delete" in actions:
            found.append((change.get("address") or "?", actions, bool(change.get("deposed"))))
    return found


def protected(settings: dict) -> bool:
    """True for a prod stage stack or a DR standby."""
    settings = settings or {}
    stage = (settings.get("context") or {}).get("stage")
    return stage in PROTECTED_STAGES or bool((settings.get("dr") or {}).get("standby_of"))


def parse_trailers(text: str) -> set[str]:
    """The Allow-Destroy values, one per non-empty line of `git log --format=%(trailers:...)`."""
    return {line.strip() for line in text.splitlines() if line.strip()}


def scoped(component: str, stack: str, address: str) -> str:
    return f"{component}/{stack}:{address}"


def check(plan: dict, stack: str, component: str, settings: dict, allows: set[str]):
    """(errors, notes): errors fail the deploy; notes are (level, text), reported only."""
    errors, notes = [], []
    enforce = protected(settings)
    for address, actions, deposed in destroys(plan):
        kind = "replace" if len(actions) > 1 else "destroy"
        what = f"{component} in {stack}: {address} ({kind}, actions {actions})"
        if deposed:
            notes.append(("warning", f"{what}: a deposed object (failed create_before_destroy) is cleaned up"))
        elif not enforce:
            notes.append(("warning", what))
        elif scoped(component, stack, address) in allows:
            notes.append(("notice", f"{what}, allowed by an {TRAILER} trailer"))
        else:
            errors.append(
                f"{what}: not applied. If intended, merge a commit whose message ends with the trailer "
                f"'{TRAILER}: {scoped(component, stack, address)}'"
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
    parser.add_argument("--changes-only", action="store_true", help="only report whether the plan changes anything")
    parser.add_argument("--stack")
    parser.add_argument("--component")
    parser.add_argument("--base", help="the stack's last deployed commit (deployed/<stack>)")
    parser.add_argument("--head", default=os.environ.get("GITHUB_SHA", "HEAD"))
    args = parser.parse_args()
    if not args.changes_only and not (args.stack and args.component and args.base):
        parser.error("--stack, --component and --base are required unless --changes-only")
    try:
        plan = load_plan(sys.stdin.read())
    except ValueError as error:
        print(f"::error::{args.component or 'plan'} in {args.stack or '?'}: stdin holds {error}")
        return 2
    if args.changes_only:
        return 0 if has_changes(plan) else NO_CHANGES
    try:
        settings = component_settings(args.component, args.stack)
        allows = trailers(args.base, args.head) if protected(settings) else set()
    except subprocess.CalledProcessError as error:
        print(f"::error::{args.component} in {args.stack}: {' '.join(error.cmd[:3])} failed; not applying")
        return 1
    errors, notes = check(plan, args.stack, args.component, settings, allows)
    for level, note in notes:
        print(f"::{level} title=Plan deletes::{note}")
    for error in errors:
        print(f"::error title=Destroy not allowed::{error}")
    summarize([f"⚠️ {note}" for _, note in notes] + [f"❌ {error}" for error in errors])
    if errors:
        return 1
    if not has_changes(plan):
        print(f"{args.component} in {args.stack}: no changes, nothing to apply")
        return NO_CHANGES
    print(f"{args.component} in {args.stack}: {len(notes)} delete(s) in the plan, none blocking")
    return 0


if __name__ == "__main__":
    sys.exit(main())

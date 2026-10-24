#!/usr/bin/env python3
"""Drift issues for drift-detection.yml (stdlib only).

  record  (each plan leg) writes the leg's result: drift-result/<key>.json with
          its clean, drifted (plus a plan summary) and failed instances.
  sync    (the final job) upserts one open issue per drifted (stack, component),
          labelled drift, and closes the open one of a pair a later run planned
          clean (or no longer plans). A pair whose plan FAILED is left alone and
          reported, as is a leg that wrote no result; either fails the job.

Issue shape mirrors Cloud Posse's (deprecated) github-action-atmos-terraform-
drift-detection, so a move to Atmos Pro starts from familiar issues: title
"Drift Detected in `<stack>-<component>`", label drift, a ```json metadata
block naming the pair, and on recovery the label drift-recovered and a comment.
"""
import argparse
import json
import os
import pathlib
import re
import sys
import urllib.error
import urllib.request

LABELS = {"drift": "d93f0b", "drift-recovered": "0e8a16"}
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
# Terraform's resource headers ("  # aws_x.y will be updated in-place") and totals.
SUMMARY = re.compile(r"^\s*# \S+ (will|must) be |^(Plan|Changes to Outputs):")
METADATA = re.compile(r"```json\s+(\{.*?\})\s+```", re.S)
MAX_SUMMARY_LINES = 60


def summarize(log_text):
    lines = [ANSI.sub("", line).rstrip() for line in log_text.splitlines()]
    picked = [line for line in lines if SUMMARY.search(line)]
    if len(picked) > MAX_SUMMARY_LINES:
        picked = picked[:MAX_SUMMARY_LINES] + [f"... {len(picked) - MAX_SUMMARY_LINES} more (see the run)"]
    return "\n".join(picked) or "(no plan summary found; see the run)"


def record(args):
    drifted = {}
    for item in args.drifted:
        component, _, log = item.partition("=")
        drifted[component] = summarize(pathlib.Path(log).read_text(errors="replace"))
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"stack": args.stack, "clean": args.clean, "drifted": drifted, "failed": args.failed}))


class GitHub:
    def __init__(self, token, repo, api_url="https://api.github.com"):
        self.token, self.base = token, f"{api_url}/repos/{repo}"

    def api(self, method, path, body=None):
        request = urllib.request.Request(
            self.base + path, method=method, data=None if body is None else json.dumps(body).encode(),
            headers={"Authorization": f"Bearer {self.token}", "Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read()
        return json.loads(data) if data else None


def ensure_labels(gh):
    for name, color in LABELS.items():
        try:
            gh.api("GET", f"/labels/{name}")
        except urllib.error.HTTPError as err:
            if err.code != 404:
                raise
            gh.api("POST", "/labels", {"name": name, "color": color, "description": "Drift detection (drift-detection.yml)"})


def open_issues(gh):
    """{(stack, component): issue} of the open drift issues, keyed by their metadata block."""
    issues, page = {}, 1
    while True:
        batch = gh.api("GET", f"/issues?labels=drift&state=open&per_page=100&page={page}")
        for issue in batch:
            match = METADATA.search(issue.get("body") or "")
            if "pull_request" in issue or not issue["title"].startswith("Drift Detected in") or not match:
                continue
            meta = json.loads(match.group(1))
            issues[(meta["stack"], meta["component"])] = issue
        if len(batch) < 100:
            return issues
        page += 1


def issue_body(stack, component, summary, run_url):
    meta = json.dumps({"stack": stack, "component": component})
    return (f"`atmos terraform plan {component} -s {stack}` has changes: the deployed resources differ from "
            f"the stack.\n\n```text\n{summary}\n```\n\nFix: codify an intended manual change in the stack and "
            f"`atmos terraform deploy`; otherwise re-apply (docs/OPERATIONS.md, Day-2 tasks). This issue closes "
            f"itself when a later run plans the instance clean.\n\n# Related\n"
            f"* [:building_construction: Action Workflow Logs]({run_url})\n\n```json\n{meta}\n```\n")


def sync(results_dir, expected, gh, run_url):
    """Returns (report lines, errors)."""
    clean, drifted, errors, complete = set(), {}, [], {}
    for key, stack in expected:
        path = pathlib.Path(results_dir) / f"{key}.json"
        complete.setdefault(stack, True)
        if not path.is_file():
            errors.append(f"{key}: no result (the leg failed before it planned)")
            complete[stack] = False
            continue
        result = json.loads(path.read_text())
        clean.update((stack, c) for c in result["clean"])
        drifted.update({(stack, c): s for c, s in result["drifted"].items()})
        errors.extend(f"{stack} {c}: plan failed" for c in result["failed"])
        if result["failed"]:
            complete[stack] = False
    ensure_labels(gh)
    issues, report = open_issues(gh), []
    for (stack, component), summary in sorted(drifted.items()):
        body, issue = issue_body(stack, component, summary, run_url), issues.get((stack, component))
        if issue is None:
            new = gh.api("POST", "/issues", {"title": f"Drift Detected in `{stack}-{component}`", "body": body,
                                             "labels": ["drift"]})
            report.append(f"opened #{new['number']}: {stack} {component}")
        elif issue.get("body") != body:
            gh.api("PATCH", f"/issues/{issue['number']}", {"body": body})
            report.append(f"updated #{issue['number']}: {stack} {component}")
    for (stack, component), issue in sorted(issues.items()):
        if (stack, component) in drifted:
            continue
        if (stack, component) in clean:
            why = "planned clean"
        elif complete.get(stack):
            why = "no longer planned (removed, disabled or opted out of CI)"
        else:
            continue
        gh.api("POST", f"/issues/{issue['number']}/comments",
               {"body": f"Component `{stack}-{component}` is not drifting anymore: {why} in {run_url}."})
        gh.api("POST", f"/issues/{issue['number']}/labels", {"labels": ["drift-recovered"]})
        gh.api("PATCH", f"/issues/{issue['number']}", {"state": "closed", "state_reason": "completed"})
        report.append(f"closed #{issue['number']}: {stack} {component} ({why})")
    return report, errors


def expected_keys(matrix, in_vpc):
    keys = [(entry["stack"], entry["stack"]) for entry in json.loads(matrix or "{}").get("include", [])]
    keys += [(f"{e['stack']}--{e['label']}", e["stack"]) for e in json.loads(in_vpc or "{}").get("include", [])]
    return keys


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    rec = sub.add_parser("record")
    rec.add_argument("--out", required=True)
    rec.add_argument("--stack", required=True)
    for name in ("clean", "drifted", "failed"):
        rec.add_argument(f"--{name}", nargs="*", default=[])
    syn = sub.add_parser("sync")
    syn.add_argument("--results", required=True)
    args = parser.parse_args()
    if args.cmd == "record":
        return record(args)
    env = os.environ
    gh = GitHub(env["GITHUB_TOKEN"], env["GITHUB_REPOSITORY"], env.get("GITHUB_API_URL", "https://api.github.com"))
    run_url = f"{env['GITHUB_SERVER_URL']}/{env['GITHUB_REPOSITORY']}/actions/runs/{env['GITHUB_RUN_ID']}"
    report, errors = sync(args.results, expected_keys(env.get("MATRIX"), env.get("IN_VPC")), gh, run_url)
    lines = ["## Drift issues", ""] + [f"- {line}" for line in report or ["no issue changes"]]
    lines += [f"- ERROR (issues untouched) {e}" for e in errors]
    print("\n".join(lines))
    if env.get("GITHUB_STEP_SUMMARY"):
        with open(env["GITHUB_STEP_SUMMARY"], "a") as summary:
            summary.write("\n".join(lines) + "\n")
    for error in errors:
        print(f"::error title=Drift check incomplete::{error}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

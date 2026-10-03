#!/usr/bin/env python3
"""Print the CI role ARN of stack $STACK (and append arn=<ARN> to $GITHUB_OUTPUT when set).

  --kind apply (default)  terraform-cd.yml
  --kind plan             terraform-ci.yml plans, drift-detection.yml, disaster-recovery.yml

Each stack's iam/ci instance creates both roles in the stack's own account
(Cloud Posse's per-account github-oidc-role planner/terraform pair), so the
role is not a repository or GitHub Environment variable: it is
arn:aws:iam::<settings.environment.account_id>:role/<ci_role_name_prefix>-<kind>.
The apply role trusts only the branch-pinned ref subject (Cloud Posse's
trusted_github_repos); the plan role trusts ci_plan_role_subjects.
account_id() is the one place that picks the account, so a later account map
(Cloud Posse's core-account model) only has to change it.
"""
import argparse
import json
import os
import re
import subprocess
import sys

ARN = re.compile(r"arn:aws:iam::\d{12}:role/[\w+=,.@-]{1,64}")
KINDS = ("plan", "apply")


def account_id(ci: dict) -> str:
    """The account that holds the stack's CI roles."""
    return ci["settings"]["environment"]["account_id"]


def role_arn(ci: dict, kind: str = "apply") -> str:
    """The plan or apply role ARN from `atmos describe component iam/ci` output."""
    if kind not in KINDS:
        raise ValueError(f"unknown role kind {kind!r}")
    if kind == "apply" and not (ci["vars"].get("github_oidc_enabled") and ci["vars"].get("ci_apply_role_enabled")):
        raise ValueError("iam/ci does not create an apply role (github_oidc_enabled / ci_apply_role_enabled)")
    if kind == "plan" and not ci["vars"].get("github_oidc_enabled"):
        raise ValueError("iam/ci does not create a plan role (github_oidc_enabled)")
    arn = f"arn:aws:iam::{account_id(ci)}:role/{ci['vars']['ci_role_name_prefix']}-{kind}"
    if not ARN.fullmatch(arn):
        raise ValueError(f"resolved an invalid role ARN {arn!r}")
    return arn


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--kind", choices=KINDS, default="apply")
    kind = parser.parse_args().kind
    stack = os.environ.get("STACK", "")
    if not stack:
        print("STACK is required", file=sys.stderr)
        return 1
    try:
        ci = json.loads(subprocess.check_output(
            ["atmos", "describe", "component", "iam/ci", "-s", stack,
             "--process-functions=false", "--provenance=false", "--format", "json"]))
    except subprocess.CalledProcessError:
        print(f"::error::{stack}: no iam/ci instance (atmos describe failed)")
        return 1
    try:
        arn = role_arn(ci, kind)
    except (KeyError, ValueError) as error:
        print(f"::error::{stack}: {error}")
        return 1
    print(f"{stack}: {arn}")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as out:
            out.write(f"arn={arn}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

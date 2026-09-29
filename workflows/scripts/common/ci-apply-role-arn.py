#!/usr/bin/env python3
"""Print the CI apply role ARN of stack $STACK (and append arn=<ARN> to $GITHUB_OUTPUT when set).

terraform-cd.yml uses no GitHub Environment (the apply roles trust only the
branch-pinned ref subject, Cloud Posse's trusted_github_repos), so the role is
not stored in an environment variable: it is the role the stack's iam/ci
instance creates, arn:aws:iam::<settings.environment.account_id>:role/<ci_role_name_prefix>-apply.
"""
import json
import os
import re
import subprocess
import sys

ARN = re.compile(r"arn:aws:iam::\d{12}:role/[\w+=,.@-]{1,64}")


def apply_role_arn(ci: dict) -> str:
    """The apply role ARN from `atmos describe component iam/ci` output."""
    if not ci["vars"].get("github_oidc_enabled") or not ci["vars"].get("ci_apply_role_enabled"):
        raise ValueError("iam/ci does not create an apply role (github_oidc_enabled / ci_apply_role_enabled)")
    arn = f"arn:aws:iam::{ci['settings']['environment']['account_id']}:role/{ci['vars']['ci_role_name_prefix']}-apply"
    if not ARN.fullmatch(arn):
        raise ValueError(f"resolved an invalid role ARN {arn!r}")
    return arn


def main() -> int:
    stack = os.environ.get("STACK", "")
    if not stack:
        print("STACK is required", file=sys.stderr)
        return 1
    ci = json.loads(subprocess.check_output(
        ["atmos", "describe", "component", "iam/ci", "-s", stack,
         "--process-functions=false", "--provenance=false", "--format", "json"]))
    try:
        arn = apply_role_arn(ci)
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

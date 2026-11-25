#!/usr/bin/env python3
"""Print the CI role ARN of stack $STACK (and append arn=<ARN> to $GITHUB_OUTPUT when set).

  --kind apply (default)  terraform-cd.yml
  --kind plan             terraform-ci.yml plans, drift-detection.yml, disaster-recovery.yml

Each stack's aws-iam-role/ci-plan and aws-iam-role/ci-apply instances (the vendored Cloud
Posse aws-iam-role, stacks/catalog/aws-iam-role/ci.yaml: CP Evolution 4's per-account
planner/terraform machine roles) create the roles in the stack's own account, so the role
is not a repository or GitHub Environment variable: it is
arn:aws:iam::<settings.environment.account_id>:role/<null-label id>, the id the component
names the role with (use_fullname, Cloud Posse null-label: the label_order fields of the
instance's vars, each var over its vars.context field, joined by the delimiter). That is
<tenant>-<settings.prefix>-<stage>-ci-<kind>, the stack name plus -ci-<kind> on every
stage stack. The apply role trusts only the branch-pinned ref subject; the plan role adds
pull_request where the stage plans pull requests (check-prod-protection.py).
settings.environment.account_id is read from the account map
(settings.account_map.full_account_map, stacks/orgs/fnx/_defaults.yaml), so account
changes need no edit here; account_id() is the one lookup. check-ci-state-roles.py derives
the backend's trusted ARNs with this module, so there is one copy of the name.
"""
import argparse
import json
import os
import re
import subprocess
import sys

# IAM's role-name cap, and the cap cloudposse/iam-role/aws hard-codes (id_length_limit = 64) on the
# null-label id it names the role with when use_fullname is true: a longer id is truncated and hashed.
MAX_ROLE_NAME = 64
ARN = re.compile(r"arn:aws:iam::\d{12}:role/[\w+=,.@-]{1,%d}" % MAX_ROLE_NAME)
KINDS = ("plan", "apply")
# kind -> the stack's aws-iam-role instance (stacks/catalog/aws-iam-role/ci.yaml)
INSTANCES = {kind: f"aws-iam-role/ci-{kind}" for kind in KINDS}
# null-label 0.25.0 defaults (main.tf) for the fields an id depends on: its default order has no
# tenant, which is why the vendored abstract sets label_order (tests/ci_roles.tftest.hcl saw it).
LABEL_ORDER = ("namespace", "environment", "stage", "name", "attributes")
DELIMITER = "-"


def account_id(ci: dict) -> str:
    """The account that holds the stack's CI roles."""
    return ci["settings"]["environment"]["account_id"]


def label(ci: dict, field: str):
    """null-label: a non-null var wins, else the context's field."""
    variables = ci.get("vars") or {}
    value = variables.get(field)
    return value if value is not None else (variables.get("context") or {}).get(field)


def creates_role(ci: dict) -> bool:
    """Whether the instance creates a GitHub-trusted role (the component's github_oidc_enabled)."""
    variables = ci.get("vars") or {}
    return ((ci.get("metadata") or {}).get("enabled", True) is not False
            and label(ci, "enabled") is not False
            and variables.get("github_oidc_provider_enabled") is True
            and bool(variables.get("trusted_github_repos")))


def uses_fullname(ci: dict) -> bool:
    """The component's use_fullname (default true; Atmos may render the bool as a string)."""
    value = (ci.get("vars") or {}).get("use_fullname")
    return str(value).strip().lower() != "false" if isinstance(value, str) else value is not False


def role_name(ci: dict) -> str:
    """The role's name before the module's own truncation: the null-label id (use_fullname) or var.name."""
    variables = ci.get("vars") or {}
    if not uses_fullname(ci):
        return str(variables.get("name") or "")
    context = variables.get("context") or {}
    attributes = list(variables.get("attributes") or []) + list(context.get("attributes") or [])
    parts = []
    for field in label(ci, "label_order") or LABEL_ORDER:
        values = attributes if field == "attributes" else [label(ci, field)]
        parts += [str(value) for value in values if value not in (None, "")]
    name = (label(ci, "delimiter") or DELIMITER).join(parts)
    case = label(ci, "label_value_case") or "lower"
    return {"lower": name.lower(), "upper": name.upper(), "title": name.title()}.get(case, name)


def role_arn(ci: dict, kind: str = "apply") -> str:
    """The plan or apply role ARN from `atmos describe component aws-iam-role/ci-<kind>` output."""
    if kind not in KINDS:
        raise ValueError(f"unknown role kind {kind!r}")
    if not creates_role(ci):
        raise ValueError(f"{INSTANCES[kind]} does not create {'an' if kind == 'apply' else 'a'} {kind} role (enabled, github_oidc_provider_enabled, "
                         "trusted_github_repos)")
    if (ci.get("vars") or {}).get("path", "/") != "/":
        raise ValueError(f"{INSTANCES[kind]} sets a role path; the CI role ARNs assume path /")
    arn = f"arn:aws:iam::{account_id(ci)}:role/{role_name(ci)}"
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
            ["atmos", "describe", "component", INSTANCES[kind], "-s", stack,
             "--process-functions=false", "--provenance=false", "--format", "json"]))
    except subprocess.CalledProcessError:
        print(f"::error::{stack}: no {INSTANCES[kind]} instance (atmos describe failed)")
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

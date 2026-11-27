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
instance's vars, each var over its vars.context field, cleaned by regex_replace_chars and
cased by label_value_case, joined by the delimiter: role_name()). That is
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
REGEX_REPLACE_CHARS = "/[^-a-zA-Z0-9]/"
LABEL_VALUE_CASE = "lower"
# id_length_limit (default 0) is not modelled: the component caps the id at MAX_ROLE_NAME, and ARN rejects a longer one.


def account_id(ci: dict) -> str:
    """The account that holds the stack's CI roles."""
    return ci["settings"]["environment"]["account_id"]


def label(ci: dict, field: str):
    """null-label: a non-null var wins, else the context's field."""
    variables = ci.get("vars") or {}
    value = variables.get(field)
    return value if value is not None else (variables.get("context") or {}).get(field)


def flag(value, where: str, default=None):
    """A bool var Atmos may render as a string: "true"/"false" (case and space insensitive) become bools.

    The one boolean reader of the lint scripts: they all import this module. None gives default (the
    value's unset meaning); anything else, "yes", "0", 1, fails loudly, because Terraform would reject
    it too and a guess could pass a disabled role. Numeric rules (a retention of "7") are not booleans:
    check-prod-protection.py's normalize() reads those.
    """
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, str) and value.strip().lower() in ("true", "false"):
        return value.strip().lower() == "true"
    raise ValueError(f"{where} is {value!r}, not a boolean (true or false)")


def is_deployable(instance: dict) -> bool:
    """Not abstract and not disabled by metadata.enabled (default true; "false" counts as false)."""
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and flag(metadata.get("enabled"), "metadata.enabled", True) is not False


def creates_role(ci: dict) -> bool:
    """Whether the instance creates a GitHub-trusted role (the component's github_oidc_enabled)."""
    variables = ci.get("vars") or {}
    return (flag((ci.get("metadata") or {}).get("enabled"), "metadata.enabled") is not False
            and flag(label(ci, "enabled"), "vars.enabled") is not False
            and flag(variables.get("github_oidc_provider_enabled"), "vars.github_oidc_provider_enabled") is True
            and bool(variables.get("trusted_github_repos")))


def uses_fullname(ci: dict) -> bool:
    """The component's use_fullname (default true; Atmos may render the bool as a string)."""
    return flag((ci.get("vars") or {}).get("use_fullname"), "vars.use_fullname", True)


def clean(value: str, regex: str) -> str:
    """null-label's replace(value, regex_replace_chars, ""): "/.../" is a regex, anything else a literal.

    Python's re is not RE2: only a custom regex_replace_chars could diverge; the default is identical.
    """
    if len(regex) >= 2 and regex.startswith("/") and regex.endswith("/"):
        return re.sub(regex[1:-1], "", value)
    return value.replace(regex, "")


def cased(value: str, case: str) -> str:
    """null-label's label_value_case: none keeps, title and upper change, any other value lowers."""
    if case == "none":
        return value
    if case == "title":
        return re.sub(r"(^|[^A-Za-z0-9_])([a-z])", lambda m: m[1] + m[2].upper(), value.lower())
    return value.upper() if case == "upper" else value.lower()


def text(value) -> str:
    """Terraform's string form of a label value: bools are lowercase."""
    return str(value).lower() if isinstance(value, bool) else str(value)


def role_name(ci: dict) -> str:
    """The role's name before the module's own truncation: the null-label id (use_fullname) or var.name.

    null-label 0.25.0 main.tf: every label value and attribute goes through regex_replace_chars then
    label_value_case; attributes are the context's then the var's, de-duplicated, empty ones dropped;
    labels that end up empty are left out of the join; a delimiter of "" is kept.
    """
    variables = ci.get("vars") or {}
    context = variables.get("context") or {}
    regex = label(ci, "regex_replace_chars") or REGEX_REPLACE_CHARS
    case = label(ci, "label_value_case") or LABEL_VALUE_CASE
    if not uses_fullname(ci):  # iam-role 0.23.0 names the role module.this.name: the cleaned, cased label
        name = label(ci, "name")  # an explicit None check: 0 and false are the names "0" and "false"
        return cased(clean("" if name is None else text(name), regex), case)
    delimiter = label(ci, "delimiter")
    raw = list(context.get("attributes") or []) + list(variables.get("attributes") or [])
    # null-label de-duplicates and compacts twice; once on the cleaned, cased strings covers both.
    attributes = list(dict.fromkeys(a for a in (cased(clean(text(v), regex), case) for v in raw if v is not None and v != "") if a))
    parts = []
    for field in label(ci, "label_order") or LABEL_ORDER:
        values = attributes if field == "attributes" else [label(ci, field)]
        parts += [cased(clean(text(value), regex), case) for value in values if value is not None]
    return (DELIMITER if delimiter is None else str(delimiter)).join(p for p in parts if p)


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

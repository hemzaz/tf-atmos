#!/usr/bin/env python3
"""Fail an aws-organization plan that would take anything away from the live organization.

Usage:
  atmos terraform show aws-organization -s <stack> -json <planfile> \\
    | check-organization-plan.py

Reads `terraform show -json <planfile>` on stdin (any lines before the JSON
document, such as Atmos log lines, are skipped). For every
aws_organizations_organization change in the plan, compares the state before
(the live organization: an import's planned state, or the last apply's) with
the planned state after, and exits 1 when the plan would:
  - disable a trusted service: a principal in before.aws_service_access_principals
    that is not in after's (DisableAWSServiceAccess; dropping sso.amazonaws.com
    breaks Identity Center sign-in, controltower.amazonaws.com Control Tower);
  - disable a policy type: a type in before.enabled_policy_types that is not in
    after's (DisablePolicyType detaches every policy of that type);
  - change feature_set, except the in-place CONSOLIDATED_BILLING -> ALL upgrade
    (EnableAllFeatures, the catalog's supported import path: every invited
    member account must accept its handshake before it completes); ALL back to
    CONSOLIDATED_BILLING replaces the organization;
  - delete or replace the organization (the house lifecycle_override.tf
    prevent_destroy already refuses it at plan).
Both lists are authoritative in the Cloud Posse aws-organization component, so
importing an existing organization with a shorter list in the stack would do
exactly that on its first apply (stacks/catalog/aws-organization/defaults.yaml,
import runbook). A create (no state before) and a plan that only adds pass.
Exits 2 when stdin holds no plan JSON, or the plan lists no
aws_organizations_organization at all (the wrong component's planfile).
"""
import json
import sys

RESOURCE_TYPE = "aws_organizations_organization"
# (attribute, what losing an entry does)
GUARDED_LISTS = (
    ("aws_service_access_principals", "trusted access disabled for"),
    ("enabled_policy_types", "policy type disabled (its policies detached):"),
)
# The one feature_set change an existing organization may take (EnableAllFeatures, in place).
ALLOWED_FEATURE_SET_CHANGE = ("CONSOLIDATED_BILLING", "ALL")


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


def organization_changes(plan: dict) -> list[dict]:
    return [change for change in plan.get("resource_changes") or [] if change.get("type") == RESOURCE_TYPE]


def change_errors(resource: dict) -> list[str]:
    address = resource.get("address") or RESOURCE_TYPE
    change = resource.get("change") or {}
    actions = change.get("actions") or []
    before, after = change.get("before"), change.get("after")
    errors = []
    if "delete" in actions:
        errors.append(f"{address}: the plan deletes or replaces the organization (actions {actions})")
    if not before:
        return errors
    after = after or {}
    for attribute, effect in GUARDED_LISTS:
        lost = sorted(set(before.get(attribute) or []) - set(after.get(attribute) or []))
        if lost:
            errors.append(
                f"{address}: {effect} {', '.join(lost)} (live {attribute} not in the stack's list; "
                "add them to the instance's vars, see the import runbook)"
            )
    old, new = before.get("feature_set"), after.get("feature_set")
    if new not in (None, old) and (old, new) != ALLOWED_FEATURE_SET_CHANGE:
        errors.append(
            f"{address}: feature_set changes from {old} to {new} (only CONSOLIDATED_BILLING -> ALL "
            "is in place; keep the live organization's feature_set)"
        )
    return errors


def check(plan: dict) -> list[str]:
    errors = []
    for resource in organization_changes(plan):
        errors += change_errors(resource)
    return errors


def main() -> int:
    try:
        plan = load_plan(sys.stdin.read())
    except json.JSONDecodeError:
        print("ERROR stdin holds no `terraform show -json` plan document")
        return 2
    if not organization_changes(plan):
        print(f"ERROR the plan lists no {RESOURCE_TYPE}: not an aws-organization planfile?")
        return 2
    errors = check(plan)
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} organization change(s) would remove what the live organization has: not applying")
        return 1
    print("the aws-organization plan removes no trusted service principal or policy type from the organization")
    return 0


if __name__ == "__main__":
    sys.exit(main())

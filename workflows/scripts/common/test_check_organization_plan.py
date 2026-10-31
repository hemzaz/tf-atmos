"""Tests for check-organization-plan.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import contextlib
import importlib.util
import io
import json
import pathlib
import unittest
from unittest import mock

_spec = importlib.util.spec_from_file_location(
    "check_organization_plan", pathlib.Path(__file__).with_name("check-organization-plan.py")
)
guard = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(guard)

STACK = ["cloudtrail.amazonaws.com", "sso.amazonaws.com", "account.amazonaws.com"]


def org(principals, types=("SERVICE_CONTROL_POLICY",), feature_set="ALL"):
    return {"aws_service_access_principals": list(principals), "enabled_policy_types": list(types),
            "feature_set": feature_set}


def plan(before, after, actions=("update",), importing=False):
    change = {"actions": list(actions), "before": before, "after": after}
    if importing:
        change["importing"] = {"id": "o-abcdefghij"}
    return {"format_version": "1.2", "resource_changes": [
        {"address": "aws_organizations_organization.this[0]", "type": "aws_organizations_organization",
         "change": change},
        {"address": "aws_iam_organizations_features.this[0]", "type": "aws_iam_organizations_features",
         "change": {"actions": ["create"], "before": None, "after": {}}},
    ]}


def run(text):
    out = io.StringIO()
    with mock.patch("sys.stdin", io.StringIO(text)), contextlib.redirect_stdout(out):
        code = guard.main()
    return code, out.getvalue()


class CheckTest(unittest.TestCase):
    def test_create_passes(self):
        self.assertEqual(guard.check(plan(None, org(STACK), actions=("create",))), [])

    def test_import_with_a_superset_passes(self):
        live = org(["sso.amazonaws.com"])
        self.assertEqual(guard.check(plan(live, org(STACK), importing=True)), [])

    def test_no_op_passes(self):
        self.assertEqual(guard.check(plan(org(STACK), org(STACK), actions=("no-op",))), [])

    def test_import_that_drops_a_trusted_service_fails(self):
        live = org(STACK + ["controltower.amazonaws.com", "ram.amazonaws.com"])
        errors = guard.check(plan(live, org(STACK), importing=True))
        self.assertEqual(len(errors), 1)
        self.assertIn("controltower.amazonaws.com, ram.amazonaws.com", errors[0])

    def test_dropping_a_policy_type_fails(self):
        live = org(STACK, types=("SERVICE_CONTROL_POLICY", "TAG_POLICY"))
        errors = guard.check(plan(live, org(STACK)))
        self.assertEqual(len(errors), 1)
        self.assertIn("TAG_POLICY", errors[0])

    def test_consolidated_billing_to_all_upgrade_passes(self):
        live = org(STACK, feature_set="CONSOLIDATED_BILLING")
        self.assertEqual(guard.check(plan(live, org(STACK), importing=True)), [])

    def test_all_to_consolidated_billing_fails(self):
        errors = guard.check(plan(org(STACK), org(STACK, feature_set="CONSOLIDATED_BILLING")))
        self.assertEqual(len(errors), 1)
        self.assertIn("feature_set changes from ALL to CONSOLIDATED_BILLING", errors[0])

    def test_delete_or_replace_fails(self):
        errors = guard.check(plan(org(STACK), None, actions=("delete", "create")))
        self.assertTrue(any("deletes or replaces" in e for e in errors))


class MainTest(unittest.TestCase):
    def test_log_lines_before_the_json_are_skipped(self):
        code, out = run("INFO atmos something\n" + json.dumps(plan(None, org(STACK), actions=("create",))) + "\n")
        self.assertEqual(code, 0, out)

    def test_a_removal_fails_main(self):
        live = org(STACK + ["controltower.amazonaws.com"])
        code, out = run(json.dumps(plan(live, org(STACK))))
        self.assertEqual(code, 1)
        self.assertIn("controltower.amazonaws.com", out)

    def test_no_json_fails_closed(self):
        self.assertEqual(run("no such planfile\n")[0], 2)

    def test_a_plan_without_the_organization_fails_closed(self):
        self.assertEqual(run(json.dumps({"format_version": "1.2", "resource_changes": []}))[0], 2)


if __name__ == "__main__":
    unittest.main()

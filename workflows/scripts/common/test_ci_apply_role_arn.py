"""Tests for ci-apply-role-arn.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import contextlib
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import sys
import unittest
from unittest import mock

_spec = importlib.util.spec_from_file_location(
    "ci_apply_role_arn", pathlib.Path(__file__).with_name("ci-apply-role-arn.py")
)
ci_apply_role_arn = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ci_apply_role_arn)

# The vendored abstract's label (stacks/catalog/_base/vendored.yaml): tenant first.
LABEL_ORDER = ["tenant", "environment", "stage", "name", "attributes"]


def ci(account="123456789012", kind="apply", stage="prod", environment="ue1", metadata=None, **overrides):
    """`atmos describe component aws-iam-role/ci-<kind>` output, as catalog/aws-iam-role/ci.yaml renders it."""
    variables = {
        "enabled": True, "github_oidc_provider_enabled": True, "trusted_github_repos": ["hemzaz/tf-atmos:master"],
        "tenant": "fnx", "environment": environment, "stage": stage, "name": f"ci-{kind}",
        "context": {"enabled": True, "tenant": "fnx", "environment": environment, "stage": stage, "name": None,
                    "delimiter": None, "attributes": [], "label_order": LABEL_ORDER, "label_value_case": None},
    }
    variables.update(overrides)
    return {"settings": {"environment": {"account_id": account}}, "vars": variables, "metadata": metadata or {}}


class ApplyRoleArnTest(unittest.TestCase):
    def test_arn_is_the_stack_apply_role(self):
        # The name the backend's prod_write role trusts (stacks/orgs/fnx/root/us-east-1.yaml)
        self.assertEqual(
            ci_apply_role_arn.role_arn(ci()),
            "arn:aws:iam::123456789012:role/fnx-ue1-prod-ci-apply",
        )
        self.assertEqual(ci_apply_role_arn.role_arn(ci(), "apply"), ci_apply_role_arn.role_arn(ci()))

    def test_role_without_github_trust_fails(self):
        for bad in (ci(github_oidc_provider_enabled=False), ci(trusted_github_repos=[]), ci(enabled=False),
                    ci(metadata={"enabled": False})):
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, "does not create an apply role"):
                ci_apply_role_arn.role_arn(bad)

    def test_disabled_context_fails(self):
        bad = ci()
        del bad["vars"]["enabled"]
        bad["vars"]["context"]["enabled"] = False
        with self.assertRaisesRegex(ValueError, "does not create an apply role"):
            ci_apply_role_arn.role_arn(bad)

    def test_unrendered_or_bad_values_fail(self):
        for bad in (ci(account="{{ .settings.environment.account_id }}"), ci(name="a b"), ci(account="")):
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, "invalid role ARN"):
                ci_apply_role_arn.role_arn(bad)

    def test_a_role_path_fails(self):
        with self.assertRaisesRegex(ValueError, "role path"):
            ci_apply_role_arn.role_arn(ci(path="/ci/"))


class RoleNameTest(unittest.TestCase):
    """The null-label id the vendored component names the role with (use_fullname)."""

    def test_var_over_context_and_label_order(self):
        role = ci()
        role["vars"]["environment"] = None  # null var: the context's field
        self.assertEqual(ci_apply_role_arn.role_name(role), "fnx-ue1-prod-ci-apply")

    def test_lane_prefix_is_the_environment(self):
        # A lane's settings.prefix (ue1-<name>) is the vendored environment: the lane form.
        self.assertEqual(ci_apply_role_arn.role_name(ci(environment="ue1-webapp", stage="fixtures")),
                         "fnx-ue1-webapp-fixtures-ci-apply")

    def test_attributes_delimiter_case_and_short_name(self):
        role = ci(attributes=["x"])
        role["vars"]["context"].update({"attributes": ["y"], "delimiter": "_", "label_value_case": "upper"})
        self.assertEqual(ci_apply_role_arn.role_name(role), "FNX_UE1_PROD_CI-APPLY_X_Y")
        self.assertEqual(ci_apply_role_arn.role_name(ci(use_fullname=False)), "ci-apply")

    def test_null_label_default_order_without_a_context_order(self):
        role = ci()
        del role["vars"]["context"]["label_order"]
        # null-label 0.25.0's default order: namespace (unset), environment, stage, name; no tenant.
        self.assertEqual(ci_apply_role_arn.role_name(role), "ue1-prod-ci-apply")


class PlanRoleArnTest(unittest.TestCase):
    def test_arn_is_the_stack_accounts_plan_role(self):
        # Each stack's own account and name: staging no longer plans with dev's role.
        self.assertEqual(
            ci_apply_role_arn.role_arn(ci(account="210987654321", kind="plan", stage="staging"), "plan"),
            "arn:aws:iam::210987654321:role/fnx-ue1-staging-ci-plan",
        )

    def test_disabled_oidc_fails(self):
        with self.assertRaisesRegex(ValueError, "does not create a plan role"):
            ci_apply_role_arn.role_arn(ci(kind="plan", github_oidc_provider_enabled=False), "plan")

    def test_bad_values_fail(self):
        with self.assertRaisesRegex(ValueError, "invalid role ARN"):
            ci_apply_role_arn.role_arn(ci(account="{{ .settings.environment.account_id }}", kind="plan"), "plan")

    def test_unknown_kind_fails(self):
        with self.assertRaisesRegex(ValueError, "unknown role kind"):
            ci_apply_role_arn.role_arn(ci(), "admin")


class MainTest(unittest.TestCase):
    def run_main(self, check_output, *argv):
        out = io.StringIO()
        with mock.patch.dict(os.environ, {"STACK": "fnx-ue1-root"}, clear=False), \
                mock.patch.object(sys, "argv", ["ci-apply-role-arn.py", *argv]), \
                mock.patch.object(ci_apply_role_arn.subprocess, "check_output", check_output), \
                contextlib.redirect_stdout(out):
            os.environ.pop("GITHUB_OUTPUT", None)
            return ci_apply_role_arn.main(), out.getvalue()

    def test_stack_without_the_ci_role_fails_with_an_annotation(self):
        def describe_fails(cmd):
            raise subprocess.CalledProcessError(1, cmd)

        for argv, instance in (((), "aws-iam-role/ci-apply"), (("--kind", "plan"), "aws-iam-role/ci-plan")):
            with self.subTest(argv=argv):
                rc, out = self.run_main(describe_fails, *argv)
                self.assertEqual(rc, 1)
                self.assertEqual(out, f"::error::fnx-ue1-root: no {instance} instance (atmos describe failed)\n")

    def test_resolved_role_is_printed(self):
        seen = []

        def describe(cmd):
            seen.append(cmd[3])
            return json.dumps(ci(kind="plan"))

        rc, out = self.run_main(describe, "--kind", "plan")
        self.assertEqual(rc, 0)
        self.assertEqual(seen, ["aws-iam-role/ci-plan"])
        self.assertEqual(out, "fnx-ue1-root: arn:aws:iam::123456789012:role/fnx-ue1-prod-ci-plan\n")


if __name__ == "__main__":
    unittest.main()

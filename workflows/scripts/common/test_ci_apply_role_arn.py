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


def ci(account="123456789012", prefix="fnx-production-prod-ci", **overrides):
    variables = {"github_oidc_enabled": True, "ci_apply_role_enabled": True, "ci_role_name_prefix": prefix}
    variables.update(overrides)
    return {"settings": {"environment": {"account_id": account}}, "vars": variables}


class ApplyRoleArnTest(unittest.TestCase):
    def test_arn_is_the_iam_ci_apply_role(self):
        # The name the backend's prod_write role trusts (stacks/orgs/fnx/core/us-east-1/root.yaml)
        self.assertEqual(
            ci_apply_role_arn.role_arn(ci()),
            "arn:aws:iam::123456789012:role/fnx-production-prod-ci-apply",
        )
        self.assertEqual(ci_apply_role_arn.role_arn(ci(), "apply"), ci_apply_role_arn.role_arn(ci()))

    def test_disabled_apply_role_fails(self):
        with self.assertRaisesRegex(ValueError, "does not create an apply role"):
            ci_apply_role_arn.role_arn(ci(ci_apply_role_enabled=False))
        with self.assertRaisesRegex(ValueError, "does not create an apply role"):
            ci_apply_role_arn.role_arn(ci(github_oidc_enabled=False))

    def test_unrendered_or_bad_values_fail(self):
        for bad in (ci(account="{{ .settings.environment.account_id }}"), ci(prefix="a b"), ci(account="")):
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, "invalid role ARN"):
                ci_apply_role_arn.role_arn(bad)


class PlanRoleArnTest(unittest.TestCase):
    def test_arn_is_the_stack_accounts_plan_role(self):
        # Each stack's own account and prefix: staging no longer plans with dev's role.
        self.assertEqual(
            ci_apply_role_arn.role_arn(ci(account="210987654321", prefix="fnx-staging-01-staging-ci"), "plan"),
            "arn:aws:iam::210987654321:role/fnx-staging-01-staging-ci-plan",
        )

    def test_plan_role_does_not_need_the_apply_role(self):
        self.assertEqual(
            ci_apply_role_arn.role_arn(ci(ci_apply_role_enabled=False), "plan"),
            "arn:aws:iam::123456789012:role/fnx-production-prod-ci-plan",
        )

    def test_disabled_oidc_fails(self):
        with self.assertRaisesRegex(ValueError, "does not create a plan role"):
            ci_apply_role_arn.role_arn(ci(github_oidc_enabled=False), "plan")

    def test_bad_values_fail(self):
        with self.assertRaisesRegex(ValueError, "invalid role ARN"):
            ci_apply_role_arn.role_arn(ci(account="{{ .settings.environment.account_id }}"), "plan")

    def test_unknown_kind_fails(self):
        with self.assertRaisesRegex(ValueError, "unknown role kind"):
            ci_apply_role_arn.role_arn(ci(), "admin")


class MainTest(unittest.TestCase):
    def run_main(self, check_output, *argv):
        out = io.StringIO()
        with mock.patch.dict(os.environ, {"STACK": "fnx-core-root"}, clear=False), \
                mock.patch.object(sys, "argv", ["ci-apply-role-arn.py", *argv]), \
                mock.patch.object(ci_apply_role_arn.subprocess, "check_output", check_output), \
                contextlib.redirect_stdout(out):
            os.environ.pop("GITHUB_OUTPUT", None)
            return ci_apply_role_arn.main(), out.getvalue()

    def test_stack_without_iam_ci_fails_with_an_annotation(self):
        def describe_fails(cmd):
            raise subprocess.CalledProcessError(1, cmd)

        for argv in ((), ("--kind", "plan")):
            with self.subTest(argv=argv):
                rc, out = self.run_main(describe_fails, *argv)
                self.assertEqual(rc, 1)
                self.assertEqual(out, "::error::fnx-core-root: no iam/ci instance (atmos describe failed)\n")

    def test_resolved_role_is_printed(self):
        rc, out = self.run_main(lambda cmd: json.dumps(ci(ci_apply_role_enabled=False)), "--kind", "plan")
        self.assertEqual(rc, 0)
        self.assertEqual(out, "fnx-core-root: arn:aws:iam::123456789012:role/fnx-production-prod-ci-plan\n")


if __name__ == "__main__":
    unittest.main()

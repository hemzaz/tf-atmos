"""Tests for ci-apply-role-arn.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "ci_apply_role_arn", pathlib.Path(__file__).with_name("ci-apply-role-arn.py")
)
ci_apply_role_arn = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ci_apply_role_arn)


def ci(account="123456789012", prefix="fnx-prod-production-ci", **overrides):
    variables = {"github_oidc_enabled": True, "ci_apply_role_enabled": True, "ci_role_name_prefix": prefix}
    variables.update(overrides)
    return {"settings": {"environment": {"account_id": account}}, "vars": variables}


class ApplyRoleArnTest(unittest.TestCase):
    def test_arn_is_the_iam_ci_apply_role(self):
        # The name the backend's prod_write role trusts (stacks/orgs/fnx/core/us-east-1/root.yaml)
        self.assertEqual(
            ci_apply_role_arn.role_arn(ci()),
            "arn:aws:iam::123456789012:role/fnx-prod-production-ci-apply",
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
            ci_apply_role_arn.role_arn(ci(account="210987654321", prefix="fnx-staging-staging-01-ci"), "plan"),
            "arn:aws:iam::210987654321:role/fnx-staging-staging-01-ci-plan",
        )

    def test_plan_role_does_not_need_the_apply_role(self):
        self.assertEqual(
            ci_apply_role_arn.role_arn(ci(ci_apply_role_enabled=False), "plan"),
            "arn:aws:iam::123456789012:role/fnx-prod-production-ci-plan",
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


if __name__ == "__main__":
    unittest.main()

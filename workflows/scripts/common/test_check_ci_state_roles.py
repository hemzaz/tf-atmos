"""Tests for check-ci-state-roles.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_ci_state_roles", pathlib.Path(__file__).with_name("check-ci-state-roles.py")
)
check_ci_state_roles = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_ci_state_roles)

ACCOUNTS = {"dev": "222222222222", "staging": "333333333333", "prod": "444444444444"}
PREFIXES = {"dev": "fnx-testenv-01-dev-ci", "staging": "fnx-staging-01-staging-ci", "prod": "fnx-production-prod-ci"}


def arn(stage, kind):
    return f"arn:aws:iam::{ACCOUNTS[stage]}:role/{PREFIXES[stage]}-{kind}"


def access_roles(**overrides):
    roles = {
        "read": [arn("dev", "plan"), arn("staging", "plan")],
        "write": [arn("dev", "apply"), arn("staging", "apply")],
        "prod_read": [arn("prod", "plan")],
        "prod_write": [arn("prod", "apply")],
        "core_write": [],
    }
    roles.update(overrides)
    return {key: {"allowed_principal_arns": principals} for key, principals in roles.items()}


def ci(stage, prefix=None, apply=True, oidc=True, **metadata):
    return {
        "component": "iam",
        "metadata": metadata,
        "vars": {"github_oidc_enabled": oidc, "ci_apply_role_enabled": apply,
                 "ci_role_name_prefix": prefix or PREFIXES[stage]},
        "settings": {"context": {"stage": stage}, "environment": {"account_id": ACCOUNTS.get(stage, "555555555555")}},
    }


def stacks(roles=None, **cis):
    result = {"fnx-core-root": {"components": {"terraform": {
        "backend/main": {"component": "backend", "vars": {"access_roles": roles or access_roles()}},
    }}}}
    for stack, instance in cis.items():
        result[stack] = {"components": {"terraform": {"iam/ci": instance}}}
    return result


def today(**overrides):
    cis = {"fnx-dev-testenv-01": ci("dev"), "fnx-staging-staging-01": ci("staging"),
           "fnx-prod-production": ci("prod")}
    cis.update(overrides)
    return cis


class CheckCiStateRolesTest(unittest.TestCase):
    def assert_errors(self, described, *fragments):
        errors = check_ci_state_roles.check(described)
        self.assertEqual(len(errors), len(fragments), errors)
        for error, fragment in zip(errors, fragments):
            self.assertIn(fragment, error)

    def test_trusted_roles_pass(self):
        self.assert_errors(stacks(**today()))

    def test_renamed_prefix_fails(self):
        # The old <tenant>-<account>-<environment>-ci name no longer matches the trusted ARNs
        self.assert_errors(
            stacks(**today(**{"fnx-prod-production": ci("prod", prefix="fnx-prod-production-ci")})),
            "fnx-prod-production: iam/ci plan role arn:aws:iam::444444444444:role/fnx-prod-production-ci-plan "
            "is not in backend access_roles.prod_read",
            "apply role arn:aws:iam::444444444444:role/fnx-prod-production-ci-apply is not in backend "
            "access_roles.prod_write",
        )

    def test_plan_role_in_the_write_role_only_fails(self):
        roles = access_roles(read=[arn("dev", "plan")], write=[arn("dev", "apply"), arn("staging", "apply"),
                                                               arn("staging", "plan")])
        self.assert_errors(stacks(roles=roles, **today()), "fnx-staging-staging-01: iam/ci plan role")

    def test_prod_role_in_the_non_prod_role_fails(self):
        roles = access_roles(prod_write=[], write=[arn("dev", "apply"), arn("staging", "apply"), arn("prod", "apply")])
        self.assert_errors(stacks(roles=roles, **today()), "is not in backend access_roles.prod_write")

    def test_no_apply_role_needs_only_the_plan_role(self):
        roles = access_roles(prod_write=[])
        self.assert_errors(stacks(roles=roles, **today(**{"fnx-prod-production": ci("prod", apply=False)})))

    def test_oidc_disabled_disabled_and_fixtures_are_skipped(self):
        self.assert_errors(stacks(**today(
            **{"fnx-x": ci("dev", prefix="other", oidc=False), "fnx-y": ci("dev", prefix="other", enabled=False),
               "fnx-fixtures-webapp": ci("fixtures", prefix="fnx-webapp-fixtures-ci")},
        )))

    def test_missing_backend_fails(self):
        described = stacks(**today())
        del described["fnx-core-root"]
        self.assert_errors(described, "expected exactly one deployable 'backend' instance, found 0")

    def test_unresolvable_arn_fails(self):
        self.assert_errors(stacks(**today(**{"fnx-prod-production": ci("prod", prefix="bad name", apply=False)})),
                           "plan role: resolved an invalid role ARN")


if __name__ == "__main__":
    unittest.main()

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
PREFIXES = {"dev": "fnx-ue1-dev-ci", "staging": "fnx-ue1-staging-ci", "prod": "fnx-ue1-prod-ci"}


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
    return {key: {"role_name": ROLE_NAMES[key], "allowed_principal_arns": principals}
            for key, principals in roles.items()}


# backend/main's role names; each stage's backend assumes its write role (TFSTATE_ACCESS unset).
ROLE_NAMES = {
    "read": "fnx-terraform-backend-read-role", "write": "fnx-terraform-backend-role",
    "prod_read": "fnx-terraform-backend-prod-read-role", "prod_write": "fnx-terraform-backend-prod-role",
    "core_write": "fnx-terraform-backend-core-role",
}
ASSUMED = {"dev": "write", "staging": "write", "prod": "prod_write"}


def ci(stage, prefix=None, apply=True, oidc=True, assumes=None, **metadata):
    role = ROLE_NAMES[assumes or ASSUMED.get(stage, "write")]
    return {
        "component": "iam",
        "metadata": metadata,
        "backend": {"assume_role": {"role_arn": f"arn:aws:iam::111111111111:role/{role}"}},
        "vars": {"github_oidc_enabled": oidc, "ci_apply_role_enabled": apply,
                 "ci_role_name_prefix": prefix or PREFIXES[stage]},
        "settings": {"context": {"stage": stage}, "environment": {"account_id": ACCOUNTS.get(stage, "555555555555")}},
    }


def stacks(roles=None, **cis):
    result = {"fnx-ue1-core": {"components": {"terraform": {
        "backend/main": {"component": "backend", "vars": {"access_roles": roles or access_roles()}},
    }}}}
    for stack, instance in cis.items():
        result[stack] = {"components": {"terraform": {"iam/ci": instance}}}
    return result


def today(**overrides):
    cis = {"fnx-ue1-dev": ci("dev"), "fnx-ue1-staging": ci("staging"),
           "fnx-ue1-prod": ci("prod")}
    cis.update(overrides)
    return cis


class CheckCiStateRolesTest(unittest.TestCase):
    def assert_errors(self, described, *fragments):
        errors = check_ci_state_roles.check(described)
        self.assertEqual(len(errors), len(fragments), errors)
        for error, fragment in zip(errors, fragments):
            self.assertIn(fragment, error)

    def assert_has(self, described, *fragments):
        errors = check_ci_state_roles.check(described)
        for fragment in fragments:
            self.assertTrue(any(fragment in error for error in errors), (fragment, errors))

    def test_trusted_roles_pass(self):
        self.assert_errors(stacks(**today()))

    def test_renamed_prefix_fails(self):
        # A prefix rendered from the old names no longer matches the trusted ARNs,
        # and the trusted ARNs no longer match a CI role (both directions fail)
        self.assert_errors(
            stacks(**today(**{"fnx-ue1-prod": ci("prod", prefix="fnx-production-prod-ci")})),
            "fnx-ue1-prod: iam/ci plan role arn:aws:iam::444444444444:role/fnx-production-prod-ci-plan "
            "is not in backend access_roles.prod_read",
            "apply role arn:aws:iam::444444444444:role/fnx-production-prod-ci-apply is not in backend "
            "access_roles.prod_write",
            f"backend access_roles.prod_read trusts {arn('prod', 'plan')}",
            f"backend access_roles.prod_write trusts {arn('prod', 'apply')}",
        )

    def test_dev_apply_role_on_prod_write_fails(self):
        roles = access_roles(prod_write=[arn("prod", "apply"), arn("dev", "apply")])
        self.assert_errors(
            stacks(roles=roles, **today()),
            f"backend access_roles.prod_write trusts {arn('dev', 'apply')}, which is no apply role of an "
            "iam/ci instance in a stage this role serves",
        )

    def test_stale_ci_role_arn_fails(self):
        # The old <tenant>-<stage>-<environment>-ci name left behind after a rename
        stale = "arn:aws:iam::444444444444:role/fnx-ue2-prod-ci-plan"
        roles = access_roles(prod_read=[arn("prod", "plan"), stale])
        self.assert_errors(stacks(roles=roles, **today()), f"backend access_roles.prod_read trusts {stale}")

    def test_plan_role_on_a_write_role_fails(self):
        roles = access_roles(write=[arn("dev", "apply"), arn("staging", "apply"), arn("dev", "plan")])
        self.assert_errors(stacks(roles=roles, **today()),
                           f"access_roles.write trusts {arn('dev', 'plan')}, which is no apply role")

    def test_operator_and_non_ci_roles_are_not_reverse_checked(self):
        admin = "arn:aws:iam::222222222222:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Admin_1"
        roles = access_roles(write=[arn("dev", "apply"), arn("staging", "apply"), admin])
        self.assert_errors(stacks(roles=roles, **today()))
        shaped = "arn:aws:iam::222222222222:role/ops-ci-apply"
        roles = access_roles(write=[arn("dev", "apply"), arn("staging", "apply"), shaped])
        self.assertEqual(len(check_ci_state_roles.check(stacks(roles=roles, **today()))), 1)
        original = check_ci_state_roles.OPERATOR_ROLE_ARNS
        check_ci_state_roles.OPERATOR_ROLE_ARNS = frozenset({shaped})
        try:
            self.assert_errors(stacks(roles=roles, **today()))
        finally:
            check_ci_state_roles.OPERATOR_ROLE_ARNS = original

    def test_unmapped_stage_fails(self):
        # A new tier must not fall into the non-prod roles silently
        self.assert_errors(
            stacks(**today(**{"fnx-ue1-qa": ci("qa", prefix="fnx-ue1-qa-ci")})),
            "fnx-ue1-qa: iam/ci is in stage 'qa', which STAGE_ROLES does not map to backend roles",
        )

    def test_backend_assuming_another_stages_role_fails(self):
        self.assert_errors(
            stacks(**today(**{"fnx-ue1-prod": ci("prod", assumes="write")})),
            "backend assumes access_roles.write (backend.assume_role.role_arn), not one of stage 'prod'",
        )

    def test_read_access_assumes_the_read_role(self):
        # TFSTATE_ACCESS=read renders the read roles: still the stage's own
        self.assert_errors(stacks(**today(**{"fnx-ue1-prod": ci("prod", assumes="prod_read")})))

    def test_plan_role_in_the_write_role_only_fails(self):
        roles = access_roles(read=[arn("dev", "plan")], write=[arn("dev", "apply"), arn("staging", "apply"),
                                                               arn("staging", "plan")])
        self.assert_errors(stacks(roles=roles, **today()), "fnx-ue1-staging: iam/ci plan role",
                           f"backend access_roles.write trusts {arn('staging', 'plan')}, which is no apply role")

    def test_prod_role_in_the_non_prod_role_fails(self):
        roles = access_roles(prod_write=[], write=[arn("dev", "apply"), arn("staging", "apply"), arn("prod", "apply")])
        self.assert_errors(stacks(roles=roles, **today()), "is not in backend access_roles.prod_write",
                           f"backend access_roles.write trusts {arn('prod', 'apply')}")

    def test_no_apply_role_needs_only_the_plan_role(self):
        roles = access_roles(prod_write=[])
        self.assert_errors(stacks(roles=roles, **today(**{"fnx-ue1-prod": ci("prod", apply=False)})))

    def test_oidc_disabled_disabled_and_fixtures_are_skipped(self):
        self.assert_errors(stacks(**today(
            **{"fnx-x": ci("dev", prefix="other", oidc=False), "fnx-y": ci("dev", prefix="other", enabled=False),
               "fnx-ue1-fixtures-webapp": ci("fixtures", prefix="fnx-webapp-fixtures-ci")},
        )))

    def test_missing_backend_fails(self):
        described = stacks(**today())
        del described["fnx-ue1-core"]
        self.assert_errors(described, "expected exactly one deployable 'backend' instance, found 0")

    def test_unresolvable_arn_fails(self):
        self.assert_has(stacks(**today(**{"fnx-ue1-prod": ci("prod", prefix="bad name", apply=False)})),
                        "plan role: resolved an invalid role ARN")


if __name__ == "__main__":
    unittest.main()

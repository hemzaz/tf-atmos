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
        "root_write": [],
    }
    roles.update(overrides)
    return {key: {"role_name": ROLE_NAMES[key], "allowed_principal_arns": principals}
            for key, principals in roles.items()}


# backend/main's role names; each stage's backend assumes its write role (TFSTATE_ACCESS unset).
ROLE_NAMES = {
    "read": "fnx-terraform-backend-read-role", "write": "fnx-terraform-backend-role",
    "prod_read": "fnx-terraform-backend-prod-read-role", "prod_write": "fnx-terraform-backend-prod-role",
    "root_write": "fnx-terraform-backend-root-role",
}
ASSUMED = {"dev": "write", "staging": "write", "prod": "prod_write"}


US_BUCKET, EU_BUCKET = "fnx-terraform-state", "fnx-ew1-terraform-state"


def role_arn(name):
    return f"arn:aws:iam::111111111111:role/{name}"


def ci(stage, prefix=None, apply=True, oidc=True, assumes=None, bucket=US_BUCKET, role=None, grants=None, **metadata):
    role = role or ROLE_NAMES[assumes or ASSUMED.get(stage, "write")]
    # (ci_backend_read_role_arns role, ci_backend_write_role_arn role): the stage's own by default
    read, write = grants or [ROLE_NAMES[k] for k in check_ci_state_roles.STAGE_ROLES.get(stage, ("read", "write"))]
    return {
        "component": "iam",
        "metadata": metadata,
        "backend": {"bucket": bucket, "assume_role": {"role_arn": role_arn(role)}},
        "vars": {"github_oidc_enabled": oidc, "ci_apply_role_enabled": apply,
                 "ci_role_name_prefix": prefix or PREFIXES[stage],
                 "ci_backend_read_role_arns": [role_arn(read)], "ci_backend_write_role_arn": role_arn(write)},
        "settings": {"context": {"stage": stage}, "environment": {"account_id": ACCOUNTS.get(stage, "555555555555")}},
    }


def backend(roles, bucket=US_BUCKET, region="us-east-1"):
    return {"component": "backend", "vars": {"bucket_name": bucket, "region": region, "access_roles": roles}}


def stacks(roles=None, **cis):
    result = {"fnx-ue1-root": {"components": {"terraform": {"backend/main": backend(roles or access_roles())}}}}
    for stack, instance in cis.items():
        result[stack] = {"components": {"terraform": {"iam/ci": instance}}}
    return result


# The EU backend (fnx-ew1-root) and its prod stack's CI roles.
EU_PREFIX = "fnx-ew1-prod-ci"
EU_ROLE_NAMES = {"prod_read": "fnx-ew1-terraform-backend-prod-read-role",
                 "prod_write": "fnx-ew1-terraform-backend-prod-role",
                 "root_write": "fnx-ew1-terraform-backend-root-role"}


def eu_arn(kind):
    return f"arn:aws:iam::{ACCOUNTS['prod']}:role/{EU_PREFIX}-{kind}"


def eu_roles(**overrides):
    principals = {"prod_read": [eu_arn("plan")], "prod_write": [eu_arn("apply")], "root_write": []}
    principals.update(overrides)
    return {key: {"role_name": EU_ROLE_NAMES[key], "allowed_principal_arns": arns} for key, arns in principals.items()}


def eu_ci(**kwargs):
    kwargs.setdefault("role", EU_ROLE_NAMES["prod_write"])
    kwargs.setdefault("grants", (EU_ROLE_NAMES["prod_read"], EU_ROLE_NAMES["prod_write"]))
    return ci("prod", prefix=EU_PREFIX, bucket=EU_BUCKET, **kwargs)


def two_backends(us=None, eu=None, eu_instance=None):
    described = stacks(roles=us, **today(**{"fnx-ew1-prod": eu_instance or eu_ci()}))
    described["fnx-ew1-root"] = {"components": {"terraform": {
        "backend/main": backend(eu or eu_roles(), EU_BUCKET, "eu-west-1")}}}
    return described


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

    def test_role_without_principals_fails(self):
        roles = access_roles()
        del roles["prod_write"]["allowed_principal_arns"]
        self.assert_errors(stacks(roles=roles, **today()), "is not in backend access_roles.prod_write")

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
        del described["fnx-ue1-root"]
        self.assert_errors(described, "no state bucket has one deployable 'backend' instance owning it")

    def test_bucket_without_one_owner_fails(self):
        # Another bucket's backend does not stand in; a bucket created twice has no owner
        self.assert_errors(stacks(**today(**{"fnx-ue1-dev": ci("dev", bucket="fnx-other-state")})),
                           "fnx-ue1-dev: iam/ci state bucket 'fnx-other-state' has no one owning 'backend' instance",
                           f"backend access_roles.read trusts {arn('dev', 'plan')}",
                           f"backend access_roles.write trusts {arn('dev', 'apply')}")
        described = stacks(**today())
        described["fnx-ue1-copy"] = {"components": {"terraform": {"backend/main": backend(access_roles())}}}
        # Created twice: no owner
        self.assert_errors(described, "no state bucket has one deployable 'backend' instance owning it")

    def test_us_and_eu_backends_each_trusting_their_own_ci_pass(self):
        self.assert_errors(two_backends())

    def test_eu_ci_trusted_only_by_a_us_role_fails(self):
        us = access_roles(prod_read=[arn("prod", "plan"), eu_arn("plan")],
                          prod_write=[arn("prod", "apply"), eu_arn("apply")])
        self.assert_errors(
            two_backends(us=us, eu=eu_roles(prod_read=[], prod_write=[])),
            f"fnx-ew1-prod: iam/ci plan role {eu_arn('plan')} is not in backend access_roles.prod_read "
            "allowed_principal_arns of fnx-ew1-root: backend/main",
            f"fnx-ew1-prod: iam/ci apply role {eu_arn('apply')} is not in backend access_roles.prod_write",
            f"fnx-ue1-root: backend/main: backend access_roles.prod_read trusts {eu_arn('plan')}",
            f"fnx-ue1-root: backend/main: backend access_roles.prod_write trusts {eu_arn('apply')}",
        )

    def test_eu_ci_granted_the_us_roles_fails(self):
        # ci_backend_*_role_arn pointed at the US backend's prod roles: not the roles of the backend owning its state
        us = (ROLE_NAMES["prod_read"], ROLE_NAMES["prod_write"])
        self.assert_errors(
            two_backends(eu_instance=eu_ci(grants=us)),
            f"fnx-ew1-prod: iam/ci plan role may assume ['{role_arn(us[0])}'] (ci_backend_read_role_arns), "
            f"not fnx-ew1-root: backend/main access_roles.prod_read ({EU_ROLE_NAMES['prod_read']})",
            f"fnx-ew1-prod: iam/ci apply role may assume ['{role_arn(us[1])}'] (ci_backend_write_role_arn), "
            "not fnx-ew1-root: backend/main access_roles.prod_write",
        )

    def test_grant_of_another_stage_or_none_fails(self):
        non_prod = ci("prod", grants=(ROLE_NAMES["read"], ROLE_NAMES["write"]))
        self.assert_errors(stacks(**today(**{"fnx-ue1-prod": non_prod})),
                           "fnx-ue1-prod: iam/ci plan role may assume", "fnx-ue1-prod: iam/ci apply role may assume")
        unset = ci("dev")
        unset["vars"]["ci_backend_read_role_arns"] = []
        unset["vars"]["ci_backend_write_role_arn"] = None
        self.assert_errors(stacks(**today(**{"fnx-ue1-dev": unset})),
                           "plan role may assume [] (ci_backend_read_role_arns)",
                           "apply role may assume [] (ci_backend_write_role_arn)")

    def test_eu_ci_assuming_a_us_role_fails(self):
        # backend.assume_role.role_arn rendered from the US backend: not a role of the backend owning its state
        self.assert_errors(
            two_backends(eu_instance=eu_ci(role=ROLE_NAMES["prod_write"])),
            "fnx-ew1-prod: iam/ci backend assumes access_roles.None (backend.assume_role.role_arn), "
            "not one of stage 'prod''s ['prod_read', 'prod_write'] of fnx-ew1-root: backend/main",
        )

    def test_eu_ci_assuming_a_role_of_another_stage_fails(self):
        self.assert_errors(
            two_backends(eu_instance=eu_ci(role=EU_ROLE_NAMES["root_write"])),
            "fnx-ew1-prod: iam/ci backend assumes access_roles.root_write (backend.assume_role.role_arn)",
        )

    def test_unresolvable_arn_fails(self):
        self.assert_has(stacks(**today(**{"fnx-ue1-prod": ci("prod", prefix="bad name", apply=False)})),
                        "plan role: resolved an invalid role ARN")


if __name__ == "__main__":
    unittest.main()

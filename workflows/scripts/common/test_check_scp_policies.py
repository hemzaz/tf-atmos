"""Tests for scripts/check-scp-policies.py (stdlib only): python3 -m unittest workflows/scripts/common/test_check_scp_policies.py"""

import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_scp_policies",
    pathlib.Path(__file__).resolve().parents[3] / "scripts" / "check-scp-policies.py",
)
check = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check)

SSO = "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_"
CI_APPLY = "arn:aws:iam::*:role/fnx-*-ci-apply"
OAAR = "arn:aws:iam::*:role/OrganizationAccountAccessRole"
DEPLOY_ROLES = [CI_APPLY, OAAR, SSO + "TerraformApplyAccess_*", SSO + "TerraformApplyAccess-*",
                SSO + "AdministratorAccess_*"]
PROTECT = {"Sid": "DenyProtectedRoleTampering", "Effect": "Deny",
           "Action": ["iam:CreateRole", "iam:DeleteRole", "iam:UpdateAssumeRolePolicy",
                      "iam:PutRolePolicy", "iam:AttachRolePolicy"],
           "Resource": [CI_APPLY, OAAR, "arn:aws:iam::*:role/aws-reserved/*"],
           "Condition": {"ArnNotLike": {"aws:PrincipalArn": DEPLOY_ROLES}}}


def security_deny(principals):
    return {"Sid": "DenySecurityServicesTampering", "Effect": "Deny",
            "Action": ["cloudtrail:StopLogging"], "Resource": "*",
            "Condition": {"ArnNotLike": {"aws:PrincipalArn": principals}}}


def deny(action, test, key, values):
    return {"Effect": "Deny", "Action": [action], "Resource": "*", "Condition": {test: {key: values}}}


class ConditionKeys(unittest.TestCase):
    def test_real_keys_are_not_near_misses(self):
        for key in ("aws:PrincipalOrgPaths", "aws:ResourceAccount", "aws:SourceArn"):
            with self.subTest(key=key):
                self.assertEqual(check.statement_findings("s", deny("s3:PutObject", "StringNotEquals", key, ["x"])), [])

    def test_misspelled_key_is_a_near_miss(self):
        errs = check.statement_findings("s", deny("s3:PutObject", "StringNotLike", "aws:PrincipalOrgPath", ["x"]))
        self.assertEqual(len(errs), 1)
        self.assertIn("aws:principalorgpaths", errs[0])


class Denies(unittest.TestCase):
    def test_non_principal_condition_still_denies(self):
        st = deny("cloudwatch:PutMetricAlarm", "StringNotEquals", "aws:ResourceAccount", ["111111111111"])
        self.assertTrue(check.denies(st, "cloudwatch:PutMetricAlarm", "us-east-1"))

    def test_principal_exception_does_not_deny(self):
        for key in ("aws:PrincipalArn", "aws:PrincipalOrgID"):
            with self.subTest(key=key):
                self.assertFalse(check.denies(deny("kms:CreateKey", "ArnNotLike", key, ["x"]), "kms:CreateKey", "us-east-1"))

    def test_region_condition_denies_outside_its_regions(self):
        st = deny("events:PutRule", "StringNotEquals", "aws:RequestedRegion", ["eu-west-1"])
        self.assertTrue(check.denies(st, "events:PutRule", "us-east-1"))
        self.assertFalse(check.denies(st, "events:PutRule", "eu-west-1"))


class IdentityCenterExceptions(unittest.TestCase):
    def test_deploy_roles_pass(self):
        self.assertEqual(check.statement_findings("s", security_deny(DEPLOY_ROLES)), [])

    def test_sso_role_outside_the_reserved_path_fails(self):
        roles = DEPLOY_ROLES + ["arn:aws:iam::*:role/AWSReservedSSO_AdministratorAccess_*"]
        errs = check.statement_findings("s", security_deny(roles))
        self.assertEqual(len(errs), 1)
        self.assertIn("aws-reserved/sso.amazonaws.com", errs[0])

    def test_sso_wildcard_permission_set_fails(self):
        errs = check.statement_findings("s", security_deny(DEPLOY_ROLES + [SSO + "*"]))
        self.assertEqual(len(errs), 1)
        self.assertIn("one named permission set", errs[0])

    def test_dash_wildcard_only_on_required_sets(self):
        # TerraformApplyAccess-* (its -Prod/-Core/-Eu variants) passes; another set's -* is too broad.
        errs = check.statement_findings("s", security_deny(DEPLOY_ROLES + [SSO + "ReadOnlyAccess-*"]))
        self.assertEqual(len(errs), 1)
        self.assertIn("ends in -*", errs[0])

    def test_security_deny_without_identity_center_sets_fails(self):
        for missing in (SSO + "AdministratorAccess_*", SSO + "TerraformApplyAccess_*"):
            with self.subTest(missing=missing):
                roles = [r for r in DEPLOY_ROLES if r != missing and not (
                    "TerraformApplyAccess" in missing and "TerraformApplyAccess" in r)]
                errs = check.statement_findings("s", security_deny(roles))
                self.assertEqual(len(errs), 1)
                self.assertIn("Identity Center sets", errs[0])


class RoleNameSquatting(unittest.TestCase):
    def test_protected_exceptions_pass(self):
        self.assertEqual(check.squat_findings("p", [security_deny(DEPLOY_ROLES), PROTECT]), [])

    def test_unprotected_role_name_exception_fails(self):
        errs = check.squat_findings("p", [security_deny(DEPLOY_ROLES)])
        self.assertEqual(sorted(e.split("'")[1] for e in errs), sorted([CI_APPLY, OAAR]))

    def test_protection_missing_create_role_fails(self):
        weak = dict(PROTECT, Action=[a for a in PROTECT["Action"] if a != "iam:CreateRole"])
        errs = check.squat_findings("p", [security_deny(DEPLOY_ROLES), weak])
        self.assertEqual(len(errs), 2)

    def test_protection_missing_one_role_fails(self):
        partial = dict(PROTECT, Resource=[OAAR])
        errs = check.squat_findings("p", [security_deny(DEPLOY_ROLES), partial])
        self.assertEqual([e.split("'")[1] for e in errs], [CI_APPLY])


class CheckWiring(unittest.TestCase):
    def stacks(self, statements):
        def to_vars(st):
            conds = [{"test": t, "variable": k, "values": v}
                     for t, keys in (st.get("Condition") or {}).items() for k, v in keys.items()]
            return {"sid": st.get("Sid"), "effect": st["Effect"], "actions": st["Action"],
                    "resources": st["Resource"] if isinstance(st["Resource"], list) else [st["Resource"]],
                    "conditions": conds}
        scp = {"component": "aws-scp", "metadata": {},
               "vars": {"tags": {"Account": "root"},
                        "target_ids": ["!terraform.state aws-organizational-unit/core organizational_unit_id"],
                        "policy_statements": [to_vars(s) for s in statements]}}
        return {"fnx-gbl-root": {"components": {"terraform": {"aws-scp/security-services-core": scp}}}}

    def test_catalog_shape_is_clean(self):
        self.assertEqual(check.check(self.stacks([security_deny(DEPLOY_ROLES), PROTECT])), [])

    def test_missing_protection_fails_the_check(self):
        errs = check.check(self.stacks([security_deny(DEPLOY_ROLES)]))
        self.assertEqual(len(errs), 2)
        self.assertTrue(all("escapes the deny" in e for e in errs))


if __name__ == "__main__":
    unittest.main()

"""Tests for scripts/check-scp-policies.py (stdlib only): python3 -m unittest workflows/scripts/common/test_check_scp_policies.py"""

import importlib.util
import json
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


WORKLOAD_ROLES = [r for r in DEPLOY_ROLES if r != OAAR]
CORE, PLAT = "aws-organizational-unit/core", "aws-organizational-unit/plat"


def security_deny(principals, actions=("cloudtrail:StopLogging", "config:StopConfigurationRecorder"),
                  sid="DenyTrailConfigTampering"):
    return {"Sid": sid, "Effect": "Deny", "Action": list(actions), "Resource": "*",
            "Condition": {"ArnNotLike": {"aws:PrincipalArn": principals}}}


def detector_deny(principals):
    return security_deny(principals, ("guardduty:DeleteDetector", "securityhub:DisableSecurityHub",
                                      "access-analyzer:DeleteAnalyzer"), "DenyDetectorTampering")


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


class SecurityServicesSplit(unittest.TestCase):
    """E5b8 / owner decision OQ-F: trail/Config and detector denies are separate statements, and
    OrganizationAccountAccessRole is excepted from the trail/Config one on core only."""

    def test_mixed_trail_and_detector_statement_fails(self):
        st = security_deny(DEPLOY_ROLES, ("cloudtrail:StopLogging", "guardduty:DeleteDetector"))
        errs = check.statement_findings("s", st, [CORE])
        self.assertEqual(len(errs), 1)
        self.assertIn("split it", errs[0])

    def test_detector_deny_needs_oaar_on_every_ou(self):
        for ou in (CORE, PLAT):
            with self.subTest(ou=ou):
                self.assertEqual(check.statement_findings("s", detector_deny(DEPLOY_ROLES), [ou]), [])
                errs = check.statement_findings("s", detector_deny(WORKLOAD_ROLES), [ou])
                self.assertEqual(len(errs), 1)
                self.assertIn("OrganizationAccountAccessRole", errs[0])

    def test_plat_trail_config_deny_without_oaar_passes(self):
        self.assertEqual(check.statement_findings("s", security_deny(WORKLOAD_ROLES), [PLAT]), [])

    def test_plat_trail_config_deny_with_oaar_fails(self):
        for ou in (PLAT, "aws-organizational-unit/eu"):
            with self.subTest(ou=ou):
                errs = check.statement_findings("s", security_deny(DEPLOY_ROLES), [ou])
                self.assertEqual(len(errs), 1)
                self.assertIn("OQ-F", errs[0])

    def test_core_trail_config_deny_needs_oaar(self):
        self.assertEqual(check.statement_findings("s", security_deny(DEPLOY_ROLES), [CORE]), [])
        errs = check.statement_findings("s", security_deny(WORKLOAD_ROLES), [CORE])
        self.assertEqual(len(errs), 1)
        self.assertIn("core stacks' trails", errs[0])

    def test_trail_config_deny_on_core_and_plat_fails(self):
        errs = check.statement_findings("s", security_deny(DEPLOY_ROLES), [CORE, PLAT])
        self.assertEqual(len(errs), 1)
        self.assertIn("its own policy", errs[0])

    def test_trail_config_deny_still_needs_ci_and_identity_center(self):
        errs = check.statement_findings("s", security_deny([OAAR]), [CORE])
        self.assertEqual(len(errs), 1)
        self.assertIn("ci-apply", errs[0])


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


def to_vars(st):
    conds = [{"test": t, "variable": k, "values": v}
             for t, keys in (st.get("Condition") or {}).items() for k, v in keys.items()]
    return {"sid": st.get("Sid"), "effect": st["Effect"], "actions": st["Action"],
            "resources": st["Resource"] if isinstance(st["Resource"], list) else [st["Resource"]],
            "conditions": conds}


def scp(statements, ou=CORE):
    return {"component": "aws-scp", "metadata": {},
            "vars": {"tags": {"Account": "root"},
                     "target_ids": [f"!terraform.state {ou} organizational_unit_id"],
                     "policy_statements": [to_vars(s) for s in statements]}}


PLAT_PROTECT = dict(PROTECT, Condition={"ArnNotLike": {"aws:PrincipalArn": WORKLOAD_ROLES}})
IDENTITY_CENTER = {"component": "aws-identity-center", "metadata": {}}


class CheckWiring(unittest.TestCase):
    def stacks(self, statements, ou=CORE, identity_center=True):
        name = "aws-scp/security-services-" + ou.rsplit("/", 1)[1]
        comps = {name: scp(statements, ou)}
        if identity_center:
            comps["aws-identity-center"] = IDENTITY_CENTER
        return {"fnx-gbl-root": {"components": {"terraform": comps}}}

    def test_catalog_shape_is_clean(self):
        # The catalog's two copies (stacks/catalog/aws-scp/defaults.yaml): core keeps
        # OrganizationAccountAccessRole in every exception; plat drops it from the trail/Config
        # and protected-role ones (it stays a protected role) and keeps it for detectors.
        for ou, roles, protect in ((CORE, DEPLOY_ROLES, PROTECT), (PLAT, WORKLOAD_ROLES, PLAT_PROTECT)):
            with self.subTest(ou=ou):
                statements = [security_deny(roles), detector_deny(DEPLOY_ROLES), protect]
                self.assertEqual(check.check(self.stacks(statements, ou)), [])

    def test_plat_copy_with_oaar_fails_the_check(self):
        errs = check.check(self.stacks([security_deny(DEPLOY_ROLES), detector_deny(DEPLOY_ROLES), PLAT_PROTECT], PLAT))
        self.assertEqual(len(errs), 1)
        self.assertIn("DenyTrailConfigTampering", errs[0])
        self.assertIn("OQ-F", errs[0])

    def test_plat_protection_exempting_oaar_is_an_escalation(self):
        # #516's first head: OAAR may create or re-trust a <stack>-ci-apply role, assume it and
        # stop the trail DenyTrailConfigTampering denies it.
        errs = check.check(self.stacks([security_deny(WORKLOAD_ROLES), detector_deny(DEPLOY_ROLES), PROTECT], PLAT))
        self.assertEqual(len(errs), 1)
        self.assertIn(OAAR, errs[0])
        self.assertIn("may create or re-trust a role DenyTrailConfigTampering excepts", errs[0])

    def test_escalation_compares_actions_case_insensitively(self):
        lower = dict(PROTECT, Action=[a.lower() for a in PROTECT["Action"]])
        errs = check.escalation_findings("p", [security_deny(WORKLOAD_ROLES), lower])
        self.assertEqual(len(errs), 1)
        upper = security_deny(WORKLOAD_ROLES, ("CloudTrail:StopLogging",))
        self.assertEqual(len(check.statement_findings("s", upper, [PLAT])), 0)
        self.assertEqual(len(check.statement_findings("s", security_deny(DEPLOY_ROLES, ("CloudTrail:StopLogging",)),
                                                      [PLAT])), 1)

    def test_enabled_without_identity_center_fails(self):
        statements = [security_deny(DEPLOY_ROLES), detector_deny(DEPLOY_ROLES), PROTECT]
        errs = check.check(self.stacks(statements, identity_center=False))
        self.assertEqual(len(errs), 1)
        self.assertIn("enabled while aws-identity-center is disabled", errs[0])
        stacks = self.stacks(statements)
        terraform = stacks["fnx-gbl-root"]["components"]["terraform"]
        terraform["aws-identity-center"] = dict(IDENTITY_CENTER, metadata={"enabled": False})
        self.assertEqual(len(check.check(stacks)), 1)

    def test_disabled_without_identity_center_passes(self):
        stacks = self.stacks([security_deny(DEPLOY_ROLES), detector_deny(DEPLOY_ROLES), PROTECT], identity_center=False)
        stacks["fnx-gbl-root"]["components"]["terraform"]["aws-scp/security-services-core"]["metadata"] = {"enabled": False}
        self.assertEqual(check.check(stacks), [])

    def test_core_copy_without_oaar_fails_the_check(self):
        # Also an escalation: core's protection still exempts OAAR, which the trail deny now binds.
        errs = check.check(self.stacks([security_deny(WORKLOAD_ROLES), detector_deny(DEPLOY_ROLES), PROTECT]))
        self.assertEqual(len(errs), 2)
        self.assertTrue(any("core stacks' trails" in e for e in errs))
        self.assertTrue(any("may create or re-trust" in e for e in errs))

    def test_missing_protection_fails_the_check(self):
        errs = check.check(self.stacks([security_deny(DEPLOY_ROLES)]))
        self.assertEqual(len(errs), 2)
        self.assertTrue(all("escapes the deny" in e for e in errs))


class Limits(unittest.TestCase):
    def test_size_counts_minified_json(self):
        # AWS counts the policy without whitespace outside strings: indentation is free.
        st = dict(deny("s3:PutObject", "StringNotEquals", "aws:RequestedRegion", ["us-east-1"]), Sid="S")
        doc = check.policy_document(scp([st])["vars"])
        size = len(json.dumps(doc, separators=(",", ":")))
        pad = check.MAX_CHARS - size
        ok = dict(st, Sid="S" + "x" * pad)
        over = dict(st, Sid="S" + "x" * (pad + 1))
        stacks = {"fnx-gbl-root": {"components": {"terraform": {"aws-scp/a": scp([ok])}}}}
        self.assertEqual(check.check(stacks), [])
        stacks = {"fnx-gbl-root": {"components": {"terraform": {"aws-scp/a": scp([over])}}}}
        errs = check.check(stacks)
        self.assertEqual(len(errs), 1)
        self.assertIn(f"{check.MAX_CHARS + 1} characters", errs[0])

    def test_five_policies_on_one_ou_fail(self):
        st = deny("s3:PutObject", "StringNotEquals", "aws:RequestedRegion", ["us-east-1"])
        four = {f"aws-scp/p{i}": scp([st]) for i in range(check.MAX_PER_TARGET)}
        self.assertEqual(check.check({"fnx-gbl-root": {"components": {"terraform": four}}}), [])
        five = dict(four, **{"aws-scp/p4": scp([st])})
        errs = check.check({"fnx-gbl-root": {"components": {"terraform": five}}})
        self.assertEqual(len(errs), 1)
        self.assertIn("5 SCPs", errs[0])


if __name__ == "__main__":
    unittest.main()

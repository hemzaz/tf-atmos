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
BREAK_GLASS = SSO + "AdministratorAccess_*"
DEPLOY_ROLES = [CI_APPLY, OAAR, SSO + "TerraformApplyAccess_*", SSO + "TerraformApplyAccess-*", BREAK_GLASS]
ROLE_ACTIONS = ["iam:CreateRole", "iam:DeleteRole", "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy",
                "iam:AttachRolePolicy"]
PROTECT = {"Sid": "DenyProtectedRoleTampering", "Effect": "Deny", "Action": ROLE_ACTIONS,
           "Resource": [CI_APPLY, OAAR],
           "Condition": {"ArnNotLike": {"aws:PrincipalArn": DEPLOY_ROLES}}}
# aws-reserved/: no principal exception (only Identity Center's service-linked role writes there).
RESERVED = {"Sid": "DenyReservedRoleTampering", "Effect": "Deny", "Action": ROLE_ACTIONS,
            "Resource": ["arn:aws:iam::*:role/aws-reserved/*"]}


WORKLOAD_ROLES = [r for r in DEPLOY_ROLES if r != OAAR]
CORE, PLAT = "aws-organizational-unit/core", "aws-organizational-unit/plat"
SEC = "111111111111"


def pin(role, account=SEC):
    return role.replace("arn:aws:iam::*:", f"arn:aws:iam::{account}:")


# Core's detector exception: the deploy roles pinned to the security account, the break-glass anywhere.
CORE_DETECTOR_ROLES = [pin(r) for r in DEPLOY_ROLES if r != BREAK_GLASS] + [BREAK_GLASS]


def security_deny(principals, actions=("cloudtrail:StopLogging", "config:StopConfigurationRecorder"),
                  sid="DenyTrailConfigTampering"):
    return {"Sid": sid, "Effect": "Deny", "Action": list(actions), "Resource": "*",
            "Condition": {"ArnNotLike": {"aws:PrincipalArn": principals}}}


def detector_deny(principals):
    return security_deny(principals, ("guardduty:DeleteDetector", "securityhub:DisableSecurityHub",
                                      "inspector2:Disable"), "DenyDetectorTampering")


def analyzer_deny(principals):
    return security_deny(principals, ("access-analyzer:DeleteAnalyzer", "access-analyzer:DeleteArchiveRule"),
                         "DenyAnalyzerTampering")


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

    def test_sso_role_pinned_to_an_account_passes(self):
        self.assertEqual(check.statement_findings("s", security_deny(DEPLOY_ROLES + [pin(BREAK_GLASS)])), [])

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
    """E5b8 / owner decision OQ-F / E5c10: trail/Config, detector and Access Analyzer denies are
    separate statements; OrganizationAccountAccessRole is excepted from the trail/Config one on
    core only."""

    def test_mixed_trail_and_detector_statement_fails(self):
        st = security_deny(DEPLOY_ROLES, ("cloudtrail:StopLogging", "guardduty:DeleteDetector"))
        errs = check.statement_findings("s", st, [CORE])
        self.assertEqual(len(errs), 1)
        self.assertIn("split it", errs[0])

    def test_mixed_analyzer_and_other_statement_fails(self):
        for other in ("guardduty:DeleteDetector", "inspector2:Disable", "config:PutConfigurationRecorder"):
            with self.subTest(other=other):
                st = security_deny(DEPLOY_ROLES, ("access-analyzer:DeleteAnalyzer", other))
                errs = check.statement_findings("s", st, [PLAT])
                self.assertEqual(len(errs), 1)
                self.assertIn("Access Analyzer", errs[0])
                self.assertIn("split it", errs[0])

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

    def test_trail_config_deny_pinned_to_one_account_fails(self):
        # Each stack applies its own trail: the exception must hold in every account.
        errs = check.statement_findings("s", security_deny([pin(r) for r in WORKLOAD_ROLES]), [PLAT])
        self.assertEqual(len(errs), 1)
        self.assertIn("in every account", errs[0])


class DetectorExceptions(unittest.TestCase):
    """E5c10: plat excepts the break-glass only; core the security account's deploy roles too."""

    def test_plat_break_glass_only_passes(self):
        for ou in (PLAT, "aws-organizational-unit/eu"):
            with self.subTest(ou=ou):
                self.assertEqual(check.statement_findings("s", detector_deny([BREAK_GLASS]), [ou], SEC), [])

    def test_plat_detector_exception_with_ci_apply_fails(self):
        errs = check.statement_findings("s", detector_deny([CI_APPLY, BREAK_GLASS]), [PLAT], SEC)
        self.assertEqual(len(errs), 1)
        self.assertIn(CI_APPLY, errs[0])
        self.assertIn("only", errs[0])

    def test_detector_without_break_glass_fails(self):
        errs = check.statement_findings("s", detector_deny(CORE_DETECTOR_ROLES[:-1]), [CORE], SEC)
        self.assertEqual(len(errs), 1)
        self.assertIn("break-glass", errs[0])

    def test_core_pinned_to_the_security_account_passes(self):
        self.assertEqual(check.statement_findings("s", detector_deny(CORE_DETECTOR_ROLES), [CORE], SEC), [])

    def test_core_unpinned_exception_fails(self):
        # The pre-E5c10 exception (the deploy roles in every account) also lacks the pinned ci-apply.
        for roles, count in ((DEPLOY_ROLES, 2), ([pin(CI_APPLY), CI_APPLY, BREAK_GLASS], 1)):
            with self.subTest(roles=roles):
                errs = check.statement_findings("s", detector_deny(roles), [CORE], SEC)
                self.assertEqual(len(errs), count)
                self.assertIn("not pinned to the security account", errs[0])

    def test_core_pinned_to_another_account_fails(self):
        roles = [pin(r, "222222222222") for r in DEPLOY_ROLES if r != BREAK_GLASS] + [BREAK_GLASS]
        errs = check.statement_findings("s", detector_deny(roles), [CORE], SEC)
        self.assertEqual(len(errs), 2)
        self.assertTrue(any("not pinned" in e for e in errs))
        self.assertTrue(any("does not except the security account's" in e for e in errs))

    def test_core_without_security_account_fails(self):
        errs = check.statement_findings("s", detector_deny(CORE_DETECTOR_ROLES), [CORE])
        self.assertEqual(len(errs), 1)
        self.assertIn("full_account_map.security", errs[0])

    def test_detector_deny_on_core_and_plat_fails(self):
        errs = check.statement_findings("s", detector_deny(CORE_DETECTOR_ROLES), [CORE, PLAT], SEC)
        self.assertEqual(len(errs), 1)
        self.assertIn("its own policy", errs[0])


class AnalyzerExceptions(unittest.TestCase):
    """E5c10: the OU's deploy roles in every account (E5c7b's ACCOUNT analyzers)."""

    def test_deploy_roles_pass(self):
        for ou, roles in ((CORE, DEPLOY_ROLES), (PLAT, WORKLOAD_ROLES)):
            with self.subTest(ou=ou):
                self.assertEqual(check.statement_findings("s", analyzer_deny(roles), [ou], SEC), [])

    def test_break_glass_only_fails(self):
        errs = check.statement_findings("s", analyzer_deny([BREAK_GLASS]), [PLAT], SEC)
        self.assertEqual(len(errs), 1)
        self.assertIn("ci-apply", errs[0])

    def test_pinned_ci_apply_fails(self):
        roles = [pin(CI_APPLY)] + [r for r in WORKLOAD_ROLES if r != CI_APPLY]
        errs = check.statement_findings("s", analyzer_deny(roles), [PLAT], SEC)
        self.assertEqual(len(errs), 1)
        self.assertIn("in every account", errs[0])


class ReservedProtection(unittest.TestCase):
    def test_reserved_protection_without_exception_passes(self):
        self.assertEqual(check.statement_findings("s", RESERVED), [])

    def test_reserved_protection_with_exception_fails(self):
        for st in (dict(RESERVED, Condition=PROTECT["Condition"]),
                   dict(PROTECT, Resource=PROTECT["Resource"] + ["arn:aws:iam::*:role/aws-reserved/*"])):
            with self.subTest(resources=st["Resource"]):
                errs = check.statement_findings("s", st)
                self.assertEqual(len(errs), 1)
                self.assertIn("aws-reserved/ with a principal exception", errs[0])


class RoleNameSquatting(unittest.TestCase):
    def test_protected_exceptions_pass(self):
        self.assertEqual(check.squat_findings("p", [security_deny(DEPLOY_ROLES), PROTECT, RESERVED]), [])

    def test_pinned_exceptions_are_covered(self):
        self.assertEqual(check.squat_findings("p", [detector_deny(CORE_DETECTOR_ROLES), PROTECT, RESERVED]), [])

    def test_unprotected_role_name_exception_fails(self):
        # Identity Center's exceptions too: without the aws-reserved/ protection, anyone could create them.
        errs = check.squat_findings("p", [security_deny(DEPLOY_ROLES)])
        self.assertEqual(sorted(e.split("'")[1] for e in errs), sorted(DEPLOY_ROLES))
        errs = check.squat_findings("p", [security_deny(DEPLOY_ROLES), PROTECT])
        self.assertEqual(sorted(e.split("'")[1] for e in errs), sorted(r for r in DEPLOY_ROLES if "SSO" in r))

    def test_protection_missing_create_role_fails(self):
        weak = dict(PROTECT, Action=[a for a in PROTECT["Action"] if a != "iam:CreateRole"])
        errs = check.squat_findings("p", [security_deny(DEPLOY_ROLES), weak, RESERVED])
        self.assertEqual(len(errs), 2)

    def test_protection_missing_one_role_fails(self):
        partial = dict(PROTECT, Resource=[OAAR])
        errs = check.squat_findings("p", [security_deny(DEPLOY_ROLES), partial, RESERVED])
        self.assertEqual([e.split("'")[1] for e in errs], [CI_APPLY])


class Escalation(unittest.TestCase):
    """Per protected role and account: whoever may create a role an exception names must be exempt too."""

    def test_catalog_shape_has_no_escalation(self):
        for statements in ([security_deny(DEPLOY_ROLES), detector_deny(CORE_DETECTOR_ROLES),
                            analyzer_deny(DEPLOY_ROLES), PROTECT, RESERVED],
                           [security_deny(WORKLOAD_ROLES), detector_deny([BREAK_GLASS]),
                            analyzer_deny(WORKLOAD_ROLES), PLAT_PROTECT, RESERVED]):
            with self.subTest(statements=[s["Sid"] for s in statements]):
                self.assertEqual(check.escalation_findings("p", statements), [])

    def test_no_exception_protection_closes_the_break_glass(self):
        # The detector deny exempts AdministratorAccess only; the deploy roles cannot mint one.
        self.assertEqual(check.escalation_findings("p", [detector_deny([BREAK_GLASS]), PLAT_PROTECT, RESERVED]), [])
        # Were aws-reserved/ protected with the deploy roles' exception, they could.
        leaky = dict(RESERVED, Condition=PLAT_PROTECT["Condition"])
        errs = check.escalation_findings("p", [detector_deny([BREAK_GLASS]), PLAT_PROTECT, leaky])
        self.assertEqual(len(errs), 1)
        self.assertIn(CI_APPLY, errs[0])

    def test_protection_exempt_role_creating_an_exempt_role_in_another_account(self):
        # A role pinned to the security account: a principal exempt from its protection in every
        # account (arn:aws:iam::*:...) can create it there, so it must be exempt there too.
        ops = "arn:aws:iam::*:role/ops"
        protect = dict(PROTECT, Condition={"ArnNotLike": {"aws:PrincipalArn": DEPLOY_ROLES + [ops]}})
        errs = check.escalation_findings("p", [detector_deny(CORE_DETECTOR_ROLES), protect, RESERVED])
        self.assertEqual(len(errs), 1)
        self.assertIn(pin(ops), errs[0])
        self.assertIn("DenyDetectorTampering", errs[0])

    def test_principal_pinned_elsewhere_cannot_create_the_role(self):
        # ops in account 222222222222 creates roles only there, never the security account's.
        ops = "arn:aws:iam::222222222222:role/ops"
        protect = dict(PROTECT, Condition={"ArnNotLike": {"aws:PrincipalArn": DEPLOY_ROLES + [ops]}})
        self.assertEqual(check.escalation_findings("p", [detector_deny(CORE_DETECTOR_ROLES), protect, RESERVED]), [])
        # But an unpinned exception (any account) it could create in its own.
        errs = check.escalation_findings("p", [security_deny(WORKLOAD_ROLES), protect, RESERVED])
        self.assertEqual(len(errs), 1)
        self.assertIn(ops, errs[0])

    def test_escalation_compares_actions_case_insensitively(self):
        lower = dict(PROTECT, Action=[a.lower() for a in PROTECT["Action"]])
        errs = check.escalation_findings("p", [security_deny(WORKLOAD_ROLES), lower, RESERVED])
        self.assertEqual(len(errs), 1)
        upper = security_deny(WORKLOAD_ROLES, ("CloudTrail:StopLogging",))
        self.assertEqual(len(check.statement_findings("s", upper, [PLAT])), 0)
        self.assertEqual(len(check.statement_findings("s", security_deny(DEPLOY_ROLES, ("CloudTrail:StopLogging",)),
                                                      [PLAT])), 1)


def to_vars(st):
    conds = [{"test": t, "variable": k, "values": v}
             for t, keys in (st.get("Condition") or {}).items() for k, v in keys.items()]
    return {"sid": st.get("Sid"), "effect": st["Effect"], "actions": st["Action"],
            "resources": st["Resource"] if isinstance(st["Resource"], list) else [st["Resource"]],
            "conditions": conds}


def scp(statements, ou=CORE):
    return {"component": "aws-scp", "metadata": {},
            "settings": {"account_map": {"full_account_map": {"security": SEC}}},
            "vars": {"tags": {"Account": "root"},
                     "target_ids": [f"!terraform.state {ou} organizational_unit_id"],
                     "policy_statements": [to_vars(s) for s in statements]}}


PLAT_PROTECT = dict(PROTECT, Condition={"ArnNotLike": {"aws:PrincipalArn": WORKLOAD_ROLES}})
IDENTITY_CENTER = {"component": "aws-identity-center", "metadata": {}}


def catalog(ou):
    """The catalog's copy for an OU (stacks/catalog/aws-scp/defaults.yaml)."""
    if ou == CORE:
        return [security_deny(DEPLOY_ROLES), detector_deny(CORE_DETECTOR_ROLES), analyzer_deny(DEPLOY_ROLES),
                PROTECT, RESERVED]
    return [security_deny(WORKLOAD_ROLES), detector_deny([BREAK_GLASS]), analyzer_deny(WORKLOAD_ROLES),
            PLAT_PROTECT, RESERVED]


class CheckWiring(unittest.TestCase):
    def stacks(self, statements, ou=CORE, identity_center=True):
        name = "aws-scp/security-services-" + ou.rsplit("/", 1)[1]
        comps = {name: scp(statements, ou)}
        if identity_center:
            comps["aws-identity-center"] = IDENTITY_CENTER
        return {"fnx-gbl-root": {"components": {"terraform": comps}}}

    def test_catalog_shape_is_clean(self):
        # core keeps OrganizationAccountAccessRole in its deploy roles and pins the detector
        # exception to the security account; plat drops it everywhere and excepts only the
        # break-glass from the detector deny. Both protect aws-reserved/ with no exception.
        for ou in (CORE, PLAT):
            with self.subTest(ou=ou):
                self.assertEqual(check.check(self.stacks(catalog(ou), ou)), [])

    def test_plat_copy_with_oaar_fails_the_check(self):
        statements = [security_deny(DEPLOY_ROLES)] + catalog(PLAT)[1:]
        errs = check.check(self.stacks(statements, PLAT))
        self.assertEqual(len(errs), 1)
        self.assertIn("DenyTrailConfigTampering", errs[0])
        self.assertIn("OQ-F", errs[0])

    def test_plat_protection_exempting_oaar_is_an_escalation(self):
        # #516's first head: OAAR may create or re-trust a <stack>-ci-apply role, assume it and
        # stop the trail DenyTrailConfigTampering denies it (and delete an analyzer).
        statements = catalog(PLAT)[:3] + [PROTECT, RESERVED]
        errs = check.check(self.stacks(statements, PLAT))
        self.assertEqual(len(errs), 2)
        self.assertTrue(all(OAAR in e for e in errs))
        self.assertTrue(any("may create or re-trust a role DenyTrailConfigTampering excepts" in e for e in errs))
        self.assertTrue(any("may create or re-trust a role DenyAnalyzerTampering excepts" in e for e in errs))

    def test_plat_copy_with_old_detector_exception_fails_the_check(self):
        statements = [catalog(PLAT)[0], detector_deny(DEPLOY_ROLES)] + catalog(PLAT)[2:]
        errs = check.check(self.stacks(statements, PLAT))
        self.assertEqual(len(errs), 1)
        self.assertIn("only " + BREAK_GLASS, errs[0])

    def test_security_account_comes_from_settings(self):
        stacks = self.stacks(catalog(CORE))
        scp_comp = stacks["fnx-gbl-root"]["components"]["terraform"]["aws-scp/security-services-core"]
        scp_comp["settings"]["account_map"]["full_account_map"]["security"] = "222222222222"
        errs = check.check(stacks)
        self.assertTrue(errs)
        self.assertTrue(all("DenyDetectorTampering" in e for e in errs))

    def test_enabled_without_identity_center_fails(self):
        errs = check.check(self.stacks(catalog(CORE), identity_center=False))
        self.assertEqual(len(errs), 1)
        self.assertIn("enabled while aws-identity-center is disabled", errs[0])
        stacks = self.stacks(catalog(CORE))
        terraform = stacks["fnx-gbl-root"]["components"]["terraform"]
        terraform["aws-identity-center"] = dict(IDENTITY_CENTER, metadata={"enabled": False})
        self.assertEqual(len(check.check(stacks)), 1)

    def test_disabled_without_identity_center_passes(self):
        stacks = self.stacks(catalog(CORE), identity_center=False)
        stacks["fnx-gbl-root"]["components"]["terraform"]["aws-scp/security-services-core"]["metadata"] = {"enabled": False}
        self.assertEqual(check.check(stacks), [])

    def test_core_copy_without_oaar_fails_the_check(self):
        # Also an escalation: core's protection still exempts OAAR, which the trail deny now binds.
        errs = check.check(self.stacks([security_deny(WORKLOAD_ROLES)] + catalog(CORE)[1:]))
        self.assertEqual(len(errs), 2)
        self.assertTrue(any("core stacks' trails" in e for e in errs))
        self.assertTrue(any("may create or re-trust" in e for e in errs))

    def test_missing_protection_fails_the_check(self):
        errs = check.check(self.stacks([security_deny(DEPLOY_ROLES)]))
        self.assertEqual(len(errs), len(DEPLOY_ROLES))
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
        self.assertEqual(check.policy_sizes(stacks), [("fnx-gbl-root", "aws-scp/a", check.MAX_CHARS)])
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

"""Tests for check-first-deploy-inputs.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import contextlib
import importlib.util
import io
import json
import pathlib
import sys
import unittest
from unittest import mock

_spec = importlib.util.spec_from_file_location(
    "check_first_deploy_inputs", pathlib.Path(__file__).with_name("check-first-deploy-inputs.py")
)
preflight = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(preflight)

MGMT = "111111111111"


def env(stage, account, **extra):
    environment = {"account_id": account, "management_account_id": MGMT, "domain_name": f"{stage}.acme.io"}
    environment.update(extra)
    return environment


def inst(stage, environment, component="vpc", enabled=True, **variables):
    return {
        "component": component,
        "metadata": {"component": component, "enabled": enabled},
        "settings": {"context": {"stage": stage}, "environment": environment},
        "vars": variables,
    }


def stack(stage, account, extra_env=None, **instances):
    environment = env(stage, account, **(extra_env or {}))
    built = {name: inst(stage, environment, **spec) for name, spec in instances.items()} or {
        "vpc/main": inst(stage, environment)
    }
    return {"components": {"terraform": built}}


def clean():
    """Real-looking, distinct accounts: no errors."""
    return {
        "fnx-ue1-root": stack("root", None, backend_main={"component": "backend",
                                                             "account_id": MGMT}),
        "fnx-ue1-dev": stack("dev", "222222222222"),
        "fnx-ue1-staging": stack("staging", "333333333333"),
        "fnx-ue1-prod": stack("prod", "444444444444", rds_main={
            "component": "rds", "sns_topic_arn": "arn:aws:sns:us-east-1:444444444444:alarms"}),
    }


def errors(stacks, only=None):
    return [f for f in preflight.check(stacks, only) if f.level == "error"]


class CleanTest(unittest.TestCase):
    def test_real_inputs_pass(self):
        self.assertEqual(errors(clean()), [])

    def test_repository_notices_are_always_printed(self):
        rows = {f.row for f in preflight.check(clean()) if f.level == "notice"}
        self.assertEqual(rows, {"Lambda packages", "GitHub", "Deploy tags", "GitHub App", "Budgets", "Cost-allocation tags", "Backend service images"})


class PlaceholderTest(unittest.TestCase):
    def assert_one(self, stacks, stack_name, key_fragment, row):
        found = errors(stacks)
        self.assertEqual(len(found), 1, [f.line(False) for f in found])
        self.assertEqual((found[0].stack, found[0].row), (stack_name, row))
        self.assertIn(key_fragment, found[0].key)

    def test_placeholder_workload_account(self):
        for placeholder in preflight.PLACEHOLDER_ACCOUNTS:
            with self.subTest(placeholder=placeholder):
                stacks = clean()
                stacks["fnx-ue1-dev"] = stack("dev", placeholder)
                self.assert_one(stacks, "fnx-ue1-dev", "settings.environment.account_id", "Account IDs")

    def test_placeholder_management_account_reported_per_stack(self):
        stacks = clean()
        stacks["fnx-ue1-prod"] = stack("prod", "444444444444", {"management_account_id": "123456789012"},
                                              rds_main={"component": "rds", "sns_topic_arn": "arn:x"})
        self.assert_one(stacks, "fnx-ue1-prod", "management_account_id", "Account IDs")

    def test_placeholder_account_inside_an_arn(self):
        stacks = clean()
        stacks["fnx-ue1-root"] = stack("root", None, backend_main={"component": "backend", "access_roles": {
            "read": {"allowed_principal_arns": ["arn:aws:iam::123456789012:role/fnx-ue1-dev-ci-plan"]}}})
        self.assert_one(stacks, "fnx-ue1-root", "access_roles.read.allowed_principal_arns[0]", "Account IDs")

    def test_a_longer_number_is_not_a_placeholder(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222", vpc_main={"cidr_note": "91234567890123"})
        self.assertEqual(errors(stacks), [])

    def test_uuid_and_hex_runs_are_not_placeholders(self):
        for value in ("00000000-0000-0000-0000-000000000000", "a1b2c3d4-0000-4abc-8def-123456789012",
                      "sha256:deadbeef000000000000cafe", "f123456789012"):  # pragma: allowlist secret (test values, not secrets)
            with self.subTest(value=value):
                stacks = clean()
                stacks["fnx-ue1-dev"] = stack("dev", "222222222222", vpc_main={"token": value})
                self.assertEqual(errors(stacks), [])

    def test_account_regex_cases(self):
        matches = (
            # after a hex-ish "-xxxx-" segment (review-301's misses)
            "backups-2026-123456789012", "fnx-feed-123456789012", "logs-cafe-123456789012",
            # ARN, JSON, S3 log prefix, role name, bare
            "arn:aws:iam::123456789012:role/fnx-ue1-dev-ci-plan",
            '{"Principal": {"AWS": "123456789012"}}',
            "AWSLogs/123456789012/",
            "fnx-ue1-dev-123456789012-ci",
            "123456789012", "000000000000",
        )
        non_matches = (
            "00000000-0000-0000-0000-000000000000",
            "a1b2c3d4-0000-4abc-8def-123456789012",
            "sha256:deadbeef000000000000cafe",  # pragma: allowlist secret (test value)
        )
        for value in matches:
            with self.subTest(match=value):
                self.assertTrue(preflight.ACCOUNT_RE.search(value))
        for value in non_matches:
            with self.subTest(non_match=value):
                self.assertFalse(preflight.ACCOUNT_RE.search(value))

    def test_placeholder_in_a_name_still_matches(self):
        for value in ("fnx-ue1-dev-lambda-artifacts-123456789012", "my-data-123456789012", "000000000000"):  # pragma: allowlist secret (placeholder IDs)
            with self.subTest(value=value):
                stacks = clean()
                stacks["fnx-ue1-dev"] = stack("dev", "222222222222", vpc_main={"bucket": value})
                self.assert_one(stacks, "fnx-ue1-dev", "vars.bucket", "Account IDs")

    def test_placeholder_org_id(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222", iam_ci={
            "component": "iam", "trusted_principal_org_id": "o-xxxxxxxxxx"})
        self.assert_one(stacks, "fnx-ue1-dev", "trusted_principal_org_id", "AWS Organization ID")

    def test_example_domain(self):
        stacks = clean()
        stacks["fnx-ue1-staging"] = stack("staging", "333333333333", {"domain_name": "staging.fnx.example.com"})
        self.assert_one(stacks, "fnx-ue1-staging", "settings.environment.domain_name", "Domains")

    def test_example_alert_address(self):
        for address in ("ops@example.com", "team@example.org", "oncall@corp.test"):
            with self.subTest(address=address):
                stacks = clean()
                stacks["fnx-ue1-staging"] = stack("staging", "333333333333", {
                    "monitoring": {"critical_alerts": [address]}})
                self.assert_one(stacks, "fnx-ue1-staging", "monitoring.critical_alerts[0]", "Alert recipients")

    def test_a_real_domain_containing_the_word_example_passes(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222", {"domain_name": "dev.myexample.com"})
        self.assertEqual(errors(stacks), [])

    def test_empty_eks_admin_roles(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222", eks_main={
            "component": "eks", "map_additional_iam_roles": []})
        self.assert_one(stacks, "fnx-ue1-dev", "map_additional_iam_roles", "EKS cluster admins")

    def test_eks_admin_role_set_passes(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222", eks_main={
            "component": "eks", "map_additional_iam_roles": [{"rolearn": "arn:aws:iam::222222222222:role/admin"}]})
        self.assertEqual(errors(stacks), [])

    def test_placeholder_github_app(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222", rotator_main={
            "component": "github-runners", "github_app_id": "0", "github_app_installation_id": "7654321"})
        self.assert_one(stacks, "fnx-ue1-dev", "vars.github_app_id", "GitHub App")

    def test_github_app_set_passes(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222", rotator_main={
            "component": "github-runners", "github_app_id": "123456", "github_app_installation_id": "7654321"})
        self.assertEqual(errors(stacks), [])

    def test_prod_rds_without_alarm_target(self):
        stacks = clean()
        stacks["fnx-ue1-prod"] = stack("prod", "444444444444", rds_main={"component": "rds"})
        self.assert_one(stacks, "fnx-ue1-prod", "rds_main vars.sns_topic_arn", "Prod RDS alarm target")

    def test_non_prod_rds_without_alarm_target_passes(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222", rds_main={"component": "rds"})
        self.assertEqual(errors(stacks), [])

    def test_disabled_and_abstract_instances_are_skipped(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222",
                                             lambda_api={"component": "lambda", "enabled": False,
                                                         "notify": "ops@example.com"})
        self.assertEqual(errors(stacks), [])

    def test_settings_are_reported_once_per_stack(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "123456789012", a={}, b={}, c={})
        self.assertEqual(len(errors(stacks)), 1)


class ExemptStagesTest(unittest.TestCase):
    def test_local_and_fixture_stacks_keep_their_placeholders(self):
        stacks = clean()
        stacks["fnx-ue1-local-sandbox"] = stack("local", "000000000000", {"domain_name": "local.example.com"})
        stacks["fnx-ue1-fixtures-webapp"] = stack("fixtures", "000000000000", eks={"component": "eks"})
        self.assertEqual(errors(stacks), [])


class AccountModelTest(unittest.TestCase):
    def test_workload_account_equal_to_management(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", MGMT)
        found = errors(stacks)
        self.assertEqual(len(found), 1)
        self.assertIn("is the management account", found[0].detail)

    def test_management_stage_may_use_the_management_account(self):
        stacks = clean()
        stacks["fnx-ue1-root"] = stack("root", MGMT)
        self.assertEqual(errors(stacks), [])

    def test_two_stages_sharing_an_account(self):
        stacks = clean()
        stacks["fnx-ue1-staging"] = stack("staging", "222222222222")
        found = errors(stacks)
        self.assertEqual(sorted(f.stack for f in found), ["fnx-ue1-dev", "fnx-ue1-staging"])
        self.assertTrue(all("one account per stage" in f.detail for f in found))

    def test_two_stacks_of_one_stage_may_share_its_account(self):
        stacks = clean()
        stacks["fnx-ue1-prod-eu"] = stack("prod", "444444444444", rds_main={
            "component": "rds", "sns_topic_arn": "arn:x"})
        self.assertEqual(errors(stacks), [])

    @staticmethod
    def eu_prod(account):
        """fnx-ew1-prod: stage prod, eu- region, gdpr-tagged (GDPR-scoped)."""
        return stack("prod", account, iam_ci={"component": "iam", "region": "eu-west-1",
                                              "tags": {"Compliance": "pci-sox-gdpr"}})

    def test_eu_prod_sharing_the_us_prod_account_fails(self):
        stacks = clean()
        stacks["fnx-ew1-prod"] = self.eu_prod("444444444444")
        found = errors(stacks)
        self.assertEqual(sorted(f.stack for f in found), ["fnx-ew1-prod", "fnx-ue1-prod"])
        self.assertTrue(all("never share an account" in f.detail and f.row == "Account IDs" for f in found))
        self.assertIn("fnx-ue1-prod", next(f.detail for f in found if f.stack == "fnx-ew1-prod"))

    def test_eu_prod_sharing_is_reported_on_the_target_only(self):
        stacks = clean()
        stacks["fnx-ew1-prod"] = self.eu_prod("444444444444")
        self.assertEqual([f.stack for f in errors(stacks, ["fnx-ew1-prod"])], ["fnx-ew1-prod"])

    def test_eu_prod_in_its_own_account_passes(self):
        stacks = clean()
        stacks["fnx-ew1-prod"] = self.eu_prod("555555555555")
        self.assertEqual(errors(stacks), [])

    def test_eu_prod_placeholder_is_not_reported_as_shared(self):
        stacks = clean()
        stacks["fnx-ue1-prod"] = stack("prod", "123456789012", rds_main={
            "component": "rds", "sns_topic_arn": "arn:x"})
        stacks["fnx-ew1-prod"] = self.eu_prod("123456789012")
        found = errors(stacks)
        self.assertEqual({f.row for f in found}, {"Account IDs"})
        self.assertFalse(any("never share an account" in f.detail for f in found))

    def test_placeholders_are_not_double_reported_as_shared(self):
        stacks = clean()
        for name, stage in (("fnx-ue1-dev", "dev"), ("fnx-ue1-staging", "staging")):
            stacks[name] = stack(stage, "123456789012")
        found = errors(stacks)
        self.assertEqual({f.row for f in found}, {"Account IDs"})
        self.assertFalse(any("one account per stage" in f.detail for f in found))


class OnlyStacksTest(unittest.TestCase):
    def test_only_limits_the_per_stack_checks(self):
        stacks = clean()
        stacks["fnx-ue1-prod"] = stack("prod", "123456789012", rds_main={"component": "rds"})
        self.assertEqual(errors(stacks, ["fnx-ue1-dev"]), [])
        self.assertEqual(len(errors(stacks, ["fnx-ue1-prod"])), 2)

    def test_shared_account_is_reported_on_the_target_only(self):
        stacks = clean()
        stacks["fnx-ue1-staging"] = stack("staging", "222222222222")
        self.assertEqual([f.stack for f in errors(stacks, ["fnx-ue1-staging"])], ["fnx-ue1-staging"])


class MainTest(unittest.TestCase):
    def run_main(self, stacks, *argv):
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(sys, "argv", ["check-first-deploy-inputs.py", *argv]), \
                mock.patch.object(sys, "stdin", io.StringIO(json.dumps(stacks))), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            return preflight.main(), out.getvalue(), err.getvalue()

    def placeholder_stacks(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "123456789012")
        return stacks

    def test_fatal_mode_fails(self):
        rc, out, _ = self.run_main(self.placeholder_stacks())
        self.assertEqual(rc, 1)
        self.assertIn("ERROR fnx-ue1-dev: settings.environment.account_id", out)
        self.assertIn("By row: Account IDs 1", out)

    def test_warn_mode_prints_and_passes(self):
        rc, out, _ = self.run_main(self.placeholder_stacks(), "--warn")
        self.assertEqual(rc, 0)
        self.assertIn("WARN fnx-ue1-dev: settings.environment.account_id", out)
        self.assertNotIn("ERROR", out)

    def many_placeholder_stacks(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222", vpc_main={
            "emails": [f"ops{i}@example.com" for i in range(preflight.WARN_LIMIT + 5)]})
        return stacks

    def test_warn_mode_shows_the_first_findings_and_the_counts(self):
        rc, out, _ = self.run_main(self.many_placeholder_stacks(), "--warn")
        self.assertEqual(rc, 0)
        self.assertEqual(out.count("\nWARN ") + out.startswith("WARN "), preflight.WARN_LIMIT)
        self.assertNotIn("NOTICE repository", out)
        self.assertIn("... 5 more WARN and 7 NOTICE line(s) not shown; see them all with --warn --all", out)
        self.assertIn(f"By row: Alert recipients {preflight.WARN_LIMIT + 5}", out)

    def test_warn_all_and_fatal_mode_show_everything(self):
        for argv, label in ((("--warn", "--all"), "WARN"), ((), "ERROR")):
            with self.subTest(argv=argv):
                _, out, _ = self.run_main(self.many_placeholder_stacks(), *argv)
                self.assertEqual(out.count(f"{label} fnx-ue1-dev"), preflight.WARN_LIMIT + 5)
                self.assertEqual(out.count("NOTICE repository"), 7)
                self.assertNotIn("not shown", out)

    def test_clean_passes(self):
        rc, out, _ = self.run_main(clean())
        self.assertEqual(rc, 0)
        self.assertIn("no placeholders", out)

    def test_unknown_stack_fails(self):
        rc, _, err = self.run_main(clean(), "--stacks", "fnx-typo")
        self.assertEqual(rc, 1)
        self.assertIn("unknown stack(s): fnx-typo", err)

    def test_exempt_target_is_noted_not_checked(self):
        stacks = clean()
        stacks["fnx-ue1-local-sandbox"] = stack("local", "000000000000")
        rc, out, _ = self.run_main(stacks, "--stacks", "fnx-ue1-local-sandbox")
        self.assertEqual(rc, 0)
        self.assertIn("not checked: fnx-ue1-local-sandbox", out)


if __name__ == "__main__":
    unittest.main()

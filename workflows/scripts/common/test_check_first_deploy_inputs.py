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
# settings.account_map: real-looking, distinct core and workload accounts (the clean() stacks' IDs).
ACCOUNTS = {"root": MGMT, "audit": "777777777771", "security": "777777777772", "network": "777777777773",
            "identity": "777777777774", "artifacts": "777777777775", "dev": "222222222222",
            "staging": "333333333333", "prod": "444444444444", "prod-eu": "666666666666"}


def env(stage, account, **extra):
    environment = {"account_id": account, "management_account_id": MGMT, "domain_name": f"{stage}.acme.io"}
    environment.update(extra)
    return environment


def inst(stage, environment, component="vpc", enabled=True, accounts=None, **variables):
    return {
        "component": component,
        "metadata": {"component": component, "enabled": enabled},
        "settings": {"context": {"stage": stage}, "environment": environment,
                     "account_map": {"full_account_map": ACCOUNTS if accounts is None else accounts}},
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
        self.assertEqual(rows, {"Lambda packages", "GitHub", "Deploy tags", "GitHub App", "Cost-allocation tags"})


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

    def test_placeholder_backend_service_images(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222", {"backend_service_images": {
            "api_gateway": "ghcr.io/fnx-platform/api-gateway:1.4.2",
            "platform_api": "123456789.dkr.ecr.us-east-1.amazonaws.com/platform-api:2.0.0"}})
        self.assert_one(stacks, "fnx-ue1-dev", "settings.environment.backend_service_images.api_gateway",
                        "Backend service images")

    def test_real_backend_service_images_pass(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222", {"backend_service_images": {
            "api_gateway": "ghcr.io/fnx-platform/api-gateway:1.5.0",
            "platform_api": "ghcr.io/acme/platform-api:1.4.2"}})
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


class StackNoticeTest(unittest.TestCase):
    @staticmethod
    def notices(stacks, stack_name):
        return [f for f in preflight.check(stacks) if f.level == "notice" and f.stack == stack_name]

    def test_empty_security_email_subscriptions_is_a_notice(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222", security_monitoring_main={
            "component": "security-monitoring", "security_email_subscriptions": []})
        found = self.notices(stacks, "fnx-ue1-dev")
        self.assertEqual([(f.key, f.row) for f in found],
                         [("security_monitoring_main vars.security_email_subscriptions", "Alert recipients")])
        self.assertEqual(errors(stacks), [])

    def test_security_email_subscriptions_set_or_instance_disabled_has_no_notice(self):
        stacks = clean()
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222", sm_set={
            "component": "security-monitoring", "security_email_subscriptions": ["sec@acme.io"]}, sm_off={
            "component": "security-monitoring", "enabled": False, "security_email_subscriptions": []})
        self.assertEqual(self.notices(stacks, "fnx-ue1-dev"), [])

    def test_budget_notice_names_the_amount_and_the_tag_per_stack(self):
        stacks = clean()
        stacks["fnx-ew1-prod"] = stack("prod", "555555555555", cost_main={
            "component": "cost-optimization", "monthly_budget_limit": "10000", "tags": {"Environment": "ew1"}})
        found = self.notices(stacks, "fnx-ew1-prod")
        self.assertEqual([(f.key, f.row) for f in found], [("cost_main vars.monthly_budget_limit", "Budgets")])
        self.assertIn("10000 USD a month, counting only spend tagged Environment=ew1;", found[0].detail)
        self.assertEqual(self.notices(clean(), "fnx-ue1-prod"), [])

    def test_budget_notice_names_every_counted_tag(self):
        stacks = clean()
        stacks["fnx-ew1-prod"] = stack("prod", "555555555555", cost_main={
            "component": "cost-optimization", "monthly_budget_limit": "10000", "tags": {"Environment": "ew1"},
            "budget_additional_environment_tags": ["ec1", "ew1"]})
        found = self.notices(stacks, "fnx-ew1-prod")
        self.assertIn("counting only spend tagged Environment=ew1 or ec1;", found[0].detail)


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


class CoreAccountTest(unittest.TestCase):
    """settings.account_map's Cloud Posse core accounts (Q1): real, distinct, apart from workloads."""

    @staticmethod
    def with_map(component="vpc", **changes):
        accounts = {k: v for k, v in {**ACCOUNTS, **changes}.items() if v is not None}
        return {"fnx-ue1-root": stack("root", MGMT, backend_main={"component": "backend", "accounts": accounts}),
                "fnx-ue1-dev": stack("dev", "222222222222", main={"component": component, "accounts": accounts})}

    def core_errors(self, only=None, **changes):
        return [(f.stack, f.key.rsplit(".", 1)[-1], f.detail) for f in errors(self.with_map(**changes), only)]

    def test_distinct_real_core_accounts_pass(self):
        self.assertEqual(self.core_errors(), [])

    def test_placeholder_core_accounts_fail_for_a_map_consumer(self):
        found = errors(self.with_map("guardduty", audit="123456789012", identity="000000000000"), ["fnx-ue1-dev"])
        self.assertEqual(sorted(f.key.rsplit(".", 1)[-1] for f in found), ["audit", "identity"])
        self.assertTrue(all(f.stack == "repository" and f.row == "Account IDs" for f in found))

    def test_placeholder_core_accounts_are_a_notice_for_the_backend_bootstrap(self):
        stacks = self.with_map(audit="123456789012", artifacts=None)
        self.assertEqual(errors(stacks, ["fnx-ue1-root"]), [])
        notes = [f.key for f in preflight.check(stacks, ["fnx-ue1-root"]) if f.level == "notice"
                 and "account_map" in f.key]
        self.assertEqual(sorted(k.rsplit(".", 1)[-1] for k in notes), ["artifacts", "audit"])

    def test_a_core_stage_stack_needs_the_core_accounts(self):
        stacks = self.with_map(security="123456789012")
        accounts = {**ACCOUNTS, "security": "123456789012"}
        stacks["fnx-ue1-security"] = stack("security", "777777777772", main={"accounts": accounts})
        self.assertEqual(self.core_errors(), [])
        self.assertEqual([f.key.rsplit(".", 1)[-1] for f in errors(stacks, ["fnx-ue1-security"])], ["security"])

    def test_missing_core_account_fails(self):
        self.assertEqual(self.core_errors(component="cloudtrail", artifacts=None),
                         [("repository", "artifacts", "core account missing")])

    def test_two_core_accounts_sharing_an_id_fail(self):
        found = self.core_errors(["fnx-ue1-root"], identity=MGMT)
        self.assertEqual([(s, k) for s, k, _ in found], [("repository", "identity")])
        self.assertIn("also core account root", found[0][2])

    def test_workload_account_equal_to_a_core_account_fails(self):
        found = self.core_errors(["fnx-ue1-root"], **{"prod-eu": "777777777772"})
        self.assertEqual([(s, k) for s, k, _ in found], [("repository", "prod-eu")])
        self.assertIn("also core account security", found[0][2])

    def test_stack_account_in_a_core_account_fails(self):
        stacks = self.with_map()
        stacks["fnx-ue1-staging"] = stack("staging", "777777777773", main={"accounts": ACCOUNTS})
        self.assertEqual([(f.stack, f.detail) for f in errors(stacks)],
                         [("fnx-ue1-staging", "777777777773 is core account network's")])

    def test_ids_must_be_12_digits(self):
        for typo in ("55555555555", "5555555555555"):
            with self.subTest(typo=typo):
                self.assertEqual(self.core_errors(["fnx-ue1-root"], staging=typo),
                                 [("repository", "staging", f"{typo!r} is not a 12-digit account ID")])

    def test_stacks_that_disagree_fail(self):
        stacks = self.with_map()
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222", main={"accounts": {**ACCOUNTS, "dev": "999999999999"}})
        self.assertEqual([(f.stack, f.detail) for f in errors(stacks)],
                         [("fnx-ue1-root", "differs from fnx-ue1-dev's: the account map is one map")])

    def test_no_account_map_fails(self):
        stacks = {"fnx-ue1-dev": stack("dev", "222222222222")}
        stacks["fnx-ue1-dev"]["components"]["terraform"]["vpc/main"]["settings"].pop("account_map")
        self.assertEqual([f.detail for f in errors(stacks)], ["no account map in any deployable stack"])

    def test_an_empty_map_fails(self):
        stacks = {"fnx-ue1-dev": stack("dev", "222222222222", main={"component": "guardduty", "accounts": {}})}
        self.assertEqual({f.detail for f in errors(stacks)}, {"core account missing"})

    def test_bad_core_account_fails_main_and_leads_warn(self):
        stacks = self.with_map(network="777777777771")
        accounts = {**ACCOUNTS, "network": "777777777771"}
        stacks["fnx-ue1-dev"] = stack("dev", "222222222222", vpc_main={"accounts": accounts, "emails": [
            f"ops{i}@example.com" for i in range(preflight.WARN_LIMIT + 5)]})
        for argv, rc, label in (((), 1, "ERROR"), (("--warn",), 0, "WARN")):
            out = io.StringIO()
            with self.subTest(argv=argv), mock.patch.object(sys, "argv", ["check-first-deploy-inputs.py", *argv]), \
                    mock.patch.object(sys, "stdin", io.StringIO(json.dumps(stacks))), contextlib.redirect_stdout(out):
                self.assertEqual(preflight.main(), rc)
                self.assertTrue(out.getvalue().startswith(
                    f"{label} repository: settings.account_map.full_account_map.network"), out.getvalue()[:200])


class StaticAccountMapTest(unittest.TestCase):
    """A vendored component's vars.account_map, a hand copy of settings.static_account_map."""
    STATIC = {"full_account_map": {f"fnx-{k}": v for k, v in ACCOUNTS.items()},
              "root_account_account_name": "fnx-root", "identity_account_account_name": "fnx-identity",
              "audit_account_account_name": "fnx-audit"}

    DRIFTED = {**STATIC, "audit_account_account_name": "fnx-security"}

    def stacks(self, account_map, enabled=False):
        stacks = CoreAccountTest.with_map()
        root = stacks["fnx-ue1-root"]["components"]["terraform"]
        spec = inst("root", env("root", MGMT), component="access-analyzer", enabled=enabled,
                    account_map=account_map)
        spec["settings"]["static_account_map"] = self.STATIC
        root["access-analyzer/root"] = spec
        return stacks

    @staticmethod
    def failures(stacks):
        return [f for f in preflight.check(stacks, ["fnx-ue1-root"]) if f.level in ("fatal", "error")]

    def test_an_equal_map_passes(self):
        self.assertEqual(self.failures(self.stacks(self.STATIC)), [])

    def test_a_drifted_map_is_fatal_on_a_disabled_instance(self):
        full = dict(self.STATIC["full_account_map"])
        full.popitem()
        for account_map in (self.DRIFTED, {**self.STATIC, "full_account_map": full}):
            with self.subTest(account_map=account_map):
                self.assertEqual([(f.level, f.stack, f.key, f.row) for f in self.failures(self.stacks(account_map))],
                                 [("fatal", "fnx-ue1-root", "access-analyzer/root vars.account_map", "Account IDs")])

    def run_main(self, stacks, *argv):
        out = io.StringIO()
        with mock.patch.object(sys, "argv", ["check-first-deploy-inputs.py", *argv]), \
                mock.patch.object(sys, "stdin", io.StringIO(json.dumps(stacks))), contextlib.redirect_stdout(out):
            return preflight.main(), out.getvalue()

    def with_warnings(self, account_map):
        """More than WARN_LIMIT placeholder errors besides the map under test."""
        stacks = self.stacks(account_map)
        stacks["fnx-ue1-root"]["components"]["terraform"]["backend_main"]["vars"]["emails"] = [
            f"ops{i}@example.com" for i in range(preflight.WARN_LIMIT + 5)]
        return stacks

    def test_drift_fails_warn_mode_and_is_always_printed(self):
        rc, out = self.run_main(self.with_warnings(self.DRIFTED), "--warn")
        self.assertEqual(rc, 1, out)
        self.assertTrue(out.startswith("ERROR fnx-ue1-root: access-analyzer/root vars.account_map: differs"), out[:200])
        self.assertEqual(out.count("\nWARN "), preflight.WARN_LIMIT, out)
        self.assertIn("1 configuration error(s), fatal even with --warn", out)

    def test_placeholders_alone_still_pass_warn_mode(self):
        rc, out = self.run_main(self.with_warnings(self.STATIC), "--warn")
        self.assertEqual(rc, 0, out)
        self.assertNotIn("vars.account_map", out)
        self.assertNotIn("configuration error", out)

    def test_access_analyzer_needs_the_core_accounts_when_enabled(self):
        self.assertIn("access-analyzer", preflight.MAP_CONSUMERS)
        disabled, enabled = self.stacks(self.STATIC), self.stacks(self.STATIC, enabled=True)
        self.assertFalse(preflight.needs_core_accounts(disabled["fnx-ue1-root"]))
        self.assertTrue(preflight.needs_core_accounts(enabled["fnx-ue1-root"]))


class OnlyStacksTest(unittest.TestCase):
    def test_only_limits_the_per_stack_checks(self):
        stacks = clean()
        stacks["fnx-ue1-prod"] = stack("prod", "123456789012", eks_main={"component": "eks"})
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
        self.assertIn("... 5 more WARN and 5 NOTICE line(s) not shown; see them all with --warn --all", out)
        self.assertIn(f"By row: Alert recipients {preflight.WARN_LIMIT + 5}", out)

    def test_warn_all_and_fatal_mode_show_everything(self):
        for argv, label in ((("--warn", "--all"), "WARN"), ((), "ERROR")):
            with self.subTest(argv=argv):
                _, out, _ = self.run_main(self.many_placeholder_stacks(), *argv)
                self.assertEqual(out.count(f"{label} fnx-ue1-dev"), preflight.WARN_LIMIT + 5)
                self.assertEqual(out.count("NOTICE repository"), 5)
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


class OrganizationInputsTest(unittest.TestCase):
    """fnx-gbl-root's accounts layer: OU ID placeholders and the aws-account root-user emails."""

    def gbl(self, **instances):
        stacks = clean()
        stacks["fnx-gbl-root"] = stack("root", None, **instances)
        return stacks

    @staticmethod
    def account(email, enabled=True):
        return {"component": "aws-account", "enabled": enabled, "account_email": email,
                "parent_id": "ou-abcd-12345678"}

    def test_placeholder_ou_id(self):
        stacks = self.gbl(ou_eu={"component": "aws-organizational-unit", "import_resource_id": "ou-xxxx-xxxxxxxx"})
        found = errors(stacks)
        self.assertEqual([(f.stack, f.row) for f in found], [("fnx-gbl-root", "AWS Organization ID")])
        self.assertIn("organizational unit", found[0].detail)

    def test_real_ou_id_passes(self):
        stacks = self.gbl(ou_eu={"component": "aws-organizational-unit", "import_resource_id": "ou-ab12-cd34ef56"})
        self.assertEqual(errors(stacks), [])

    def test_example_account_email_is_its_own_row(self):
        stacks = self.gbl(aws_account_dev=self.account("root+dev@example.com"))
        self.assertEqual([(f.stack, f.row) for f in errors(stacks)], [("fnx-gbl-root", "Account emails")])

    def test_distinct_real_emails_pass(self):
        stacks = self.gbl(aws_account_dev=self.account("root+dev@acme.io"),
                          aws_account_prod=self.account("root+prod@acme.io"))
        self.assertEqual(errors(stacks), [])

    def test_shared_email_fails_case_insensitively_disabled_included(self):
        stacks = self.gbl(aws_account_dev=self.account("aws+fnx@acme.io"),
                          aws_account_prod=self.account("AWS+fnx@acme.io ", enabled=False))
        found = errors(stacks)
        self.assertEqual([(f.stack, f.row) for f in found], [("repository", "Account emails")])
        self.assertIn("aws_account_dev", found[0].detail)
        self.assertIn("aws_account_prod", found[0].detail)

    def test_shared_email_found_by_the_top_level_component_alone(self):
        stacks = self.gbl(aws_account_dev=self.account("root@acme.io"),
                          aws_account_prod=self.account("root@acme.io"))
        for spec in stacks["fnx-gbl-root"]["components"]["terraform"].values():
            del spec["metadata"]["component"]
        self.assertEqual([(f.stack, f.row) for f in errors(stacks)], [("repository", "Account emails")])


class BootstrapOrderTest(unittest.TestCase):
    """Backend cold start -> accounts layer: neither may need the account IDs the accounts layer creates."""

    PLACEHOLDER_CORE = {**ACCOUNTS, "security": "123456789012", "audit": "123456789012"}

    def root(self):
        backend = {"component": "backend", "account_id": MGMT, "access_roles": {
            "write": {"allowed_principal_arns": ["arn:aws:iam::123456789012:role/fnx-ue1-dev-ci-apply"]},
            "root_write": {"allowed_principal_arns": []}}}
        return {"fnx-ue1-root": stack("root", None, backend_main=backend)}

    def test_cold_start_downgrades_access_role_principals_to_notices(self):
        findings = preflight.check(self.root(), ["fnx-ue1-root"], cold_start=True)
        self.assertEqual([f for f in findings if f.level == "error"], [])
        notice = [f for f in findings if f.level == "notice" and "allowed_principal_arns" in f.key]
        self.assertEqual(len(notice), 1, notice)
        self.assertIn("not applied by the cold start", notice[0].detail)

    def test_backend_re_apply_still_fails_on_placeholder_principals(self):
        found = errors(self.root(), ["fnx-ue1-root"])
        self.assertEqual([(f.stack, f.row) for f in found], [("fnx-ue1-root", "Account IDs")])

    def test_cold_start_keeps_other_placeholders_fatal(self):
        stacks = self.root()
        stacks["fnx-ue1-root"]["components"]["terraform"]["backend_main"]["vars"]["account_id"] = "123456789012"
        found = preflight.check(stacks, ["fnx-ue1-root"], cold_start=True)
        self.assertEqual([f.key for f in found if f.level == "error"], ["backend_main vars.account_id"])

    def test_accounts_layer_does_not_need_the_core_accounts(self):
        stacks = clean()
        stacks["fnx-gbl-root"] = stack("root", None, **{
            "aws-organization": {"component": "aws-organization", "accounts": self.PLACEHOLDER_CORE},
            "aws-account-settings": {"component": "aws-account-settings", "accounts": self.PLACEHOLDER_CORE}})
        for name in stacks:
            for spec in stacks[name]["components"]["terraform"].values():
                spec["settings"]["account_map"]["full_account_map"] = self.PLACEHOLDER_CORE
        findings = preflight.check(stacks, ["fnx-gbl-root"])
        core = [f for f in findings if "full_account_map." in f.key]
        self.assertTrue(core)
        self.assertEqual({f.level for f in core}, {"notice"})

    def test_cold_start_flag_reaches_main(self):
        out = io.StringIO()
        argv = ["check-first-deploy-inputs.py", "--stacks", "fnx-ue1-root", "--cold-start"]
        with mock.patch.object(sys, "argv", argv), mock.patch("sys.stdin", io.StringIO(json.dumps(self.root()))), \
                contextlib.redirect_stdout(out):
            self.assertEqual(preflight.main(), 0, out.getvalue())


if __name__ == "__main__":
    unittest.main()

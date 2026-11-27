"""One boolean reader for the lint scripts (ci-apply-role-arn.py flag/is_deployable/flag_errors) in every checker.

python3 -m unittest discover -s workflows/scripts/common
"""
import contextlib
import importlib.util
import io
import json
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))


def load(filename: str):
    spec = importlib.util.spec_from_file_location(filename.replace("-", "_").removesuffix(".py"), HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


backends = load("backends.py")
check_ci_state_roles = load("check-ci-state-roles.py")
check_cluster_api_ci = load("check-cluster-api-ci.py")
check_data_residency = load("check-data-residency.py")
check_deploy_layers = load("check-deploy-layers.py")
check_domains = load("check-domains.py")
check_lambda_packages = load("check-lambda-packages.py")
check_lane_names = load("check-lane-names.py")
check_state_keys = load("check-state-keys.py")
ci_components = load("ci-components.py")
ci_stacks = load("ci-stacks.py")
check_first_deploy_inputs = load("check-first-deploy-inputs.py")

CHECKERS = (check_ci_state_roles, check_cluster_api_ci, check_data_residency, check_deploy_layers,
            check_domains, check_lambda_packages, check_lane_names, check_state_keys)
OIDC = "github_oidc_provider_enabled"


def stacks_with(**instance):
    return {"s1": {"components": {"terraform": {"x": instance}}}}


def run_main(module, stacks):
    """main() of a checker on stacks (stdin; deploy-layers and cluster-api-ci also take their arguments)."""
    out = io.StringIO()
    with tempfile.TemporaryDirectory() as tmp:
        stacks_file, workflows_file = pathlib.Path(tmp, "stacks.json"), pathlib.Path(tmp, "workflows.json")
        stacks_file.write_text(json.dumps(stacks))
        workflows_file.write_text("{}")
        argv = {check_deploy_layers: ["x", str(stacks_file), str(workflows_file)],
                check_cluster_api_ci: ["x", tmp]}.get(module, ["x"])
        with mock.patch("sys.argv", argv), mock.patch("sys.stdin", io.StringIO(json.dumps(stacks))), \
                contextlib.redirect_stdout(out):
            rc = module.main()
    return rc, out.getvalue()


class GarbageIsACleanError(unittest.TestCase):
    def test_every_checker_prints_an_error_and_exits_1(self):
        for module in CHECKERS:
            for case in (stacks_with(metadata={"enabled": "maybe"}), stacks_with(vars={"enabled": "maybe"})):
                with self.subTest(module=module.__name__, case=case):
                    rc, out = run_main(module, case)
                    self.assertEqual(rc, 1)
                    self.assertIn("ERROR s1: x ", out)
                    self.assertIn("is 'maybe', not a boolean (true or false); Atmos/Terraform reads only true or false",
                                  out)

    def test_ci_components_prints_a_clean_error_and_exits_1(self):
        err = io.StringIO()
        instances = {"x": {"metadata": {"enabled": "maybe"}}}
        with mock.patch("sys.argv", ["x", "--stack", "s1"]), mock.patch.object(
                ci_components, "stack_instances", return_value=instances), contextlib.redirect_stderr(err):
            self.assertEqual(ci_components.main(), 1)
        self.assertIn("::error::s1: x metadata.enabled is 'maybe'", err.getvalue())


class OtherScriptsAreClean(unittest.TestCase):
    def test_first_deploy_inputs_prints_an_error_and_exits_1(self):
        err = io.StringIO()
        with mock.patch("sys.argv", ["x"]), mock.patch(
                "sys.stdin", io.StringIO(json.dumps(stacks_with(metadata={"enabled": "maybe"})))), \
                contextlib.redirect_stderr(err):
            self.assertEqual(check_first_deploy_inputs.main(), 1)
        self.assertIn("ERROR s1: x metadata.enabled is 'maybe'", err.getvalue())

    def test_ci_stacks_prints_an_error_and_exits_1(self):
        err = io.StringIO()
        with mock.patch("sys.argv", ["x"]), mock.patch.object(
                ci_stacks, "describe_stacks", return_value=stacks_with(metadata={"enabled": "maybe"})), \
                contextlib.redirect_stderr(err):
            self.assertEqual(ci_stacks.main(), 1)
        self.assertIn("::error::s1: x metadata.enabled is 'maybe'", err.getvalue())


class OneAnswerPerField(unittest.TestCase):
    def test_residency_rejects_yes_with_a_located_error_from_main(self):
        for key in ("accessanalyzer_organization_enabled", "admin_delegated"):
            instance = {"component": "access-analyzer", "vars": {key: "yes"}}
            with self.subTest(key=key):
                rc, out = run_main(check_data_residency, stacks_with(**instance))
                self.assertEqual(rc, 1)
                self.assertIn(f"ERROR s1: x vars.{key} is 'yes', not a boolean", out)

    def test_residency_flag_on_reads_strings_and_rejects_numbers(self):
        self.assertFalse(check_data_residency.flag_on("False"))
        self.assertTrue(check_data_residency.flag_on(" true "))
        self.assertFalse(check_data_residency.flag_on(None))
        with self.assertRaises(ValueError):
            check_data_residency.flag_on(1)

    def test_lane_names_agrees_with_flag_on_github_oidc_provider_enabled(self):
        for value in ("true", "false", True, False, None, "yes"):
            with self.subTest(value=value):
                try:
                    expected = check_lane_names.backends.ci_apply_role_arn.flag(value, "v") is True
                except ValueError:
                    with self.assertRaises(ValueError):
                        check_lane_names.residency.flag_on(value)
                    continue
                self.assertEqual(check_lane_names.residency.flag_on(value), expected)

    def test_a_nested_zone_garbage_names_its_location(self):
        instance = {"component": "dns", "vars": {"external_zones": {"corp": {"enable_query_logging": "maybe"}}}}
        rc, out = run_main(check_domains, stacks_with(**instance))
        self.assertEqual(rc, 1)
        self.assertIn("ERROR s1: x vars.external_zones.corp.enable_query_logging is 'maybe', not a boolean", out)


class StringFalseIsDisabled(unittest.TestCase):
    def test_every_is_deployable_reads_a_string(self):
        for is_deployable in (backends.is_deployable, check_data_residency.is_deployable,
                              check_lambda_packages.is_deployable, ci_components.is_deployable,
                              ci_stacks.deployable, check_first_deploy_inputs.deployable):
            with self.subTest(is_deployable=is_deployable):
                self.assertFalse(is_deployable({"metadata": {"enabled": "False"}}))
                self.assertTrue(is_deployable({"metadata": {"enabled": " TRUE "}}))
                self.assertTrue(is_deployable({}))

    def test_lane_names_reads_metadata_and_vars_enabled(self):
        self.assertFalse(check_lane_names.is_deployable({"metadata": {"enabled": "false"}}))
        self.assertFalse(check_lane_names.is_deployable({"vars": {"enabled": "false"}}))
        self.assertTrue(check_lane_names.is_deployable({"vars": {"enabled": "true"}}))

    def test_lane_names_singleton_gate_reads_a_string(self):
        for value, count in (("true", 1), ("false", 0)):
            instance = {"component": "aws-account-settings",
                        "vars": {"account_alias_enabled": value, "s3_block_public_access_enabled": "false"}}
            found = [c for c in check_lane_names.created(instance, "dev") if c[0] == "IAM account alias"]
            self.assertEqual(len(found), count, value)

    def test_domains_flag_on(self):
        self.assertFalse(check_domains.flag_on("false"))
        self.assertFalse(check_domains.flag_on(None))
        self.assertTrue(check_domains.flag_on("True"))
        with self.assertRaises(ValueError):
            check_domains.flag_on("yes")

    def test_cluster_api_is_public(self):
        self.assertFalse(check_cluster_api_ci.is_public("false"))
        self.assertFalse(check_cluster_api_ci.is_public(None))
        self.assertTrue(check_cluster_api_ci.is_public("True"))

    def test_ci_state_roles_reads_a_rendered_true(self):
        role = {"component": "aws-iam-role", "vars": {OIDC: "true"}}
        stack = {"components": {"terraform": {"aws-iam-role/ci-apply": role}}}
        self.assertEqual(list(check_ci_state_roles.ci_roles(stack)), ["apply"])
        role["vars"][OIDC] = "false"
        self.assertEqual(check_ci_state_roles.ci_roles(stack), {})

    def test_a_string_false_uploader_is_skipped(self):
        uploader = {"metadata": {"enabled": "false"}, "vars": {"enabled": "true", "trusted_github_repos": []}}
        stacks = {"s1": {"components": {"terraform": {check_lambda_packages.UPLOADER_INSTANCE: uploader}}}}
        self.assertEqual(check_lambda_packages.check(stacks), [])


class CiComponentsSelectionIsUnchanged(unittest.TestCase):
    def selected(self, enabled):
        instances = {
            "a": {"metadata": {"enabled": enabled}, "dependencies": {"components": []}},
            "b": {"metadata": {}, "dependencies": {"components": []}},
            "c": {"metadata": {"type": "abstract"}},
            "d": {"metadata": {"enabled": False}},
        }
        return ci_components.select(instances, "s1", None, "hosted", None)

    def test_bool_and_string_forms_select_the_same_set(self):
        self.assertEqual(self.selected(True), self.selected("true"))
        self.assertEqual(self.selected(True)[0], ["a", "b"])
        self.assertEqual(self.selected(False), self.selected("False"))
        self.assertEqual(self.selected(False)[0], ["b"])


if __name__ == "__main__":
    unittest.main()

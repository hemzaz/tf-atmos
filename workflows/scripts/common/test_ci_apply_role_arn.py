"""Tests for ci-apply-role-arn.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import contextlib
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import sys
import unittest
from unittest import mock

_spec = importlib.util.spec_from_file_location(
    "ci_apply_role_arn", pathlib.Path(__file__).with_name("ci-apply-role-arn.py")
)
ci_apply_role_arn = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ci_apply_role_arn)

# The vendored abstract's label (stacks/catalog/_base/vendored.yaml): tenant first.
LABEL_ORDER = ["tenant", "environment", "stage", "name", "attributes"]


def ci(account="123456789012", kind="apply", stage="prod", environment="ue1", metadata=None, **overrides):
    """`atmos describe component aws-iam-role/ci-<kind>` output, as catalog/aws-iam-role/ci.yaml renders it."""
    variables = {
        "enabled": True, "github_oidc_provider_enabled": True, "trusted_github_repos": ["hemzaz/tf-atmos:master"],
        "tenant": "fnx", "environment": environment, "stage": stage, "name": f"ci-{kind}",
        "context": {"enabled": True, "tenant": "fnx", "environment": environment, "stage": stage, "name": None,
                    "delimiter": None, "attributes": [], "label_order": LABEL_ORDER, "label_value_case": None},
    }
    variables.update(overrides)
    return {"settings": {"environment": {"account_id": account}}, "vars": variables, "metadata": metadata or {}}


class ApplyRoleArnTest(unittest.TestCase):
    def test_arn_is_the_stack_apply_role(self):
        # The name the backend's prod_write role trusts (stacks/orgs/fnx/root/us-east-1.yaml)
        self.assertEqual(
            ci_apply_role_arn.role_arn(ci()),
            "arn:aws:iam::123456789012:role/fnx-ue1-prod-ci-apply",
        )
        self.assertEqual(ci_apply_role_arn.role_arn(ci(), "apply"), ci_apply_role_arn.role_arn(ci()))

    def test_role_without_github_trust_fails(self):
        for bad in (ci(github_oidc_provider_enabled=False), ci(trusted_github_repos=[]), ci(enabled=False),
                    ci(metadata={"enabled": False})):
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, "does not create an apply role"):
                ci_apply_role_arn.role_arn(bad)

    def test_disabled_context_fails(self):
        bad = ci()
        del bad["vars"]["enabled"]
        bad["vars"]["context"]["enabled"] = False
        with self.assertRaisesRegex(ValueError, "does not create an apply role"):
            ci_apply_role_arn.role_arn(bad)

    def test_string_booleans_are_read_like_terraform(self):
        for value in ("false", "False ", " FALSE"):
            with self.subTest(vars_enabled=value), self.assertRaisesRegex(ValueError, "does not create an apply role"):
                ci_apply_role_arn.role_arn(ci(enabled=value))
            with self.subTest(metadata_enabled=value), self.assertRaisesRegex(ValueError, "does not create an apply role"):
                ci_apply_role_arn.role_arn(ci(metadata={"enabled": value}))
        context_only = ci()
        del context_only["vars"]["enabled"]
        context_only["vars"]["context"]["enabled"] = "false"
        with self.assertRaisesRegex(ValueError, "does not create an apply role"):
            ci_apply_role_arn.role_arn(context_only)
        for value in ("true", "True ", True):
            with self.subTest(enabled=value):
                self.assertEqual(ci_apply_role_arn.role_arn(ci(enabled=value, metadata={"enabled": value})),
                                 "arn:aws:iam::123456789012:role/fnx-ue1-prod-ci-apply")

    def test_an_unparseable_enabled_fails_loudly(self):
        for bad, where in ((ci(enabled="maybe"), "vars.enabled"), (ci(metadata={"enabled": "maybe"}), "metadata.enabled"),
                           (ci(enabled=1), "vars.enabled")):
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, where + r" is .* not a boolean"):
                ci_apply_role_arn.role_arn(bad)

    def test_github_oidc_provider_enabled_reads_a_rendered_string(self):
        self.assertEqual(ci_apply_role_arn.role_arn(ci(github_oidc_provider_enabled="true")),
                         "arn:aws:iam::123456789012:role/fnx-ue1-prod-ci-apply")
        with self.assertRaisesRegex(ValueError, "does not create an apply role"):
            ci_apply_role_arn.role_arn(ci(github_oidc_provider_enabled="False"))
        with self.assertRaisesRegex(ValueError, "vars.github_oidc_provider_enabled is 'yes'"):
            ci_apply_role_arn.role_arn(ci(github_oidc_provider_enabled="yes"))

    def test_flag_default_is_for_none_only(self):
        self.assertIs(ci_apply_role_arn.flag(None, "x", True), True)
        self.assertIsNone(ci_apply_role_arn.flag(None, "x"))
        self.assertIs(ci_apply_role_arn.flag("False", "x", True), False)

    def test_is_deployable_reads_a_string_enabled(self):
        for metadata, expected in (({}, True), ({"enabled": "false"}, False), ({"enabled": " True"}, True),
                                   ({"enabled": False}, False), ({"type": "abstract"}, False)):
            with self.subTest(metadata=metadata):
                self.assertIs(ci_apply_role_arn.is_deployable({"metadata": metadata}), expected)
        self.assertIs(ci_apply_role_arn.is_deployable({}), True)
        with self.assertRaisesRegex(ValueError, "metadata.enabled is 'no'"):
            ci_apply_role_arn.is_deployable({"metadata": {"enabled": "no"}})

    def test_unrendered_or_bad_values_fail(self):
        for bad in (ci(account="{{ .settings.environment.account_id }}"), ci(name="x" * 70), ci(account="")):
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, "invalid role ARN"):
                ci_apply_role_arn.role_arn(bad)

    def test_a_role_path_fails(self):
        with self.assertRaisesRegex(ValueError, "role path"):
            ci_apply_role_arn.role_arn(ci(path="/ci/"))


class RoleNameTest(unittest.TestCase):
    """The null-label id the vendored component names the role with (use_fullname)."""

    def test_var_over_context_and_label_order(self):
        role = ci()
        role["vars"]["environment"] = None  # null var: the context's field
        self.assertEqual(ci_apply_role_arn.role_name(role), "fnx-ue1-prod-ci-apply")

    def test_lane_prefix_is_the_environment(self):
        # A lane's settings.prefix (ue1-<name>) is the vendored environment: the lane form.
        self.assertEqual(ci_apply_role_arn.role_name(ci(environment="ue1-webapp", stage="fixtures")),
                         "fnx-ue1-webapp-fixtures-ci-apply")

    def test_attributes_delimiter_case_and_short_name(self):
        role = ci(attributes=["x"])
        role["vars"]["context"].update({"attributes": ["y"], "delimiter": "_", "label_value_case": "upper"})
        # null-label: the context's attributes first, then the var's
        self.assertEqual(ci_apply_role_arn.role_name(role), "FNX_UE1_PROD_CI-APPLY_Y_X")
        self.assertEqual(ci_apply_role_arn.role_name(ci(use_fullname=False)), "ci-apply")

    def test_use_fullname_defaults_true_and_reads_string_forms(self):
        for value, expected in ((None, True), (True, True), ("true", True), (False, False), ("false", False),
                                (" False ", False)):
            with self.subTest(value=value):
                self.assertIs(ci_apply_role_arn.uses_fullname(ci(use_fullname=value)), expected)
        for value in ("yes", "0", 1):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "vars.use_fullname is .* not a boolean"):
                ci_apply_role_arn.uses_fullname(ci(use_fullname=value))

    def test_null_label_default_order_without_a_context_order(self):
        role = ci()
        del role["vars"]["context"]["label_order"]
        # null-label 0.25.0's default order: namespace (unset), environment, stage, name; no tenant.
        self.assertEqual(ci_apply_role_arn.role_name(role), "ue1-prod-ci-apply")


class NullLabelParityTest(unittest.TestCase):
    """Each case is a deliberately bad input for one way the name once drifted from null-label 0.25.0."""

    def test_special_characters_are_removed_per_label(self):
        # (b) default regex_replace_chars /[^-a-zA-Z0-9]/ on each value: an underscore or dot is dropped
        self.assertEqual(ci_apply_role_arn.role_name(ci(environment="ue1_web.app", name="ci_apply")),
                         "fnx-ue1webapp-prod-ciapply")
        self.assertEqual(ci_apply_role_arn.role_name(ci(attributes=["a_b"])), "fnx-ue1-prod-ci-apply-ab")

    def test_a_label_that_cleans_to_empty_is_left_out(self):
        self.assertEqual(ci_apply_role_arn.role_name(ci(stage="__")), "fnx-ue1-ci-apply")

    def test_regex_replace_chars_var_beats_context_and_context_beats_default(self):
        role = ci(environment="ue1_x", regex_replace_chars="/[q]/")
        self.assertEqual(ci_apply_role_arn.role_name(role), "fnx-ue1_x-prod-ci-apply")
        role = ci(environment="ue1_x")
        role["vars"]["context"]["regex_replace_chars"] = "/[_]/"
        self.assertEqual(ci_apply_role_arn.role_name(role), "fnx-ue1x-prod-ci-apply")
        role["vars"]["regex_replace_chars"] = "/[^-a-zA-Z0-9_]/"  # var over context
        self.assertEqual(ci_apply_role_arn.role_name(role), "fnx-ue1_x-prod-ci-apply")

    def test_an_empty_delimiter_is_kept(self):
        # (c) delimiter: "" joins with nothing; only null falls back to "-"
        self.assertEqual(ci_apply_role_arn.role_name(ci(delimiter="")), "fnxue1prodci-apply")
        role = ci()
        role["vars"]["context"]["delimiter"] = ""
        self.assertEqual(ci_apply_role_arn.role_name(role), "fnxue1prodci-apply")
        self.assertEqual(ci_apply_role_arn.role_name(ci(delimiter=None)), "fnx-ue1-prod-ci-apply")

    def test_attributes_are_context_then_var_distinct_and_compact(self):
        # (d) null-label: compact(distinct(concat(context, var)))
        role = ci(attributes=["v1", "", "dup", "v2"])
        role["vars"]["context"]["attributes"] = ["c1", "dup", ""]
        self.assertEqual(ci_apply_role_arn.role_name(role), "fnx-ue1-prod-ci-apply-c1-dup-v1-v2")

    def test_attributes_distinct_after_cleaning_and_casing(self):
        self.assertEqual(ci_apply_role_arn.role_name(ci(attributes=["A_b", "ab", "AB"])), "fnx-ue1-prod-ci-apply-ab")

    def test_label_value_case_lowers_each_value_by_default(self):
        # null-label's default label_value_case is lower; uppercase values are lowered
        self.assertEqual(ci_apply_role_arn.role_name(ci(stage="PROD", attributes=["X"])), "fnx-ue1-prod-ci-apply-x")

    def test_label_value_case_none_title_upper_and_unknown(self):
        for case, expected in (("none", "fnx-uE1-Prod-ci-Apply"), ("title", "Fnx-Ue1-Prod-Ci-Apply"),
                               ("upper", "FNX-UE1-PROD-CI-APPLY"), ("bogus", "fnx-ue1-prod-ci-apply")):
            with self.subTest(case=case):
                self.assertEqual(ci_apply_role_arn.role_name(ci(environment="uE1", stage="Prod", name="ci-Apply",
                                                                label_value_case=case)), expected)

    def test_without_use_fullname_the_name_is_the_cleaned_cased_label(self):
        # iam-role names the role module.this.name when use_fullname is false
        self.assertEqual(ci_apply_role_arn.role_name(ci(name="CI_Apply", use_fullname=False)), "ciapply")
        role = ci(name=None, use_fullname=False)
        role["vars"]["context"]["name"] = "ctx"
        self.assertEqual(ci_apply_role_arn.role_name(role), "ctx")
        self.assertEqual(ci_apply_role_arn.role_name(ci(name=None, use_fullname=False)), "")
        for value, expected in ((0, "0"), (False, "false")):  # Terraform keeps them as strings, not ""
            self.assertEqual(ci_apply_role_arn.role_name(ci(name=value, use_fullname=False)), expected)

    def test_numeric_and_bool_attributes_are_kept_as_terraform_strings(self):
        self.assertEqual(ci_apply_role_arn.role_name(ci(attributes=[0, True, False, ""])), "fnx-ue1-prod-ci-apply-0-true-false")

    def test_empty_label_order_falls_back_to_the_default(self):
        # null-label: coalescelist(label_order, default order), which has no tenant
        self.assertEqual(ci_apply_role_arn.role_name(ci(label_order=[])), "ue1-prod-ci-apply")


class PlanRoleArnTest(unittest.TestCase):
    def test_arn_is_the_stack_accounts_plan_role(self):
        # Each stack's own account and name: staging no longer plans with dev's role.
        self.assertEqual(
            ci_apply_role_arn.role_arn(ci(account="210987654321", kind="plan", stage="staging"), "plan"),
            "arn:aws:iam::210987654321:role/fnx-ue1-staging-ci-plan",
        )

    def test_disabled_oidc_fails(self):
        with self.assertRaisesRegex(ValueError, "does not create a plan role"):
            ci_apply_role_arn.role_arn(ci(kind="plan", github_oidc_provider_enabled=False), "plan")

    def test_bad_values_fail(self):
        with self.assertRaisesRegex(ValueError, "invalid role ARN"):
            ci_apply_role_arn.role_arn(ci(account="{{ .settings.environment.account_id }}", kind="plan"), "plan")

    def test_unknown_kind_fails(self):
        with self.assertRaisesRegex(ValueError, "unknown role kind"):
            ci_apply_role_arn.role_arn(ci(), "admin")


class MainTest(unittest.TestCase):
    def run_main(self, check_output, *argv):
        out = io.StringIO()
        with mock.patch.dict(os.environ, {"STACK": "fnx-ue1-root"}, clear=False), \
                mock.patch.object(sys, "argv", ["ci-apply-role-arn.py", *argv]), \
                mock.patch.object(ci_apply_role_arn.subprocess, "check_output", check_output), \
                contextlib.redirect_stdout(out):
            os.environ.pop("GITHUB_OUTPUT", None)
            return ci_apply_role_arn.main(), out.getvalue()

    def test_stack_without_the_ci_role_fails_with_an_annotation(self):
        def describe_fails(cmd):
            raise subprocess.CalledProcessError(1, cmd)

        for argv, instance in (((), "aws-iam-role/ci-apply"), (("--kind", "plan"), "aws-iam-role/ci-plan")):
            with self.subTest(argv=argv):
                rc, out = self.run_main(describe_fails, *argv)
                self.assertEqual(rc, 1)
                self.assertEqual(out, f"::error::fnx-ue1-root: no {instance} instance (atmos describe failed)\n")

    def test_resolved_role_is_printed(self):
        seen = []

        def describe(cmd):
            seen.append(cmd[3])
            return json.dumps(ci(kind="plan"))

        rc, out = self.run_main(describe, "--kind", "plan")
        self.assertEqual(rc, 0)
        self.assertEqual(seen, ["aws-iam-role/ci-plan"])
        self.assertEqual(out, "fnx-ue1-root: arn:aws:iam::123456789012:role/fnx-ue1-prod-ci-plan\n")


if __name__ == "__main__":
    unittest.main()

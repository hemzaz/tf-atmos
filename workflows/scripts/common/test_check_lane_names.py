"""Tests for check-lane-names.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""

import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_lane_names", pathlib.Path(__file__).with_name("check-lane-names.py")
)
check_lane_names = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_lane_names)


def instance(tag, name=None, component="kms", stage="dev", **variables):
    """An instance whose tags.Environment is tag, in fnx-ue1-<stage>[-<name>]."""
    ctx = {"tenant": "fnx", "environment": "ue1", "stage": stage, **({"name": name} if name else {})}
    return {"component": component, "settings": {"context": ctx}, "vars": {"tags": {"Environment": tag}, **variables}}


def stack(**instances):
    return {"components": {"terraform": instances}}


class CheckLaneNamesTest(unittest.TestCase):
    def errors(self, stacks):
        return check_lane_names.check(stacks)

    def test_prefixed_lane_passes(self):
        self.assertEqual(self.errors({
            "fnx-ue1-dev": stack(**{"kms/main": instance("ue1", alias_name="ue1-main", name_prefix="fnx-ue1-dev")}),
            "fnx-ue1-dev-perf": stack(**{"kms/main": instance(
                "ue1-perf", "perf", alias_name="ue1-perf-main", name_prefix="fnx-ue1-dev-perf")}),
        }), [])

    def test_shared_environment_tag_fails(self):
        errors = self.errors({
            "fnx-ue1-dev": stack(**{"kms/main": instance("ue1")}),
            "fnx-ue1-dev-perf": stack(**{"kms/main": instance("ue1", "perf")}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("both use tags.Environment 'ue1' in fnx-ue1-dev", errors[0])

    def test_shared_built_name_fails(self):
        errors = self.errors({
            "fnx-ue1-dev": stack(**{"kms/main": instance("ue1", alias_name="ue1-main")}),
            "fnx-ue1-dev-perf": stack(**{"kms/main": instance("ue1-perf", "perf", alias_name="ue1-main")}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("kms/main vars.alias_name and fnx-ue1-dev: kms/main vars.alias_name both use name 'ue1-main'",
                      errors[0])

    def test_shared_full_id_name_fails(self):
        errors = self.errors({
            "fnx-ue1-dev": stack(**{"iam/ci": instance("ue1", ci_role_name_prefix="fnx-ue1-dev-ci")}),
            "fnx-ue1-dev-perf": stack(**{"iam/ci": instance("ue1-perf", "perf", ci_role_name_prefix="fnx-ue1-dev-ci")}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("name 'fnx-ue1-dev-ci'", errors[0])

    def test_shared_secret_name_fails(self):
        secrets = {"db": {"name": "credentials", "path": "/database/"}}
        errors = self.errors({
            "fnx-ue1-dev": stack(**{"secretsmanager/app": instance(
                "ue1", component="secretsmanager", context_name="app", environment="dev", secrets=secrets)}),
            "fnx-ue1-dev-perf": stack(**{"secretsmanager/app": instance(
                "ue1-perf", "perf", component="secretsmanager", context_name="app", environment="dev", secrets=secrets)}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("secret 'app/dev/database/credentials'", errors[0])

    def test_other_stage_or_region_is_another_account(self):
        self.assertEqual(self.errors({
            "fnx-ue1-dev": stack(**{"kms/main": instance("ue1", alias_name="ue1-main")}),
            "fnx-ue1-staging": stack(**{"kms/main": instance("ue1", stage="staging", alias_name="ue1-main")}),
        }), [])

    def test_unprefixed_values_and_descriptions_are_not_names(self):
        self.assertEqual(self.errors({
            "fnx-ue1-dev": stack(**{"x/main": instance("ue1", component="x", region="us-east-1", description="ue1-x y")}),
            "fnx-ue1-dev-perf": stack(**{"x/main": instance(
                "ue1-perf", "perf", component="x", region="us-east-1", description="ue1-x y")}),
        }), [])

    def test_global_name_shared_across_accounts_fails(self):
        # S3 bucket names are global: another stage's account does not help.
        errors = self.errors({
            "fnx-ue1-dev-perf": stack(**{"s3/assets": instance("ue1-perf", "perf", component="s3",
                                                               bucket_name="fnx-assets")}),
            "fnx-ue1-prod": stack(**{"s3/assets": instance("ue1", stage="prod", component="s3",
                                                           bucket_name="fnx-assets")}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("both use the global name 'fnx-assets'", errors[0])

    def test_nested_global_name_and_cognito_domain(self):
        errors = self.errors({
            "fnx-ue1-dev": stack(**{"cognito/main": instance("ue1", component="cognito", domain_prefix="fnx-api"),
                                    "x/main": instance("ue1", component="x", logs={"bucket_name": "fnx-logs"})}),
            "fnx-ue2-dev": stack(**{"cognito/main": instance("ue2", component="cognito", domain_prefix="fnx-api"),
                                    "x/main": instance("ue2", component="x", logs={"bucket_name": "fnx-logs"})}),
        })
        self.assertEqual(len(errors), 2, errors)

    def test_full_id_global_names_pass(self):
        self.assertEqual(self.errors({
            "fnx-ue1-dev": stack(**{"s3/assets": instance("ue1", component="s3", bucket_name="fnx-ue1-dev-assets")}),
            "fnx-ue1-dev-perf": stack(**{"s3/assets": instance("ue1-perf", "perf", component="s3",
                                                               bucket_name="fnx-ue1-dev-perf-assets")}),
        }), [])

    def test_abstract_and_disabled_instances_are_skipped(self):
        abstract = instance("ue1")
        abstract["metadata"] = {"type": "abstract"}
        disabled = instance("ue1")
        disabled["metadata"] = {"enabled": False}
        self.assertEqual(self.errors({
            "fnx-ue1-dev": stack(**{"kms/main": instance("ue1")}),
            "fnx-ue1-dev-perf": stack(**{"kms/defaults": abstract, "kms/off": disabled}),
        }), [])


if __name__ == "__main__":
    unittest.main()

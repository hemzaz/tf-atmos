"""Tests for check-lane-names.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""

import importlib.util
import json
import os
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_lane_names", pathlib.Path(__file__).with_name("check-lane-names.py")
)
check_lane_names = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_lane_names)


def instance(tag, lane=None, component="kms", stage="dev", account=None, region="us-east-1", **variables):
    """An instance whose tags.Environment is tag, in fnx-ue1-<stage>[-<lane>], in account <stage>."""
    ctx = {"tenant": "fnx", "environment": "ue1", "stage": stage, **({"name": lane} if lane else {})}
    return {
        "component": component,
        "settings": {"context": ctx, "environment": {"account": account or stage}},
        "vars": {"region": region, "tags": {"Environment": tag}, **variables},
    }


def stack(**instances):
    return {"components": {"terraform": instances}}


class GroupTest(unittest.TestCase):
    def errors(self, stacks):
        return check_lane_names.check(stacks)

    def test_prefixed_lane_passes(self):
        self.assertEqual(self.errors({
            "fnx-ue1-dev": stack(**{"kms/main": instance("ue1", alias_name="ue1-main", name_prefix="fnx-ue1-dev")}),
            "fnx-ue1-dev-perf": stack(**{"kms/main": instance(
                "ue1-perf", "perf", alias_name="ue1-perf-main", name_prefix="fnx-ue1-dev-perf")}),
        }), [])

    def test_shared_environment_tag_fails_once_per_stack(self):
        errors = self.errors({
            "fnx-ue1-dev": stack(**{"kms/main": instance("ue1"), "x/main": instance("ue1", component="x")}),
            "fnx-ue1-dev-perf": stack(**{"kms/main": instance("ue1", "perf"), "x/main": instance("ue1", "perf", component="x")}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("both use tags.Environment 'ue1' in account dev, us-east-1", errors[0])

    def test_raw_name_fails_whatever_its_prefix(self):
        # ecs uses cluster_name verbatim: "main-apps" twice is one ECS cluster name.
        errors = self.errors({
            "fnx-ue1-dev": stack(**{"ecs/main": instance("ue1", component="ecs", cluster_name="main-apps")}),
            "fnx-ue1-dev-perf": stack(**{"ecs/main": instance("ue1-perf", "perf", component="ecs", cluster_name="main-apps")}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("both create the ECS cluster 'main-apps' in account dev, us-east-1", errors[0])

    def test_shared_kms_alias_fails(self):
        errors = self.errors({
            "fnx-ue1-dev": stack(**{"kms/main": instance("ue1", alias_name="ue1-main")}),
            "fnx-ue1-dev-perf": stack(**{"kms/main": instance("ue1-perf", "perf", alias_name="ue1-main")}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("both create the KMS alias 'ue1-main'", errors[0])

    def test_reference_to_the_stage_resource_passes(self):
        # A lane's eks-addons naming dev's cluster reads it; it creates nothing.
        self.assertEqual(self.errors({
            "fnx-ue1-dev": stack(**{"eks-addons/main": instance("ue1", component="eks-addons", cluster_name="ue1-main")}),
            "fnx-ue1-dev-perf": stack(**{"eks-addons/main": instance(
                "ue1-perf", "perf", component="eks-addons", cluster_name="ue1-main")}),
        }), [])

    def test_gated_name_counts_only_when_created(self):
        # iam/ci sets policy_name from the catalog but creates no cross-account policy.
        self.assertEqual(self.errors({"fnx-ue1-dev": stack(**{
            "iam/dev": instance("ue1", component="iam", policy_name="fnx-ue1-dev-CrossAccountPolicy"),
            "iam/ci": instance("ue1", component="iam", policy_name="fnx-ue1-dev-CrossAccountPolicy",
                               create_cross_account_role=False, ci_role_name_prefix="fnx-ue1-dev-ci"),
        })}), [])
        errors = self.errors({"fnx-ue1-dev": stack(**{
            "iam/dev": instance("ue1", component="iam", policy_name="fnx-ue1-dev-CrossAccountPolicy"),
            "iam/other": instance("ue1", component="iam", policy_name="fnx-ue1-dev-CrossAccountPolicy",
                                  resource_name_prefix="other"),
        })})
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("both create the IAM policy 'fnx-ue1-dev-CrossAccountPolicy'", errors[0])

    def test_two_account_singletons_fail(self):
        errors = self.errors({
            "fnx-ue1-dev": stack(**{"iam/ci": instance("ue1", component="iam", github_oidc_create_provider=True,
                                                       create_cross_account_role=False)}),
            "fnx-ue1-dev-perf": stack(**{"iam/ci": instance("ue1-perf", "perf", component="iam",
                                                            github_oidc_create_provider=True,
                                                            create_cross_account_role=False)}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("both create the GitHub OIDC provider", errors[0])

    def test_fixture_singletons_are_exempt(self):
        self.assertEqual(self.errors({
            f"fnx-ue1-fixtures-{n}": stack(**{"iam/fixtures": instance(
                f"ue1-{n}", n, component="iam", stage="fixtures", enable_autoscaling_service_linked_role=True,
                create_cross_account_role=False)})
            for n in ("a", "b")
        }), [])

    def test_shared_secret_name_fails(self):
        secrets = {"db": {"name": "credentials", "path": "/database/"}}
        errors = self.errors({
            "fnx-ue1-dev": stack(**{"secretsmanager/app": instance(
                "ue1", component="secretsmanager", context_name="app", environment="dev", secrets=secrets)}),
            "fnx-ue1-dev-perf": stack(**{"secretsmanager/app": instance(
                "ue1-perf", "perf", component="secretsmanager", context_name="app", environment="dev", secrets=secrets)}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("both create the secret 'app/dev/database/credentials'", errors[0])

    def test_another_account_or_region_is_another_group(self):
        self.assertEqual(self.errors({
            "fnx-ue1-dev": stack(**{"kms/main": instance("ue1", alias_name="ue1-main")}),
            "fnx-ue1-staging": stack(**{"kms/main": instance("ue1", stage="staging", alias_name="ue1-main")}),
            "fnx-ue2-dev": stack(**{"kms/main": instance("ue1", region="us-east-2", alias_name="ue1-main")}),
        }), [])

    def test_dr_region_with_its_own_iam_names_passes(self):
        # fnx-ue1-prod and its DR stack fnx-ue2-prod share the prod account.
        self.assertEqual(self.errors({
            "fnx-ue1-prod": stack(**{"iam/ci": instance(
                "ue1", component="iam", stage="prod", ci_role_name_prefix="fnx-ue1-prod-ci",
                github_oidc_enabled=True, github_oidc_create_provider=True, create_cross_account_role=False)}),
            "fnx-ue2-prod": stack(**{"iam/ci": instance(
                "ue2", component="iam", stage="prod", region="us-east-2", ci_role_name_prefix="fnx-ue2-prod-ci",
                github_oidc_enabled=True, github_oidc_create_provider=False, create_cross_account_role=False)}),
        }), [])

    def test_dr_region_creating_the_account_singleton_again_fails(self):
        errors = self.errors({
            "fnx-ue1-prod": stack(**{"iam/ci": instance(
                "ue1", component="iam", stage="prod", github_oidc_create_provider=True, create_cross_account_role=False)}),
            "fnx-ue2-prod": stack(**{"iam/ci": instance(
                "ue2", component="iam", stage="prod", region="us-east-2", github_oidc_create_provider=True,
                create_cross_account_role=False)}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("both create the GitHub OIDC provider '(one per account)' in account prod", errors[0])

    def test_dr_region_reusing_an_iam_name_fails(self):
        errors = self.errors({
            "fnx-ue1-prod": stack(**{"iam/ci": instance(
                "ue1", component="iam", stage="prod", github_oidc_enabled=True, ci_role_name_prefix="shared-ci",
                create_cross_account_role=False)}),
            "fnx-ue2-prod": stack(**{"iam/ci": instance(
                "ue2", component="iam", stage="prod", region="us-east-2", github_oidc_enabled=True,
                ci_role_name_prefix="shared-ci", create_cross_account_role=False)}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("IAM CI role prefix 'shared-ci' in account prod", errors[0])

    def test_regional_names_in_another_region_of_the_account_pass(self):
        # A KMS alias is regional: the same alias in us-east-2 is another alias.
        self.assertEqual(self.errors({
            "fnx-ue1-prod": stack(**{"kms/main": instance("ue1", stage="prod", alias_name="main")}),
            "fnx-ue2-prod": stack(**{"kms/main": instance("ue2", stage="prod", region="us-east-2", alias_name="main")}),
        }), [])

    def test_stages_sharing_an_account_are_one_group(self):
        errors = self.errors({
            "fnx-ue1-dev": stack(**{"kms/main": instance("ue1", account="shared", alias_name="ue1-main")}),
            "fnx-ue1-qa": stack(**{"kms/main": instance("ue1-qa", stage="qa", account="shared", alias_name="ue1-main")}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("in account shared, us-east-1", errors[0])

    def test_stack_without_account_or_region_fails(self):
        no_account = instance("ue1-perf", "perf")
        no_account["settings"]["environment"] = {}
        no_region = instance("ue1-qa", stage="qa")
        del no_region["vars"]["region"]
        abstract_only = instance("ue1-x")
        abstract_only["metadata"] = {"type": "abstract"}
        del abstract_only["vars"]["region"]
        errors = self.errors({
            "fnx-ue1-dev": stack(**{"kms/main": instance("ue1")}),
            "fnx-ue1-dev-perf": stack(**{"kms/main": no_account}),
            "fnx-ue1-qa": stack(**{"kms/main": no_region}),
            "fnx-ue1-x": stack(**{"kms/defaults": abstract_only}),
        })
        self.assertEqual(len(errors), 2, errors)
        self.assertIn("fnx-ue1-dev-perf: no deployable instance sets both settings.environment.account and "
                      "vars.region", errors[0])
        self.assertIn("fnx-ue1-qa: no deployable instance", errors[1])

    def test_dr_region_sharing_an_iam_environment_fails(self):
        # backup builds <Environment>-backup-service-role: one IAM role in the account.
        errors = self.errors({
            "fnx-ue1-prod": stack(**{"backup/main": instance("ue1", component="backup", stage="prod")}),
            "fnx-ue2-prod": stack(**{"backup/main": instance(
                "ue1", component="backup", stage="prod", region="us-east-2")}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("fnx-ue2-prod: backup/main (us-east-2) and fnx-ue1-prod: backup/main (us-east-1) both use "
                      "tags.Environment 'ue1' in account prod", errors[0])
        self.assertEqual(self.errors({
            "fnx-ue1-prod": stack(**{"backup/main": instance("ue1", component="backup", stage="prod")}),
            "fnx-ue2-prod": stack(**{"backup/main": instance(
                "ue2", component="backup", stage="prod", region="us-east-2")}),
        }), [])

    def test_abstract_and_disabled_instances_are_skipped(self):
        abstract = instance("ue1")
        abstract["metadata"] = {"type": "abstract"}
        disabled = instance("ue1")
        disabled["metadata"] = {"enabled": False}
        off = instance("ue1", enabled=False)
        self.assertEqual(self.errors({
            "fnx-ue1-dev": stack(**{"kms/main": instance("ue1")}),
            "fnx-ue1-dev-perf": stack(**{"kms/defaults": abstract, "kms/off": disabled, "kms/x": off}),
        }), [])


class InstanceTest(unittest.TestCase):
    def errors(self, stacks):
        return check_lane_names.check(stacks)

    def test_instances_with_the_same_name_inputs_fail(self):
        # vpc/main and vpc/services both naming their flow-logs role
        # <Environment>-vpc-flow-logs-role.
        errors = self.errors({"fnx-ue1-prod": stack(**{
            "vpc/main": instance("ue1", component="vpc", stage="prod"),
            "vpc/services": instance("ue1", component="vpc", stage="prod"),
        })})
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("fnx-ue1-prod: vpc/main, vpc/services (vpc) set the same name inputs (none)", errors[0])

    def test_instances_with_their_own_names_pass(self):
        self.assertEqual(self.errors({"fnx-ue1-prod": stack(**{
            "vpc/main": instance("ue1", component="vpc", stage="prod", name="main"),
            "vpc/services": instance("ue1", component="vpc", stage="prod", name="services"),
            "acm/main": instance("ue1", component="acm", stage="prod", dns_domains=["a.example.com"]),
            "acm/services": instance("ue1", component="acm", stage="prod", dns_domains=["b.example.com"]),
        })}), [])

    def test_same_name_with_other_differences_fails(self):
        # availability_zones differs, but both build <Environment>-vpc-main-flow-logs-role.
        errors = self.errors({"fnx-ue1-prod": stack(**{
            "vpc/main": instance("ue1", component="vpc", stage="prod", name="main",
                                 availability_zones=["us-east-1a"]),
            "vpc/other": instance("ue1", component="vpc", stage="prod", name="main",
                                  availability_zones=["us-east-1b"]),
        })})
        self.assertEqual(len(errors), 1, errors)
        self.assertIn('fnx-ue1-prod: vpc/main, vpc/other (vpc) set the same name "main"', errors[0])

    def test_same_identifier_with_another_db_name_fails(self):
        errors = self.errors({"fnx-ue1-prod": stack(**{
            "rds/main": instance("ue1", component="rds", stage="prod", identifier="orders", db_name="orders"),
            "rds/data": instance("ue1", component="rds", stage="prod", identifier="orders", db_name="reports"),
        })})
        self.assertEqual(len(errors), 1, errors)
        self.assertIn('rds/data, rds/main (rds) set the same identifier "orders"', errors[0])

    def test_instances_without_primary_keys_compare_all_name_inputs(self):
        # iam/ci and iam/dev share policy_name but differ in ci_role_name_prefix.
        self.assertEqual(self.errors({"fnx-ue1-dev": stack(**{
            "iam/ci": instance("ue1", component="iam", policy_name="p", ci_role_name_prefix="fnx-ue1-dev-ci",
                               create_cross_account_role=False),
            "iam/dev": instance("ue1", component="iam", policy_name="p"),
        })}), [])


class RealStacksTest(unittest.TestCase):
    """No false positives on the repository's stacks: the lint step check-lane-names sets
    $LANE_NAMES_STACKS_JSON to its `atmos describe stacks` JSON."""

    def test_real_stacks_pass(self):
        path = os.environ.get("LANE_NAMES_STACKS_JSON")
        if not path:
            self.skipTest("set LANE_NAMES_STACKS_JSON to an `atmos describe stacks` JSON file")
        with open(path, encoding="utf-8") as handle:
            self.assertEqual(check_lane_names.check(json.load(handle)), [])


class GlobalTest(unittest.TestCase):
    def errors(self, stacks):
        return check_lane_names.check(stacks)

    def test_global_name_shared_across_accounts_fails(self):
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
            "fnx-ue2-dev": stack(**{"cognito/main": instance("ue2", component="cognito", region="us-east-2",
                                                             domain_prefix="fnx-api"),
                                    "x/main": instance("ue2", component="x", region="us-east-2",
                                                       logs={"bucket_name": "fnx-logs"})}),
        })
        self.assertEqual(len(errors), 2, errors)

    def test_full_id_global_names_pass(self):
        self.assertEqual(self.errors({
            "fnx-ue1-dev": stack(**{"s3/assets": instance("ue1", component="s3", bucket_name="fnx-ue1-dev-assets")}),
            "fnx-ue1-dev-perf": stack(**{"s3/assets": instance("ue1-perf", "perf", component="s3",
                                                               bucket_name="fnx-ue1-dev-perf-assets")}),
        }), [])


if __name__ == "__main__":
    unittest.main()

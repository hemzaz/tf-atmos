"""Tests for check-lane-names.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""

import importlib.util
import json
import os
import pathlib
import re
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

    def test_second_region_without_trail_and_with_regional_config_passes(self):
        # A second nonprod stack of an account (scaffold account_singletons=no): the home stack's
        # multi-region trail records its region, and its recorder skips global types.
        self.assertEqual(self.errors({
            "fnx-ue1-dev": stack(**{
                "cloudtrail": instance("ue1", component="aws-cloudtrail"),
                "aws-config": instance("ue1", component="aws-config", global_resource_collector_region="us-east-1"),
            }),
            "fnx-uw2-dev": stack(**{
                "aws-config": instance("uw2", component="aws-config", region="us-west-2",
                                       global_resource_collector_region="us-east-1"),
            }),
        }), [])

    def test_second_region_multi_region_trail_and_global_config_fail(self):
        errors = self.errors({
            "fnx-ue1-dev": stack(**{
                "cloudtrail": instance("ue1", component="aws-cloudtrail"),
                "aws-config": instance("ue1", component="aws-config", global_resource_collector_region="us-east-1"),
            }),
            "fnx-uw2-dev": stack(**{
                "cloudtrail": instance("uw2", component="aws-cloudtrail", region="us-west-2"),
                "aws-config": instance("uw2", component="aws-config", region="us-west-2",
                                       global_resource_collector_region="us-west-2"),
            }),
        })
        self.assertEqual(len(errors), 3, errors)
        self.assertIn("both create the AWS Config global-resource recording '(one per account)' in account dev",
                      errors[0])
        self.assertIn("both create the CloudTrail global-service-event recording '(one per account)' in account dev",
                      errors[2])
        self.assertIn("both create the multi-region CloudTrail trail '(one per account)' in account dev", errors[1])

    def test_second_region_trail_recording_global_service_events_fails(self):
        # A regional trail that still records IAM/STS events duplicates the account trail's.
        errors = self.errors({
            "fnx-ue1-dev": stack(**{"cloudtrail": instance("ue1", component="aws-cloudtrail")}),
            "fnx-uw2-dev": stack(**{"cloudtrail": instance(
                "uw2", component="aws-cloudtrail", region="us-west-2", is_multi_region_trail=False)}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("both create the CloudTrail global-service-event recording '(one per account)' in account dev",
                      errors[0])

    def test_vendored_trail_and_config_one_per_account_pass(self):
        # One multi-region trail in the home stack; every region records, globals only in the collector region.
        self.assertEqual(self.errors({
            "fnx-ue1-prod": stack(**{
                "cloudtrail": instance("ue1", component="aws-cloudtrail", stage="prod"),
                "aws-config": instance("ue1", component="aws-config", stage="prod",
                                       global_resource_collector_region="us-east-1"),
            }),
            "fnx-ue2-prod": stack(**{"aws-config": instance(
                "ue2", component="aws-config", stage="prod", region="us-east-2",
                global_resource_collector_region="us-east-1")}),
        }), [])

    def test_second_vendored_trail_in_an_account_fails_through_its_defaults(self):
        # Neither instance sets is_multi_region_trail or include_global_service_events: CP defaults both true.
        errors = self.errors({
            "fnx-ue1-prod": stack(**{"cloudtrail": instance("ue1", component="aws-cloudtrail", stage="prod")}),
            "fnx-ue2-prod": stack(**{"cloudtrail": instance(
                "ue2", component="aws-cloudtrail", stage="prod", region="us-east-2")}),
        })
        self.assertEqual(len(errors), 2, errors)
        self.assertIn("fnx-ue2-prod: cloudtrail vars.is_multi_region_trail (us-east-2) and fnx-ue1-prod: cloudtrail "
                      "vars.is_multi_region_trail (us-east-1) both create the multi-region CloudTrail trail", errors[0])
        self.assertIn("both create the CloudTrail global-service-event recording '(one per account)' in account prod",
                      errors[1])

    def test_regional_vendored_trail_in_a_second_region_passes(self):
        self.assertEqual(self.errors({
            "fnx-ue1-dev": stack(**{"cloudtrail": instance("ue1", component="aws-cloudtrail")}),
            "fnx-uw2-dev": stack(**{"cloudtrail": instance(
                "uw2", component="aws-cloudtrail", region="us-west-2", is_multi_region_trail=False,
                include_global_service_events=False)}),
        }), [])

    def test_two_config_collectors_in_an_account_fail(self):
        # The standby names its own region (and the third leaves it unset): three global-resource collectors.
        errors = self.errors({
            "fnx-ue1-prod": stack(**{"aws-config": instance(
                "ue1", component="aws-config", stage="prod", global_resource_collector_region="us-east-1")}),
            "fnx-ue2-prod": stack(**{"aws-config": instance(
                "ue2", component="aws-config", stage="prod", region="us-east-2",
                global_resource_collector_region="us-east-2")}),
            "fnx-uw2-prod": stack(**{"aws-config": instance(
                "uw2", component="aws-config", stage="prod", region="us-west-2")}),
        })
        self.assertEqual(len(errors), 2, errors)
        self.assertIn("fnx-ue2-prod: aws-config vars.global_resource_collector_region (us-east-2) and fnx-ue1-prod: "
                      "aws-config vars.global_resource_collector_region (us-east-1) both create the AWS Config "
                      "global-resource recording '(one per account)' in account prod", errors[0])
        self.assertIn("fnx-uw2-prod: aws-config", errors[1])

    def test_account_settings_in_a_second_region_without_its_account_wide_settings_passes(self):
        # fnx-ue2-prod imports catalog/aws-account-settings/main-standby.
        self.assertEqual(self.errors({
            "fnx-ue1-prod": stack(**{"aws-account-settings": instance(
                "ue1", component="aws-account-settings", stage="prod")}),
            "fnx-ue2-prod": stack(**{"aws-account-settings": instance(
                "ue2", component="aws-account-settings", stage="prod", region="us-east-2",
                account_alias_enabled=False, s3_block_public_access_enabled=False)}),
        }), [])

    def test_account_settings_alias_and_s3_block_in_two_regions_fail(self):
        errors = self.errors({
            "fnx-ue1-prod": stack(**{"aws-account-settings": instance(
                "ue1", component="aws-account-settings", stage="prod")}),
            "fnx-ue2-prod": stack(**{"aws-account-settings": instance(
                "ue2", component="aws-account-settings", stage="prod", region="us-east-2",
                account_alias_enabled=True)}),
        })
        self.assertEqual(len(errors), 2, errors)
        self.assertIn("both create the IAM account alias '(one per account)' in account prod", errors[0])
        self.assertIn("both create the S3 account public access block '(one per account)' in account prod",
                      errors[1])

    def test_trusted_oidc_provider_with_a_creator_passes(self):
        arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
        self.assertEqual(self.errors({
            "fnx-ue1-dev": stack(**{"iam/ci": instance(
                "ue1", component="iam", github_oidc_create_provider=True, create_cross_account_role=False)}),
            "fnx-uw2-dev": stack(**{"iam/ci": instance(
                "uw2", component="iam", region="us-west-2", github_oidc_create_provider=False,
                github_oidc_provider_arn=arn, create_cross_account_role=False)}),
        }), [])

    def test_trusted_oidc_provider_without_a_creator_fails(self):
        # The account's creating stack was deleted: the second stack trusts a provider nobody creates.
        arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
        errors = self.errors({
            "fnx-ue1-dev": stack(**{"iam/dev": instance("ue1", component="iam", create_cross_account_role=False)}),
            "fnx-uw2-dev": stack(**{"iam/ci": instance(
                "uw2", component="iam", region="us-west-2", github_oidc_create_provider=False,
                github_oidc_provider_arn=arn, create_cross_account_role=False)}),
            # Another account's creator does not satisfy account dev.
            "fnx-ue1-prod": stack(**{"iam/ci": instance(
                "ue1", component="iam", stage="prod", github_oidc_create_provider=True,
                create_cross_account_role=False)}),
            "fnx-ue1-fixtures-a": stack(**{"iam/ci": instance(
                "ue1-a", "a", component="iam", stage="fixtures", account="dev", github_oidc_create_provider=True,
                create_cross_account_role=False)}),
        })
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("fnx-uw2-dev: iam/ci trusts the account's GitHub OIDC provider", errors[0])
        self.assertIn("no stack of account dev creates it", errors[0])

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

    def test_account_wide_component_in_two_regions_fails(self):
        # s3 builds <Environment>-<name>-<account id>, alb <Environment>-<name>-access-logs-<account id>:
        # global bucket names without a region.
        for component in ("s3", "alb"):
            errors = self.errors({
                "fnx-ue1-prod": stack(**{f"{component}/main": instance("ue1", component=component, stage="prod")}),
                "fnx-ue2-prod": stack(**{f"{component}/main": instance(
                    "ue1", component=component, stage="prod", region="us-east-2")}),
            })
            self.assertEqual(len(errors), 1, (component, errors))
            self.assertIn("both use tags.Environment 'ue1' in account prod", errors[0])
            self.assertIn("IAM/S3 names", errors[0])


class ComponentSetTest(unittest.TestCase):
    """ACCOUNT_WIDE_COMPONENTS is hand-kept: it must cover every component that creates IAM
    roles/policies or an Environment-named S3 bucket."""

    ROOT = pathlib.Path(__file__).resolve().parents[3] / "components" / "terraform"
    # iam: names are RAW_NAMES; backend: names built from its bucket name; apigateway-account: role name carries the region;
    # aws-cloudtrail: vendored, names its role from the null-label id (vars.context, region code included), not tags.Environment.
    EXCLUDED = {"iam", "backend", "apigateway-account", "aws-cloudtrail"}

    def scan(self, pattern):
        regex = re.compile(pattern)
        return {
            path.parent.name
            for path in self.ROOT.glob("*/*.tf")
            if regex.search(path.read_text())
        }

    def test_iam_creating_components_are_covered(self):
        found = self.scan(r'resource\s+"aws_iam_(role|policy|instance_profile|user)"') - self.EXCLUDED
        self.assertEqual(found - check_lane_names.ACCOUNT_WIDE_COMPONENTS, set())

    def test_bucket_creating_components_are_covered(self):
        # Every component creating a bucket (aws_s3_bucket) is either covered or builds its name elsewhere (backend).
        found = self.scan(r'resource\s+"aws_s3_bucket"') - self.EXCLUDED
        self.assertEqual(found - check_lane_names.ACCOUNT_WIDE_COMPONENTS, set())


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

    def test_cluster_name_that_names_the_attached_cluster_is_not_primary(self):
        self.assertEqual(self.errors({"fnx-ue1-prod": stack(**{
            "alb-controller-ingress-group/a": instance("ue1", component="alb-controller-ingress-group", stage="prod",
                                                       cluster_name="main", group_name="a"),
            "alb-controller-ingress-group/b": instance("ue1", component="alb-controller-ingress-group", stage="prod",
                                                       cluster_name="main", group_name="b"),
        })}), [])

    def test_default_lambda_alias_is_not_primary(self):
        self.assertEqual(self.errors({"fnx-ue1-prod": stack(**{
            "lambda/a": instance("ue1", component="lambda", stage="prod", function_name="a", alias_name="live"),
            "lambda/b": instance("ue1", component="lambda", stage="prod", function_name="b", alias_name="live"),
        })}), [])

    def test_empty_primary_values_do_not_match(self):
        self.assertEqual(self.errors({"fnx-ue1-prod": stack(**{
            "rds/a": instance("ue1", component="rds", stage="prod", identifier="", db_name="a"),
            "rds/b": instance("ue1", component="rds", stage="prod", identifier="", db_name="b"),
        })}), [])


class RealStacksTest(unittest.TestCase):
    """No false positives on the repository's stacks: validate-all's check-dependencies step sets
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


# The E5c4-E5c6 simulation (security + root stacks of 4 regions) from the residency test, the one copy.
_spec = importlib.util.spec_from_file_location(
    "test_check_data_residency", pathlib.Path(__file__).with_name("test_check_data_residency.py")
)
residency_test = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(residency_test)


class OrgServicesTest(unittest.TestCase):
    """ORG_SERVICES account singletons: root, delegated-administrator, org-settings, the resource policy."""

    def org(self, stacks):
        return [e for e in check_lane_names.check(stacks) if "aws-" in e]

    @staticmethod
    def instances(stacks, stack_name):
        return stacks[stack_name]["components"]["terraform"]

    def test_simulated_e5c_slices_pass(self):
        self.assertEqual(check_lane_names.check(residency_test.org_services_stacks()), [])

    def test_two_delegated_administrators_in_one_service_and_region_fail(self):
        stacks = residency_test.org_services_stacks()
        security = self.instances(stacks, "fnx-ue1-security")
        security["aws-guardduty/delegated-administrator-2"] = security["aws-guardduty/delegated-administrator"]
        # A lane of the security stack holding a second one is the same finding.
        stacks["fnx-ue1-security-lane"] = {"components": {"terraform": {
            "aws-guardduty/delegated-administrator": security["aws-guardduty/delegated-administrator"]}}}
        found = self.org(stacks)
        self.assertEqual(len(found), 2, found)  # the singleton, and the in-stack same-name pair
        self.assertIn("fnx-ue1-security: aws-guardduty/delegated-administrator and fnx-ue1-security: "
                      "aws-guardduty/delegated-administrator-2 and fnx-ue1-security-lane: "
                      "aws-guardduty/delegated-administrator are all the aws-guardduty delegated-administrator step in "
                      "us-east-1", found[-1])

    def test_two_org_settings_or_roots_in_one_region_fail(self):
        for stack_name, name in (("fnx-ec1-security", "aws-security-hub/org-settings"),
                                 ("fnx-ue2-root", "aws-inspector2/root")):
            with self.subTest(name=name):
                stacks = residency_test.org_services_stacks()
                stacks[f"{stack_name}-x"] = {"components": {"terraform": {
                    name: self.instances(stacks, stack_name)[name]}}}
                found = self.org(stacks)
                self.assertEqual(len(found), 1, found)
                self.assertIn(f"are all the {name.split('/')[0]} {name.split('/')[1]} step", found[0])

    def test_one_region_per_step_is_not_a_collision(self):
        # The 4 regions' instances of one step are separate singletons (the simulation passes).
        stacks = residency_test.org_services_stacks()
        self.assertEqual(len([n for s in stacks.values() for n in s["components"]["terraform"]
                              if n == "aws-guardduty/root"]), 4)
        self.assertEqual(self.org(stacks), [])

    def test_a_delegated_administrator_outside_the_security_account_fails(self):
        stacks = residency_test.org_services_stacks()
        rogue = residency_test.org_instance("aws-guardduty", "prod", "us-east-1")
        self.instances(stacks, "fnx-ue1-prod")["aws-guardduty/delegated-administrator"] = rogue
        self.assertEqual(self.org(stacks), [
            "fnx-ue1-prod: aws-guardduty/delegated-administrator is in account fnx-prod, neither the management "
            "account (fnx-root) nor the delegated administrator (fnx-security): it creates nothing there"])
        rogue["vars"]["delegated_administrator_account_name"] = "fnx-prod"
        self.assertEqual(self.org(stacks), [
            "fnx-ue1-prod: aws-guardduty/delegated-administrator names delegated administrator 'fnx-prod': the org "
            "services' delegated administrator is fnx-security"])
        rogue["vars"].pop("delegated_administrator_account_name")  # CP default core-security
        self.assertIn("names delegated administrator 'core-security'", self.org(stacks)[0])

    def test_two_resource_policies_fail(self):
        stacks = residency_test.org_services_stacks()
        hub = self.instances(stacks, "fnx-ew1-root")["aws-security-hub/root"]
        hub["vars"].pop("organizations_resource_policy_enabled")  # CP default true
        self.assertEqual(self.org(stacks), [
            "fnx-ew1-root: aws-security-hub/root and fnx-ue1-root: aws-security-hub/root all create the Security Hub "
            "Organizations resource policy, an organization singleton: set organizations_resource_policy_enabled "
            "false in all but one"])

    def test_inspector_has_no_step_one(self):
        stacks = residency_test.org_services_stacks()
        self.instances(stacks, "fnx-ue1-security")["aws-inspector2/org-settings"]["vars"]["admin_delegated"] = False
        self.assertEqual(self.org(stacks), [
            "fnx-ue1-security: aws-inspector2/org-settings is an aws-inspector2 instance with admin_delegated off: "
            "Inspector has no step 1, only org-settings"])

    def test_a_string_admin_delegated_fails(self):
        # Terraform reads "true" as step 3, but the security-org layer's query matches only the bool.
        stacks = residency_test.org_services_stacks()
        self.instances(stacks, "fnx-ue1-security")["aws-security-hub/org-settings"]["vars"]["admin_delegated"] = "true"
        # (Its step unknown, it is also compared by name with the stack's delegated-administrator.)
        self.assertIn("fnx-ue1-security: aws-security-hub/org-settings sets admin_delegated 'true', not a bool: "
                      "deploy-full-stack's security-org layer selects step 3 by .vars.admin_delegated == true",
                      self.org(stacks))

    def test_steps_sharing_a_stack_collide_with_an_sns_topic(self):
        stacks = residency_test.org_services_stacks()
        for name in ("aws-guardduty/delegated-administrator", "aws-guardduty/org-settings"):
            self.instances(stacks, "fnx-ue1-security")[name]["vars"]["name"] = "guardduty"
        self.assertEqual(self.org(stacks), [])
        self.instances(stacks, "fnx-ue1-security")["aws-guardduty/org-settings"]["vars"]["create_sns_topic"] = True
        self.assertEqual(len(self.org(stacks)), 1)
        self.assertIn('set the same name "guardduty"', self.org(stacks)[0])

    def test_disabled_and_fixture_instances_are_exempt(self):
        stacks = residency_test.org_services_stacks()
        twin = dict(self.instances(stacks, "fnx-ue1-root")["aws-security-hub/root"])
        twin["metadata"] = {"component": "aws-security-hub", "enabled": False}
        stacks["fnx-ue1-root-x"] = {"components": {"terraform": {"aws-security-hub/root": twin}}}
        fixture = residency_test.org_instance("aws-security-hub", "root", "us-east-1")
        fixture["settings"]["context"]["stage"] = "fixtures"
        stacks["fnx-ue1-fixtures-org"] = {"components": {"terraform": {"aws-security-hub/root": fixture}}}
        self.assertEqual(self.org(stacks), [])


if __name__ == "__main__":
    unittest.main()

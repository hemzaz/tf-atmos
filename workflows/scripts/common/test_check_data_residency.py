"""Tests for check-data-residency.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_data_residency", pathlib.Path(__file__).with_name("check-data-residency.py")
)
residency = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(residency)

EU = "pci-sox-gdpr"
US = "pci-sox"
OUTSIDE = "outside the EU, in a GDPR-scoped stack"


def instance(region="eu-west-1", compliance=EU, deps=(), **extra_vars):
    tfstate = "us-east-1" if region.startswith("us-") else region
    return {
        "metadata": {},
        "vars": {"region": region, "tags": {"Compliance": compliance}, **extra_vars},
        "settings": {"tfstate": {"region": tfstate, "replica_region": tfstate}},
        "dependencies": {"components": list(deps)},
        "backend_type": "s3",
        "backend": {"region": tfstate},
        "remote_state_backend_type": "s3",
        "remote_state_backend": {"region": tfstate},
        "providers": {"aws": {"allowed_account_ids": ["123456789012"]}},
    }


def stack(**components):
    return {"components": {"terraform": components}}


def eu_stack(**components):
    return stack(**{"vpc": instance(), **components})


def us_stack(compliance=US):
    return stack(vpc=instance(region="us-east-1", compliance=compliance))


class DataResidencyTest(unittest.TestCase):
    def test_eu_stack_in_eu_west_1_passes(self):
        stacks = {
            "fnx-ew1-prod": eu_stack(**{"kms/main": instance(replica_regions=["eu-central-1"],
                                                            deps=[{"component": "vpc"}])}),
            "fnx-ue1-prod": us_stack(),
        }
        self.assertEqual(residency.check(stacks), [])

    def test_us_kms_replica_fails(self):
        stacks = {"fnx-ew1-prod": eu_stack(**{"kms/main": instance(replica_regions=["eu-central-1", "us-east-1"])})}
        self.assertEqual(residency.check(stacks), [f"fnx-ew1-prod: kms/main vars.replica_regions is 'us-east-1', {OUTSIDE}"])

    def test_nested_regions_in_dicts_lists_and_state_fail(self):
        eu = instance(backup={"rules": [{"copy": {"destination_region": "us-east-2"}}]})
        eu["settings"]["tfstate"]["replica_region"] = "us-east-2"
        eu["remote_state_backend"]["region"] = "us-east-1"
        eu["providers"]["aws"]["region"] = "us-west-2"
        self.assertEqual(residency.check({"fnx-ew1-prod": stack(**{"backup/main": eu})}), [
            f"fnx-ew1-prod: backup/main vars.backup.rules.copy.destination_region is 'us-east-2', {OUTSIDE}",
            f"fnx-ew1-prod: backup/main settings.tfstate.replica_region is 'us-east-2', {OUTSIDE}",
            f"fnx-ew1-prod: backup/main remote_state_backend.s3.region is 'us-east-1', {OUTSIDE}",
            f"fnx-ew1-prod: backup/main providers.aws.region is 'us-west-2', {OUTSIDE}",
        ])

    def test_regional_arn_fails_and_regionless_arns_pass(self):
        api = instance(health_check_alarm_actions=["arn:aws:sns:us-east-1:123456789012:ue1-main-alarms"],
                       policy={"roles": ["arn:aws:iam::123456789012:role/x", "arn:aws:s3:::bucket"]},
                       zone="arn:aws:route53:::hostedzone/Z1", topic="arn:aws:sns:eu-west-1:123456789012:t")
        self.assertEqual(residency.check({"fnx-ew1-prod": stack(**{"apigateway/main": api})}), [
            f"fnx-ew1-prod: apigateway/main vars.health_check_alarm_actions is 'us-east-1', {OUTSIDE}",
        ])

    def test_arns_inside_policy_strings(self):
        bad = instance(topic_policy='{"Statement":[{"Resource":"arn:aws:sns:us-east-1:111111111111:t"}]}')
        self.assertEqual(residency.check({"fnx-ew1-prod": stack(sns=bad)}), [
            f"fnx-ew1-prod: sns vars.topic_policy is 'us-east-1', {OUTSIDE}",
        ])
        good = instance(topic_policy='{"Statement":[{"Resource":"arn:aws:sns:eu-west-1:111111111111:t",'
                                     '"Principal":{"AWS":"arn:aws:iam::111111111111:root"}}]}')
        self.assertEqual(residency.check({"fnx-ew1-prod": stack(sns=good)}), [])

    def test_non_map_dependency_is_an_error(self):
        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(app=instance(deps=["vpc"]))}), [
            "fnx-ew1-prod: app dependencies.components entry 'vpc' is not a {component, stack} map",
        ])

    def test_dependency_on_us_stack_fails(self):
        stacks = {
            "fnx-ew1-prod": eu_stack(app=instance(deps=[{"component": "vpc", "stack": "fnx-ue1-prod"}])),
            "fnx-ue1-prod": us_stack(),
        }
        self.assertEqual(
            residency.check(stacks), ["fnx-ew1-prod: app depends on vpc in fnx-ue1-prod, which is not GDPR-scoped"]
        )

    def test_dependency_on_eu_root_stack_passes(self):
        stacks = {
            "fnx-ew1-prod": eu_stack(**{"iam/main": instance(deps=[{"component": "iam/root", "stack": "fnx-ew1-root"}])}),
            "fnx-ew1-root": stack(**{"iam/root": instance()}),
        }
        self.assertEqual(residency.check(stacks), [])

    def test_eu_stack_without_gdpr_tag_fails(self):
        errors = residency.check({"fnx-ew1-prod": stack(vpc=instance(compliance=US))})
        self.assertEqual(
            errors, ["fnx-ew1-prod: vpc is in a GDPR-scoped stack but its tags.Compliance does not contain 'gdpr'"]
        )

    def test_depends_on_fails(self):
        app = instance()
        app["settings"]["depends_on"] = {"1": {"component": "vpc"}}
        self.assertEqual(
            residency.check({"fnx-ew1-prod": eu_stack(app=app)}),
            ["fnx-ew1-prod: app sets settings.depends_on: list dependencies in dependencies.components"],
        )

    def test_us_stack_tagged_gdpr_fails(self):
        errors = residency.check({"fnx-ue1-prod": us_stack(compliance=EU)})
        self.assertIn(f"fnx-ue1-prod: vpc vars.region is 'us-east-1', {OUTSIDE}", errors)
        self.assertIn(f"fnx-ue1-prod: vpc backend.s3.region is 'us-east-1', {OUTSIDE}", errors)

    def test_exempted_pair_passes_and_only_that_pair(self):
        api = instance(health_check_alarm_actions=["arn:aws:sns:us-east-1:123456789012:ue1-main-alarms"])
        stacks = {"fnx-ew1-prod": eu_stack(**{"apigateway/main": api})}
        exemptions = (residency.Exemption("apigateway/*", "vars.health_check_alarm_actions", "us-east-1",
                                          "Route 53 health-check metrics exist only in us-east-1"),)
        self.assertEqual(residency.check(stacks, exemptions), [])
        self.assertEqual(len(residency.check(stacks)), 1)
        api["vars"]["health_check_alarm_actions"] = ["arn:aws:sns:us-west-2:123456789012:t"]
        self.assertEqual(len(residency.check(stacks, exemptions)), 1)

    def test_disabled_instances_are_skipped(self):
        off = instance(region="us-east-1", compliance=US)
        off["metadata"] = {"enabled": False}
        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(off=off)}), [])

    def test_dns_query_logging_fails_in_eu_only(self):
        def dns(main_logging):
            spec = instance(zones={"main": {"name": "d", "enable_query_logging": main_logging},
                                   "internal": {"name": "internal.d", "vpc_associations": ["vpc-1"]}})
            spec["metadata"] = {"component": "dns"}
            return spec

        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"network/main": dns(False)})}), [])
        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"network/main": dns(True)})}), [
            "fnx-ew1-prod: network/main zone main sets enable_query_logging: Route 53 query logs are only "
            "written to us-east-1, outside the EU",
        ])
        us = dns(True)
        us["vars"].update(region="us-east-1", tags={"Compliance": US})
        us["settings"]["tfstate"] = {"region": "us-east-1"}
        us["backend"] = us["remote_state_backend"] = {"region": "us-east-1"}
        self.assertEqual(residency.check({"fnx-ue1-prod": stack(**{"network/main": us})}), [])

    def test_dns_query_logging_quoted_and_numeric_values_count_as_on(self):
        on = "fnx-ew1-prod: network/main zone main sets enable_query_logging"
        for value in ("true", "True", 1):
            spec = instance(zones={"main": {"name": "d", "enable_query_logging": value}})
            spec["metadata"] = {"component": "dns"}
            errors = residency.check({"fnx-ew1-prod": eu_stack(**{"network/main": spec})})
            self.assertEqual(len(errors), 1, value)
            self.assertTrue(errors[0].startswith(on), value)
        for value in (None, False, "false", "FALSE"):
            spec = instance(zones={"main": {"name": "d", "enable_query_logging": value}})
            spec["metadata"] = {"component": "dns"}
            self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"network/main": spec})}), [], value)

    def test_dns_non_map_zones_is_an_error(self):
        spec = instance(zones=["main"])
        spec["metadata"] = {"component": "dns"}
        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"network/main": spec})}), [
            "fnx-ew1-prod: network/main vars.zones is list, not a map: its query logging cannot be checked",
        ])

    def test_security_monitoring_alert_enrichment_fails_in_eu_only(self):
        def monitoring(value, **extra):
            spec = instance(enable_alert_enrichment=value, **extra)
            spec["metadata"] = {"component": "security-monitoring", "inherits": ["security-monitoring/defaults"]}
            return spec

        on = ("fnx-ew1-prod: security-monitoring/main sets enable_alert_enrichment: its Lambda sends "
              "findings to Slack/PagerDuty, outside the EU")
        for value in (True, "true", 1):
            self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"security-monitoring/main": monitoring(value)})}),
                             [on], value)
        for value in (None, False, "false"):
            self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"security-monitoring/main": monitoring(value)})}),
                             [], value)
        us = monitoring(True)
        us["vars"].update(region="us-east-1", tags={"Compliance": US})
        us["settings"]["tfstate"] = {"region": "us-east-1"}
        us["backend"] = us["remote_state_backend"] = {"region": "us-east-1"}
        self.assertEqual(residency.check({"fnx-ue1-prod": stack(**{"security-monitoring/main": us})}), [])

    def test_us_stack_depending_on_an_eu_stack_fails(self):
        # A US read replica, Global Datastore secondary or state read of an EU
        # instance copies EU data out: the US stack lists the EU one.
        replica = instance(region="us-east-1", compliance=US,
                           deps=[{"component": "rds/main", "stack": "fnx-ew1-prod"}])
        stacks = {
            "fnx-ew1-prod": eu_stack(**{"rds/main": instance()}),
            "fnx-ue1-prod": stack(**{"rds/main": replica}),
        }
        self.assertEqual(residency.check(stacks), [
            "fnx-ue1-prod: rds/main depends on rds/main in fnx-ew1-prod, which is GDPR-scoped: "
            "EU data may not be read outside the EU",
        ])
        replica["dependencies"]["components"] = [{"component": "rds/main", "stack": "fnx-ue1-prod"}]
        self.assertEqual(residency.check(stacks), [])

    def test_us_stack_depending_on_itself_or_a_us_stack_passes(self):
        own = instance(region="us-east-1", compliance=US, deps=[{"component": "vpc"}])
        stacks = {"fnx-ue1-prod": stack(vpc=instance(region="us-east-1", compliance=US), **{"eks/main": own}),
                  "fnx-ew1-prod": eu_stack()}
        self.assertEqual(residency.check(stacks), [])

    def test_us_stack_naming_an_eu_arn_fails(self):
        # A literal EU ARN needs no dependency: the US replica still copies EU data out.
        replica = instance(region="us-east-1", compliance=US,
                           replicate_source_db="arn:aws:rds:eu-west-1:123456789012:db:prod-main-db")
        stacks = {"fnx-ew1-prod": eu_stack(), "fnx-ue1-prod": stack(**{"rds/replica": replica})}
        self.assertEqual(residency.check(stacks), [
            "fnx-ue1-prod: rds/replica vars.replicate_source_db names an ARN in 'eu-west-1': "
            "EU data may not be read outside the EU",
        ])
        exemptions = (residency.Exemption("rds/*", "vars.replicate_source_db", "eu-west-1", "test"),)
        self.assertEqual(residency.check(stacks, exemptions), [])

    def test_us_stack_with_us_arns_and_eu_region_vars_passes(self):
        # US data copied into the EU is fine: only eu- ARNs count, not *_region vars.
        us = instance(region="us-east-1", compliance=US, replica_region="eu-west-1",
                      replicate_source_db="arn:aws:rds:us-east-1:123456789012:db:prod-main-db")
        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(), "fnx-ue1-prod": stack(**{"rds/main": us})}), [])

    def test_eu_stack_with_a_us_arn_is_only_flagged_as_outside_the_eu(self):
        eu = instance(replicate_source_db="arn:aws:rds:us-east-1:123456789012:db:prod-main-db")
        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"rds/main": eu}), "fnx-ue1-prod": us_stack()}), [
            f"fnx-ew1-prod: rds/main vars.replicate_source_db is 'us-east-1', {OUTSIDE}",
        ])

    def test_backup_copy_outside_the_eu_fails(self):
        def backup(region, key_region):
            return instance(enable_cross_region_backup=True, replica_region=region,
                            replica_kms_key_arn=f"arn:aws:kms:{key_region}:123456789012:key/mrk-1")

        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"backup/main": backup("eu-central-1", "eu-central-1")})}), [])
        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"backup/main": backup("us-east-2", "us-east-2")})}), [
            f"fnx-ew1-prod: backup/main vars.replica_region is 'us-east-2', {OUTSIDE}",
            f"fnx-ew1-prod: backup/main vars.replica_kms_key_arn is 'us-east-2', {OUTSIDE}",
        ])


if __name__ == "__main__":
    unittest.main()

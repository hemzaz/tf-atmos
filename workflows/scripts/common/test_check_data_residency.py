"""Tests for check-data-residency.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import copy
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

    def test_secret_replica_regions(self):
        # secretsmanager's replica_regions: a list of {region, kms_key_id} objects.
        def secrets(*regions):
            return instance(replica_regions=[
                {"region": r, "kms_key_id": f"!terraform.state kms/main '.replica_keys[\"{r}\"].key_arn'"}
                for r in regions])
        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"secretsmanager/app": secrets("eu-central-1")})}), [])
        self.assertEqual(
            residency.check({"fnx-ew1-prod": eu_stack(**{"secretsmanager/app": secrets("eu-central-1", "us-east-1")})}),
            [f"fnx-ew1-prod: secretsmanager/app vars.replica_regions.region is 'us-east-1', {OUTSIDE}"],
        )

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
        # No exemptions: the rule itself (EXEMPTIONS admits this pair, tested below).
        self.assertEqual(residency.check({"fnx-ew1-prod": stack(**{"apigateway/main": api})}, ()), [
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
        self.assertEqual(len(residency.check(stacks, ())), 1)
        api["vars"]["health_check_alarm_actions"] = ["arn:aws:sns:us-west-2:123456789012:t"]
        self.assertEqual(len(residency.check(stacks, exemptions)), 1)

    def test_eu_failover_pair_passes_with_the_exemptions_and_only_them(self):
        regions = ["eu-west-1", "us-east-1", "ap-southeast-1"]
        relay = ["eu-west-1", "eu-central-1"]
        primary = instance(health_check_regions=regions, health_check_alarm_relay_regions=relay)
        secondary = instance(region="eu-central-1", health_check_regions=regions,
                             health_check_alarm_relay_regions=relay)
        stacks = {"fnx-ew1-prod": eu_stack(**{"apigateway/main": primary}),
                  "fnx-ec1-prod": eu_stack(**{"apigateway/main": secondary})}
        self.assertEqual(residency.check(stacks), [])
        self.assertEqual(len(residency.check(stacks, ())), 4)
        # Deliberately bad: another checker region, another instance, a relay to us-east-1.
        secondary["vars"]["health_check_regions"] = ["eu-west-1", "us-east-1", "us-west-2"]
        secondary["vars"]["health_check_alarm_relay_regions"] = ["eu-central-1", "us-east-1"]
        self.assertEqual(residency.check(stacks), [
            f"fnx-ec1-prod: apigateway/main vars.health_check_regions is 'us-west-2', {OUTSIDE}",
            f"fnx-ec1-prod: apigateway/main vars.health_check_alarm_relay_regions is 'us-east-1', {OUTSIDE}",
        ])
        stacks["fnx-ec1-prod"] = eu_stack(**{"apigateway/data": instance(health_check_regions=regions)})
        self.assertEqual(residency.check(stacks), [
            f"fnx-ec1-prod: apigateway/data vars.health_check_regions is 'us-east-1', {OUTSIDE}",
            f"fnx-ec1-prod: apigateway/data vars.health_check_regions is 'ap-southeast-1', {OUTSIDE}",
        ])

    def test_eu_health_check_alarm_action_in_us_east_1_fails(self):
        # No us-east-1 alarm topic is exempt: an EU alarm is relayed instead.
        api = instance(health_check_alarm_actions=["arn:aws:sns:us-east-1:123456789012:ew1-prod-main-api-health-check-alarms"])
        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"apigateway/main": api})}), [
            f"fnx-ew1-prod: apigateway/main vars.health_check_alarm_actions is 'us-east-1', {OUTSIDE}",
        ])

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

    def test_dns_dnssec_fails_in_eu_only(self):
        def dns(value):
            spec = instance(dnssec_enabled=value, zones={"main": {"name": "d"}})
            spec["metadata"] = {"component": "dns"}
            return spec

        for off in (None, False, "false"):
            self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"network/main": dns(off)})}), [], off)
        for on in (True, "true", 1):
            self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"network/main": dns(on)})}), [
                "fnx-ew1-prod: network/main sets dnssec_enabled: Route 53 signs only with a KMS key in "
                "us-east-1, outside the EU",
            ], on)
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

    def test_dns_external_zone_query_logging_fails_in_eu_only(self):
        spec = instance(external_zones={"apex": {"name": "d", "enable_query_logging": True}, "quiet": {"name": "q"}})
        spec["metadata"] = {"component": "dns"}
        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"network/main": spec})}), [
            "fnx-ew1-prod: network/main external_zones.apex sets enable_query_logging: Route 53 query logs are "
            "only written to us-east-1, outside the EU",
        ])
        spec["vars"]["external_zones"]["apex"]["enable_query_logging"] = False
        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"network/main": spec})}), [])

    def test_eu_zones_under_or_into_a_us_held_zone_fail(self):
        # B5: an EU zone may not hang off, or write into, a zone a US stack holds, at any depth.
        def cp(component, **variables):
            spec = instance(**variables)
            spec["metadata"] = {"component": component}
            return spec

        us = cp("aws-dns-primary", region="us-east-1", compliance=US, domain_names=["svc.example.net"])
        us["settings"]["tfstate"] = {"region": "us-east-1"}
        us["backend"] = us["remote_state_backend"] = {"region": "us-east-1"}
        tail = "which is not GDPR-scoped: an EU zone may not hang off, or write into, a zone in a US account"
        cases = {
            "delegated": ({"d": cp("aws-dns-delegated", zone_config=[{"subdomain": "eu", "zone_name": "SVC.example.net."}])},
                          ["fnx-ew1-prod: d zone eu.svc.example.net sits below svc.example.net, held in fnx-gbl-network, " + tail]),
            "primary": ({"p": cp("aws-dns-primary", domain_names=["eu.svc.example.net"])},
                        ["fnx-ew1-prod: p zone eu.svc.example.net sits below svc.example.net, held in fnx-gbl-network, " + tail]),
            "chain": ({"p": cp("aws-dns-primary", domain_names=["eu.svc.example.net"]),
                       "d": cp("aws-dns-delegated", zone_config=[{"subdomain": "a", "zone_name": "eu.svc.example.net"}])},
                      ["fnx-ew1-prod: p zone eu.svc.example.net sits below svc.example.net, held in fnx-gbl-network, " + tail]),
            "dns": ({"n": cp("dns", zones={"main": {"name": "eu.svc.example.net"}})},
                    ["fnx-ew1-prod: n zone eu.svc.example.net sits below svc.example.net, held in fnx-gbl-network, " + tail]),
            "external": ({"n": cp("dns", external_zones={"primary": {"name": "svc.example.net", "dns_account": True}})},
                         ["fnx-ew1-prod: n external_zones.primary names svc.example.net, held in fnx-gbl-network, " + tail]),
        }
        for case, (eu_instances, errors) in cases.items():
            stacks = {"fnx-ew1-prod": eu_stack(**eu_instances), "fnx-gbl-network": stack(**{"dns-primary": us})}
            self.assertEqual(residency.check(stacks), errors, case)
        # An EU parent, or a disabled US one, is fine.
        eu_parent = cp("aws-dns-primary", domain_names=["svc.example.net"])
        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(p=eu_parent, d=cases["chain"][0]["d"])}), [])
        us["metadata"]["enabled"] = False
        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**cases["dns"][0]), "fnx-gbl-network": stack(**{"dns-primary": us})}), [])

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

    def test_global_service_email_subscribers_fail_in_eu_only(self):
        def budget(**variables):
            spec = instance(**variables)
            spec["metadata"] = {"component": "cost-optimization", "inherits": ["cost-optimization/defaults"]}
            return spec

        def errors(spec):
            return residency.check({"fnx-ew1-prod": eu_stack(**{"cost-optimization/main": spec})})

        prefix = "fnx-ew1-prod: cost-optimization/main sets vars."
        suffix = (": a global service in us-east-1 would store those email addresses; "
                  "notify an in-region SNS topic instead")
        self.assertEqual(errors(budget(budget_notification_emails=["a@example.com"])),
                         [f"{prefix}budget_notification_emails{suffix}"])
        self.assertEqual(errors(budget(cost_anomaly_notification_email="a@example.com")),
                         [f"{prefix}cost_anomaly_notification_email{suffix}"])
        self.assertEqual(errors(budget(billing_notifications_sns_enabled=True, budget_notification_emails=[],
                                       cost_anomaly_notification_email=None, cost_alert_emails=["a@example.com"])), [])
        disabled = budget(budget_notification_emails=["a@example.com"])
        disabled["metadata"]["enabled"] = False
        self.assertEqual(errors(disabled), [])
        us = budget(budget_notification_emails=["a@example.com"], cost_anomaly_notification_email="a@example.com")
        us["vars"].update(region="us-east-1", tags={"Compliance": US})
        us["settings"]["tfstate"] = {"region": "us-east-1"}
        us["backend"] = us["remote_state_backend"] = {"region": "us-east-1"}
        self.assertEqual(residency.check({"fnx-ue1-prod": stack(**{"cost-optimization/main": us})}), [])

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

    # EU core stacks (stack-wiring.py's EU_CORE_STAGES, E5a1): the guards admit fnx-ew1-audit in the
    # shared audit account, but this check holds it to the same rules as fnx-ew1-prod, unchanged.
    @staticmethod
    def audit_stacks(eu=None, us=None):
        return {"fnx-ew1-audit": stack(**{"aws-account-settings": eu or instance()}),
                "fnx-ue1-audit": stack(**{"aws-account-settings": us or instance(region="us-east-1", compliance=US)})}

    def test_eu_audit_stack_with_eu_state_and_gdpr_tag_passes(self):
        self.assertEqual(residency.check(self.audit_stacks()), [])

    def test_eu_audit_stack_on_the_us_backend_fails(self):
        eu = instance()
        eu["settings"]["tfstate"] = {"region": "us-east-1", "replica_region": "us-east-2"}
        eu["backend"] = eu["remote_state_backend"] = {"region": "us-east-1"}
        self.assertEqual(residency.check(self.audit_stacks(eu=eu)), [
            f"fnx-ew1-audit: aws-account-settings settings.tfstate.region is 'us-east-1', {OUTSIDE}",
            f"fnx-ew1-audit: aws-account-settings settings.tfstate.replica_region is 'us-east-2', {OUTSIDE}",
            f"fnx-ew1-audit: aws-account-settings backend.s3.region is 'us-east-1', {OUTSIDE}",
            f"fnx-ew1-audit: aws-account-settings remote_state_backend.s3.region is 'us-east-1', {OUTSIDE}",
        ])

    def test_eu_audit_stack_without_gdpr_tag_fails(self):
        self.assertEqual(residency.check(self.audit_stacks(eu=instance(compliance=US))), [
            "fnx-ew1-audit: aws-account-settings is in a GDPR-scoped stack but its tags.Compliance does not "
            "contain 'gdpr'",
        ])

    def test_eu_audit_stack_depending_on_the_us_audit_stack_fails(self):
        eu = instance(deps=[{"component": "aws-account-settings", "stack": "fnx-ue1-audit"}])
        self.assertEqual(residency.check(self.audit_stacks(eu=eu)), [
            "fnx-ew1-audit: aws-account-settings depends on aws-account-settings in fnx-ue1-audit, "
            "which is not GDPR-scoped",
        ])

    def test_us_audit_stack_depending_on_the_eu_audit_stack_fails(self):
        us = instance(region="us-east-1", compliance=US,
                      deps=[{"component": "aws-account-settings", "stack": "fnx-ew1-audit"}])
        self.assertEqual(residency.check(self.audit_stacks(us=us)), [
            "fnx-ue1-audit: aws-account-settings depends on aws-account-settings in fnx-ew1-audit, which is "
            "GDPR-scoped: EU data may not be read outside the EU",
        ])

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

    @staticmethod
    def cache(region="eu-west-1", compliance=EU, deps=(), **extra):
        spec = instance(region=region, compliance=compliance, deps=deps, **extra)
        spec["metadata"] = {"component": "elasticache"}
        return spec

    def global_datastore(self, secondary_stack, secondary):
        return {
            "fnx-ew1-prod": eu_stack(**{"elasticache/main": self.cache(
                global_replication_group_id_suffix="fnx-ew1-prod-cache")}),
            secondary_stack: stack(**{"elasticache/main": secondary}),
        }

    def test_eu_global_datastore_with_an_eu_secondary_passes(self):
        secondary = self.cache(
            region="eu-central-1",
            global_replication_group_id="!terraform.state elasticache/main fnx-ew1-prod .global_replication_group_id",
            deps=[{"component": "elasticache/main", "stack": "fnx-ew1-prod"}])
        self.assertEqual(residency.check(self.global_datastore("fnx-ec1-prod", secondary)), [])

    def test_us_secondary_naming_an_eu_global_datastore_literally_fails(self):
        # Deliberately bad: no dependency and no ARN, only the group's literal id, which the
        # outside-reader rule cannot see.
        joined = ("fnx-ue2-prod: elasticache/main joins fnx-ew1-prod elasticache/main's Global Datastore "
                  "(fnx-ew1-prod-cache) outside the GDPR scope: EU cache data may not be replicated outside the EU")
        for gid in ("ldgnf-fnx-ew1-prod-cache", "fnx-ew1-prod-cache"):
            secondary = self.cache(region="us-east-2", compliance=US, global_replication_group_id=gid)
            self.assertEqual(residency.check(self.global_datastore("fnx-ue2-prod", secondary)), [joined], gid)

    def test_us_secondary_reading_an_eu_global_datastore_fails(self):
        secondary = self.cache(
            region="us-east-2", compliance=US,
            global_replication_group_id="!terraform.state elasticache/main fnx-ew1-prod '.global_replication_group_id'",
            deps=[{"component": "elasticache/main", "stack": "fnx-ew1-prod"}])
        errors = residency.check(self.global_datastore("fnx-ue2-prod", secondary))
        self.assertIn("fnx-ue2-prod: elasticache/main joins fnx-ew1-prod elasticache/main's Global Datastore "
                      "(fnx-ew1-prod-cache) outside the GDPR scope: EU cache data may not be replicated outside the EU",
                      errors)
        self.assertIn("fnx-ue2-prod: elasticache/main depends on elasticache/main in fnx-ew1-prod, which is "
                      "GDPR-scoped: EU data may not be read outside the EU", errors)

    def test_us_global_datastore_and_unrelated_us_groups_pass(self):
        # A US primary's group may be joined by US stacks; a US cache joining another group
        # (a different suffix) is not this rule's business.
        stacks = {
            "fnx-ew1-prod": eu_stack(**{"elasticache/main": self.cache(
                global_replication_group_id_suffix="fnx-ew1-prod-cache")}),
            "fnx-ue1-prod": stack(**{"elasticache/main": self.cache(
                region="us-east-1", compliance=US, global_replication_group_id_suffix="fnx-ue1-prod-cache")}),
            "fnx-ue2-prod": stack(**{"elasticache/main": self.cache(
                region="us-east-2", compliance=US,
                global_replication_group_id="!terraform.state elasticache/main fnx-ue1-prod .global_replication_group_id",
                deps=[{"component": "elasticache/main", "stack": "fnx-ue1-prod"}])}),
            "fnx-ue1-staging": stack(**{"elasticache/main": self.cache(
                region="us-east-1", compliance=US, global_replication_group_id="ldgnf-other-cache")}),
        }
        self.assertEqual(residency.check(stacks), [])

    def test_disabled_us_secondary_is_skipped(self):
        secondary = self.cache(region="us-east-2", compliance=US, global_replication_group_id="ldgnf-fnx-ew1-prod-cache")
        secondary["metadata"]["enabled"] = False
        self.assertEqual(residency.check(self.global_datastore("fnx-ue2-prod", secondary)), [])

    def test_backup_copy_outside_the_eu_fails(self):
        def backup(region, key_region):
            return instance(enable_cross_region_backup=True, replica_region=region,
                            replica_kms_key_arn=f"arn:aws:kms:{key_region}:123456789012:key/mrk-1")

        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"backup/main": backup("eu-central-1", "eu-central-1")})}), [])
        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(**{"backup/main": backup("us-east-2", "us-east-2")})}), [
            f"fnx-ew1-prod: backup/main vars.replica_region is 'us-east-2', {OUTSIDE}",
            f"fnx-ew1-prod: backup/main vars.replica_kms_key_arn is 'us-east-2', {OUTSIDE}",
        ])


def archived(component, env, region="eu-west-1", compliance=EU, deps=None, account=None, account_id=None,
             **extra_vars):
    """An aws-cloudtrail/aws-config instance delivering to fnx-<env>-audit, listed as its dependency.

    An aws-config instance is its account's global-resource collector unless extra_vars say otherwise.
    """
    bucket, env_var, stage_var = {
        "aws-cloudtrail": ("cloudtrail-bucket", "cloudtrail_bucket_environment_name", "cloudtrail_bucket_stage_name"),
        "aws-config": ("config-bucket", "config_bucket_env", "config_bucket_stage"),
    }[component]
    if deps is None:
        deps = [{"component": bucket, "stack": f"fnx-{env}-audit"}]
    if component == "aws-config":
        extra_vars = {"global_resource_collector_region": region, **extra_vars}
    spec = instance(region, compliance, deps, tenant="fnx", **{env_var: env, stage_var: "audit"}, **extra_vars)
    spec["metadata"] = {"component": component}
    if account:
        spec["settings"]["environment"] = {"account": account, "account_id": account_id or "123456789012"}
    return spec


def eu_core_recorder(account, **extra_vars):
    """A shared account's eu-west-1 recorder: its collector is the US home stack's (OQ-A), and it
    authorizes the EU aggregator (aws-config/main-core-region-eu, owner 2026-11-13)."""
    extra_vars = {"iam_role_arn": f"arn:aws:iam::123456789012:role/fnx-ue1-{account}-aws-config-config",
                  "aggregator_authorization_region": "eu-west-1", **extra_vars}
    return archived("aws-config", "ew1", account=account, global_resource_collector_region="us-east-1", **extra_vars)


def home_collector(account):
    """A shared account's US home-stack collector, with the null-label context the vendored component names from."""
    spec = archived("aws-config", "ue1", "us-east-1", US, account=account, name="aws-config")
    spec["vars"]["context"] = {"tenant": "fnx", "environment": "ue1", "stage": account}
    return spec


def audit_stacks():
    def bucket(component, region, compliance):
        spec = instance(region, compliance)
        spec["metadata"] = {"component": component}
        return spec

    return {
        "fnx-ue1-audit": stack(**{
            "cloudtrail-bucket": bucket("aws-cloudtrail-bucket", "us-east-1", US),
            "config-bucket": bucket("aws-config-bucket", "us-east-1", US),
        }),
        "fnx-ew1-audit": stack(**{
            "cloudtrail-bucket": bucket("aws-cloudtrail-bucket", "eu-west-1", EU),
            "config-bucket": bucket("aws-config-bucket", "eu-west-1", EU),
        }),
    }


class LogArchiveTest(unittest.TestCase):
    """aws-cloudtrail and aws-config deliver to their residency's audit stack (owner OQ-A, OQ-E)."""

    def check(self, **stacks):
        return residency.check({**audit_stacks(), **stacks})

    def test_trails_and_recorders_delivering_to_their_residency_pass(self):
        self.assertEqual(self.check(**{
            "fnx-ue1-prod": stack(**{
                "cloudtrail": archived("aws-cloudtrail", "ue1", "us-east-1", US),
                "aws-config": archived("aws-config", "ue1", "us-east-1", US, config_bucket_tenant=""),
            }),
            "fnx-ew1-prod": eu_stack(**{
                "cloudtrail": archived("aws-cloudtrail", "ew1"),
                "aws-config": archived("aws-config", "ew1", config_bucket_tenant="fnx"),
            }),
            # A shared account's EU recorder delivers to the EU archive and leaves IAM to its US home
            # stack's collector (OQ-A: its trail stays US too).
            "fnx-ew1-root": eu_stack(**{"aws-config": eu_core_recorder("root")}),
            "fnx-ue1-root": stack(**{
                "cloudtrail": archived("aws-cloudtrail", "ue1", "us-east-1", US, account="root"),
                "aws-config": home_collector("root"),
            }),
        }), [])

    def test_a_literal_collector_role_arn_names_the_collectors_role(self):
        wrong = "arn:aws:iam::123456789012:role/fnx-ue1-audit-aws-config-config"
        errors = self.check(**{
            "fnx-ew1-root": eu_stack(**{"aws-config": eu_core_recorder("root", iam_role_arn=wrong)}),
            "fnx-ue1-root": stack(**{"aws-config": home_collector("root")}),
        })
        self.assertEqual(errors, [
            f"fnx-ew1-root: aws-config vars.iam_role_arn is {wrong!r}, not the role of its collector region's or "
            "its residency's collector (arn:aws:iam::123456789012:role/fnx-ue1-root-aws-config-config)",
        ])
        other_account = home_collector("root")
        other_account["settings"]["environment"]["account_id"] = "210987654321"
        errors = self.check(**{
            "fnx-ew1-root": eu_stack(**{"aws-config": eu_core_recorder("root")}),
            "fnx-ue1-root": stack(**{"aws-config": other_account}),
        })
        self.assertEqual(errors, [
            "fnx-ew1-root: aws-config vars.iam_role_arn is "
            "'arn:aws:iam::123456789012:role/fnx-ue1-root-aws-config-config', not the role of its collector "
            "region's or its residency's collector (arn:aws:iam::210987654321:role/fnx-ue1-root-aws-config-config)",
        ])

    def test_shared_eu_recorder_must_authorize_an_eu_region(self):
        # Owner 2026-11-13: a shared account's EU recorder (eu-west-1 and eu-central-1) keeps its US
        # home collector region (no IAM recording) only while it authorizes the EU aggregator. With
        # no aggregator_authorization_region CP authorizes its US collector region: refused, as is
        # authorizing a US region outright.
        home = {"fnx-ue1-root": stack(**{"aws-config": home_collector("root")})}
        for region, code in (("eu-west-1", "ew1"), ("eu-central-1", "ec1")):
            with self.subTest(region=region):
                def recorder(**override):
                    spec = eu_core_recorder("root", **override)
                    spec["vars"]["region"] = region
                    return {f"fnx-{code}-root": eu_stack(**{"aws-config": spec})}

                self.assertEqual(self.check(**home, **recorder()), [])
                self.assertEqual(self.check(**home, **recorder(aggregator_authorization_region=None)), [
                    f"fnx-{code}-root: aws-config vars.global_resource_collector_region is 'us-east-1', {OUTSIDE}",
                ])
                self.assertEqual(sorted(self.check(**home, **recorder(aggregator_authorization_region="us-east-1"))), [
                    f"fnx-{code}-root: aws-config vars.aggregator_authorization_region is 'us-east-1', {OUTSIDE}",
                    f"fnx-{code}-root: aws-config vars.global_resource_collector_region is 'us-east-1', {OUTSIDE}",
                ])

    def test_a_recorder_never_names_the_other_residencys_collector_role(self):
        # L2: a US recorder outside its collector region may not take fnx-ew1-security's EU role.
        eu_collector = archived("aws-config", "ew1", account="security", name="aws-config")
        eu_collector["vars"]["context"] = {"tenant": "fnx", "environment": "ew1", "stage": "security"}
        ue2 = archived("aws-config", "ue1", "us-east-2", US, account="security", global_resource_collector_region="us-east-1",
                       iam_role_arn="arn:aws:iam::123456789012:role/fnx-ew1-security-aws-config-config")
        stacks = {"fnx-ue1-security": stack(**{"aws-config": home_collector("security")}),
                  "fnx-ew1-security": eu_stack(**{"aws-config": eu_collector}),
                  "fnx-ue2-security": stack(**{"aws-config": ue2})}
        self.assertIn(
            "fnx-ue2-security: aws-config vars.iam_role_arn is "
            "'arn:aws:iam::123456789012:role/fnx-ew1-security-aws-config-config', not the role of its collector "
            "region's or its residency's collector (arn:aws:iam::123456789012:role/fnx-ue1-security-aws-config-config)",
            self.check(**stacks))
        ue2["vars"]["iam_role_arn"] = "arn:aws:iam::123456789012:role/fnx-ue1-security-aws-config-config"
        self.assertFalse([e for e in self.check(**stacks) if "iam_role_arn" in e])

    def test_us_collector_region_without_a_us_collector_in_the_account_fails(self):
        # prod-eu's stacks are all GDPR-scoped; and root's US home stack here holds no collector.
        no_collector = archived("aws-config", "ue1", "us-east-1", US, account="root",
                                global_resource_collector_region="us-west-2", iam_role_arn="arn:aws:iam::1:role/x")
        errors = self.check(**{
            "fnx-ew1-prod": eu_stack(**{"aws-config": eu_core_recorder("prod-eu")}),
            "fnx-ew1-root": eu_stack(**{"aws-config": eu_core_recorder("root")}),
            "fnx-ue1-root": stack(**{"aws-config": no_collector}),
        })
        self.assertEqual(errors, [
            f"fnx-ew1-prod: aws-config vars.global_resource_collector_region is 'us-east-1', {OUTSIDE}",
            f"fnx-ew1-root: aws-config vars.global_resource_collector_region is 'us-east-1', {OUTSIDE}",
        ])

    def test_a_disabled_or_accountless_us_collector_is_no_collector(self):
        accountless = archived("aws-config", "ue1", "us-east-1", US, account="root")
        accountless["settings"]["environment"]["account"] = ""
        for home in (archived("aws-config", "ue1", "us-east-1", US, account="root", enabled=False), accountless):
            with self.subTest(home=home):
                recorder = eu_core_recorder("root")
                recorder["settings"]["environment"]["account"] = home["settings"]["environment"]["account"]
                errors = self.check(**{
                    "fnx-ew1-root": eu_stack(**{"aws-config": recorder}),
                    "fnx-ue1-root": stack(**{"aws-config": home}),
                })
                self.assertIn(f"fnx-ew1-root: aws-config vars.global_resource_collector_region is 'us-east-1', "
                              f"{OUTSIDE}", errors)

    def test_recorder_outside_its_collector_region_needs_the_collectors_role(self):
        errors = self.check(**{
            "fnx-ue2-prod": stack(**{"aws-config": archived(
                "aws-config", "ue1", "us-east-2", US, global_resource_collector_region="us-east-1")}),
            "fnx-uw2-prod": stack(**{"aws-config": archived(
                "aws-config", "ue1", "us-west-2", US, global_resource_collector_region="us-east-1",
                iam_role_arn="arn:aws:iam::123456789012:role/r", create_iam_role=True)}),
        })
        self.assertEqual(errors, [
            f"fnx-{s}-prod: aws-config records outside its global_resource_collector_region, so it sets iam_role_arn "
            "to the collector's role and not create_iam_role" for s in ("ue2", "uw2")
        ])

    def aggregator_stacks(self, delegated, regions="default"):
        """US security aggregator, a US account (prod, 111) and an all-GDPR account (prod-eu, 222)."""
        return {
            "fnx-ue1-security": stack(**{"aws-config": archived(
                "aws-config", "ue1", "us-east-1", US, account="security", account_id="333333333333",
                central_resource_collector_account="fnx-security", delegated_accounts=delegated,
                aggregator_regions=["us-east-1"] if regions == "default" else regions)}),
            "fnx-ue1-prod": stack(**{"aws-config": archived(
                "aws-config", "ue1", "us-east-1", US, account="prod", account_id="111111111111",
                central_resource_collector_account="fnx-security")}),
            "fnx-ew1-prod": eu_stack(**{"aws-config": archived(
                "aws-config", "ew1", account="prod-eu", account_id="222222222222",
                central_resource_collector_account="fnx-security")}),
        }

    def test_us_aggregator_over_an_all_gdpr_account_fails(self):
        self.assertEqual(self.check(**self.aggregator_stacks(["111111111111", "333333333333"])), [])
        self.assertEqual(self.check(**self.aggregator_stacks(["111111111111", "222222222222"])), [
            "fnx-ue1-security: aws-config delegated_accounts lists 222222222222, an account whose stacks are all "
            "GDPR-scoped: its Config data may not be aggregated outside the EU",
        ])
        self.assertEqual(self.check(**self.aggregator_stacks(None)), [
            "fnx-ue1-security: aws-config leaves delegated_accounts unset, so it aggregates every account, including "
            "prod-eu, whose stacks are all GDPR-scoped",
        ])

    def test_us_aggregator_names_only_non_eu_source_regions(self):
        # Owner 2026-11-13: CP's all_regions reads EU regions too (the aggregator account's own data
        # there as well), so the US aggregator names its regions: set, no eu- one, every US recorder's.
        ok = ["111111111111", "333333333333"]
        where = "fnx-ue1-security: aws-config"
        self.assertEqual(self.check(**self.aggregator_stacks(ok, ["us-east-1", "us-east-2"])), [])
        self.assertEqual(self.check(**self.aggregator_stacks(ok, None)), [
            f"{where} leaves aggregator_regions unset: Cloud Posse then aggregates all regions, both residencies' "
            "(its own account's too); name its residency's regions",
        ])
        self.assertEqual(self.check(**self.aggregator_stacks(ok, [])), [
            f"{where} leaves aggregator_regions []: Cloud Posse then aggregates all regions, both residencies' "
            "(its own account's too); name its residency's regions",
        ])
        self.assertEqual(self.check(**self.aggregator_stacks(ok, ["us-east-1", "eu-central-1"])), [
            f"{where} aggregator_regions names 'eu-central-1': EU Config data may not be aggregated outside the EU",
        ])
        stacks = self.aggregator_stacks(ok, ["us-east-1"])
        stacks["fnx-ue2-prod"] = stack(**{"aws-config": archived(
            "aws-config", "ue1", "us-east-2", US, account="prod", account_id="111111111111",
            global_resource_collector_region="us-east-1", iam_role_arn="arn:aws:iam::1:role/r",
            central_resource_collector_account="fnx-security")})
        self.assertIn(f"{where} aggregator_regions misses 'us-east-2', where a recorder authorizes it: its data "
                      "would not be aggregated", self.check(**stacks))

    def test_eu_aggregator_names_only_eu_source_regions(self):
        # L1 (owner 2026-11-13): the EU aggregator names EU regions only, so the security account's
        # US data stays out of it, and covers every EU region where a recorder authorizes it.
        def stacks(regions):
            eu_agg = archived("aws-config", "ew1", account="security", account_id="333333333333",
                              central_resource_collector_account="fnx-security",
                              delegated_accounts=["222222222222"], aggregator_regions=regions)
            ec1 = archived("aws-config", "ew1", "eu-central-1", account="prod-eu", account_id="222222222222",
                           central_resource_collector_account="fnx-security",
                           global_resource_collector_region="eu-west-1", iam_role_arn="arn:aws:iam::1:role/r")
            return {"fnx-ew1-security": eu_stack(**{"aws-config": eu_agg}),
                    "fnx-ec1-prod": eu_stack(**{"aws-config": ec1})}

        where = "fnx-ew1-security: aws-config"
        self.assertEqual(self.check(**stacks(["eu-west-1", "eu-central-1"])), [])
        self.assertIn(f"{where} aggregator_regions names 'us-east-1': an EU aggregator names EU regions only (the "
                      "aggregator account's own data elsewhere stays out)",
                      self.check(**stacks(["eu-west-1", "eu-central-1", "us-east-1"])))
        self.assertIn(f"{where} aggregator_regions misses 'eu-central-1', where a recorder authorizes it: its data "
                      "would not be aggregated", self.check(**stacks(["eu-west-1"])))
        self.assertIn(f"{where} leaves aggregator_regions unset: Cloud Posse then aggregates all regions, both "
                      "residencies' (its own account's too); name its residency's regions", self.check(**stacks(None)))

    def test_aggregator_ids_shared_with_another_account_are_skipped(self):
        # Today every account carries the placeholder id: it cannot be told apart, so no noise.
        stacks = self.aggregator_stacks(["123456789012"])
        for spec in (s["components"]["terraform"]["aws-config"] for s in stacks.values()):
            spec["settings"]["environment"]["account_id"] = "123456789012"
        self.assertEqual(self.check(**stacks), [])

    def test_us_bucket_environment_in_a_gdpr_stack_fails(self):
        errors = self.check(**{"fnx-ew1-prod": eu_stack(**{"cloudtrail": archived("aws-cloudtrail", "ue1")})})
        self.assertIn("fnx-ew1-prod: cloudtrail delivers to fnx-ue1-audit, but its stack is GDPR-scoped: a trail or "
                      "recorder delivers to its residency's archive (EU iff GDPR-scoped)", errors)
        self.assertEqual(len(errors), 2, errors)  # and the dependency on a US stack

    def test_eu_bucket_environment_in_a_us_stack_fails(self):
        errors = self.check(**{"fnx-ue1-prod": stack(**{
            "aws-config": archived("aws-config", "ew1", "us-east-1", US)})})
        self.assertIn("fnx-ue1-prod: aws-config delivers to fnx-ew1-audit, but its stack is not GDPR-scoped: a trail "
                      "or recorder delivers to its residency's archive (EU iff GDPR-scoped)", errors)
        self.assertEqual(len(errors), 2, errors)  # and the US stack reading an EU one

    def test_literal_bucket_name_fails(self):
        errors = self.check(**{
            "fnx-ue1-prod": stack(**{"cloudtrail": archived(
                "aws-cloudtrail", "ue1", "us-east-1", US, s3_bucket_name="fnx-ue1-audit-cloudtrail")}),
            "fnx-ew1-prod": eu_stack(**{"aws-config": archived(
                "aws-config", "ew1", config_bucket_arn="arn:aws:s3:::fnx-ew1-audit-config")}),
        })
        self.assertEqual(errors, [
            "fnx-ew1-prod: aws-config sets vars.config_bucket_arn: the log archive bucket is computed from "
            "config_bucket_env and config_bucket_stage (remote-state_override.tf), never named",
            "fnx-ue1-prod: cloudtrail sets vars.s3_bucket_name: the log archive bucket is computed from "
            "cloudtrail_bucket_environment_name and cloudtrail_bucket_stage_name (remote-state_override.tf), never named",
        ])

    def test_another_stage_or_a_missing_bucket_fails(self):
        trail = archived("aws-cloudtrail", "ue1", "us-east-1", US, deps=[{"component": "cloudtrail-bucket",
                                                                            "stack": "fnx-ue1-root"}])
        trail["vars"]["cloudtrail_bucket_stage_name"] = "root"
        errors = self.check(**{"fnx-ue1-prod": stack(cloudtrail=trail)})
        self.assertEqual(errors, [
            "fnx-ue1-prod: cloudtrail vars.cloudtrail_bucket_stage_name is 'root': the log archive is in stage 'audit'",
            "fnx-ue1-prod: cloudtrail delivers to cloudtrail-bucket in fnx-ue1-root, which holds no "
            "aws-cloudtrail-bucket instance cloudtrail-bucket",
        ])

    def test_wrong_bucket_instance_or_tenant_fails(self):
        errors = self.check(**{"fnx-ue1-prod": stack(**{
            "aws-config": archived("aws-config", "ue1", "us-east-1", US,
                                   deps=[{"component": "cloudtrail-bucket", "stack": "fnx-ue1-audit"}],
                                   config_bucket_component_name="cloudtrail-bucket"),
            "aws-config/other": archived("aws-config", "ue1", "us-east-1", US, config_bucket_tenant="acme"),
        })})
        self.assertEqual(errors, [
            "fnx-ue1-prod: aws-config delivers to cloudtrail-bucket in fnx-ue1-audit, which holds no "
            "aws-config-bucket instance cloudtrail-bucket",
            "fnx-ue1-prod: aws-config/other delivers to config-bucket in acme-ue1-audit, which holds no "
            "aws-config-bucket instance config-bucket",
            "fnx-ue1-prod: aws-config/other does not list {component: config-bucket, stack: acme-ue1-audit} in "
            "dependencies.components",
        ])

    def test_missing_dependency_or_environment_fails(self):
        no_env = archived("aws-cloudtrail", "ue1", "us-east-1", US)
        del no_env["vars"]["cloudtrail_bucket_environment_name"]
        del no_env["vars"]["cloudtrail_bucket_stage_name"]  # one error, not a stage error beside it
        context_tenant = archived("aws-cloudtrail", "ue1", "us-east-1", US, context={"tenant": "fnx"})
        del context_tenant["vars"]["tenant"]  # null-label module.this.tenant
        errors = self.check(**{"fnx-ue1-prod": stack(**{
            "cloudtrail": archived("aws-cloudtrail", "ue1", "us-east-1", US, deps=[]),
            "cloudtrail/other": no_env,
            "cloudtrail/context": context_tenant,
        })})
        self.assertEqual(errors, [
            "fnx-ue1-prod: cloudtrail does not list {component: cloudtrail-bucket, stack: fnx-ue1-audit} in "
            "dependencies.components",
            "fnx-ue1-prod: cloudtrail/other sets no tenant, vars.cloudtrail_bucket_environment_name or "
            "vars.cloudtrail_bucket_stage_name: its log archive stack cannot be checked",
        ])

    def test_other_components_and_disabled_trails_are_not_checked(self):
        other = instance("us-east-1", US, s3_bucket_name="fnx-trail")
        other["metadata"] = {"component": "s3"}
        disabled = archived("aws-cloudtrail", "ew1", "us-east-1", US, deps=[])
        disabled["metadata"]["enabled"] = False
        self.assertEqual(self.check(**{"fnx-ue1-prod": stack(**{"s3/trail": other,
                                                                 "cloudtrail": disabled})}), [])


# E5c4-E5c6 on E5c1's catalog variants (feat/e5c1-detector-catalogs: catalog/{aws-guardduty,
# aws-security-hub,aws-inspector2}/defaults.yaml, _base/account-map-bypass{,-us}), resolved as describe
# stacks would, so the guards are proven on the shapes the later slices commit: delegated-administrator
# + org-settings in the 4 security stacks, the delegation in the 4 root stacks (the resource policy only
# in fnx-ue1-root, root-organization-policy), US org-settings on account-map-bypass-us.
ORG_IDS = {a: f"10000000000{i}" if i < 10 else f"1000000000{i}" for i, a in enumerate(
    ("root", "audit", "security", "network", "identity", "artifacts", "dev", "staging", "prod", "prod-eu"))}
# account-map-bypass (settings.static_account_map's copy) and account-map-bypass-us (no prod-eu, no templates).
STATIC_MAP = {"full_account_map": {f"fnx-{a}": i for a, i in ORG_IDS.items()},
              "root_account_account_name": "fnx-root", "identity_account_account_name": "fnx-identity",
              "audit_account_account_name": "fnx-audit", "iam_role_arn_templates": {
                  "dns-delegation": f"arn:aws:iam::{ORG_IDS['network']}:role/fnx-ue1-network-dns-delegation-security"}}
US_MAP = {k: v for k, v in STATIC_MAP.items() if k != "iam_role_arn_templates"}
US_MAP["full_account_map"] = {k: v for k, v in STATIC_MAP["full_account_map"].items() if k != "fnx-prod-eu"}
# catalog aws-security-hub/eu-shared-account-suppressions: the shared accounts are the map minus prod-eu.
SHARED = sorted(k for k in STATIC_MAP["full_account_map"] if k != "fnx-prod-eu")
EU_SHARED = {"account_scoped_control_suppressions": {
    "shared-accounts-global-iam": {"control_ids": ["IAM.1"], "account_names": SHARED, "disabled_reason": "home us-east-1"},
    "shared-accounts-home-trail": {"control_ids": ["KMS.1"], "account_names": SHARED, "disabled_reason": "home us-east-1"}}}
ORG_REGIONS = {"ue1": "us-east-1", "ue2": "us-east-2", "ew1": "eu-west-1", "ec1": "eu-central-1"}
# Each component's `defaults` abstract.
ORG_DEFAULTS = {
    "aws-guardduty": dict(
        enabled=True, name="aws-guardduty", delegated_administrator_component_name="aws-guardduty/delegated-administrator",
        admin_delegated=False, auto_enable_organization_members="NEW", finding_publishing_frequency="FIFTEEN_MINUTES",
        s3_protection_enabled=True, kubernetes_audit_logs_enabled=True, malware_protection_scan_ec2_ebs_volumes_enabled=True,
        lambda_network_logs_enabled=False, runtime_monitoring_enabled=False, eks_runtime_monitoring_enabled=False,
        create_sns_topic=False, cloudwatch_enabled=False),
    "aws-security-hub": dict(
        enabled=True, name="aws-security-hub", admin_delegated=False, default_standards_enabled=True,
        enabled_standards=[], auto_enable_organization_members=True, finding_aggregator_enabled=False,
        organizations_resource_policy_enabled=False, create_sns_topic=False),
    "aws-inspector2": dict(
        enabled=True, name="aws-inspector2", admin_delegated=False, auto_enable_ec2=True, auto_enable_ecr=True,
        auto_enable_lambda=True, member_association_excludes=[]),
}
# aws-security-hub/delegated-administrator-us; standby-suppressions (a sample of its automation rules).
HUB_US = dict(finding_aggregator_enabled=True, finding_aggregation_region="us-east-1",
              finding_aggregator_linking_mode="SPECIFIED_REGIONS", finding_aggregator_regions=["us-east-2"])
STANDBY = {"disabled_control_finding_reasons": {"IAM.1": {
    "control_id": "IAM.1", "reason_code": "GLOBAL_IAM", "disabled_reason": "Not a home region"}}}


def org_instance(component, account, region, deps=(), account_map=None, **variables):
    eu = region.startswith("eu-")
    spec = instance(region=region, compliance=EU if eu else US, deps=deps, tenant="fnx", account_map_enabled=False,
                    account_map=account_map or STATIC_MAP, delegated_administrator_account_name="fnx-security",
                    **{**ORG_DEFAULTS.get(component, {}), **variables})
    spec["component"] = component
    spec["metadata"] = {"component": component}
    spec["settings"].update(environment={"account": account, "account_id": ORG_IDS[account]},
                            context={"tenant": "fnx", "stage": account}, static_account_map=STATIC_MAP)
    return spec


def org_services_stacks():
    """The simulated fnx-<r>-security and fnx-<r>-root stacks of E5c4-E5c6, plus prod and prod-eu workloads."""
    stacks = {}
    for code, region in ORG_REGIONS.items():
        eu, security, root = region.startswith("eu-"), f"fnx-{code}-security", f"fnx-{code}-root"
        standby = STANDBY if code in ("ue2", "ec1") else {}
        us_org = {} if eu else {"account_map": US_MAP}

        def on_root(component):
            return [{"component": f"{component}/root", "stack": root}]

        stacks[security] = stack(**{
            "aws-guardduty/delegated-administrator": org_instance("aws-guardduty", "security", region),
            "aws-guardduty/org-settings": org_instance("aws-guardduty", "security", region, on_root("aws-guardduty"),
                                                       admin_delegated=True, **us_org),
            "aws-security-hub/delegated-administrator": org_instance(
                "aws-security-hub", "security", region, **({} if eu else HUB_US)),
            # CP creates the suppression automation rules only with create_org_configuration (step 3).
            "aws-security-hub/org-settings": org_instance("aws-security-hub", "security", region,
                                                          on_root("aws-security-hub"), admin_delegated=True, **us_org,
                                                          **standby, **(copy.deepcopy(EU_SHARED) if code == "ew1" else {})),
            "aws-inspector2/org-settings": org_instance(
                "aws-inspector2", "security", region, on_root("aws-inspector2"), admin_delegated=True,
                member_association_excludes=[] if eu else [ORG_IDS["prod-eu"]]),
        })
        stacks[root] = stack(**{
            f"{c}/root": org_instance(c, "root", region, [{"component": f"{c}/delegated-administrator", "stack": security}]
                                      if c != "aws-inspector2" else [],
                                      **({"organizations_resource_policy_enabled": True}
                                         if c == "aws-security-hub" and code == "ue1" else {}))
            for c in ("aws-guardduty", "aws-security-hub", "aws-inspector2")
        })
    stacks["fnx-ue1-prod"] = stack(vpc=org_instance("vpc", "prod", "us-east-1"))
    stacks["fnx-ew1-prod"] = stack(vpc=org_instance("vpc", "prod-eu", "eu-west-1"))
    return stacks


class OrgServicesTest(unittest.TestCase):
    """GuardDuty, Security Hub, Inspector (ORG_SERVICES): members and aggregation kept in their residency."""

    def org(self, stacks):
        return [e for e in residency.check(stacks) if "aws-" in e]

    @staticmethod
    def instances_map(stack_name, name):
        return org_services_stacks()[stack_name]["components"]["terraform"][name]["vars"]["account_map"]

    def test_simulated_e5c_slices_pass(self):
        self.assertEqual(residency.check(org_services_stacks()), [])

    def test_us_hub_aggregating_all_or_eu_regions_fails(self):
        for hub, fragment in (
            ({"finding_aggregator_linking_mode": "ALL_REGIONS"}, "finding_aggregator_linking_mode 'ALL_REGIONS'"),
            ({"finding_aggregator_linking_mode": None}, "finding_aggregator_linking_mode None"),
            ({"finding_aggregator_linking_mode": "ALL_REGIONS_EXCEPT_SPECIFIED"}, "ALL_REGIONS_EXCEPT_SPECIFIED"),
            ({"finding_aggregator_regions": ["us-east-2", "eu-west-1"]}, "links 'eu-west-1'"),
            ({"finding_aggregator_regions": []}, "needs a non-empty list"),
        ):
            with self.subTest(hub=hub):
                stacks = org_services_stacks()
                stacks["fnx-ue1-security"]["components"]["terraform"]["aws-security-hub/delegated-administrator"][
                    "vars"].update(hub)
                self.assertEqual(len(self.org(stacks)), 1, self.org(stacks))
                self.assertIn("fnx-ue1-security: aws-security-hub/delegated-administrator", self.org(stacks)[0])
                self.assertIn(fragment, self.org(stacks)[0])

    def test_unset_linking_mode_is_cp_all_regions(self):
        stacks = org_services_stacks()
        stacks["fnx-ue1-security"]["components"]["terraform"]["aws-security-hub/delegated-administrator"][
            "vars"].pop("finding_aggregator_linking_mode")
        self.assertEqual(len(self.org(stacks)), 1)
        self.assertIn("'ALL_REGIONS'", self.org(stacks)[0])

    def test_only_the_aggregating_instance_is_judged(self):
        # ue2's hub (aggregation region us-east-1), org-settings and a disabled aggregator create none.
        stacks = org_services_stacks()
        for name, stack_name in (("aws-security-hub/delegated-administrator", "fnx-ue2-security"),
                                 ("aws-security-hub/org-settings", "fnx-ue1-security")):
            stacks[stack_name]["components"]["terraform"][name]["vars"]["finding_aggregator_linking_mode"] = "ALL_REGIONS"
        self.assertEqual(self.org(stacks), [])
        hub = stacks["fnx-ue1-security"]["components"]["terraform"]["aws-security-hub/delegated-administrator"]
        hub["vars"].update(finding_aggregator_linking_mode="ALL_REGIONS", finding_aggregator_enabled=False)
        self.assertEqual(self.org(stacks), [])

    def test_eu_hub_never_aggregates(self):
        stacks = org_services_stacks()
        stacks["fnx-ew1-security"]["components"]["terraform"]["aws-security-hub/delegated-administrator"]["vars"].update(
            finding_aggregator_enabled=True, finding_aggregation_region="eu-west-1",
            finding_aggregator_linking_mode="SPECIFIED_REGIONS", finding_aggregator_regions=["eu-central-1"])
        self.assertEqual(self.org(stacks), [
            "fnx-ew1-security: aws-security-hub/delegated-administrator creates a Security Hub finding aggregator in a "
            "GDPR-scoped stack: EU hubs are not aggregated (set finding_aggregator_enabled false)"])
        # Aggregating into us-east-1 is also a non-eu region in a GDPR-scoped stack.
        stacks["fnx-ew1-security"]["components"]["terraform"]["aws-security-hub/delegated-administrator"]["vars"].update(
            finding_aggregation_region="us-east-1")
        self.assertEqual(self.org(stacks), [
            "fnx-ew1-security: aws-security-hub/delegated-administrator vars.finding_aggregation_region is 'us-east-1', "
            f"{OUTSIDE}"])

    def suppressions(self, stacks, stack_name="fnx-ew1-security"):
        return stacks[stack_name]["components"]["terraform"]["aws-security-hub/org-settings"]["vars"][
            "account_scoped_control_suppressions"]

    def test_account_scoped_suppressions_never_name_a_gdpr_account(self):
        # Review SF-2: prod-eu's home is eu-west-1, so its findings there must stay.
        stacks = org_services_stacks()
        self.suppressions(stacks)["shared-accounts-global-iam"]["account_names"] = SHARED + ["fnx-prod-eu"]
        self.assertEqual(self.org(stacks), [
            "fnx-ew1-security: aws-security-hub/org-settings account_scoped_control_suppressions.shared-accounts-global-iam "
            "names fnx-prod-eu, an account whose stacks are all GDPR-scoped: its findings in its own home region must stay"])

    def test_account_scoped_suppressions_only_in_a_gdpr_stack(self):
        stacks = org_services_stacks()
        for stack_name in ("fnx-ue1-security", "fnx-ue2-security"):
            stacks[stack_name]["components"]["terraform"]["aws-security-hub/org-settings"]["vars"].update(copy.deepcopy(EU_SHARED))
        errs = self.org(stacks)
        self.assertEqual(len(errs), 2, errs)
        for stack_name, err in zip(("fnx-ue1-security", "fnx-ue2-security"), errs):
            self.assertTrue(err.startswith(f"{stack_name}: aws-security-hub/org-settings sets "
                                           "account_scoped_control_suppressions outside the GDPR scope"), err)

    def test_account_scoped_suppressions_cover_exactly_the_shared_accounts(self):
        # Review SF-3: one shared account missing, or a name not in the map, both fail.
        for names in (SHARED[1:], SHARED + ["fnx-sandbox"]):
            with self.subTest(names=names):
                stacks = org_services_stacks()
                self.suppressions(stacks)["shared-accounts-home-trail"]["account_names"] = names
                errs = self.org(stacks)
                self.assertEqual(len(errs), 1, errs)
                self.assertIn("account_scoped_control_suppressions.shared-accounts-home-trail account_names", errs[0])
                self.assertIn("are not the shared accounts (the account map minus ['fnx-prod-eu']", errs[0])

    def test_prod_eu_in_a_us_map_fails(self):
        # Step 1 (delegated-administrator) and root hold the full map: only org-settings makes members.
        self.assertEqual(self.instances_map("fnx-ue2-security", "aws-guardduty/delegated-administrator"), STATIC_MAP)
        for stack_name, name in (("fnx-ue1-security", "aws-guardduty/org-settings"),
                                 ("fnx-ue2-security", "aws-guardduty/org-settings"),
                                 ("fnx-ue1-security", "aws-security-hub/org-settings")):
            with self.subTest(stack=stack_name, name=name):
                stacks = org_services_stacks()
                stacks[stack_name]["components"]["terraform"][name]["vars"]["account_map"] = STATIC_MAP
                self.assertEqual(self.org(stacks), [
                    f"{stack_name}: {name} account_map.full_account_map holds fnx-prod-eu ({ORG_IDS['prod-eu']}), an "
                    "account whose stacks are all GDPR-scoped: it would be a member outside the EU; drop it from the map"])

    def test_prod_eu_id_under_another_key_fails_but_a_shared_placeholder_is_keyed(self):
        stacks = org_services_stacks()
        org = stacks["fnx-ue1-security"]["components"]["terraform"]["aws-guardduty/org-settings"]["vars"]
        org["account_map"] = {**US_MAP, "full_account_map": {**US_MAP["full_account_map"], "fnx-eu": ORG_IDS["prod-eu"]}}
        self.assertEqual(len(self.org(stacks)), 1)
        self.assertIn("holds fnx-eu (", self.org(stacks)[0])
        # Every account on one placeholder ID: IDs cannot be told apart, the fnx-prod-eu key still can.
        stacks = org_services_stacks()
        for stack_ in stacks.values():
            for spec in stack_["components"]["terraform"].values():
                spec["settings"]["environment"]["account_id"] = "123456789012"
        stacks["fnx-ue1-security"]["components"]["terraform"]["aws-guardduty/org-settings"]["vars"][
            "account_map"] = STATIC_MAP
        self.assertEqual(len(self.org(stacks)), 1)
        self.assertIn("holds fnx-prod-eu", self.org(stacks)[0])

    def test_inspector_excludes_prod_eu_by_id(self):
        stacks = org_services_stacks()
        inspector = stacks["fnx-ue1-security"]["components"]["terraform"]["aws-inspector2/org-settings"]["vars"]
        inspector["member_association_excludes"] = ["fnx-prod-eu"]  # names: CP compares IDs (main.tf:6)
        exact = (f"exclude exactly the IDs of the accounts whose stacks are all GDPR-scoped (['{ORG_IDS['prod-eu']}']), "
                 "no other member")
        self.assertEqual(self.org(stacks), [
            f"fnx-ue1-security: aws-inspector2/org-settings member_association_excludes is ['fnx-prod-eu']: {exact}"])
        # A superset (prod excluded too) and an empty list fail the same way.
        for excludes in ([ORG_IDS["prod-eu"], ORG_IDS["prod"]], []):
            inspector["member_association_excludes"] = excludes
            self.assertEqual(len(self.org(stacks)), 1, excludes)
            self.assertIn(exact, self.org(stacks)[0])
        # OQ-IN: org-settings is committed disabled, so it is not judged until it is turned on.
        stacks["fnx-ue1-security"]["components"]["terraform"]["aws-inspector2/org-settings"]["metadata"] = {
            "component": "aws-inspector2", "enabled": False}
        self.assertEqual(self.org(stacks), [])

    def test_us_guardduty_auto_enable_all_fails(self):
        # ALL enrolls every existing account, prod-eu included, whatever the map (review B1).
        stacks = org_services_stacks()
        org = stacks["fnx-ue1-security"]["components"]["terraform"]["aws-guardduty/org-settings"]["vars"]
        for mode, fails in (("ALL", True), ("NEW", False), ("NONE", False), (None, False)):
            with self.subTest(mode=mode):
                if mode is None:
                    org.pop("auto_enable_organization_members", None)  # CP default NEW
                else:
                    org["auto_enable_organization_members"] = mode
                self.assertEqual(self.org(stacks), [
                    "fnx-ue1-security: aws-guardduty/org-settings sets auto_enable_organization_members 'ALL': outside "
                    "the EU only NEW or NONE (ALL enrolls every existing account, the all-GDPR ones included, whatever "
                    "the account_map)"] if fails else [])
        # The EU admin may enroll everyone.
        stacks = org_services_stacks()
        stacks["fnx-ew1-security"]["components"]["terraform"]["aws-guardduty/org-settings"]["vars"][
            "auto_enable_organization_members"] = "ALL"
        self.assertEqual(self.org(stacks), [])

    def test_eu_org_settings_keep_every_gdpr_account(self):
        # Review S1: the US map, or an Inspector exclude, in an EU admin drops prod-eu from its only admin.
        stacks = org_services_stacks()
        eu = stacks["fnx-ew1-security"]["components"]["terraform"]
        eu["aws-guardduty/org-settings"]["vars"]["account_map"] = US_MAP
        eu["aws-inspector2/org-settings"]["vars"]["member_association_excludes"] = [ORG_IDS["prod-eu"]]
        self.assertEqual(self.org(stacks), [
            "fnx-ew1-security: aws-guardduty/org-settings account_map.full_account_map lacks fnx-prod-eu, an account "
            "whose stacks are all GDPR-scoped: its EU admin must make it a member (use the full map)",
            f"fnx-ew1-security: aws-inspector2/org-settings member_association_excludes lists fnx-prod-eu "
            f"({ORG_IDS['prod-eu']}): its EU admin must make it a member"])

    def test_naming_its_own_account_management_does_not_skip_the_member_rule(self):
        # Review L1: the root step is the map's root account only.
        stacks = org_services_stacks()
        org = stacks["fnx-ue1-security"]["components"]["terraform"]["aws-guardduty/org-settings"]["vars"]
        org.update(organization_management_account_name="fnx-security", account_map=STATIC_MAP)
        self.assertEqual(len(self.org(stacks)), 1)
        self.assertIn("holds fnx-prod-eu", self.org(stacks)[0])

    def test_a_drifted_gdpr_account_declaration_fails(self):
        # Review L4: the stacks derive the all-GDPR accounts; GDPR_ONLY_ACCOUNTS must name the same set.
        stacks = org_services_stacks()
        stacks["fnx-ec1-prod"] = stack(vpc=org_instance("vpc", "prod-eu", "eu-central-1"))
        self.assertEqual(self.org(stacks), [])
        # The prod account's only stack moved to the EU: it is all-GDPR now, but not declared.
        stacks["fnx-ue1-prod"]["components"]["terraform"]["vpc"]["settings"]["environment"]["account"] = "prod-us"
        stacks["fnx-ew1-prod"]["components"]["terraform"]["vpc"]["settings"]["environment"]["account"] = "prod"
        found = [e for e in residency.check(stacks) if "GDPR_ONLY_ACCOUNTS" in e]
        self.assertEqual(found, ["the accounts whose stacks are all GDPR-scoped are ['prod', 'prod-eu'], not "
                                 "GDPR_ONLY_ACCOUNTS ['prod-eu']: update the declaration (check-data-residency.py)"])

    def test_a_us_member_map_from_account_map_state_fails(self):
        # (Every root and EU instance of the simulation holds the full map and passes.)
        stacks = org_services_stacks()
        stacks["fnx-ue1-security"]["components"]["terraform"]["aws-guardduty/org-settings"]["vars"][
            "account_map_enabled"] = True
        self.assertEqual(len(self.org(stacks)), 1)
        self.assertIn("sets account_map_enabled", self.org(stacks)[0])

    def test_root_security_dependencies_stay_in_one_residency(self):
        stacks = org_services_stacks()
        stacks["fnx-ew1-root"]["components"]["terraform"]["aws-guardduty/root"]["dependencies"]["components"] = [
            {"component": "aws-guardduty/delegated-administrator", "stack": "fnx-ue1-security"}]
        stacks["fnx-ue1-security"]["components"]["terraform"]["aws-guardduty/org-settings"]["dependencies"][
            "components"] = [{"component": "aws-guardduty/root", "stack": "fnx-ew1-root"}]
        self.assertEqual(residency.check(stacks), [
            "fnx-ew1-root: aws-guardduty/root depends on aws-guardduty/delegated-administrator in fnx-ue1-security, "
            "which is not GDPR-scoped",
            "fnx-ue1-security: aws-guardduty/org-settings depends on aws-guardduty/root in fnx-ew1-root, which is "
            "GDPR-scoped: EU data may not be read outside the EU"])


if __name__ == "__main__":
    unittest.main()

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
    """A shared account's eu-west-1 recorder: its collector is the US home stack's (OQ-A)."""
    return archived("aws-config", "ew1", account=account, global_resource_collector_region="us-east-1",
                    iam_role_arn=f"arn:aws:iam::123456789012:role/fnx-ue1-{account}-aws-config-config", **extra_vars)


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
                "aws-config": archived("aws-config", "ue1", "us-east-1", US, account="root"),
            }),
        }), [])

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

    def aggregator_stacks(self, delegated):
        """US security aggregator, a US account (prod, 111) and an all-GDPR account (prod-eu, 222)."""
        return {
            "fnx-ue1-security": stack(**{"aws-config": archived(
                "aws-config", "ue1", "us-east-1", US, account="security", account_id="333333333333",
                central_resource_collector_account="fnx-security", delegated_accounts=delegated)}),
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

    def test_hand_written_and_disabled_trails_are_not_checked(self):
        hand_written = instance("us-east-1", US, s3_bucket_name="fnx-trail")
        hand_written["metadata"] = {"component": "cloudtrail"}
        disabled = archived("aws-cloudtrail", "ew1", "us-east-1", US, deps=[])
        disabled["metadata"]["enabled"] = False
        self.assertEqual(self.check(**{"fnx-ue1-prod": stack(**{"cloudtrail/main": hand_written,
                                                                 "cloudtrail": disabled})}), [])


if __name__ == "__main__":
    unittest.main()

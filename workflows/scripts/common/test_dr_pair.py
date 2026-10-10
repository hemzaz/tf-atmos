"""Tests for dr-pair.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import contextlib
import copy
import importlib.util
import io
import json
import pathlib
import sys
import unittest
from unittest import mock

_spec = importlib.util.spec_from_file_location("dr_pair", pathlib.Path(__file__).with_name("dr-pair.py"))
dr_pair = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dr_pair)

PRIMARY_SIZES = {"workers": (3, 6, 12), "monitoring": (2, 3, 4), "memory-optimized": (2, 3, 6)}
WARM_SIZES = {"workers": (2, 2, 12), "monitoring": (0, 0, 4), "memory-optimized": (0, 0, 6)}


def instance(env, region, settings, **variables):
    return {"settings": settings, "vars": {"region": region, "tags": {"Environment": env}, **variables}, "metadata": {}}


def node_groups(groups):
    return {g: {"min_group_size": a, "desired_group_size": b, "max_group_size": c} for g, (a, b, c) in groups.items()}


def prod_pair(primary_env, primary_region, standby_env, standby_region, tfstate, relay=None):
    """A primary and its standby as describe stacks returns them (--sections settings,vars,metadata)."""
    p_settings = {"context": {"stage": "prod"}, "tfstate": tfstate}
    s_settings = {**p_settings, "dr": {"standby_of": f"fnx-{primary_env}-prod"}}
    api = {"health_check_alarm_relay_regions": relay} if relay else {
        "health_check_alarm_actions": [f"arn:aws:sns:us-east-1:123456789012:{primary_env}-main-alarms"]}
    primary = {
        "vpc/main": instance(primary_env, primary_region, p_settings),
        "backup/main": instance(primary_env, primary_region, p_settings,
                                enable_cross_region_backup=True, replica_region=standby_region),
        "kms/main": instance(primary_env, primary_region, p_settings,
                             replica_alias_names={standby_region: f"{standby_env}-main"}),
        "rds/main": instance(primary_env, primary_region, p_settings, identifier="prod-main-db", db_name="productionapp"),
        "elasticache/main": instance(primary_env, primary_region, p_settings, cluster_id="prod-cache"),
        "eks/main": instance(primary_env, primary_region, p_settings, name="main", node_groups=node_groups(PRIMARY_SIZES)),
        "apigateway/main": instance(primary_env, primary_region, p_settings, **api),
        "monitoring/main": instance(primary_env, primary_region, p_settings, name="main"),
    }
    standby = {
        "vpc/main": instance(standby_env, standby_region, s_settings),
        "backup/main": instance(standby_env, standby_region, s_settings),
        "rds/main": instance(standby_env, standby_region, s_settings, identifier="prod-main-db", db_name="productionapp"),
        "elasticache/main": instance(standby_env, standby_region, s_settings, cluster_id="prod-cache"),
        "eks/main": instance(standby_env, standby_region, s_settings, name="main", node_groups=node_groups(WARM_SIZES)),
        "lambda/cognito-user-migration": instance(standby_env, standby_region, s_settings,
                                                  function_name="cognito-user-migration"),
        "monitoring/main": instance(standby_env, standby_region, s_settings, name="main"),
    }
    return {
        f"fnx-{primary_env}-prod": {"components": {"terraform": primary}},
        f"fnx-{standby_env}-prod": {"components": {"terraform": standby}},
    }


def root(env, region, replicated=True):
    settings = {"context": {"stage": "root"}}
    backend = instance(env, region, settings, s3_replication_enabled=replicated)
    return {f"fnx-{env}-root": {"components": {"terraform": {"backend/main": backend, "vpc/main": instance(env, region, settings)}}}}


US_STATE = {"region": "us-east-1", "replica_region": "us-east-2", "bucket": "fnx-terraform-state", "stack": "fnx-ue1-root"}
EU_STATE = {"region": "eu-west-1", "replica_region": "eu-central-1", "bucket": "fnx-ew1-terraform-state", "stack": "fnx-ew1-root"}


def today():
    """The shape of today's DR stacks: the US and EU pairs, their backends, and dev."""
    stacks = {}
    stacks.update(prod_pair("ue1", "us-east-1", "ue2", "us-east-2", US_STATE))
    stacks.update(prod_pair("ew1", "eu-west-1", "ec1", "eu-central-1", EU_STATE, relay=["eu-west-1", "eu-central-1"]))
    stacks.update(root("ue1", "us-east-1"))
    stacks.update(root("ew1", "eu-west-1"))
    dev = {"vpc/main": instance("ue1", "us-east-1", {"context": {"stage": "dev"}, "tfstate": US_STATE}),
           "backup/main": instance("ue1", "us-east-1", {"context": {"stage": "dev"}})}
    stacks["fnx-ue1-dev"] = {"components": {"terraform": dev}}
    return stacks


class UsPairTest(unittest.TestCase):
    def test_us_facts_equal_the_former_hard_coded_runbook(self):
        facts = dr_pair.pair_facts(today(), "fnx-ue1-prod")
        self.assertEqual(facts["standby"], "fnx-ue2-prod")
        self.assertEqual(facts["standby_region"], "us-east-2")
        self.assertEqual(facts["db_instance"], "ue2-prod-main-db")
        self.assertEqual(facts["primary_db_instance"], "ue1-prod-main-db")
        self.assertEqual(facts["db_name"], "productionapp")
        self.assertEqual(facts["cache"], "ue2-prod-cache")
        self.assertEqual(facts["primary_cache"], "ue1-prod-cache")
        self.assertEqual(facts["cluster"], "ue2-main")
        self.assertEqual(facts["kms_alias"], "alias/ue2-main")
        self.assertEqual(facts["user_migration"], "ue2-cognito-user-migration")
        self.assertEqual(facts["health_check_alarm"], {"relayed": False, "topics": ["ue1-main-alarms"]})
        self.assertEqual(facts["state"]["replica_bucket"], "fnx-terraform-state-replica")
        self.assertEqual(facts["state"]["replica_region"], "us-east-2")


class EuPairTest(unittest.TestCase):
    def test_eu_facts(self):
        facts = dr_pair.pair_facts(today(), "fnx-ew1-prod")
        self.assertEqual(facts["standby"], "fnx-ec1-prod")
        self.assertEqual(facts["primary_region"], "eu-west-1")
        self.assertEqual(facts["standby_region"], "eu-central-1")
        self.assertEqual(facts["db_instance"], "ec1-prod-main-db")
        self.assertEqual(facts["cache"], "ec1-prod-cache")
        self.assertEqual(facts["primary_cache"], "ew1-prod-cache")
        self.assertEqual(facts["cluster"], "ec1-main")
        self.assertEqual(facts["kms_alias"], "alias/ec1-main")
        self.assertEqual(facts["user_migration"], "ec1-cognito-user-migration")
        self.assertEqual(facts["backup_replica_vault"], "ew1-backup-replica")
        self.assertEqual(facts["backup_replica_region"], "eu-central-1")
        self.assertEqual(facts["primary_node_groups"]["workers"], [3, 6, 12])
        self.assertEqual(facts["standby_node_groups"]["workers"], [2, 2, 12])

    def test_eu_health_check_alarm_is_relayed_to_both_eu_topics(self):
        facts = dr_pair.pair_facts(today(), "fnx-ew1-prod")
        self.assertEqual(facts["health_check_alarm"], {"relayed": True, "topics": ["ew1-main-alarms", "ec1-main-alarms"]})

    def test_eu_state_replica_is_in_the_eu(self):
        state = dr_pair.pair_facts(today(), "fnx-ew1-prod")["state"]
        self.assertEqual(state, {
            "bucket": "fnx-ew1-terraform-state", "region": "eu-west-1", "backend_stack": "fnx-ew1-root",
            "replicated": True, "replica_bucket": "fnx-ew1-terraform-state-replica", "replica_region": "eu-central-1"})

    def test_a_backend_without_replication_reports_no_replica(self):
        stacks = today()
        stacks["fnx-ew1-root"]["components"]["terraform"]["backend/main"]["vars"]["s3_replication_enabled"] = False
        state = dr_pair.pair_facts(stacks, "fnx-ew1-prod")["state"]
        self.assertFalse(state["replicated"])
        self.assertIsNone(state["replica_bucket"])
        self.assertIsNone(state["replica_region"])

    def test_an_eu_pair_naming_a_non_eu_region_is_refused(self):
        stacks = today()
        stacks["fnx-ew1-prod"]["components"]["terraform"]["backup/main"]["vars"]["replica_region"] = "us-east-2"
        with self.assertRaisesRegex(ValueError, "backup copy is in us-east-2.*GDPR"):
            dr_pair.pair_facts(stacks, "fnx-ew1-prod")
        stacks = today()
        for config in (stacks["fnx-ew1-prod"], stacks["fnx-ec1-prod"]):
            for spec in config["components"]["terraform"].values():
                spec["settings"]["tfstate"] = dict(EU_STATE, replica_region="us-east-2")
        with self.assertRaisesRegex(ValueError, "state replica is in us-east-2"):
            dr_pair.pair_facts(stacks, "fnx-ew1-prod")


class UnsupportedStackTest(unittest.TestCase):
    def test_a_standby_dev_or_unknown_stack_is_refused(self):
        for stack in ("fnx-ue2-prod", "fnx-ec1-prod", "fnx-ue1-dev", "fnx-ue1-root"):
            with self.assertRaisesRegex(ValueError, f"no stack sets settings.dr.standby_of: {stack}"):
                dr_pair.pair_facts(today(), stack)
        with self.assertRaisesRegex(ValueError, "Unknown stack"):
            dr_pair.pair_facts(today(), "fnx-xx1-prod")

    def test_the_refusal_lists_the_supported_pairs(self):
        with self.assertRaises(ValueError) as caught:
            dr_pair.pair_facts(today(), "fnx-ue1-dev")
        self.assertIn("fnx-ew1-prod -> fnx-ec1-prod, fnx-ue1-prod -> fnx-ue2-prod", str(caught.exception))

    def test_a_standby_missing_a_failover_component_is_refused(self):
        stacks = today()
        del stacks["fnx-ec1-prod"]["components"]["terraform"]["lambda/cognito-user-migration"]
        with self.assertRaisesRegex(ValueError, "missing fnx-ec1-prod lambda/cognito-user-migration"):
            dr_pair.pair_facts(stacks, "fnx-ew1-prod")

    def test_two_standbys_are_refused(self):
        stacks = today()
        stacks["fnx-ec2-prod"] = copy.deepcopy(stacks["fnx-ec1-prod"])
        with self.assertRaisesRegex(ValueError, "more than one DR standby"):
            dr_pair.pair_facts(stacks, "fnx-ew1-prod")


class DrRegionTest(unittest.TestCase):
    def test_dr_region_of_each_stack(self):
        expected = {
            "fnx-ue1-prod": "us-east-2",     # backup/main replica_region
            "fnx-ue2-prod": "us-east-2",     # a standby: its own region
            "fnx-ew1-prod": "eu-central-1",  # backup/main replica_region, no env var needed
            "fnx-ec1-prod": "eu-central-1",
            "fnx-ue1-dev": "",               # no copy, no pair
        }
        stacks = today()
        for stack, region in expected.items():
            self.assertEqual(dr_pair.dr_region(stacks, stack), region, stack)

    def test_a_primary_without_backup_copies_falls_back_to_its_standby(self):
        stacks = today()
        stacks["fnx-ew1-prod"]["components"]["terraform"]["backup/main"]["vars"]["enable_cross_region_backup"] = False
        self.assertEqual(dr_pair.dr_region(stacks, "fnx-ew1-prod"), "eu-central-1")
        stacks["fnx-ew1-prod"]["components"]["terraform"]["backup/main"]["metadata"]["enabled"] = False
        self.assertEqual(dr_pair.dr_region(stacks, "fnx-ew1-prod"), "eu-central-1")


class MainTest(unittest.TestCase):
    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(dr_pair, "describe_stacks", return_value=today()), \
                mock.patch.object(sys, "argv", ["dr-pair.py", *argv]), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = dr_pair.main()
        return code, out.getvalue(), err.getvalue()

    def test_facts_are_json(self):
        code, out, _ = self.run_main("fnx-ew1-prod")
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["standby"], "fnx-ec1-prod")

    def test_check_is_silent_on_success_and_explains_a_refusal(self):
        self.assertEqual(self.run_main("--check", "fnx-ue1-prod"), (0, "", ""))
        code, out, err = self.run_main("--check", "fnx-ec1-prod")
        self.assertEqual((code, out), (1, ""))
        self.assertIn("no stack sets settings.dr.standby_of: fnx-ec1-prod", err)

    def test_dr_region(self):
        self.assertEqual(self.run_main("--dr-region", "fnx-ec1-prod"), (0, "eu-central-1\n", ""))


if __name__ == "__main__":
    unittest.main()

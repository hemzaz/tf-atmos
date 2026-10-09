"""Tests for check-data-residency.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import contextlib
import importlib.util
import io
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_data_residency", pathlib.Path(__file__).with_name("check-data-residency.py")
)
residency = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(residency)

EU = "pci-sox-gdpr"
US = "pci-sox"


def instance(region="eu-west-1", compliance=EU, stage="prod", environment="ew1", deps=(), **extra_vars):
    tfstate = "us-east-1" if region.startswith("us-") else region
    return {
        "metadata": {},
        "vars": {"region": region, "tags": {"Compliance": compliance}, **extra_vars},
        "settings": {
            "context": {"tenant": "fnx", "environment": environment, "stage": stage},
            "tfstate": {"region": tfstate, "replica_region": "eu-central-1" if tfstate.startswith("eu-") else "us-east-2"},
        },
        "dependencies": {"components": list(deps)},
        "backend_type": "s3",
        "backend": {"region": tfstate},
    }


def stack(**components):
    return {"components": {"terraform": components}}


def eu_stack(**components):
    return stack(**{"vpc": instance(), **components})


def us_stack(compliance=US):
    return stack(vpc=instance(region="us-east-1", compliance=compliance, environment="ue1"))


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
        self.assertEqual(
            residency.check(stacks),
            ["fnx-ew1-prod: kms/main vars.replica_regions is 'us-east-1', outside the EU, in a GDPR-scoped stack"],
        )

    def test_nested_region_and_us_state_fail(self):
        eu = instance(backup={"copy": {"destination_region": "us-east-2"}})
        eu["settings"]["tfstate"]["replica_region"] = "us-east-2"
        errors = residency.check({"fnx-ew1-prod": stack(**{"backup/main": eu})})
        self.assertEqual(len(errors), 2)
        self.assertIn("vars.backup.copy.destination_region is 'us-east-2'", errors[0])
        self.assertIn("settings.tfstate.replica_region is 'us-east-2'", errors[1])

    def test_dependency_on_us_stack_fails(self):
        stacks = {
            "fnx-ew1-prod": eu_stack(app=instance(deps=[{"component": "vpc", "stack": "fnx-ue1-prod"}])),
            "fnx-ue1-prod": us_stack(),
        }
        self.assertEqual(
            residency.check(stacks),
            ["fnx-ew1-prod: app depends on vpc in fnx-ue1-prod, which is not GDPR-scoped"],
        )

    def test_depends_on_by_context_resolves(self):
        app = instance()
        app["settings"]["depends_on"] = {"1": {"component": "vpc", "environment": "ue1"}}
        stacks = {"fnx-ew1-prod": eu_stack(app=app), "fnx-ue1-prod": us_stack()}
        self.assertEqual(
            residency.check(stacks),
            ["fnx-ew1-prod: app depends on vpc in fnx-ue1-prod, which is not GDPR-scoped"],
        )
        stacks["fnx-ec1-prod"] = stack(vpc=instance(region="eu-central-1", environment="ec1"))
        app["settings"]["depends_on"] = {"1": {"component": "vpc", "environment": "ec1"}}
        self.assertEqual(residency.check(stacks), [])
        app["settings"]["depends_on"] = {"1": {"component": "vpc", "environment": "uw2"}}
        self.assertEqual(
            residency.check(stacks), ["fnx-ew1-prod: app depends on vpc, whose stack does not resolve"]
        )

    def test_us_stack_tagged_gdpr_fails(self):
        errors = residency.check({"fnx-ue1-prod": us_stack(compliance=EU)})
        self.assertIn("fnx-ue1-prod: vpc vars.region is 'us-east-1', outside the EU, in a GDPR-scoped stack", errors)
        self.assertIn("fnx-ue1-prod: vpc backend.s3.region is 'us-east-1', outside the EU, in a GDPR-scoped stack",
                      errors)

    def test_exempted_pair_passes_and_only_that_pair(self):
        alarm = instance()
        alarm["vars"]["region"] = "us-east-1"
        stacks = {"fnx-ew1-prod": eu_stack(**{"sns/r53-health": alarm})}
        exemptions = (residency.Exemption("sns/r53-health*", "vars.region", "us-east-1", "R53 metrics"),)
        self.assertEqual(residency.check(stacks, exemptions), [])
        self.assertEqual(len(residency.check(stacks)), 1)
        alarm["vars"]["region"] = "us-west-2"
        self.assertEqual(len(residency.check(stacks, exemptions)), 1)

    def test_disabled_instances_are_skipped(self):
        off = instance(region="us-east-1")
        off["metadata"] = {"enabled": False}
        self.assertEqual(residency.check({"fnx-ew1-prod": eu_stack(off=off)}), [])

    def test_fixture_errors_follow_known_broken(self):
        errors = ["fnx-ue1-fixtures-x: vpc vars.region is 'us-east-1', outside the EU, in a GDPR-scoped stack"]
        original = dict(residency.fixtures.KNOWN_BROKEN_FIXTURES)
        try:
            self.assertEqual(residency.fixtures.fatal(errors, residency.CHECK), errors)
            residency.fixtures.KNOWN_BROKEN_FIXTURES["fnx-ue1-fixtures-x"] = frozenset({residency.CHECK})
            with contextlib.redirect_stdout(io.StringIO()) as out:
                self.assertEqual(residency.fixtures.fatal(errors, residency.CHECK), [])
            self.assertEqual(out.getvalue(), f"KNOWN-BROKEN {errors[0]}\n")
        finally:
            residency.fixtures.KNOWN_BROKEN_FIXTURES.clear()
            residency.fixtures.KNOWN_BROKEN_FIXTURES.update(original)


if __name__ == "__main__":
    unittest.main()

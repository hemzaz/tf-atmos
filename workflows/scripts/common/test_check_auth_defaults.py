"""Tests for check-auth-defaults.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import contextlib
import copy
import importlib.util
import io
import json
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

_spec = importlib.util.spec_from_file_location(
    "check_auth_defaults", pathlib.Path(__file__).with_name("check-auth-defaults.py")
)
auth_defaults = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(auth_defaults)

AUTH = {
    "providers": {"fnx-sso": {"kind": "aws/iam-identity-center", "auto_provision_identities": True}},
    "identities": {"local-aws": {"kind": "aws/emulator", "emulator": "fnx-ue1-local-sandbox/aws"}},
}
CONFIG = {"profiles": {}, "auth": AUTH}


def flag(auth, kind, name, key):
    auth = copy.deepcopy(auth)
    auth[kind].setdefault(name, {})[key] = True
    return auth


def component(auth=AUTH, **metadata):
    return {"metadata": metadata, "atmos_stack_file": "orgs/fnx/dev/us-east-1", "auth": auth}


def stacks(**components):
    components = components or {"vpc/main": component(), "eks/main": component()}
    return {"fnx-ue1-dev": {"components": {"terraform": components}}}


REGION_CONFIG = {
    "auth": {"providers": {"fnx-sso": {"kind": "aws/iam-identity-center", "region": "us-east-1"}}}
}


def region_stacks(region):
    document = stacks()
    document["fnx-gbl-root"] = {
        "components": {
            "terraform": {
                "aws-identity-center": {"metadata": {"component": "aws-identity-center"}, "vars": {"region": region}}
            }
        }
    }
    return document


def run(config, document):
    errors, in_config = auth_defaults.check_config(config)
    return errors + auth_defaults.check_stacks(document, in_config)


class AuthDefaultsTest(unittest.TestCase):
    def test_no_default_passes(self):
        self.assertEqual(run(CONFIG, stacks()), [])

    def test_default_false_passes(self):
        auth = copy.deepcopy(AUTH)
        auth["identities"]["local-aws"]["default"] = False
        self.assertEqual(run({"auth": auth}, stacks(**{"vpc/main": component(auth)})), [])

    def test_atmos_yaml_default_is_reported_once_naming_file_key_and_fix(self):
        auth = flag(AUTH, "identities", "fnx-dev/TerraformApplyAccess", "default")
        errors = run({"auth": auth}, stacks(**{"vpc/main": component(auth), "eks/main": component(auth)}))
        self.assertEqual(len(errors), 1)
        self.assertTrue(errors[0].startswith("atmos.yaml: auth.identities.fnx-dev/TerraformApplyAccess.default: true"))
        self.assertIn("move it to profiles/<role>/atmos.yaml", errors[0])

    def test_required_identity_and_default_provider_fail(self):
        auth = flag(flag(AUTH, "identities", "local-aws", "required"), "providers", "fnx-sso", "default")
        errors = run({"auth": auth}, stacks())
        self.assertEqual(len(errors), 2)
        self.assertIn("auth.providers.fnx-sso.default: true", errors[0])
        self.assertIn("auth.identities.local-aws.required: true", errors[1])

    def test_profiles_default_fails(self):
        errors = run({"profiles": {"default": "devops"}, "auth": AUTH}, stacks())
        self.assertEqual(len(errors), 1)
        self.assertIn("profiles.default is 'devops'", errors[0])
        self.assertIn("ATMOS_PROFILE=<role>", errors[0])

    def test_default_with_profiles_default_names_the_profile_too(self):
        auth = flag(AUTH, "identities", "local-emu", "default")
        errors = run({"profiles": {"default": "devops"}, "auth": auth}, stacks())
        self.assertEqual(len(errors), 2)
        self.assertTrue(errors[1].startswith("atmos.yaml or profiles/devops/atmos.yaml (loaded by profiles.default):"))
        self.assertNotIn("move it to profiles", errors[1])

    def test_provider_region_equal_to_identity_center_stack_passes(self):
        self.assertEqual(auth_defaults.check_region(REGION_CONFIG, region_stacks("us-east-1")), [])

    def test_provider_region_differing_from_identity_center_stack_fails(self):
        errors = auth_defaults.check_region(REGION_CONFIG, region_stacks("eu-west-1"))
        self.assertEqual(len(errors), 1)
        self.assertIn("atmos.yaml: auth.providers.fnx-sso.region is 'us-east-1'", errors[0])
        self.assertIn("aws-identity-center in fnx-gbl-root (aws-identity-center) has vars.region 'eu-west-1'", errors[0])
        self.assertIn("set auth.providers.fnx-sso.region: eu-west-1 in atmos.yaml", errors[0])

    def test_provider_without_identity_center_instance_fails(self):
        errors = auth_defaults.check_region(REGION_CONFIG, stacks())
        self.assertEqual(len(errors), 1)
        self.assertIn("no aws-identity-center instance", errors[0])

    def test_abstract_identity_center_and_no_provider_are_ignored(self):
        abstract = region_stacks("eu-west-1")
        abstract["fnx-gbl-root"]["components"]["terraform"]["aws-identity-center"]["metadata"]["type"] = "abstract"
        self.assertEqual(len(auth_defaults.check_region(REGION_CONFIG, abstract)), 1)  # no real instance left
        self.assertEqual(auth_defaults.check_region({"auth": {}}, region_stacks("eu-west-1")), [])

    def test_stack_level_default_names_the_stack_file(self):
        bad = flag(AUTH, "identities", "fnx-dev/TerraformApplyAccess", "default")
        errors = run(CONFIG, stacks(**{"vpc/main": component(), "eks/main": component(bad)}))
        self.assertEqual(len(errors), 1)
        self.assertTrue(errors[0].startswith("fnx-ue1-dev: auth.identities.fnx-dev/TerraformApplyAccess.default: true"))
        self.assertIn("stacks/orgs/fnx/dev/us-east-1.yaml or a file it imports", errors[0])
        self.assertIn("1 component(s), e.g. eks/main", errors[0])
        self.assertIn("move it to profiles/<role>/atmos.yaml", errors[0])

    def test_every_component_type_is_walked(self):
        bad = flag(AUTH, "identities", "local-aws", "default")
        document = {"fnx-ue1-dev": {"components": {"helmfile": {"app": component(bad)}}}}
        errors = run(CONFIG, document)
        self.assertEqual(len(errors), 1)
        self.assertIn("e.g. helmfile/app", errors[0])

    def test_abstract_instance_is_skipped(self):
        bad = flag(AUTH, "identities", "local-aws", "default")
        self.assertEqual(run(CONFIG, stacks(**{"vpc/defaults": component(bad, type="abstract")})), [])

    def main(self, config, document):
        with tempfile.NamedTemporaryFile("w", suffix=".json") as handle:
            json.dump(config, handle)
            handle.flush()
            out = io.StringIO()
            with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(document))), contextlib.redirect_stdout(out):
                code = auth_defaults.main(["--config", handle.name])
        return code, out.getvalue().splitlines()[-1]

    def test_main_exit_codes(self):
        for config, document, code in (
            (REGION_CONFIG, region_stacks("us-east-1"), 0),
            (REGION_CONFIG, region_stacks("eu-west-1"), 1),
            ({"profiles": {"default": "devops"}}, stacks(), 1),
        ):
            self.assertEqual(self.main(config, document)[0], code)

    def test_summary_names_only_the_checks_that_fired(self):
        _, region_only = self.main(REGION_CONFIG, region_stacks("eu-west-1"))
        self.assertIn("region must be the aws-identity-center stack's", region_only)
        self.assertNotIn("committed default", region_only)
        _, default_only = self.main({"profiles": {"default": "devops"}}, stacks())
        self.assertIn("a committed default breaks CI", default_only)
        self.assertNotIn("region", default_only)
        both = {**REGION_CONFIG, "profiles": {"default": "devops"}}
        _, summary = self.main(both, region_stacks("eu-west-1"))
        self.assertTrue(summary.startswith("2 auth problem(s): a committed default breaks CI"))
        self.assertIn("; the Identity Center provider's region", summary)


if __name__ == "__main__":
    unittest.main()

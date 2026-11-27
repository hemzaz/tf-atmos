"""Tests for check-auth-defaults.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import contextlib
import copy
import importlib.util
import io
import json
import os
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


ROLE_ARN = "arn:aws:iam::000000000000:role/lint"
CI_PROFILE_AUTH = {
    "providers": {"github-oidc": {"kind": "github/oidc", "spec": {"audience": "sts.amazonaws.com"}}},
    "identities": {
        "ci": {
            "kind": "aws/assume-role",
            "via": {"provider": "github-oidc"},
            # what Atmos resolves `!env ATMOS_CI_ROLE_ARN` to under the lint's dummy value
            "principal": {"assume_role": ROLE_ARN, "region": "us-east-1"},
        }
    },
}


def with_profile(config, role=ROLE_ARN):
    """`atmos describe config` with the CI profile merged into atmos.yaml's auth (role: what the env resolves to)."""
    merged = copy.deepcopy(config)
    auth = merged.setdefault("auth", {})
    for kind, entries in copy.deepcopy(CI_PROFILE_AUTH).items():
        auth.setdefault(kind, {}).update(entries)
    auth["identities"]["ci"]["principal"]["assume_role"] = role
    return merged


def check_profile(config, merged, unset=None):
    """check_profile with the env-unset describe defaulting to a clean profile's (an empty role)."""
    unset = unset if unset is not None else with_profile(config, role="")
    return auth_defaults.check_profile(config, merged, unset, ROLE_ARN)


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

    def main(self, config, document, profile_config=None):
        profile_config = profile_config if profile_config is not None else with_profile(config)
        with tempfile.TemporaryDirectory() as tmp:
            paths = []
            for name, content in (
                ("config", config),
                ("profile", profile_config),
                ("unset", with_profile(config, role="")),
            ):
                paths.append(pathlib.Path(tmp, name))
                paths[-1].write_text(json.dumps(content))
            out = io.StringIO()
            with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(document))), contextlib.redirect_stdout(out):
                code = auth_defaults.main(
                    ["--config", str(paths[0]), "--profile-config", str(paths[1]),
                     "--profile-config-unset", str(paths[2]), "--role-arn", ROLE_ARN]
                )
        return code, out.getvalue().splitlines()[-1]

    def test_ci_profile_passes(self):
        self.assertEqual(check_profile(CONFIG, with_profile(CONFIG)), [])

    def test_ci_profile_default_or_required_fails(self):
        for key, flag_kind, name in (
            ("default", "identities", "ci"),
            ("required", "identities", "ci"),
            ("default", "providers", "github-oidc"),
        ):
            merged = with_profile(CONFIG)
            merged["auth"] = flag(merged["auth"], flag_kind, name, key)
            errors = check_profile(CONFIG, merged)
            self.assertEqual(len(errors), 1, errors)
            self.assertTrue(errors[0].endswith(f"atmos.yaml: auth.{flag_kind}.{name}.{key}: true: remove it; CI selects the identity with ATMOS_IDENTITY=ci"), errors[0])

    def test_ci_profile_default_in_atmos_yaml_is_not_blamed_on_the_profile(self):
        base = {"auth": flag(AUTH, "identities", "local-aws", "default")}
        self.assertEqual(check_profile(base, with_profile(base)), [])

    def test_ci_profile_provider_must_be_oidc_with_the_sts_audience(self):
        for change in ({"kind": "aws/iam-identity-center"}, {"spec": {}}, {"spec": {"audience": "other"}}):
            merged = with_profile(CONFIG)
            merged["auth"]["providers"]["github-oidc"].update(change)
            errors = check_profile(CONFIG, merged)
            self.assertEqual(len(errors), 1, errors)
            self.assertIn("kind: github/oidc and spec.audience: sts.amazonaws.com", errors[0])

    def test_ci_profile_identity_must_be_assume_role_via_its_provider(self):
        for change in ({"kind": "aws/user"}, {"via": {"provider": "fnx-sso"}}, {"via": {}}):
            merged = with_profile(CONFIG)
            merged["auth"]["identities"]["ci"].update(change)
            errors = check_profile(CONFIG, merged)
            self.assertEqual(len(errors), 1, errors)
            self.assertIn("kind: aws/assume-role and via.provider", errors[0])

    def test_ci_profile_role_must_come_from_the_env(self):
        for role in ("arn:aws:iam::123456789012:role/fnx-ue1-dev-ci-plan", "", None):
            merged = with_profile(CONFIG)
            merged["auth"]["identities"]["ci"]["principal"]["assume_role"] = role
            errors = check_profile(CONFIG, merged)
            self.assertEqual(len(errors), 1, errors)
            self.assertIn("with no default and no literal ARN", errors[0])

    def test_ci_profile_literal_hidden_as_the_env_default_fails(self):
        hidden = "arn:aws:iam::111111111111:role/x"
        merged = with_profile(CONFIG)  # env set: the default is not used, so it looks clean
        errors = check_profile(CONFIG, merged, with_profile(CONFIG, role=hidden))  # env unset: the literal shows
        self.assertEqual(len(errors), 1, errors)
        self.assertIn(f"to '{hidden}' with it unset", errors[0])
        self.assertIn("with no default and no literal ARN", errors[0])

    def test_ci_profile_role_not_following_the_env_fails_even_when_empty_unset(self):
        errors = check_profile(CONFIG, with_profile(CONFIG, role="arn:aws:iam::1:role/y"))
        self.assertEqual(len(errors), 1, errors)

    def test_ci_profile_editing_an_atmos_yaml_entry_is_told_apart(self):
        for kind, name, key in (("providers", "fnx-sso", "region"), ("identities", "local-aws", "default")):
            merged = with_profile(CONFIG)
            merged["auth"][kind][name] = {**merged["auth"][kind][name], key: "eu-west-1"}
            errors = check_profile(CONFIG, merged)
            self.assertEqual(len(errors), 1, errors)
            self.assertIn(f"auth.{kind}.{name} edits atmos.yaml's: don't change atmos.yaml's", errors[0])

    def test_ci_profile_key_outside_auth_fails(self):
        merged = with_profile(CONFIG)
        merged["profiles"] = {"default": "github"}
        errors = check_profile(CONFIG, merged)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("adds `profiles` outside `auth`", errors[0])

    def test_main_reads_the_expected_role_from_the_env_when_no_flag(self):
        with mock.patch.dict(os.environ, {"ATMOS_CI_ROLE_ARN": ROLE_ARN}), mock.patch.object(
            sys, "stdin", io.StringIO(json.dumps(region_stacks("us-east-1")))
        ), contextlib.redirect_stdout(io.StringIO()) as out, tempfile.TemporaryDirectory() as tmp:
            paths = []
            for name, content in (("a", REGION_CONFIG), ("b", with_profile(REGION_CONFIG)), ("c", with_profile(REGION_CONFIG, role=""))):
                paths.append(pathlib.Path(tmp, name))
                paths[-1].write_text(json.dumps(content))
            args = ["--config", str(paths[0]), "--profile-config", str(paths[1]), "--profile-config-unset", str(paths[2])]
            self.assertEqual(auth_defaults.main(args), 0, out.getvalue())
        with mock.patch.dict(os.environ, {}, clear=True), self.assertRaises(SystemExit):
            auth_defaults.main(args)

    def test_profile_that_adds_nothing_fails(self):
        errors = check_profile(CONFIG, CONFIG)
        self.assertEqual(len(errors), 1)
        self.assertIn("adds no auth provider or no identity", errors[0])

    def test_main_fails_on_a_bad_ci_profile_and_names_it(self):
        merged = with_profile(CONFIG)
        merged["auth"]["providers"]["github-oidc"]["spec"] = {}
        code, summary = self.main(CONFIG, stacks(), merged)
        self.assertEqual(code, 1)
        self.assertIn("the CI profile must be an OIDC provider", summary)

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

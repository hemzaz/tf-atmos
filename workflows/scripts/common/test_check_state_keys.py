"""Tests for check-state-keys.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_state_keys", pathlib.Path(__file__).with_name("check-state-keys.py")
)
check_state_keys = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_state_keys)


def instance(workspace, key_prefix="vpc", stage="prod", backend_type="s3", key="terraform.tfstate", **metadata):
    return {
        "metadata": metadata,
        "backend_type": backend_type,
        "backend": {"workspace_key_prefix": key_prefix, "key": key},
        "workspace": workspace,
        "settings": {"context": {"tenant": "fnx", "stage": stage}},
    }


def stacks_with(**components):
    return {"fnx-prod-production": {"components": {"terraform": components}}}


class CheckStateKeysTest(unittest.TestCase):
    def assert_errors(self, stacks, *fragments):
        errors = check_state_keys.check(stacks)
        self.assertEqual(len(errors), len(fragments), errors)
        for error, fragment in zip(errors, fragments):
            self.assertIn(fragment, error)

    def test_stack_workspace_passes(self):
        self.assert_errors(stacks_with(**{"vpc/main": instance("fnx-prod-production")}))

    def test_derived_instance_workspace_passes(self):
        self.assert_errors(stacks_with(**{"iam/ci": instance("fnx-prod-production-iam-ci", key_prefix="iam")}))

    def test_workspace_of_another_stage_fails(self):
        # A prod instance whose state would land under the non-prod roles' "*/fnx-dev-*"
        self.assert_errors(
            stacks_with(**{"vpc/main": instance("fnx-dev-testenv-01")}),
            "does not start with its stage prefix 'fnx-prod-'",
        )

    def test_workspace_without_stage_prefix_fails(self):
        self.assert_errors(stacks_with(**{"vpc/main": instance("custom")}), "does not start with")

    def test_stage_name_without_separator_fails(self):
        # "fnx-production" is not "fnx-prod-..."; startswith("fnx-prod") alone would pass it
        self.assert_errors(stacks_with(**{"vpc/main": instance("fnx-production")}), "does not start with")

    def test_workspace_with_slash_fails(self):
        self.assert_errors(stacks_with(**{"vpc/main": instance("fnx-prod-x/fnx-dev-y")}), "contains '/'")

    def test_key_prefix_with_slash_fails(self):
        # "a/fnx-dev-x/<prod workspace>/..." would match the non-prod "*/fnx-dev-*"
        self.assert_errors(
            stacks_with(**{"vpc/main": instance("fnx-prod-production", key_prefix="a/fnx-dev-x")}),
            "workspace_key_prefix 'a/fnx-dev-x' contains '/'",
        )

    def test_missing_key_prefix_fails(self):
        self.assert_errors(
            stacks_with(**{"vpc/main": instance("fnx-prod-production", key_prefix="")}), "no backend.workspace_key_prefix"
        )

    def test_default_state_key_passes(self):
        self.assert_errors(stacks_with(**{"vpc/main": instance("fnx-prod-production", key="terraform.tfstate")}))

    def test_state_key_with_slash_fails(self):
        # "vpc/fnx-prod-production/fnx-dev-x/terraform.tfstate" matches the non-prod "*/fnx-dev-*"
        self.assert_errors(
            stacks_with(**{"vpc/main": instance("fnx-prod-production", key="fnx-dev-x/terraform.tfstate")}),
            "backend.key 'fnx-dev-x/terraform.tfstate' is not 'terraform.tfstate' (contains '/')",
        )

    def test_non_default_state_key_fails(self):
        self.assert_errors(
            stacks_with(**{"vpc/main": instance("fnx-prod-production", key="state.tfstate")}),
            "backend.key 'state.tfstate' is not 'terraform.tfstate'",
        )

    def test_missing_state_key_fails(self):
        self.assert_errors(stacks_with(**{"vpc/main": instance("fnx-prod-production", key=None)}), "backend.key None")

    def test_missing_context_fails(self):
        bad = instance("fnx-prod-production")
        bad["settings"] = {}
        self.assert_errors(stacks_with(**{"vpc/main": bad}), "no settings.context")

    def test_non_s3_abstract_and_disabled_instances_are_skipped(self):
        self.assert_errors(stacks_with(**{
            "local": instance("x/y", key_prefix="a/b", backend_type="local", key="a/b"),
            "base": instance("x/y", key_prefix="a/b", type="abstract", key="a/b"),
            "off": instance("x/y", key_prefix="a/b", enabled=False, key="a/b"),
        }))


if __name__ == "__main__":
    unittest.main()

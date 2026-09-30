"""Tests for check-cluster-api-ci.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import pathlib
import tempfile
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_cluster_api_ci", pathlib.Path(__file__).with_name("check-cluster-api-ci.py")
)
check_cluster_api_ci = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_cluster_api_ci)

CLUSTER = {"eks-addons", "external-secrets"}


def instance(component, actions_enabled=None, public=None, **metadata):
    settings = {} if actions_enabled is None else {"github": {"actions_enabled": actions_enabled}}
    vars_ = {} if public is None else {"cluster_endpoint_public_access": public}
    return {"component": component, "metadata": metadata, "settings": settings, "vars": vars_}


def stacks_with(**components):
    return {"fnx-dev-testenv-01": {"components": {"terraform": components}}}


class CheckClusterApiCiTest(unittest.TestCase):
    def assert_errors(self, stacks, *fragments):
        errors = check_cluster_api_ci.check(stacks, CLUSTER)
        self.assertEqual(len(errors), len(fragments), errors)
        for error, fragment in zip(errors, fragments):
            self.assertIn(fragment, error)

    def test_opted_out_instances_pass(self):
        self.assert_errors(stacks_with(**{
            "eks/main": instance("eks", public=False),
            "eks-addons/main": instance("eks-addons", actions_enabled=False),
            "vpc/main": instance("vpc"),
        }))

    def test_instance_left_on_fails(self):
        self.assert_errors(
            stacks_with(**{
                "eks/main": instance("eks"),  # unset = the variable's default, false
                "eks-addons/main": instance("eks-addons"),
                "external-secrets/main": instance("external-secrets", actions_enabled=True),
            }),
            "eks-addons/main (eks-addons)",
            "external-secrets/main (external-secrets)",
        )

    def test_templated_string_false_is_private(self):
        self.assert_errors(
            stacks_with(**{"eks/main": instance("eks", public="false"), "eks-addons/main": instance("eks-addons")}),
            "eks-addons/main",
        )

    def test_public_endpoint_stack_is_not_checked(self):
        self.assert_errors(stacks_with(**{
            "eks/main": instance("eks", public="true"),
            "eks-addons/main": instance("eks-addons"),
        }))

    def test_disabled_and_abstract_are_skipped(self):
        self.assert_errors(stacks_with(**{
            "eks/main": instance("eks"),
            "eks-addons": instance("eks-addons", type="abstract"),
            "eks-addons/off": instance("eks-addons", enabled=False),
            # a disabled private cluster does not make the stack private
            "eks/off": instance("eks", enabled=False),
        }))

    def test_cluster_components_reads_provider_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            for name, body in {
                "eks-addons": 'provider "helm" {\n}\n',
                "external-secrets": '  provider "kubernetes" {\n}\n',
                "vpc": '# provider "kubernetes" is not used here\nprovider "aws" {}\n',
            }.items():
                (root / name).mkdir()
                (root / name / "provider.tf").write_text(body)
            self.assertEqual(check_cluster_api_ci.cluster_components(root), CLUSTER)


if __name__ == "__main__":
    unittest.main()

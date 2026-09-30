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


ADMIN = "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/eu-west-2/AWSReservedSSO_AdministratorAccess_0123456789abcdef"


def admin_eks(arn, stage="dev"):
    eks = instance("eks")
    eks["settings"] = {"context": {"stage": stage}}
    eks["vars"]["map_additional_iam_roles"] = [{"rolearn": arn, "groups": ["system:masters"]}]
    return eks


def with_backend(stacks, **allowed):
    backend = instance("backend")
    backend["vars"]["access_roles"] = {key: {"allowed_principal_arns": arns} for key, arns in allowed.items()}
    return {**stacks, "fnx-core-root": {"components": {"terraform": {"backend/main": backend}}}}


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

    def test_private_stack_without_admin_role_warns_only(self):
        stacks = stacks_with(**{
            "eks/main": instance("eks"),
            "eks-addons/main": instance("eks-addons", actions_enabled=False),
        })
        errors, warnings = check_cluster_api_ci.check_operators(stacks, CLUSTER)
        self.assertEqual(errors, [])
        self.assertEqual(len(warnings), 1, warnings)
        self.assertIn("eks/main has no map_additional_iam_roles", warnings[0])
        self.assertIn("eks-addons/main", warnings[0])

    def test_admin_role_trusted_by_the_stage_write_role_passes(self):
        stacks = with_backend(
            stacks_with(**{
                "eks/main": admin_eks(ADMIN),
                "eks-addons/main": instance("eks-addons", actions_enabled=False),
            }),
            write=[ADMIN],
        )
        self.assertEqual(check_cluster_api_ci.check_operators(stacks, CLUSTER), ([], []))

    def test_admin_role_missing_from_the_stage_write_role_fails(self):
        # Trusted by prod's write role only: dev state is still out of reach.
        stacks = with_backend(
            stacks_with(**{
                "eks/main": admin_eks(ADMIN),
                "eks-addons/main": instance("eks-addons", actions_enabled=False),
            }),
            write=[],
            prod_write=[ADMIN],
        )
        errors, warnings = check_cluster_api_ci.check_operators(stacks, CLUSTER)
        self.assertEqual(warnings, [])
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("access_roles.write", errors[0])

    def test_prod_admin_role_needs_prod_write(self):
        stacks = with_backend(
            {"fnx-prod-production": {"components": {"terraform": {
                "eks/main": admin_eks(ADMIN, stage="prod"),
                "eks-addons/main": instance("eks-addons", actions_enabled=False),
            }}}},
            write=[ADMIN],
        )
        errors, _ = check_cluster_api_ci.check_operators(stacks, CLUSTER)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("access_roles.prod_write", errors[0])

    def test_non_admin_roles_and_stacks_without_in_cluster_components_are_ignored(self):
        viewer = admin_eks(ADMIN)
        viewer["vars"]["map_additional_iam_roles"][0]["groups"] = ["viewers"]
        stacks = stacks_with(**{"eks/main": viewer, "eks-addons/main": instance("eks-addons", actions_enabled=False)})
        errors, warnings = check_cluster_api_ci.check_operators(stacks, CLUSTER)
        self.assertEqual(errors, [])
        self.assertEqual(len(warnings), 1, warnings)
        self.assertEqual(
            check_cluster_api_ci.check_operators(stacks_with(**{"eks/main": instance("eks")}), CLUSTER),
            ([], []),
        )

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

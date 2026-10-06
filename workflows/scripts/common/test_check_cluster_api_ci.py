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
    return {"fnx-ue1-dev": {"components": {"terraform": components}}}


# The sso.amazonaws.com/<region>/ path segment is the IAM Identity Center home
# region, not the stack's; us-east-1 here is only an example.
ADMIN = "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/us-east-1/AWSReservedSSO_AdministratorAccess_0123456789abcdef"


def admin_eks(arn, stage="dev"):
    eks = instance("eks")
    eks["settings"] = {"context": {"stage": stage}}
    eks["vars"]["map_additional_iam_roles"] = [{"rolearn": arn, "groups": ["system:masters"]}]
    return eks


def addon(component, cluster):
    """An opted-out in-cluster instance whose dependencies.components names its eks instance."""
    i = instance(component, actions_enabled=False)
    i["dependencies"] = {"components": [{"component": cluster}, {"component": "kms/main"}]}
    return i


def with_backend(stacks, **allowed):
    backend = instance("backend")
    backend["vars"]["access_roles"] = {key: {"allowed_principal_arns": arns} for key, arns in allowed.items()}
    return {**stacks, "fnx-ue1-core": {"components": {"terraform": {"backend/main": backend}}}}


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

    def test_clusters_without_admin_role_warn_once_per_stack_with_their_own_dependents(self):
        stacks = with_backend(stacks_with(**{
            "eks/main": instance("eks"),
            "eks/data": instance("eks"),
            "eks-addons/main": addon("eks-addons", "eks/main"),
            "external-secrets/main": addon("external-secrets", "eks/main"),
            "eks-addons/data": addon("eks-addons", "eks/data"),
        }))
        errors, warnings = check_cluster_api_ci.check_operators(stacks, CLUSTER)
        self.assertEqual(errors, [])
        self.assertEqual(len(warnings), 1, warnings)
        self.assertIn("eks/data (eks-addons/data); eks/main (eks-addons/main, external-secrets/main)", warnings[0])

    def test_admin_role_trusted_by_the_stage_write_role_passes(self):
        stacks = with_backend(
            stacks_with(**{"eks/main": admin_eks(ADMIN), "eks-addons/main": addon("eks-addons", "eks/main")}),
            write=[ADMIN],
        )
        self.assertEqual(check_cluster_api_ci.check_operators(stacks, CLUSTER), ([], []))

    def test_admin_role_missing_from_the_stage_write_role_fails(self):
        # Trusted by prod's write role only: dev state is still out of reach.
        stacks = with_backend(
            stacks_with(**{"eks/main": admin_eks(ADMIN), "eks-addons/main": addon("eks-addons", "eks/main")}),
            write=[],
            prod_write=[ADMIN],
        )
        errors, warnings = check_cluster_api_ci.check_operators(stacks, CLUSTER)
        self.assertEqual(warnings, [])
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("access_roles.write", errors[0])

    def test_prod_admin_role_needs_prod_write(self):
        stacks = with_backend(
            {"fnx-ue1-prod": {"components": {"terraform": {
                "eks/main": admin_eks(ADMIN, stage="prod"),
                "eks-addons/main": addon("eks-addons", "eks/main"),
            }}}},
            write=[ADMIN],
        )
        errors, _ = check_cluster_api_ci.check_operators(stacks, CLUSTER)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("access_roles.prod_write", errors[0])

    def test_missing_backend_fails_closed(self):
        stacks = stacks_with(**{"eks/main": admin_eks(ADMIN), "eks-addons/main": addon("eks-addons", "eks/main")})
        errors, _ = check_cluster_api_ci.check_operators(stacks, CLUSTER)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("no deployable backend/main", errors[0])
        # A disabled backend/main counts as missing.
        off = with_backend(stacks, write=[ADMIN])
        off["fnx-ue1-core"]["components"]["terraform"]["backend/main"]["metadata"] = {"enabled": False}
        errors, _ = check_cluster_api_ci.check_operators(off, CLUSTER)
        self.assertEqual(len(errors), 1, errors)

    def test_non_admin_roles_and_stacks_without_in_cluster_components_are_ignored(self):
        viewer = admin_eks(ADMIN)
        viewer["vars"]["map_additional_iam_roles"][0]["groups"] = ["viewers"]
        stacks = with_backend(stacks_with(**{"eks/main": viewer, "eks-addons/main": addon("eks-addons", "eks/main")}))
        errors, warnings = check_cluster_api_ci.check_operators(stacks, CLUSTER)
        self.assertEqual(errors, [])
        self.assertEqual(len(warnings), 1, warnings)
        self.assertEqual(
            check_cluster_api_ci.check_operators(stacks_with(**{"eks/main": instance("eks")}), CLUSTER),
            ([], []),
        )

    def test_private_cluster_with_dependents_needs_an_operator_path(self):
        open_sg = instance("eks")
        open_sg["vars"]["allowed_security_group_ids"] = ["!terraform.state ec2/bastion .security_group_id"]
        open_cidr = instance("eks")
        open_cidr["vars"]["allowed_cidr_blocks"] = ["10.0.0.0/16"]
        stacks = stacks_with(**{
            "eks/main": open_sg,
            "eks/data": open_cidr,
            "eks/closed": instance("eks"),
            "eks/unused": instance("eks"),  # no in-cluster dependents: nothing to reach
            "eks/public": instance("eks", public="true"),
            "eks-addons/main": addon("eks-addons", "eks/main"),
            "eks-addons/data": addon("eks-addons", "eks/data"),
            "eks-addons/closed": addon("eks-addons", "eks/closed"),
            "eks-addons/public": addon("eks-addons", "eks/public"),
        })
        errors = check_cluster_api_ci.check_network_paths(stacks, CLUSTER)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("eks/closed has a private endpoint and in-cluster instances (eks-addons/closed)", errors[0])
        # A stack whose clusters are all public is not checked.
        public = stacks_with(**{
            "eks/main": instance("eks", public=True),
            "eks-addons/main": addon("eks-addons", "eks/main"),
        })
        self.assertEqual(check_cluster_api_ci.check_network_paths(public, CLUSTER), [])

    @staticmethod
    def peered_stack():
        """Bastion in vpc/main, eks/main there too, eks/data in vpc/services behind a peering."""
        def vpc(cidr, peer):
            v = instance("vpc")
            v["vars"].update(ipv4_primary_cidr_block=cidr, private_network_acl_peer_cidr_blocks=[peer])
            return v

        bastion = instance("ec2")
        bastion["vars"]["vpc_id"] = "!terraform.state vpc/main .vpc_id"
        peering = instance("network")
        peering["vars"].update(
            requester_vpc_id="!terraform.state vpc/main .vpc_id",
            accepter_vpc_id="!terraform.state vpc/services .vpc_id",
        )
        clusters = {}
        for name, vpc_name in (("eks/main", "vpc/main"), ("eks/data", "vpc/services")):
            eks = instance("eks")
            eks["vars"].update(
                subnet_ids=f"!terraform.state {vpc_name} .private_subnet_ids",
                allowed_security_group_ids=["!terraform.state ec2/bastion .security_group_id"],
            )
            clusters[name] = eks
        return stacks_with(**{
            "vpc/main": vpc("10.0.0.0/16", "10.1.0.0/16"),
            "vpc/services": vpc("10.1.0.0/16", "10.0.0.0/16"),
            "ec2/bastion": bastion,
            "network/vpc-peering": peering,
            **clusters,
            "eks-addons/main": addon("eks-addons", "eks/main"),
            "eks-addons/data": addon("eks-addons", "eks/data"),
        })

    def terraform(self, stacks):
        return stacks["fnx-ue1-dev"]["components"]["terraform"]

    def test_bastion_in_a_peered_vpc_with_open_nacls_passes(self):
        self.assertEqual(check_cluster_api_ci.check_network_paths(self.peered_stack(), CLUSTER), [])

    def test_bastion_in_another_vpc_needs_a_peering(self):
        stacks = self.peered_stack()
        del self.terraform(stacks)["network/vpc-peering"]
        errors = check_cluster_api_ci.check_network_paths(stacks, CLUSTER)
        # Only eks/data: eks/main shares the bastion's vpc.
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("eks/data (in vpc/services) admits ec2/bastion (in vpc/main), but no network instance peers", errors[0])
        # A disabled peering does not count either.
        stacks = self.peered_stack()
        self.terraform(stacks)["network/vpc-peering"]["metadata"] = {"enabled": False}
        self.assertEqual(len(check_cluster_api_ci.check_network_paths(stacks, CLUSTER)), 1)

    def test_bastion_in_another_vpc_needs_both_nacls_to_admit_the_peer(self):
        for vpc, message in (
            ("vpc/main", "vpc/main private_network_acl_peer_cidr_blocks lacks vpc/services (10.1.0.0/16)"),
            ("vpc/services", "vpc/services private_network_acl_peer_cidr_blocks lacks vpc/main (10.0.0.0/16)"),
        ):
            stacks = self.peered_stack()
            self.terraform(stacks)[vpc]["vars"]["private_network_acl_peer_cidr_blocks"] = []
            errors = check_cluster_api_ci.check_network_paths(stacks, CLUSTER)
            self.assertEqual(len(errors), 1, errors)
            self.assertIn(message, errors[0])
            # A vpc whose NACLs are managed elsewhere is not checked.
            self.terraform(stacks)[vpc]["vars"]["manage_network_acls"] = False
            self.assertEqual(check_cluster_api_ci.check_network_paths(stacks, CLUSTER), [])

    # In-vpc runners: the CI path into a private cluster.
    CONTEXT = {"tenant": "fnx", "environment": "ue1", "stage": "dev"}

    def runner_stack(self, admitted=True, labels=("fnx-ue1-dev",), runner_label=None):
        pool = instance("github-runners")
        pool["vars"].update(vpc_id="!terraform.state vpc/main .vpc_id", runner_labels=list(labels))
        eks = instance("eks")
        eks["vars"].update(
            subnet_ids="!terraform.state vpc/main .private_subnet_ids",
            allowed_security_group_ids=["!terraform.state github-runners/main .security_group_id"] if admitted else
            ["!terraform.state ec2/bastion .security_group_id"],
        )
        addon_ = addon("eks-addons", "eks/main")
        github = {"runner": "in-vpc"}
        if runner_label:
            github["runner_label"] = runner_label
        addon_["settings"] = {"github": github, "context": self.CONTEXT}
        return stacks_with(**{
            "vpc/main": instance("vpc"),
            "github-runners/main": pool,
            "eks/main": eks,
            "eks-addons/main": addon_,
        })

    def test_in_vpc_instance_needs_no_opt_out(self):
        self.assert_errors(self.runner_stack())

    def test_in_vpc_runners_admitted_by_the_cluster_pass(self):
        self.assertEqual(check_cluster_api_ci.check_runner_paths(self.runner_stack(), CLUSTER), [])
        self.assertEqual(check_cluster_api_ci.check_network_paths(self.runner_stack(), CLUSTER), [])

    def test_cluster_must_admit_the_runner_pool(self):
        errors = check_cluster_api_ci.check_runner_paths(self.runner_stack(admitted=False), CLUSTER)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("eks/main does not admit them", errors[0])
        self.assertIn("!terraform.state github-runners/main .security_group_id", errors[0])

    def test_label_with_no_pool_fails(self):
        errors = check_cluster_api_ci.check_runner_paths(self.runner_stack(labels=("other",)), CLUSTER)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("labelled 'fnx-ue1-dev', but no deployable github-runners instance", errors[0])

    def test_runner_label_setting_picks_another_pool(self):
        stacks = self.runner_stack(labels=("fnx-ue1-dev-microservices",), runner_label="fnx-ue1-dev-microservices")
        self.assertEqual(check_cluster_api_ci.check_runner_paths(stacks, CLUSTER), [])

    def test_unknown_runner_mode_fails(self):
        stacks = self.runner_stack()
        self.terraform(stacks)["eks-addons/main"]["settings"]["github"]["runner"] = "self-hosted"
        self.assert_errors(stacks, "settings.github.runner is 'self-hosted'")

    def test_runner_pool_in_another_vpc_needs_a_peering(self):
        stacks = self.runner_stack()
        self.terraform(stacks)["github-runners/main"]["vars"]["vpc_id"] = "!terraform.state vpc/services .vpc_id"
        errors = check_cluster_api_ci.check_network_paths(stacks, CLUSTER)
        # No peering, and neither vpc's NACLs admit the other (vpc/services is not even declared).
        self.assertEqual(len(errors), 3, errors)
        self.assertIn("admits github-runners/main (in vpc/services), but no network instance peers", errors[0])

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

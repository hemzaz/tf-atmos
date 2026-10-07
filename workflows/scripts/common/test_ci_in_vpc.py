"""Tests for ci-in-vpc.py (stdlib only): python3 -m unittest workflows/scripts/common/test_ci_in_vpc.py"""
import importlib.util
import pathlib
import tempfile
import unittest

_spec = importlib.util.spec_from_file_location("ci_in_vpc", pathlib.Path(__file__).with_name("ci-in-vpc.py"))
ci_in_vpc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ci_in_vpc)

POOLS = {
    "fnx-ue1-dev": [
        {"label": "fnx-ue1-dev", "pool": "github-runners/main", "asg": "ue1-github-runners",
         "instances": ["eks-addons/main", "external-secrets/main"]},
        {"label": "fnx-ue1-dev-microservices", "pool": "microservices/github-runners",
         "asg": "ue1-microservices-runners", "instances": ["microservices/eks-addons"]},
    ],
    "fnx-ue1-staging": [],
}


class SplitTest(unittest.TestCase):
    def split(self, include):
        calls = []

        def pools_of(stack):
            calls.append(stack)
            return POOLS[stack]

        return (*ci_in_vpc.split(include, pools_of), calls)

    def test_in_vpc_instances_group_per_stack_and_label_the_rest_stay_hosted(self):
        include = [
            {"stack": "fnx-ue1-dev", "component": "vpc/main", "component_path": "vpc"},
            {"stack": "fnx-ue1-dev", "component": "external-secrets/main"},
            {"stack": "fnx-ue1-dev", "component": "eks-addons/main"},
            {"stack": "fnx-ue1-dev", "component": "microservices/eks-addons"},
            {"stack": "fnx-ue1-staging", "component": "eks/main"},
        ]
        hosted, in_vpc, calls = self.split(include)
        self.assertEqual(hosted, [include[0], include[4]])
        self.assertEqual(in_vpc, [
            {"stack": "fnx-ue1-dev", "label": "fnx-ue1-dev", "asg": "ue1-github-runners",
             "components": "eks-addons/main external-secrets/main"},
            {"stack": "fnx-ue1-dev", "label": "fnx-ue1-dev-microservices", "asg": "ue1-microservices-runners",
             "components": "microservices/eks-addons"},
        ])
        self.assertEqual(calls, ["fnx-ue1-dev", "fnx-ue1-staging"], "one --pools call per stack")

    def test_no_in_vpc_instances_leave_the_matrix_unchanged(self):
        include = [{"stack": "fnx-ue1-staging", "component": "eks/main"}]
        hosted, in_vpc, _ = self.split(include)
        self.assertEqual((hosted, in_vpc), (include, []))


class MissingMarkersTest(unittest.TestCase):
    IN_VPC = {"include": [
        {"stack": "fnx-ue1-dev", "label": "fnx-ue1-dev"},
        {"stack": "fnx-ue1-dev", "label": "fnx-ue1-dev-microservices"},
        {"stack": "fnx-ue1-prod", "label": "fnx-ue1-prod"},
    ]}

    def markers(self, *names):
        tmp = pathlib.Path(tempfile.mkdtemp())
        for name in names:
            (tmp / name).mkdir()
            (tmp / name / "sha").write_text("0" * 40)
        return tmp

    def test_a_stack_with_every_in_vpc_marker_is_complete(self):
        markers = self.markers("in-vpc-fnx-ue1-dev--fnx-ue1-dev", "in-vpc-fnx-ue1-dev--fnx-ue1-dev-microservices")
        self.assertEqual(ci_in_vpc.missing("fnx-ue1-dev", self.IN_VPC, markers), [])

    def test_a_failed_in_vpc_deploy_holds_the_stack_marker(self):
        markers = self.markers("in-vpc-fnx-ue1-dev--fnx-ue1-dev")
        self.assertEqual(ci_in_vpc.missing("fnx-ue1-dev", self.IN_VPC, markers), ["fnx-ue1-dev-microservices"])
        self.assertEqual(ci_in_vpc.missing("fnx-ue1-prod", self.IN_VPC, markers), ["fnx-ue1-prod"])

    def test_a_stack_without_in_vpc_deploys_needs_nothing(self):
        self.assertEqual(ci_in_vpc.missing("fnx-ue1-staging", self.IN_VPC, self.markers()), [])
        self.assertEqual(ci_in_vpc.missing("fnx-ue1-staging", {}, self.markers()), [])


if __name__ == "__main__":
    unittest.main()

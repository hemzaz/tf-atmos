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
         "region": "us-east-1", "instances": ["eks-addons/main", "external-secrets/main"]},
        {"label": "fnx-ue1-dev-microservices", "pool": "microservices/github-runners",
         "asg": "ue1-microservices-runners", "region": "us-east-1", "instances": ["microservices/eks-addons"]},
    ],
    "fnx-ue1-staging": [],
    "fnx-ue2-prod": [
        {"label": "fnx-ue2-prod", "pool": "github-runners/main", "asg": "ue2-github-runners",
         "region": "us-east-2", "instances": ["eks-addons/main"]},
    ],
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
            {"stack": "fnx-ue1-dev", "label": "fnx-ue1-dev", "asg": "ue1-github-runners", "region": "us-east-1",
             "components": "eks-addons/main external-secrets/main"},
            {"stack": "fnx-ue1-dev", "label": "fnx-ue1-dev-microservices", "asg": "ue1-microservices-runners",
             "region": "us-east-1", "components": "microservices/eks-addons"},
        ])
        self.assertEqual(calls, ["fnx-ue1-dev", "fnx-ue1-staging"], "one --pools call per stack")

    def test_a_us_east_2_pool_keeps_its_region(self):
        include = [{"stack": "fnx-ue2-prod", "component": "eks-addons/main"},
                   {"stack": "fnx-ue1-dev", "component": "eks-addons/main"}]
        _, in_vpc, _ = self.split(include)
        self.assertEqual({entry["asg"]: entry["region"] for entry in in_vpc},
                         {"ue1-github-runners": "us-east-1", "ue2-github-runners": "us-east-2"})

    def test_no_in_vpc_instances_leave_the_matrix_unchanged(self):
        include = [{"stack": "fnx-ue1-staging", "component": "eks/main"}]
        hosted, in_vpc, _ = self.split(include)
        self.assertEqual((hosted, in_vpc), (include, []))


class InVpcPlansRunTest(unittest.TestCase):
    def test_only_a_push_to_the_default_branch_plans_in_the_vpc(self):
        self.assertTrue(ci_in_vpc.in_vpc_plans_run("push", "refs/heads/master", "master"))
        for event, ref in (
            ("pull_request", "refs/pull/7/merge"),
            ("pull_request", "refs/heads/master"),
            ("merge_group", "refs/heads/gh-readonly-queue/master/pr-7"),
            ("push", "refs/heads/feature"),
            ("pull_request_target", "refs/heads/master"),
        ):
            self.assertFalse(ci_in_vpc.in_vpc_plans_run(event, ref, "master"), (event, ref))

    def run_split(self, event, ref):
        import io
        import json
        import sys
        from unittest import mock
        include = {"include": [{"stack": "fnx-ue1-dev", "component": "eks-addons/main"},
                               {"stack": "fnx-ue1-dev", "component": "vpc/main"}]}
        out = io.StringIO()
        argv = ["ci-in-vpc.py", "split", "--event", event, "--ref", ref, "--default-branch", "master"]
        with mock.patch.object(sys, "argv", argv), mock.patch.object(sys, "stdin", io.StringIO(json.dumps(include))), \
                mock.patch.object(ci_in_vpc, "stack_pools", POOLS.__getitem__), mock.patch.object(sys, "stdout", out):
            self.assertEqual(ci_in_vpc.main(), 0)
        return json.loads(out.getvalue())

    def test_a_pull_request_gets_a_notice_and_no_in_vpc_plan(self):
        result = self.run_split("pull_request", "refs/pull/7/merge")
        self.assertEqual(result["in_vpc"], {"include": []})
        self.assertEqual(result["hosted"]["include"], [{"stack": "fnx-ue1-dev", "component": "vpc/main"}])
        self.assertIn("In-VPC plans run on master only", result["notice"])
        self.assertIn("fnx-ue1-dev eks-addons/main", result["notice"])

    def test_a_push_to_master_plans_in_the_vpc(self):
        result = self.run_split("push", "refs/heads/master")
        self.assertEqual([g["components"] for g in result["in_vpc"]["include"]], ["eks-addons/main"])
        self.assertEqual(result["notice"], "")


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

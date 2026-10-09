"""Tests for ci-components.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import pathlib
import subprocess
import unittest

_spec = importlib.util.spec_from_file_location("ci_components", pathlib.Path(__file__).with_name("ci-components.py"))
ci_components = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ci_components)

STACK = "fnx-ue1-dev"


def instance(*deps, actions_enabled=None, **metadata):
    settings = {} if actions_enabled is None else {"github": {"actions_enabled": actions_enabled}}
    return {
        "metadata": metadata,
        "settings": settings,
        "dependencies": {"components": [d if isinstance(d, dict) else {"component": d} for d in deps]},
    }


class DependencyOrderTest(unittest.TestCase):
    def test_dependencies_come_first_ties_by_name(self):
        instances = {
            "eks/main": instance("vpc/main", "kms/main"),
            "vpc/main": instance("kms/main"),
            "kms/main": instance(),
            "alb/main": instance(),
        }
        self.assertEqual(
            ci_components.dependency_order(instances, STACK), ["alb/main", "kms/main", "vpc/main", "eks/main"]
        )

    def test_cross_stack_missing_and_non_deployable_edges_are_ignored(self):
        instances = {
            "iam/ci": instance({"component": "backend/main", "stack": "fnx-ue1-root"}, "gone/main", "base"),
            "base": instance(type="abstract"),
            "off": instance(enabled=False),
        }
        self.assertEqual(ci_components.dependency_order(instances, STACK), ["iam/ci"])

    def test_cycle_raises(self):
        instances = {"a": instance("b"), "b": instance("a")}
        with self.assertRaisesRegex(ValueError, "cycle"):
            ci_components.dependency_order(instances, STACK)


class SelectTest(unittest.TestCase):
    instances = {
        "eks/main": instance("vpc/main"),
        "vpc/main": instance(),
        "eks-addons/main": instance("eks/main", actions_enabled=False),
        "rds/main": instance("vpc/main", actions_enabled=True),
    }

    def test_all_skips_actions_disabled(self):
        self.assertEqual(
            ci_components.select(self.instances, STACK),
            (["vpc/main", "eks/main", "rds/main"], ["eks-addons/main"]),
        )

    def test_affected_subset_keeps_order(self):
        self.assertEqual(
            ci_components.select(self.instances, STACK, {"rds/main", "eks-addons/main", "vpc/main"}),
            (["vpc/main", "rds/main"], ["eks-addons/main"]),
        )

    def test_only_disabled_affected_runs_nothing(self):
        self.assertEqual(ci_components.select(self.instances, STACK, {"eks-addons/main"}), ([], ["eks-addons/main"]))


def in_vpc(*deps, label=None):
    """An in-cluster instance routed to the in-VPC runners of its stack (or `label`)."""
    i = instance(*deps)
    i["settings"] = {
        "github": {"runner": "in-vpc", **({"runner_label": label} if label else {})},
    }
    return i


def pool(*labels, environment="ue1", var_name=None, region="us-east-1"):
    i = instance(component="github-runners")
    i["vars"] = {"runner_labels": list(labels), "tags": {"Environment": environment}, "region": region,
                 **({"name": var_name} if var_name else {})}
    return i


class RunnerRoutingTest(unittest.TestCase):
    instances = {
        "vpc/main": instance(),
        "github-runners/main": pool("fnx-ue1-dev"),
        "github-runners/ms": pool("ms-label", var_name="microservices-runners"),
        "eks/main": instance("vpc/main"),
        "eks-addons/main": in_vpc("eks/main"),
        "eks-addons/ms": in_vpc("eks/main", label="ms-label"),
        "external-secrets/off": instance("eks/main", actions_enabled=False),
    }

    def test_hosted_runs_everything_but_in_vpc_and_opted_out(self):
        run, skipped = ci_components.select(self.instances, STACK)
        self.assertEqual(run, ["github-runners/main", "github-runners/ms", "vpc/main", "eks/main"])
        self.assertEqual(skipped, ["external-secrets/off"])

    def test_in_vpc_runs_only_its_label(self):
        run, _ = ci_components.select(self.instances, STACK, runner="in-vpc", label="fnx-ue1-dev")
        self.assertEqual(run, ["eks-addons/main"])
        run, _ = ci_components.select(self.instances, STACK, runner="in-vpc", label="ms-label")
        self.assertEqual(run, ["eks-addons/ms"])

    def test_in_vpc_without_label_runs_every_in_vpc_instance(self):
        run, _ = ci_components.select(self.instances, STACK, runner="in-vpc")
        self.assertEqual(run, ["eks-addons/main", "eks-addons/ms"])

    def test_pools_name_each_needed_label_its_pool_and_group(self):
        run, _ = ci_components.select(self.instances, STACK, runner="in-vpc")
        self.assertEqual(ci_components.pools(self.instances, STACK, run), [
            {"label": "fnx-ue1-dev", "pool": "github-runners/main", "asg": "ue1-github-runners",
             "region": "us-east-1", "instances": ["eks-addons/main"]},
            {"label": "ms-label", "pool": "github-runners/ms", "asg": "ue1-microservices-runners",
             "region": "us-east-1", "instances": ["eks-addons/ms"]},
        ])

    def test_a_us_east_2_pool_starts_in_us_east_2(self):
        stack = "fnx-ue2-prod"
        instances = {
            "github-runners/main": pool(stack, environment="ue2", region="us-east-2"),
            "eks/main": instance(),
            "eks-addons/main": in_vpc("eks/main"),
        }
        run, _ = ci_components.select(instances, stack, runner="in-vpc")
        self.assertEqual(ci_components.pools(instances, stack, run), [
            {"label": stack, "pool": "github-runners/main", "asg": "ue2-github-runners",
             "region": "us-east-2", "instances": ["eks-addons/main"]},
        ])

    def test_a_pool_without_a_valid_region_fails(self):
        for region in (None, "", "US-EAST-2", "${region}"):
            instances = dict(self.instances, **{"github-runners/ms": pool("ms-label", region=region)})
            run, _ = ci_components.select(instances, STACK, runner="in-vpc", label="ms-label")
            with self.assertRaisesRegex(LookupError, "github-runners/ms has no valid vars.region"):
                ci_components.pools(instances, STACK, run)

    def test_affected_in_vpc_subset_needs_only_its_pool(self):
        run, _ = ci_components.select(self.instances, STACK, {"eks-addons/ms", "vpc/main"}, runner="in-vpc")
        self.assertEqual([p["label"] for p in ci_components.pools(self.instances, STACK, run)], ["ms-label"])

    def run_main(self, *argv):
        import contextlib
        import io
        import sys
        from unittest import mock

        out, err = io.StringIO(), io.StringIO()
        described = {STACK: {"components": {"terraform": self.instances}}}
        with mock.patch.object(ci_components, "atmos_json", return_value=described), \
                mock.patch.object(sys, "argv", ["ci-components.py", "--stack", STACK, *argv]), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = ci_components.main()
        return code, out.getvalue()

    def test_main_pools_for_one_dispatched_component(self):
        code, out = self.run_main("--pools", "--only", "eks-addons/ms")
        self.assertEqual(code, 0)
        self.assertEqual(out.splitlines(), ['{"asg": "ue1-microservices-runners", "instances": ["eks-addons/ms"], "label": "ms-label", '
                                           '"pool": "github-runners/ms", "region": "us-east-1"}'])

    def test_main_pools_for_a_hosted_component_is_empty(self):
        self.assertEqual(self.run_main("--pools", "--only", "vpc/main"), (0, ""))

    def test_main_lists_in_vpc_instances_of_a_label(self):
        self.assertEqual(self.run_main("--runner", "in-vpc", "--label", "ms-label"), (0, "eks-addons/ms\n"))

    def test_a_label_without_a_pool_fails(self):
        instances = dict(self.instances)
        del instances["github-runners/ms"]
        run, _ = ci_components.select(instances, STACK, runner="in-vpc")
        with self.assertRaisesRegex(LookupError, "registers the label 'ms-label'"):
            ci_components.pools(instances, STACK, run)


class StackInstancesTest(unittest.TestCase):
    def test_known_stack_returns_terraform_instances(self):
        described = {STACK: {"components": {"terraform": {"vpc/main": instance()}}}}
        self.assertEqual(ci_components.stack_instances(STACK, lambda *_: described), {"vpc/main": instance()})

    def test_empty_describe_is_unknown(self):
        with self.assertRaisesRegex(LookupError, "Unknown stack 'nope'"):
            ci_components.stack_instances("nope", lambda *_: {})

    def test_atmos_failure_is_unknown(self):
        def fail(*args):
            raise subprocess.CalledProcessError(1, ["atmos", *args])

        with self.assertRaisesRegex(LookupError, "Unknown stack 'nope'"):
            ci_components.stack_instances("nope", fail)

    def test_main_reports_unknown_stack_as_error(self):
        import contextlib
        import io
        import sys
        from unittest import mock

        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(ci_components, "atmos_json", side_effect=subprocess.CalledProcessError(1, "atmos")), \
                mock.patch.object(sys, "argv", ["ci-components.py", "--stack", "nope"]), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            self.assertEqual(ci_components.main(), 1)
        # stderr: callers capture stdout as the instance list.
        self.assertEqual(out.getvalue(), "")
        self.assertIn("::error::Unknown stack 'nope'", err.getvalue())

    def test_main_reports_cycle_on_stderr(self):
        import contextlib
        import io
        import sys
        from unittest import mock

        described = {STACK: {"components": {"terraform": {"a": instance("b"), "b": instance("a")}}}}
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(ci_components, "atmos_json", return_value=described), \
                mock.patch.object(sys, "argv", ["ci-components.py", "--stack", STACK]), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            self.assertEqual(ci_components.main(), 1)
        self.assertEqual(out.getvalue(), "")
        self.assertIn("::error::fnx-ue1-dev: dependency cycle", err.getvalue())


if __name__ == "__main__":
    unittest.main()

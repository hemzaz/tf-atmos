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
            "iam/ci": instance({"component": "backend/main", "stack": "fnx-ue1-core"}, "gone/main", "base"),
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

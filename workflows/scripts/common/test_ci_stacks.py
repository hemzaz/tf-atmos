"""Tests for ci-stacks.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import contextlib
import importlib.util
import io
import pathlib
import sys
import unittest
from unittest import mock

_spec = importlib.util.spec_from_file_location("ci_stacks", pathlib.Path(__file__).with_name("ci-stacks.py"))
ci_stacks = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ci_stacks)


def stack(stage, *actions_enabled):
    """A describe-stacks entry: one instance per actions_enabled value (None = unset)."""
    terraform = {}
    for i, enabled in enumerate(actions_enabled or (None,)):
        settings = {"context": {"stage": stage}}
        if enabled is not None:
            settings["github"] = {"actions_enabled": enabled}
        terraform[f"c{i}"] = {"settings": settings}
    return {"components": {"terraform": terraform}}


# The shape of today's stacks (atmos describe stacks --sections settings).
TODAY = {
    "fnx-ue1-core": stack("core", False, False),
    "fnx-ue1-dev": stack("dev", None, False),
    "fnx-ue1-fixtures-batch": stack("fixtures", False),
    "fnx-ue1-fixtures-webapp": stack("fixtures", False),
    "fnx-ue1-local-localemu": stack("local", False),
    "fnx-ue1-local-sandbox": stack("local", False),
    "fnx-ue1-prod": stack("prod", None, True, False),
    "fnx-ue1-staging": stack("staging", None, False),
}


class TodayTest(unittest.TestCase):
    def test_ci_stacks_equal_the_former_hard_coded_list(self):
        # terraform-cd.yml ORDER / choice options, disaster-recovery.yml options
        self.assertEqual(
            ci_stacks.ci_stacks(TODAY), ["fnx-ue1-dev", "fnx-ue1-staging", "fnx-ue1-prod"]
        )

    def test_plan_sweep_equals_the_former_default(self):
        # scripts/plan-sweep.sh: the three real stacks, then every fnx-ue1-fixtures-* stack
        self.assertEqual(
            ci_stacks.plan_sweep_stacks(TODAY),
            ["fnx-ue1-dev", "fnx-ue1-staging", "fnx-ue1-prod",
             "fnx-ue1-fixtures-batch", "fnx-ue1-fixtures-webapp"],
        )


class NewStackTest(unittest.TestCase):
    def test_a_new_stack_flows_in_without_edits(self):
        stacks = dict(TODAY, **{"fnx-ew1-prod": stack("prod"), "fnx-ue2-dev": stack("dev")})
        self.assertEqual(
            ci_stacks.ci_stacks(stacks),
            ["fnx-ue1-dev", "fnx-ue2-dev", "fnx-ue1-staging", "fnx-ew1-prod",
             "fnx-ue1-prod"],
        )
        self.assertEqual(ci_stacks.check(stacks, "fnx-ew1-prod"), "")
        self.assertIn("fnx-ew1-prod", ci_stacks.plan_sweep_stacks(stacks))

    def test_a_ci_stack_in_an_unordered_stage_fails(self):
        # CD would otherwise deploy a new qa stage after production.
        stacks = dict(TODAY, **{"fnx-ue1-qa": stack("qa")})
        with self.assertRaisesRegex(ValueError, r"'fnx-ue1-qa' has stage 'qa'.*add it to STAGE_ORDER"):
            ci_stacks.ci_stacks(stacks)
        # plan-sweep only orders its run, so a new stage is swept (after prod, with the fixtures).
        self.assertEqual(
            ci_stacks.plan_sweep_stacks(stacks),
            ["fnx-ue1-dev", "fnx-ue1-staging", "fnx-ue1-prod",
             "fnx-ue1-fixtures-batch", "fnx-ue1-fixtures-webapp", "fnx-ue1-qa"],
        )

    def test_a_ci_disabled_stack_in_an_unordered_stage_is_fine(self):
        self.assertNotIn("fnx-ue1-fixtures-batch", ci_stacks.ci_stacks(TODAY))


class CheckTest(unittest.TestCase):
    def test_ci_stack_passes(self):
        self.assertEqual(ci_stacks.check(TODAY, "fnx-ue1-staging"), "")

    def test_unknown_stack_fails(self):
        self.assertIn("Unknown stack", ci_stacks.check(TODAY, "fnx-dev-typo"))
        self.assertIn("Unknown stack", ci_stacks.check(TODAY, "fnx-ue1-dev\nfnx-ue1-prod"))

    def test_ci_disabled_stacks_fail(self):
        for name in ("fnx-ue1-core", "fnx-ue1-local-sandbox", "fnx-ue1-fixtures-batch"):
            with self.subTest(name=name):
                self.assertIn("actions_enabled: false", ci_stacks.check(TODAY, name))


class HelpersTest(unittest.TestCase):
    def test_a_stack_with_no_instances_is_not_ci_disabled(self):
        self.assertFalse(ci_stacks.ci_disabled({"components": {}}))

    def test_other_stages_sort_after_prod(self):
        stacks = {"b": stack("prod"), "a": stack("fixtures"), "c": stack("dev")}
        self.assertEqual(ci_stacks.ordered(stacks, ["a", "b", "c"]), ["c", "b", "a"])


class NoSingleStageTest(unittest.TestCase):
    empty = {"components": {"terraform": {}}}
    mixed = {"components": {"terraform": {
        "a": {"settings": {"context": {"stage": "dev"}}},
        "b": {"settings": {"context": {"stage": "prod"}}},
    }}}

    def test_both_list_modes_fail(self):
        for bad in (self.empty, self.mixed):
            stacks = dict(TODAY, **{"fnx-odd-odd-01": bad})
            for select in (ci_stacks.ci_stacks, ci_stacks.plan_sweep_stacks):
                with self.subTest(bad=bad, select=select.__name__), \
                        self.assertRaisesRegex(ValueError, "'fnx-odd-odd-01' has no single settings.context.stage"):
                    select(stacks)


class MainStreamsTest(unittest.TestCase):
    """stdout is the stack list only; errors reach stderr, which check_output passes through."""

    def run_main(self, stacks, *argv):
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(ci_stacks, "describe_stacks", lambda: stacks), \
                mock.patch.object(sys, "argv", ["ci-stacks.py", *argv]), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            return ci_stacks.main(), out.getvalue(), err.getvalue()

    def test_list_goes_to_stdout(self):
        self.assertEqual(
            self.run_main(TODAY), (0, "fnx-ue1-dev\nfnx-ue1-staging\nfnx-ue1-prod\n", "")
        )

    def test_refusals_go_to_stderr_only(self):
        cases = (
            (dict(TODAY, **{"fnx-ue1-qa": stack("qa")}), (), "has stage 'qa'"),
            (dict(TODAY, **{"fnx-odd-odd-01": {"components": {"terraform": {}}}}), ("--plan-sweep",),
             "no single settings.context.stage"),
            (TODAY, ("--check", "fnx-typo"), "Unknown stack 'fnx-typo'"),
            (TODAY, ("--check", "fnx-ue1-local-sandbox"), "actions_enabled: false"),
        )
        for stacks, argv, fragment in cases:
            with self.subTest(argv=argv, fragment=fragment):
                rc, out, err = self.run_main(stacks, *argv)
                self.assertEqual((rc, out), (1, ""))
                self.assertTrue(err.startswith("::error::"), err)
                self.assertIn(fragment, err)

    def test_check_echoes_an_accepted_stack_on_stdout(self):
        self.assertEqual(self.run_main(TODAY, "--check", "fnx-ue1-prod"), (0, "fnx-ue1-prod\n", ""))


if __name__ == "__main__":
    unittest.main()

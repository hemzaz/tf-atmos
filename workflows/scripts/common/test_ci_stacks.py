"""Tests for ci-stacks.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import pathlib
import unittest

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
    "fnx-core-root": stack("core", False, False),
    "fnx-dev-testenv-01": stack("dev", None, False),
    "fnx-fixtures-batch": stack("fixtures", False),
    "fnx-fixtures-webapp": stack("fixtures", False),
    "fnx-local-localemu": stack("local", False),
    "fnx-local-sandbox": stack("local", False),
    "fnx-prod-production": stack("prod", None, True, False),
    "fnx-staging-staging-01": stack("staging", None, False),
}


class TodayTest(unittest.TestCase):
    def test_ci_stacks_equal_the_former_hard_coded_list(self):
        # terraform-cd.yml ORDER / choice options, disaster-recovery.yml options
        self.assertEqual(
            ci_stacks.ci_stacks(TODAY), ["fnx-dev-testenv-01", "fnx-staging-staging-01", "fnx-prod-production"]
        )

    def test_plan_sweep_equals_the_former_default(self):
        # scripts/plan-sweep.sh: the three real stacks, then every fnx-fixtures-* stack
        self.assertEqual(
            ci_stacks.plan_sweep_stacks(TODAY),
            ["fnx-dev-testenv-01", "fnx-staging-staging-01", "fnx-prod-production",
             "fnx-fixtures-batch", "fnx-fixtures-webapp"],
        )


class NewStackTest(unittest.TestCase):
    def test_a_new_stack_flows_in_without_edits(self):
        stacks = dict(TODAY, **{"fnx-prod-production-eu": stack("prod"), "fnx-qa-qa-01": stack("qa")})
        self.assertEqual(
            ci_stacks.ci_stacks(stacks),
            ["fnx-dev-testenv-01", "fnx-staging-staging-01", "fnx-prod-production", "fnx-prod-production-eu",
             "fnx-qa-qa-01"],
        )
        self.assertEqual(ci_stacks.check(stacks, "fnx-prod-production-eu"), "")
        self.assertIn("fnx-qa-qa-01", ci_stacks.plan_sweep_stacks(stacks))


class CheckTest(unittest.TestCase):
    def test_ci_stack_passes(self):
        self.assertEqual(ci_stacks.check(TODAY, "fnx-staging-staging-01"), "")

    def test_unknown_stack_fails(self):
        self.assertIn("Unknown stack", ci_stacks.check(TODAY, "fnx-dev-typo"))
        self.assertIn("Unknown stack", ci_stacks.check(TODAY, "fnx-dev-testenv-01\nfnx-prod-production"))

    def test_ci_disabled_stacks_fail(self):
        for name in ("fnx-core-root", "fnx-local-sandbox", "fnx-fixtures-batch"):
            with self.subTest(name=name):
                self.assertIn("actions_enabled: false", ci_stacks.check(TODAY, name))


class HelpersTest(unittest.TestCase):
    def test_a_stack_with_no_instances_is_not_ci_disabled(self):
        self.assertFalse(ci_stacks.ci_disabled({"components": {}}))

    def test_mixed_or_missing_stage_sorts_last(self):
        stacks = {"b": {"components": {"terraform": {}}}, "a": stack("dev"), "c": stack("weird")}
        self.assertEqual(ci_stacks.ordered(stacks, ["b", "c", "a"]), ["a", "b", "c"])


if __name__ == "__main__":
    unittest.main()

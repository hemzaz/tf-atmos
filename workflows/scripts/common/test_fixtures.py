"""Tests for fixtures.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import contextlib
import io
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import fixtures  # noqa: E402


class FixturesTest(unittest.TestCase):
    def setUp(self):
        saved = dict(fixtures.KNOWN_BROKEN_FIXTURES)
        self.addCleanup(lambda: (fixtures.KNOWN_BROKEN_FIXTURES.clear(), fixtures.KNOWN_BROKEN_FIXTURES.update(saved)))
        fixtures.KNOWN_BROKEN_FIXTURES.clear()
        fixtures.KNOWN_BROKEN_FIXTURES.update({
            "fnx-ue1-fixtures-a": fixtures.ALL,
            "fnx-ue1-fixtures-b": frozenset({"check-domains"}),
        })

    def test_known_broken(self):
        self.assertTrue(fixtures.known_broken("fnx-ue1-fixtures-a", "plan-sweep"))
        self.assertTrue(fixtures.known_broken("fnx-ue1-fixtures-b", "check-domains"))
        self.assertFalse(fixtures.known_broken("fnx-ue1-fixtures-b", "plan-sweep"))
        self.assertFalse(fixtures.known_broken("fnx-ue1-dev", "check-domains"))
        self.assertEqual(fixtures.stacks("check-domains"), ["fnx-ue1-fixtures-a", "fnx-ue1-fixtures-b"])
        self.assertEqual(fixtures.stacks("plan-sweep"), ["fnx-ue1-fixtures-a"])

    def test_fatal_keeps_strict_stacks_and_reports_the_rest(self):
        errors = [
            "fnx-ue1-fixtures-a: x is broken",
            "deploy-full-stack.yaml `deploy`: fnx-ue1-fixtures-b: y is in no layer",
            "fnx-ue1-fixtures-b: z is broken",
            "fnx-ue1-dev: w is broken",
        ]
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rest = fixtures.fatal(errors, "check-dependencies")
        self.assertEqual(rest, errors[1:])
        self.assertEqual(out.getvalue(), "KNOWN-BROKEN fnx-ue1-fixtures-a: x is broken\n")
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(fixtures.fatal(errors, "check-domains"), errors[3:])

    def test_plan_sweep_skips_only_all_entries(self):
        self.assertEqual(fixtures.unswept(), ["fnx-ue1-fixtures-a"])
        self.assertNotIn("fnx-ue1-fixtures-b", fixtures.unswept())

    def test_fatal_matches_only_the_stack_the_error_is_about(self):
        # A strict stack's error that merely names a known-broken stack stays fatal.
        errors = [
            "fnx-ue1-dev: x reads y in fnx-ue1-fixtures-a: which does not exist",
            "fnx-ue1-dev: note fnx-ue1-fixtures-a: z",
            "xfnx-ue1-fixtures-a: not the stack",
        ]
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(fixtures.fatal(errors, "plan-sweep"), errors)


class UnguardedTest(unittest.TestCase):
    @staticmethod
    def instance(stage, enabled=None):
        github = {} if enabled is None else {"actions_enabled": enabled}
        return {"settings": {"context": {"stage": stage}, "github": github}}

    def test_fixture_instances_must_opt_out_of_actions(self):
        stacks = {
            "fnx-ue1-fixtures-a": {"components": {"terraform": {
                "ok": self.instance("fixtures", False),
                "unset": self.instance("fixtures"),
                "on": self.instance("fixtures", True),
            }}},
            "fnx-ue1-dev": {"components": {"terraform": {"real": self.instance("dev")}}},
        }
        errors = fixtures.unguarded(stacks)
        self.assertEqual(len(errors), 2, errors)
        self.assertTrue(errors[0].startswith("fnx-ue1-fixtures-a: on is in stage fixtures"))
        self.assertTrue(errors[1].startswith("fnx-ue1-fixtures-a: unset is in stage fixtures"))

    def test_never_relaxed_by_the_allowlist(self):
        # check-dependencies appends unguarded() after fatal(), so a known-broken
        # fixture cannot hide a missing opt-out.
        source = pathlib.Path(__file__).with_name("check-dependencies.py").read_text()
        self.assertIn('fixtures.fatal(errors, "check-dependencies") + fixtures.unguarded(stacks)', source)


class RealEntriesTest(unittest.TestCase):
    def test_every_entry_is_a_fixture_stack(self):
        # A stale or misspelt entry would silently relax nothing.
        root = pathlib.Path(__file__).resolve().parents[3]
        present = {f"fnx-ue1-fixtures-{p.stem}" for p in (root / "stacks/orgs/fnx/fixtures/us-east-1").glob("*.yaml")}
        self.assertTrue(present)
        self.assertLessEqual(set(fixtures.KNOWN_BROKEN_FIXTURES), present)


if __name__ == "__main__":
    unittest.main()

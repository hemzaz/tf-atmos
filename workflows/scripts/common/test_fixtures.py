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
            "fnx-fixtures-a": fixtures.ALL,
            "fnx-fixtures-b": frozenset({"check-domains"}),
        })

    def test_known_broken(self):
        self.assertTrue(fixtures.known_broken("fnx-fixtures-a", "plan-sweep"))
        self.assertTrue(fixtures.known_broken("fnx-fixtures-b", "check-domains"))
        self.assertFalse(fixtures.known_broken("fnx-fixtures-b", "plan-sweep"))
        self.assertFalse(fixtures.known_broken("fnx-dev-testenv-01", "check-domains"))
        self.assertEqual(fixtures.stacks("check-domains"), ["fnx-fixtures-a", "fnx-fixtures-b"])
        self.assertEqual(fixtures.stacks("plan-sweep"), ["fnx-fixtures-a"])

    def test_fatal_keeps_strict_stacks_and_reports_the_rest(self):
        errors = [
            "fnx-fixtures-a: x is broken",
            "deploy-full-stack.yaml `deploy`: fnx-fixtures-b: y is in no layer",
            "fnx-fixtures-b: z is broken",
            "fnx-dev-testenv-01: w is broken",
        ]
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rest = fixtures.fatal(errors, "check-dependencies")
        self.assertEqual(rest, errors[1:])
        self.assertEqual(out.getvalue(), "KNOWN-BROKEN fnx-fixtures-a: x is broken\n")
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(fixtures.fatal(errors, "check-domains"), errors[3:])

    def test_plan_sweep_skips_only_all_entries(self):
        self.assertEqual(fixtures.unswept(), ["fnx-fixtures-a"])
        self.assertNotIn("fnx-fixtures-b", fixtures.unswept())

    def test_fatal_matches_only_the_stack_the_error_is_about(self):
        # A strict stack's error that merely names a known-broken stack stays fatal.
        errors = [
            "fnx-dev-testenv-01: x reads y in fnx-fixtures-a: which does not exist",
            "fnx-dev-testenv-01: note fnx-fixtures-a: z",
            "xfnx-fixtures-a: not the stack",
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
            "fnx-fixtures-a": {"components": {"terraform": {
                "ok": self.instance("fixtures", False),
                "unset": self.instance("fixtures"),
                "on": self.instance("fixtures", True),
            }}},
            "fnx-dev-testenv-01": {"components": {"terraform": {"real": self.instance("dev")}}},
        }
        errors = fixtures.unguarded(stacks)
        self.assertEqual(len(errors), 2, errors)
        self.assertTrue(errors[0].startswith("fnx-fixtures-a: on is in stage fixtures"))
        self.assertTrue(errors[1].startswith("fnx-fixtures-a: unset is in stage fixtures"))

    def test_never_relaxed_by_the_allowlist(self):
        # check-dependencies appends unguarded() after fatal(), so a known-broken
        # fixture cannot hide a missing opt-out.
        source = pathlib.Path(__file__).with_name("check-dependencies.py").read_text()
        self.assertIn('fixtures.fatal(errors, "check-dependencies") + fixtures.unguarded(stacks)', source)


class RealEntriesTest(unittest.TestCase):
    def test_every_entry_is_a_fixture_stack(self):
        # A stale or misspelt entry would silently relax nothing.
        root = pathlib.Path(__file__).resolve().parents[3]
        present = {f"fnx-fixtures-{p.stem}" for p in (root / "stacks/orgs/fnx/fixtures/us-east-1").glob("*.yaml")}
        self.assertTrue(present)
        self.assertLessEqual(set(fixtures.KNOWN_BROKEN_FIXTURES), present)


if __name__ == "__main__":
    unittest.main()

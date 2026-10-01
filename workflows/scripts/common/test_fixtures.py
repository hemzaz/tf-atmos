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


class RealEntriesTest(unittest.TestCase):
    def test_every_entry_is_a_fixture_stack(self):
        # A stale or misspelt entry would silently relax nothing.
        root = pathlib.Path(__file__).resolve().parents[3]
        present = {f"fnx-fixtures-{p.stem}" for p in (root / "stacks/orgs/fnx/fixtures/us-east-1").glob("*.yaml")}
        self.assertTrue(present)
        self.assertLessEqual(set(fixtures.KNOWN_BROKEN_FIXTURES), present)


if __name__ == "__main__":
    unittest.main()

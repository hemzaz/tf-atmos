"""lint.yaml's tflint step must exclude the same stack paths as atmos.yaml, plus the fixtures
(stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
FIXTURES_GLOB = "orgs/fnx/fixtures/**"


def atmos_excluded_paths(text: str) -> list[str]:
    block = re.search(r"^\s*excluded_paths:\s*\n((?:\s+-\s+.*\n)+)", text, re.MULTILINE)
    if block is None:
        raise ValueError("atmos.yaml has no stacks.excluded_paths list")
    return [m.group(1) for m in re.finditer(r"^\s+-\s+[\"']?([^\"'\n]+?)[\"']?\s*$", block.group(1), re.MULTILINE)]


def lint_excluded_paths(text: str) -> list[str]:
    found = re.findall(r"ATMOS_STACKS_EXCLUDED_PATHS='([^']*)'", text)
    if len(found) != 1:
        raise ValueError(f"expected one ATMOS_STACKS_EXCLUDED_PATHS in lint.yaml, found {len(found)}")
    return found[0].split(",")


class LintExcludedPathsTest(unittest.TestCase):
    def test_lint_excludes_atmos_paths_plus_fixtures(self):
        atmos = atmos_excluded_paths((ROOT / "atmos.yaml").read_text())
        lint = lint_excluded_paths((ROOT / "workflows" / "lint.yaml").read_text())
        self.assertTrue(atmos, "atmos.yaml excluded_paths is empty")
        self.assertEqual(lint, atmos + [FIXTURES_GLOB])

    def test_parsers_read_the_expected_shapes(self):
        self.assertEqual(atmos_excluded_paths('  excluded_paths:\n    - "a/**"\n    - b\n  x: 1\n'), ["a/**", "b"])
        self.assertEqual(lint_excluded_paths("ATMOS_STACKS_EXCLUDED_PATHS='a,b' atmos"), ["a", "b"])
        with self.assertRaises(ValueError):
            lint_excluded_paths("nothing")


if __name__ == "__main__":
    unittest.main()

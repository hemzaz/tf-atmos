"""Tests for scripts/check-old-stack-names.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""

import contextlib
import importlib.util
import io
import pathlib
import tempfile
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_old_stack_names",
    pathlib.Path(__file__).resolve().parents[3] / "scripts" / "check-old-stack-names.py",
)
check = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check)


def labels(text):
    return [label for _, label, _ in check.hits(text)]


class HitsTest(unittest.TestCase):
    def test_old_names(self):
        for line in (
            "atmos terraform plan vpc/main -s fnx-dev-testenv-01",
            "STACK=fnx-prod-production",
            "fnx-core-root",
            "fnx-fixtures-batch",
            "fnx-local-sandbox",
            "DEFAULT_STACK=fnx-prod-uw2",
            'Environment = "testenv-01"',
            "cluster staging-01-main",
            "stacks/orgs/fnx/dev/us-east-1/testenv-01/components/globals.yaml",
            "stacks/orgs/fnx/prod/us-east-1/production.yaml",
            "stacks/orgs/fnx/core/us-east-1/root.yaml",
            "stacks/orgs/fnx/fixtures/us-east-1/idpplatform.yaml",
        ):
            with self.subTest(line=line):
                self.assertEqual(len(labels(line)), 1, line)

    def test_current_names_pass(self):
        for line in (
            "atmos terraform plan vpc/main -s fnx-ue1-dev",
            "fnx-ue1-prod fnx-ue2-prod fnx-ew1-prod fnx-ue1-core",
            "fnx-ue1-fixtures-batch fnx-ue1-local-sandbox fnx-ue1-dev-perf",
            "stacks/orgs/fnx/dev/us-east-1.yaml stacks/orgs/fnx/dev/us-east-1/components/globals.yaml",
            "stacks/orgs/fnx/fixtures/us-east-1/idp.yaml",
            "domain_name: dev.fnx.example.com",
            "fnx-sandbox-local-state",
            "staging-main-db staging-1234",
        ):
            with self.subTest(line=line):
                self.assertEqual(labels(line), [], line)

    def test_allow_marker(self):
        self.assertEqual(labels("stale = 'fnx-prod-production'  # old-stack-names: allow"), [])

    def test_one_hit_per_line(self):
        self.assertEqual(len(labels("fnx-dev-testenv-01 stacks/orgs/fnx/dev/us-east-1/testenv-01.yaml")), 1)


class MainTest(unittest.TestCase):
    def run_main(self, files):
        with tempfile.TemporaryDirectory() as root:
            for name, text in files.items():
                path = pathlib.Path(root, name)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = check.main([root])
            return code, out.getvalue()

    def test_hit_fails(self):
        code, out = self.run_main({"docs/a.md": "ok\nrun -s fnx-dev-testenv-01\n"})
        self.assertEqual(code, 1)
        self.assertIn("a.md:2: old stack name order", out)

    def test_clean_passes(self):
        code, _ = self.run_main({"docs/a.md": "run -s fnx-ue1-dev\n"})
        self.assertEqual(code, 0)

    def test_skips_git_terraform_and_self(self):
        code, _ = self.run_main({
            ".git/x": "fnx-dev-testenv-01",
            "c/.terraform/y": "fnx-dev-testenv-01",
            "scripts/check-old-stack-names.py": "fnx-dev-testenv-01",
            "c/.terraform.lock.hcl": "fnx-dev-testenv-01",
            "img.png": "fnx-dev-testenv-01",
        })
        self.assertEqual(code, 0)


if __name__ == "__main__":
    unittest.main()

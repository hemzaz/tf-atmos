"""Tests for scripts/check-catalog-read-overrides.py (needs yq, mikefarah v4):
python3 -m unittest workflows/scripts/common/test_check_catalog_read_overrides.py"""

import contextlib
import importlib.util
import io
import pathlib
import tempfile
import textwrap
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_catalog_read_overrides",
    pathlib.Path(__file__).resolve().parents[3] / "scripts" / "check-catalog-read-overrides.py",
)
check = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check)

CATALOG = """\
components:
  terraform:
    eks/defaults:
      metadata:
        type: abstract
      vars:
        kms_key_id: !terraform.state kms/main .key_arn
    eks/main:
      metadata:
        component: eks
        inherits: [eks/defaults]
      vars:
        subnet_ids: !terraform.state vpc/main .private_subnet_ids
        access_entries:
          - principal_arn: !terraform.output iam/ci .role_arn
        name: main
"""


class OverriddenTest(unittest.TestCase):
    def test_exact_path_and_replacing_parents(self):
        path = ("vars", "subnet_ids")
        self.assertEqual(check.overridden({"vars": {"subnet_ids": ["a"]}}, path), path)
        self.assertEqual(check.overridden({"vars": {"subnet_ids": None}}, path), path)
        self.assertEqual(check.overridden({"vars": None}, path), ("vars",))
        list_read = ("vars", "access_entries", 0, "principal_arn")
        self.assertEqual(check.overridden({"vars": {"access_entries": []}}, list_read), ("vars", "access_entries"))

    def test_map_parent_and_unrelated_keys_leave_the_read(self):
        path = ("vars", "subnet_ids")
        self.assertIsNone(check.overridden({"vars": {"name": "x"}}, path))
        self.assertIsNone(check.overridden({"settings": {}}, path))
        self.assertIsNone(check.overridden(None, path))
        self.assertIsNone(check.overridden({}, path))


class InstanceReadsTest(unittest.TestCase):
    def test_abstract_and_foreign_paths_are_skipped(self):
        doc = {"components": {"terraform": {"a": {"metadata": {"type": "abstract"}}, "b": {"vars": {}}}}}
        paths = [
            ["components", "terraform", "a", "vars", "x"],
            ["components", "terraform", "b", "vars", "y"],
            ["components", "helmfile", "b", "vars", "z"],
            ["vars", "w"],
        ]
        self.assertEqual(list(check.instance_reads(doc, paths)), [("b", ("vars", "y"))])


class MainTest(unittest.TestCase):
    def run_main(self, stack):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "catalog" / "eks").mkdir(parents=True)
            (root / "catalog" / "eks" / "main.yaml").write_text(CATALOG)
            (root / "orgs" / "fnx" / "dev").mkdir(parents=True)
            (root / "orgs" / "fnx" / "dev" / "us-east-1.yaml").write_text(textwrap.dedent(stack))
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = check.main([str(root)])
            return code, out.getvalue()

    def test_stack_overriding_a_read_fails(self):
        code, out = self.run_main("""\
            import: [catalog/eks/main]
            components:
              terraform:
                eks/main:
                  vars:
                    subnet_ids: ["subnet-1"]
                    access_entries: []
            """)
        self.assertEqual(code, 1)
        self.assertIn("eks/main sets vars.subnet_ids over the state read at vars.subnet_ids", out)
        self.assertIn("eks/main sets vars.access_entries over the state read at vars.access_entries[0].principal_arn",
                      out)
        self.assertIn("2 catalog state read(s) overridden", out)

    def test_residue_beside_the_reads_and_abstract_reads_pass(self):
        code, out = self.run_main("""\
            import: [catalog/eks/main]
            components:
              terraform:
                eks/main:
                  vars:
                    name: other
                eks/defaults:
                  vars:
                    kms_key_id: literal
            """)
        self.assertEqual(code, 0, out)
        self.assertIn("no stack overrides", out)


if __name__ == "__main__":
    unittest.main()

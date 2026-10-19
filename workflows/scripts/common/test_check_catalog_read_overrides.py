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

EKS = """\
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


def run_tree(files):
    """check.main over a stacks tree of {relative path: YAML text}; (exit code, output)."""
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        for name, text in files.items():
            (root / name).parent.mkdir(parents=True, exist_ok=True)
            (root / name).write_text(textwrap.dedent(text))
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = check.main([str(root)])
        return code, out.getvalue()


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


class ReadsTest(unittest.TestCase):
    def test_abstract_and_foreign_paths_are_skipped(self):
        doc = {"components": {"terraform": {"a": {"metadata": {"type": "abstract"}}, "b": {"vars": {}}}}}
        paths = [
            ["components", "terraform", "a", "vars", "x"],
            ["components", "terraform", "b", "vars", "y"],
            ["components", "helmfile", "b", "vars", "z"],
            ["vars", "w"],
        ]
        self.assertEqual(list(check.instance_reads(doc, paths)), [("b", ("vars", "y"))])

    def test_yaml_shapes(self):
        text = """\
            base: &base
              merged: !terraform.state vpc/main .vpc_id
            components:
              terraform:
                flow: {vars: {f: !terraform.state vpc/main .f, quoted: "!terraform.state vpc/main .q"}}
                nested:
                  vars:
                    <<: *base
                    lists: [[{deep: !terraform.output iam/ci .role_arn}]]
            ---
            components:
              terraform:
                second:
                  vars:
                    k: !terraform.state kms/main .key_arn
            """
        with tempfile.TemporaryDirectory() as tmp:
            file = pathlib.Path(tmp) / "c.yaml"
            file.write_text(textwrap.dedent(text))
            docs = check.load([file])[check.norm(file)]
        reads = {r for doc, paths in docs for r in check.instance_reads(doc, paths)}
        self.assertEqual(reads, {
            ("flow", ("vars", "f")),
            ("nested", ("vars", "merged")),
            ("nested", ("vars", "lists", 0, 0, "deep")),
            ("second", ("vars", "k")),
        })


class MainTest(unittest.TestCase):
    def test_stack_overriding_a_read_fails(self):
        code, out = run_tree({
            "catalog/eks/main.yaml": EKS,
            "orgs/fnx/dev/us-east-1.yaml": """\
                import: [catalog/eks/main]
                components:
                  terraform:
                    eks/main:
                      vars:
                        subnet_ids: ["subnet-1"]
                        access_entries: []
                """,
        })
        self.assertEqual(code, 1)
        self.assertIn("eks/main sets vars.subnet_ids over the state read at vars.subnet_ids", out)
        self.assertIn("eks/main sets vars.access_entries over the state read at vars.access_entries[0].principal_arn",
                      out)
        self.assertIn("2 catalog state read override(s)", out)

    def test_residue_beside_the_reads_and_abstract_reads_pass(self):
        code, out = run_tree({
            "catalog/eks/main.yaml": EKS,
            "orgs/fnx/dev/us-east-1.yaml": """\
                import: [catalog/eks/main]
                components:
                  terraform:
                    eks/main:
                      vars:
                        name: other
                    eks/defaults:
                      vars:
                        kms_key_id: literal
                """,
        })
        self.assertEqual(code, 0, out)
        self.assertIn("no stack overrides", out)

    def test_flavor_files_match_only_the_stacks_that_import_them(self):
        tree = {
            "catalog/vpc/main.yaml": "components: {terraform: {vpc/main: {vars: {a: !terraform.state kms/main .k}}}}\n",
            "catalog/vpc/main-standby.yaml":
                "components: {terraform: {vpc/main: {vars: {b: !terraform.state kms/main .k}}}}\n",
            # The prod stack sets b: residue, since its vpc/main reads only a.
            "orgs/fnx/prod/us-east-1.yaml": """\
                import: [catalog/vpc/main]
                components: {terraform: {vpc/main: {vars: {b: literal}}}}
                """,
        }
        standby = """\
            import: [catalog/vpc/main-standby]
            components: {terraform: {vpc/main: {vars: {%s: literal}}}}
            """
        code, out = run_tree({**tree, "orgs/fnx/prod/us-east-2.yaml": standby % "a"})
        self.assertEqual(code, 0, out)
        code, out = run_tree({**tree, "orgs/fnx/prod/us-east-2.yaml": standby % "b"})
        self.assertEqual(code, 1, out)
        self.assertIn("us-east-2.yaml: vpc/main sets vars.b over the state read at vars.b", out)
        self.assertIn("catalog/vpc/main-standby.yaml", out)
        self.assertNotIn("catalog/vpc/main.yaml", out)

    def test_overrides_sections_whatever_the_key(self):
        stack = """\
            import: [catalog/eks/main]
            %s
            """
        for section, label in (("overrides: {vars: {subnet_ids: []}}", "overrides"),
                               ("terraform: {overrides: {vars: {subnet_ids: []}}}", "terraform.overrides")):
            code, out = run_tree({"catalog/eks/main.yaml": EKS, "orgs/fnx/dev/us-east-1.yaml": stack % section})
            self.assertEqual(code, 1, out)
            self.assertIn(f"{label} sets vars.subnet_ids over the state read at vars.subnet_ids", out)
        # Overrides in a file whose own chain lacks the catalog file do not reach the instance.
        code, out = run_tree({
            "catalog/eks/main.yaml": EKS,
            "orgs/fnx/dev/us-east-1.yaml": "import: [catalog/eks/main, orgs/fnx/dev/globals]\n",
            "orgs/fnx/dev/globals.yaml": "overrides: {vars: {subnet_ids: []}}\n",
        })
        self.assertEqual(code, 0, out)

    def test_mixins_are_scanned(self):
        code, out = run_tree({
            "catalog/eks/main.yaml": EKS,
            "mixins/region/us-east-1.yaml": "components: {terraform: {eks/main: {vars: {subnet_ids: null}}}}\n",
            "orgs/fnx/dev/us-east-1.yaml": "import: [catalog/eks/main, mixins/region/us-east-1]\n",
        })
        self.assertEqual(code, 1, out)
        self.assertIn("mixins/region/us-east-1.yaml: eks/main sets vars.subnet_ids", out)

    def test_unresolvable_import_fails(self):
        code, out = run_tree({"orgs/fnx/dev/us-east-1.yaml": "import: [catalog/missing]\n"})
        self.assertEqual(code, 2)
        self.assertIn("names no file", out)


if __name__ == "__main__":
    unittest.main()

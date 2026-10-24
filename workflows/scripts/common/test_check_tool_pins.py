"""Tests for scripts/check-tool-pins.py (stdlib only): python3 -m unittest workflows/scripts/common/test_check_tool_pins.py"""

import contextlib
import importlib.util
import io
import pathlib
import tempfile
import textwrap
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_tool_pins",
    pathlib.Path(__file__).resolve().parents[3] / "scripts" / "check-tool-pins.py",
)
check = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check)

WORKFLOW = """\
workflows:
  lint:
    dependencies:
      tools:
        hashicorp/terraform: "1.16.3"
        tflint: "v0.64.0"
        wasilibs/go-yamllint: "1.38.0"
    steps:
      - command: terraform fmt
"""


class CheckToolPinsTest(unittest.TestCase):
    def run_check(self, files):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            for name, text in files.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(textwrap.dedent(text))
            err = io.StringIO()
            with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
                rc = check.main(["check-tool-pins.py", str(root)])
            return rc, err.getvalue()

    def test_agreeing_pins_pass(self):
        rc, err = self.run_check({
            "workflows/lint.yaml": WORKFLOW,
            "stacks/orgs/x/_defaults.yaml": 'terraform:\n  dependencies:\n    tools:\n      terraform: "1.16.3"\n',
            ".github/workflows/ci.yml": "run: atmos toolchain install terraform@1.16.3 tflint@0.64.0\n",
            ".pre-commit-config.yaml": "additional_dependencies: ['yamllint==1.38.0']\n",
            "README.md": "Atmos installs Terraform 1.16.3.\n",
        })
        self.assertEqual((rc, err), (0, ""))

    def test_mismatch_in_a_second_workflow_fails(self):
        rc, err = self.run_check({
            "workflows/lint.yaml": WORKFLOW,
            "workflows/validate.yaml": WORKFLOW.replace('"1.16.3"', '"1.16.4"'),
        })
        self.assertEqual(rc, 1)
        self.assertIn("terraform is pinned to 2 versions", err)
        self.assertIn("1.16.3: workflows/lint.yaml:5", err)
        self.assertIn("1.16.4: workflows/validate.yaml:5", err)

    def test_stale_copy_outside_yaml_fails(self):
        for name, text in {
            ".github/workflows/ci.yml": "run: atmos toolchain install terraform@1.16.2\n",
            "README.md": "Atmos installs Terraform 1.16.2.\n",
            ".pre-commit-config.yaml": "additional_dependencies: ['yamllint==1.37.0']\n",
            "atmos.yaml": "# tflint v0.63.0 is the old pin\n",
        }.items():
            with self.subTest(name=name):
                rc, err = self.run_check({"workflows/lint.yaml": WORKFLOW, name: text})
                self.assertEqual(rc, 1, err)
                self.assertIn(f"{name}:1", err)

    def test_command_dependencies_in_atmos_yaml_are_declarations(self):
        atmos = 'commands:\n  - name: sweep\n    dependencies:\n      tools:\n        mikefarah/yq: "v4.53.6"\n'
        rc, err = self.run_check({"atmos.yaml": atmos, "workflows/lint.yaml": WORKFLOW + '        # yq "4.53.5"\n'})
        self.assertEqual(rc, 1)
        self.assertIn("yq is pinned to 2 versions", err)

    def test_undeclared_tool_in_prose_is_ignored(self):
        rc, err = self.run_check({"workflows/lint.yaml": WORKFLOW, "README.md": "Atmos 1.229.0, Python 3.13.1\n"})
        self.assertEqual((rc, err), (0, ""))

    def test_no_declarations_fails(self):
        rc, err = self.run_check({"README.md": "nothing\n"})
        self.assertEqual(rc, 1)
        self.assertIn("no dependencies.tools", err)


if __name__ == "__main__":
    unittest.main()

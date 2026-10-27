"""Tests for scripts/check-vendor.py: python3 -m unittest workflows/scripts/common/test_check_vendor.py

The CLI cases read YAML through yq, as the script does (the lint workflow installs it).
"""

import contextlib
import hashlib
import importlib.util
import io
import json
import os
import pathlib
import tempfile
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_vendor", pathlib.Path(__file__).resolve().parents[3] / "scripts" / "check-vendor.py")
check = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check)

TARGET = "components/terraform/access-analyzer"
MAIN_TF = 'resource "aws_accessanalyzer_analyzer" "default" {}\n'
DIGEST = hashlib.sha256(MAIN_TF.encode()).hexdigest()


def source(**over):
    return {"component": "access-analyzer", "version": "v2.0.1", "targets": [TARGET],
            "source": "github.com/cloudposse-terraform-components/aws-access-analyzer.git//src?ref={{ .Version }}",
            **over}


def manifest(*srcs):
    return {"apiVersion": "atmos/v1", "kind": "AtmosVendorConfig", "spec": {"sources": list(srcs)}}


def lock(digest=DIGEST):
    return {"version": 1, "artifacts": {"id": {"name": "access-analyzer", "target": TARGET,
                                               "files": [{"path": "main.tf", "type": "file", "sha256": digest}]}}}


class Fixture(unittest.TestCase):
    """A temp root holding the vendored main.tf; write() adds files under it."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.write(f"{TARGET}/main.tf", MAIN_TF)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            fh.write(text)


class ManifestTest(unittest.TestCase):
    def test_valid(self):
        other = source(component="b", version="2.0.1", targets=["components/terraform/b"])
        self.assertEqual(check.check_manifest(manifest(source(), other)), [])

    def test_one_finding_each(self):
        with_imports = manifest(source())
        with_imports["spec"]["imports"] = ["vendor/security"]
        for label, m in {
            "branch": manifest(source(version="main")),
            "hardcoded ref": manifest(source(source="github.com/cloudposse-terraform-components/aws-x.git?ref=v2.0.1")),
            "other org": manifest(source(source="github.com/example/aws-x.git?ref={{ .Version }}")),
            "two targets": manifest(source(targets=[TARGET, "components/terraform/x"])),
            "nested target": manifest(source(targets=["components/terraform/vendor/x"])),
            "imports": with_imports,
        }.items():
            with self.subTest(label):
                self.assertEqual(len(check.check_manifest(m)), 1)
        self.assertEqual(len(check.check_manifest(manifest(source(), source()))), 2)


class LockTest(Fixture):
    def errs(self, lck=None):
        return check.check_lock(manifest(source()), lock() if lck is None else lck, self.root)

    def test_house_and_generated_files_pass(self):
        for rel in (".terraform.lock.hcl", "main_override.tf", ".terraform/modules/modules.json", "backend.tf.json"):
            self.write(f"{TARGET}/{rel}", "{}")
        self.assertEqual(self.errs(), [])

    def test_edited_missing_extra(self):
        self.write(f"{TARGET}/main.tf", MAIN_TF + "# local edit\n")
        self.assertIn("edited in place", self.errs()[0])
        os.remove(os.path.join(self.root, TARGET, "main.tf"))
        self.write(f"{TARGET}/extra.tf", "")
        errs = self.errs()
        self.assertEqual(len(errs), 2)
        self.assertIn("missing on disk", errs[0])
        self.assertIn("not from the vendor pull", errs[1])

    def test_receipt_gaps(self):
        self.assertIn("no receipt", self.errs({})[0])
        orphan = lock()
        orphan["artifacts"]["old"] = {"target": "components/terraform/old", "files": []}
        self.assertIn("does not declare", self.errs(orphan)[0])


class CliTest(Fixture):
    def run_main(self, *args):
        cwd, out = os.getcwd(), io.StringIO()
        try:
            os.chdir(self.root)
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
                code = check.main(["check-vendor.py", *args])
        finally:
            os.chdir(cwd)
        return code, out.getvalue()

    def vendor(self, digest=DIGEST):
        # JSON is YAML: yq reads these as the real files.
        self.write("vendor.yaml", json.dumps(manifest(source())))
        self.write("vendor.lock.yaml", json.dumps(lock(digest)))

    def test_no_manifest_passes(self):
        self.assertEqual(self.run_main(), (0, "check-vendor: no vendor.yaml, nothing is vendored\n"))
        self.assertEqual(self.run_main("--list"), (0, ""))
        self.assertEqual(self.run_main("--repull")[0], 0)

    def test_clean_list_and_wrong_sha(self):
        self.vendor()
        self.assertEqual(self.run_main()[0], 0)
        self.assertEqual(self.run_main("--list"), (0, f"{TARGET}\n"))
        self.vendor("0" * 64)
        code, out = self.run_main()
        self.assertEqual((code, "edited in place" in out), (1, True))

    def test_bad_usage_exits_2(self):
        self.assertEqual([self.run_main(*a)[0] for a in (("--list", "--repull"), ("--nope",))], [2, 2])


if __name__ == "__main__":
    unittest.main()

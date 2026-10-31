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
import shutil
import tempfile
import unittest
from unittest import mock

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


def mixin(**over):
    return {"component": "access-analyzer-mixins", "version": "v0.5.0", "targets": [TARGET],
            "source": "github.com/cloudposse-terraform-components/mixins.git//src/mixins?ref={{ .Version }}",
            "included_paths": ["providers-account-map-bypass.depth-1.tf"], **over}


MIXIN_TF = 'provider "aws" {}\n'


def mixin_lock(path="providers-account-map-bypass.depth-1.tf"):
    both = lock()
    both["artifacts"]["mix"] = {"name": "access-analyzer-mixins", "target": TARGET, "files": [
        {"path": path, "type": "file", "sha256": hashlib.sha256(MIXIN_TF.encode()).hexdigest()}]}
    return both


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
        catalog = source(component="c", targets=["stacks/catalog/c/catalog"],
                         source="github.com/cloudposse-terraform-components/aws-c.git//catalog?ref={{ .Version }}")
        self.assertEqual(check.check_manifest(manifest(source(), other, catalog)), [])

    def test_one_finding_each(self):
        with_imports = manifest(source())
        with_imports["spec"]["imports"] = ["vendor/security"]
        for label, m in {
            "branch": manifest(source(version="main")),
            "hardcoded ref": manifest(source(source="github.com/cloudposse-terraform-components/aws-x.git?ref=v2.0.1")),
            "other org": manifest(source(source="github.com/example/aws-x.git?ref={{ .Version }}")),
            "two targets": manifest(source(targets=[TARGET, "components/terraform/x"])),
            "nested target": manifest(source(targets=["components/terraform/vendor/x"])),
            "stack manifest target": manifest(source(targets=["stacks/orgs/x/catalog"])),
            "catalog not named catalog": manifest(source(targets=["stacks/catalog/x"])),
            "imports": with_imports,
        }.items():
            with self.subTest(label):
                self.assertEqual(len(check.check_manifest(m)), 1)
        self.assertEqual(len(check.check_manifest(manifest(source(), source()))), 2)

    def test_mixins(self):
        good = mixin()
        self.assertEqual(check.check_manifest(manifest(source(), good)), [])
        for label, m in {
            "no owning source": manifest(good),
            "wrong name": manifest(source(), mixin(component="x-mixins")),
            "other target": manifest(source(), mixin(targets=["components/terraform/x"])),
            "glob": manifest(source(), mixin(included_paths=["*.tf"])),
            "no files": manifest(source(), mixin(included_paths=[])),
            "other path": manifest(source(), mixin(
                source="github.com/cloudposse-terraform-components/mixins.git//src?ref={{ .Version }}")),
        }.items():
            with self.subTest(label):
                self.assertTrue(check.check_manifest(m), label)


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

    def test_mixin_receipt_shares_the_target(self):
        m = manifest(source(), mixin())
        self.write(f"{TARGET}/providers-account-map-bypass.depth-1.tf", MIXIN_TF)
        self.assertEqual(check.check_lock(m, mixin_lock(), self.root), [])
        # Without the mixin's receipt its file is an extra and the source has no receipt.
        errs = check.check_lock(m, lock(), self.root)
        self.assertEqual(sum("no receipt" in e for e in errs), 1, errs)
        self.assertEqual(sum("not from the vendor pull" in e for e in errs), 1, errs)
        # Two sources writing one file.
        self.write(f"{TARGET}/main.tf", MIXIN_TF)
        errs = check.check_lock(m, mixin_lock("main.tf"), self.root)
        self.assertIn("written by two vendor sources", errs[0])

    def test_receipt_gaps(self):
        self.assertIn("no receipt", self.errs({})[0])
        orphan = lock()
        orphan["artifacts"]["old"] = {"target": "components/terraform/old", "files": []}
        self.assertIn("does not declare", self.errs(orphan)[0])

    def test_symlinks_and_empty_dirs(self):
        outside = os.path.join(self.root, "outside")
        os.makedirs(outside)
        os.symlink(outside, os.path.join(self.root, TARGET, "linked-dir"))
        os.symlink("main.tf", os.path.join(self.root, TARGET, "alias.tf"))
        os.makedirs(os.path.join(self.root, TARGET, "empty"))
        errs = self.errs()
        self.assertEqual(sum("a symlink" in e for e in errs), 2, errs)
        self.assertEqual(sum("no vendored or house file" in e for e in errs), 1, errs)
        self.assertEqual(len(errs), 3, errs)

    def test_symlinked_receipt_file(self):
        os.rename(os.path.join(self.root, TARGET, "main.tf"), os.path.join(self.root, "real.tf"))
        os.symlink(os.path.join(self.root, "real.tf"), os.path.join(self.root, TARGET, "main.tf"))
        errs = self.errs()
        self.assertIn("not a regular file", errs[0])
        self.assertIn("a symlink", errs[1])

    def test_unsafe_and_non_file_receipt_entries(self):
        for path in ("../../../etc/passwd", "/etc/passwd", "a/../main.tf", "./main.tf", ""):
            with self.subTest(path):
                bad = lock()
                bad["artifacts"]["id"]["files"].append({"path": path, "type": "file", "sha256": DIGEST})
                self.assertEqual([e for e in self.errs(bad) if "unsafe path" in e], [e for e in self.errs(bad)])
        bad = lock()
        bad["artifacts"]["id"]["files"].append({"path": "link.tf", "type": "symlink"})
        self.assertIn("vendored dirs hold regular files only", self.errs(bad)[0])


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

    def test_list_with_bad_manifest_exits_2(self):
        self.write("vendor.yaml", json.dumps(manifest(source(targets=["../../etc"]))))
        self.assertEqual(self.run_main("--list"), (2, ""))

    def repull(self, fresh_lock):
        """--repull with a fake atmos (outside the repo) that writes fresh_lock into its working directory."""
        fake = tempfile.mkdtemp(prefix="fake-atmos-")
        self.addCleanup(shutil.rmtree, fake, True)
        with open(os.path.join(fake, "atmos"), "w") as fh:
            fh.write('#!/bin/sh\nprintf "%s" "$FAKE_LOCK" > vendor.lock.yaml\n')
        os.chmod(os.path.join(fake, "atmos"), 0o755)
        env = {"PATH": fake + os.pathsep + os.environ["PATH"], "FAKE_LOCK": json.dumps(fresh_lock)}
        with mock.patch.dict(os.environ, env):
            return self.run_main("--repull")

    def test_repull_match(self):
        self.vendor()
        self.assertEqual(self.repull(lock())[0], 0)

    def test_repull_mismatches(self):
        self.vendor()
        code, out = self.repull({"version": 1, "artifacts": {}})
        self.assertEqual((code, "in the committed vendor.lock.yaml only" in out), (1, True), out)
        code, out = self.repull(lock("1" * 64))
        self.assertEqual((code, "differs from a fresh pull" in out), (1, True), out)
        # The pull runs in the scratch dir: run in the repo, it would overwrite the committed lock.
        with open(os.path.join(self.root, "vendor.lock.yaml")) as fh:
            self.assertEqual(json.load(fh), lock())


if __name__ == "__main__":
    unittest.main()

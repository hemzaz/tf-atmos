"""Tests for scripts/account_map_entry.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""

import contextlib
import importlib.util
import io
import os
import pathlib
import stat
import tempfile
import unittest

_spec = importlib.util.spec_from_file_location(
    "account_map_entry",
    pathlib.Path(__file__).resolve().parents[3] / "scripts" / "account_map_entry.py",
)
entry = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(entry)

ORG = """---
terraform:
  backend:
    s3:
      bucket: x
settings:
  # comment kept
  account_map:
    full_account_map:
      root: "123456789012"
      dev: "123456789012"
    root_account_account_name: root
  environment:
    namespace: fnx
"""


class AccountMapEntryTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.tmp.name, "_defaults.yaml")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, text, newline="\n"):
        with open(self.path, "w", encoding="utf-8", newline=newline) as f:
            f.write(text)

    def read(self):
        with open(self.path, encoding="utf-8", newline="") as f:
            return f.read()

    def test_adds_after_last_entry_and_keeps_comments(self):
        self.write(ORG)
        entry.run("add", self.path, "qa", "210987654321")
        text = self.read()
        self.assertIn('      dev: "123456789012"\n      qa: "210987654321"\n    root_account_account_name', text)
        self.assertIn("# comment kept", text)

    def test_add_is_idempotent(self):
        self.write(ORG)
        entry.run("add", self.path, "qa", "210987654321")
        entry.run("add", self.path, "qa", "210987654321")
        entry.run("add", self.path, "qa")
        self.assertEqual(self.read().count("qa:"), 1)

    def test_rejects_conflicting_id(self):
        self.write(ORG)
        with self.assertRaisesRegex(entry.MapError, "already in the account map as 123456789012"):
            entry.run("add", self.path, "dev", "999999999999")
        self.assertEqual(self.read(), ORG)

    def test_rejects_bad_id_and_missing_id(self):
        self.write(ORG)
        with self.assertRaisesRegex(entry.MapError, "not 12 digits"):
            entry.run("check", self.path, "qa", "12345")
        with self.assertRaisesRegex(entry.MapError, "set AWS_ACCOUNT_ID"):
            entry.run("add", self.path, "qa")
        self.assertEqual(self.read(), ORG)

    def test_rejects_bad_account_name(self):
        self.write(ORG)
        for bad in ("Qa", "qa: x", "1qa", "qa\n", "", "q_a"):
            with self.subTest(bad=bad), self.assertRaisesRegex(entry.MapError, "account name"):
                entry.run("add", self.path, bad, "210987654321")
        self.assertEqual(self.read(), ORG)

    def test_only_the_settings_account_map_header_counts(self):
        decoy = ORG.replace("terraform:\n", "terraform:\n  full_account_map:\n    dev: \"000000000000\"\n")
        self.write(decoy)
        self.assertIn("(123456789012)", entry.run("check", self.path, "dev"))
        entry.run("add", self.path, "qa", "210987654321")
        self.assertIn('      dev: "123456789012"\n      qa: "210987654321"\n', self.read())

    def test_rejects_two_headers(self):
        self.write(ORG + "  account_map:\n    full_account_map:\n      prod: \"123456789012\"\n")
        with self.assertRaisesRegex(entry.MapError, "appears 2 times"):
            entry.run("check", self.path, "dev")

    def test_rejects_missing_header(self):
        self.write("settings:\n  environment:\n    namespace: fnx\n")
        with self.assertRaisesRegex(entry.MapError, "no settings.account_map.full_account_map"):
            entry.run("check", self.path, "dev")

    def test_keeps_crlf(self):
        self.write(ORG, newline="\r\n")
        entry.run("add", self.path, "qa", "210987654321")
        text = self.read()
        self.assertIn('      qa: "210987654321"\r\n', text)
        self.assertNotIn("\r\r", text)
        self.assertEqual(text.count("\n"), text.count("\r\n"))

    def test_keeps_crlf_when_last_entry_ends_the_file(self):
        text = 'settings:\r\n  account_map:\r\n    full_account_map:\r\n      root: "123456789012"'
        self.write(text, newline="")
        entry.run("add", self.path, "qa", "210987654321")
        self.assertEqual(self.read(), text + '\r\n      qa: "210987654321"\r\n')

    def test_header_with_trailing_comment(self):
        self.write(ORG.replace("    full_account_map:\n", "    full_account_map:   # ids\n"))
        self.assertIn("(123456789012)", entry.run("check", self.path, "dev"))
        entry.run("add", self.path, "qa", "210987654321")
        self.assertIn('      dev: "123456789012"\n      qa: "210987654321"\n', self.read())

    def test_rejects_unquoted_numeric_value(self):
        self.write(ORG.replace('root: "123456789012"', "root: 012345678901"))
        with self.assertRaisesRegex(entry.MapError, "unquoted value 012345678901; quote it"):
            entry.run("check", self.path, "dev")

    def test_atomic_write_keeps_mode_and_leaves_no_temp_file(self):
        self.write(ORG)
        os.chmod(self.path, 0o640)
        entry.run("add", self.path, "qa", "210987654321")
        self.assertEqual(stat.S_IMODE(os.stat(self.path).st_mode), 0o640)
        self.assertEqual(os.listdir(self.tmp.name), ["_defaults.yaml"])

    def test_main_exit_codes(self):
        self.write(ORG)
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            self.assertEqual(entry.main(["x", "check", self.path, "dev"]), 0)
            self.assertEqual(entry.main(["x", "check", self.path, "qa"]), 1)
            self.assertEqual(entry.main(["x", "bogus", self.path, "qa"]), 2)
        self.assertIn("error: account 'qa' is not in the account map", out.getvalue())


if __name__ == "__main__":
    unittest.main()

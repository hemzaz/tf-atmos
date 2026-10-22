"""Tests for scripts/stack-wiring.py (stdlib only): python3 -m unittest workflows/scripts/common/test_stack_wiring.py

Each test edits a copy of the committed root backend files
(stacks/orgs/fnx/root/{us-east-1,eu-west-1}.yaml), never the files themselves.
"""

import contextlib
import importlib.util
import io
import pathlib
import shutil
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[3]
_spec = importlib.util.spec_from_file_location("stack_wiring", REPO / "scripts" / "stack-wiring.py")
wiring = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wiring)

US = "stacks/orgs/fnx/root/us-east-1.yaml"
EU = "stacks/orgs/fnx/root/eu-west-1.yaml"


def arn(account: str, stack: str, kind: str) -> str:
    if account == "prod-eu":
        return (f"              - 'arn:aws:iam::{{{{ index .settings.account_map.full_account_map "
                f"\"prod-eu\" }}}}:role/{stack}-ci-{kind}'\n")
    return (f'              - "arn:aws:iam::{{{{ .settings.account_map.full_account_map.{account} }}}}'
            f':role/{stack}-ci-{kind}"\n')


def pair(stack: str) -> list[str]:
    return [f'              - "*/{stack}/*"\n', f'              - "*/{stack}-*"\n']


class Copy(unittest.TestCase):
    def setUp(self) -> None:
        self.root = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        for rel in (US, EU):
            (self.root / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(REPO / rel, self.root / rel)
        self.committed = {rel: (REPO / rel).read_text() for rel in (US, EU)}

    def text(self, rel: str) -> str:
        return (self.root / rel).read_text()

    def lines(self, rel: str) -> list[str]:
        return self.text(rel).splitlines(keepends=True)

    def wire(self, *args: str) -> list[str]:
        return wiring.wire(self.root, *args)

    def assert_only_added(self, rel: str, added: dict) -> None:
        """The file is the committed one plus exactly `added` (line after which -> new lines)."""
        original = self.committed[rel].splitlines(keepends=True)
        expected = []
        for i, line in enumerate(original):
            expected.append(line)
            expected.extend(added.get(i, []))
        self.assertEqual(self.lines(rel), expected)

    def line_of(self, rel: str, text: str) -> int:
        hits = [i for i, line in enumerate(self.committed[rel].splitlines()) if line.strip() == text]
        self.assertEqual(len(hits), 1, text)
        return hits[0]


class Wire(Copy):
    def test_dev_stack_adds_its_pair_and_roles_only(self) -> None:
        done = self.wire("fnx", "dev", "", "us-west-2", "fnx-uw2-dev")
        self.assertEqual(len(done), 3)
        # After each list's last item: the anchored &non_prod_state list (also
        # the write role's, by alias) and read/write's allowed_principal_arns.
        self.assert_only_added(US, {
            self.line_of(US, '- "*/fnx-ue1-staging-*"'): pair("fnx-uw2-dev"),
            self.line_of(US, '- "arn:aws:iam::{{ .settings.account_map.full_account_map.staging }}'
                             ':role/fnx-ue1-staging-ci-plan"'): [arn("dev", "fnx-uw2-dev", "plan")],
            self.line_of(US, '- "arn:aws:iam::{{ .settings.account_map.full_account_map.staging }}'
                             ':role/fnx-ue1-staging-ci-apply"'): [arn("dev", "fnx-uw2-dev", "apply")],
        })
        self.assertEqual(self.text(EU), self.committed[EU])
        for marker in ("object_key_patterns: &non_prod_state\n", "object_key_patterns: *non_prod_state\n",
                       "object_key_patterns: &prod_state\n", "object_key_patterns: *prod_state\n"):
            self.assertEqual(self.text(US).count(marker), 1, marker)

    def test_staging_stack_uses_the_staging_account(self) -> None:
        self.wire("fnx", "staging", "staging", "us-west-2", "fnx-uw2-staging")
        self.assertIn(arn("staging", "fnx-uw2-staging", "plan"), self.lines(US))
        self.assertIn(arn("staging", "fnx-uw2-staging", "apply"), self.lines(US))

    def test_prod_stack_goes_to_the_prod_family(self) -> None:
        self.wire("fnx", "prod", "prod", "us-west-2", "fnx-uw2-prod")
        self.assert_only_added(US, {
            self.line_of(US, '- "*/fnx-ue2-prod-*"'): pair("fnx-uw2-prod"),
            self.line_of(US, '- "arn:aws:iam::{{ .settings.account_map.full_account_map.prod }}'
                             ':role/fnx-ue2-prod-ci-plan"'): [arn("prod", "fnx-uw2-prod", "plan")],
            self.line_of(US, '- "arn:aws:iam::{{ .settings.account_map.full_account_map.prod }}'
                             ':role/fnx-ue2-prod-ci-apply"'): [arn("prod", "fnx-uw2-prod", "apply")],
        })

    def test_prod_eu_stack_goes_to_the_eu_backend(self) -> None:
        self.wire("fnx", "prod", "prod-eu", "eu-north-1", "fnx-en1-prod")
        self.assertEqual(self.text(US), self.committed[US])
        self.assert_only_added(EU, {
            self.line_of(EU, '- "*/fnx-ec1-prod-*"'): pair("fnx-en1-prod"),
            self.line_of(EU, "- 'arn:aws:iam::{{ index .settings.account_map.full_account_map \"prod-eu\" }}"
                             ":role/fnx-ec1-prod-ci-plan'"): [arn("prod-eu", "fnx-en1-prod", "plan")],
            self.line_of(EU, "- 'arn:aws:iam::{{ index .settings.account_map.full_account_map \"prod-eu\" }}"
                             ":role/fnx-ec1-prod-ci-apply'"): [arn("prod-eu", "fnx-en1-prod", "apply")],
        })

    def test_second_run_changes_nothing(self) -> None:
        self.wire("fnx", "dev", "", "us-west-2", "fnx-uw2-dev")
        once = self.text(US)
        self.assertEqual(self.wire("fnx", "dev", "", "us-west-2", "fnx-uw2-dev"), [])
        self.assertEqual(self.text(US), once)

    def test_committed_stacks_are_already_wired(self) -> None:
        for args in (("fnx", "dev", "dev", "us-east-1", "fnx-ue1-dev"),
                     ("fnx", "staging", "", "us-east-1", "fnx-ue1-staging"),
                     ("fnx", "prod", "prod", "us-east-1", "fnx-ue1-prod"),
                     ("fnx", "prod", "prod", "us-east-2", "fnx-ue2-prod"),
                     ("fnx", "prod", "prod-eu", "eu-west-1", "fnx-ew1-prod"),
                     ("fnx", "prod", "prod-eu", "eu-central-1", "fnx-ec1-prod")):
            self.assertEqual(self.wire(*args), [], args)
        self.assertEqual(self.text(US), self.committed[US])
        self.assertEqual(self.text(EU), self.committed[EU])

    def test_a_family_with_no_stack_yet_gets_its_first(self) -> None:
        stripped = "".join(line for line in self.committed[EU].splitlines(keepends=True)
                           if "fnx-ew1-prod" not in line and "fnx-ec1-prod" not in line)
        (self.root / EU).write_text(stripped)
        self.wire("fnx", "prod", "prod-eu", "eu-west-1", "fnx-ew1-prod")
        self.wire("fnx", "prod", "prod-eu", "eu-central-1", "fnx-ec1-prod")
        # Back to the committed file, comments aside: same values, same order.
        self.assertEqual([line for line in self.lines(EU) if not line.strip().startswith("#")],
                         [line for line in self.committed[EU].splitlines(keepends=True)
                          if not line.strip().startswith("#")])

    def test_crlf_and_missing_final_newline_are_kept(self) -> None:
        (self.root / US).write_bytes(self.committed[US].rstrip("\n").replace("\n", "\r\n").encode())
        self.wire("fnx", "dev", "", "us-west-2", "fnx-uw2-dev")
        data = (self.root / US).read_bytes()
        self.assertNotIn(b"\r\r", data)
        self.assertEqual(data.count(b"\n"), data.count(b"\r\n"))
        self.assertIn(b'- "*/fnx-uw2-dev-*"\r\n', data)


class Refuse(Copy):
    def mutate(self, rel: str, old: str, new: str) -> None:
        text = self.committed[rel]
        self.assertEqual(text.count(old), 1, old)
        (self.root / rel).write_text(text.replace(old, new))
        self.before = self.text(rel)

    def refused_unchanged(self, rel: str, args: tuple, message: str) -> str:
        with self.assertRaises(wiring.Refused) as caught:
            self.wire(*args)
        self.assertIn(message, str(caught.exception))
        self.assertEqual(self.text(rel), self.before)
        return str(caught.exception)

    def test_missing_anchor_prints_the_manual_edit(self) -> None:
        self.mutate(US, "object_key_patterns: &non_prod_state", "object_key_patterns:")
        error = self.refused_unchanged(US, ("fnx", "dev", "", "us-west-2", "fnx-uw2-dev"),
                                       "'object_key_patterns: &non_prod_state' lists in the read role")
        self.assertIn("Wire fnx-uw2-dev by hand in stacks/orgs/fnx/root/us-east-1.yaml", error)
        self.assertIn('"*/fnx-uw2-dev/*"', error)
        self.assertIn("fnx-uw2-dev-ci-apply", error)

    def test_missing_alias_in_the_write_role(self) -> None:
        self.mutate(US, "object_key_patterns: *prod_state", "object_key_patterns: []")
        self.refused_unchanged(US, ("fnx", "prod", "", "us-west-2", "fnx-uw2-prod"),
                               "'object_key_patterns: *prod_state' aliases in the prod_write role")

    def test_missing_role(self) -> None:
        self.mutate(US, "          write:\n", "          writes:\n")
        self.refused_unchanged(US, ("fnx", "dev", "", "us-west-2", "fnx-uw2-dev"),
                               "found 0 write: roles under access_roles")

    def test_no_non_prod_family_in_the_eu_backend(self) -> None:
        self.before = self.text(EU)
        # The EU backend has prod roles only; a non-prod EU stack is refused
        # before that, by the account/region rule.
        self.refused_unchanged(EU, ("fnx", "dev", "", "eu-west-1", "fnx-ew1-dev"),
                               "the EU regions are exactly the prod-eu account's")

    def test_half_a_pair(self) -> None:
        self.mutate(US, '              - "*/fnx-ue1-staging-*"\n',
                    '              - "*/fnx-ue1-staging-*"\n              - "*/fnx-uw2-dev/*"\n')
        self.refused_unchanged(US, ("fnx", "dev", "", "us-west-2", "fnx-uw2-dev"), "without its companion")

    def test_pattern_in_the_other_family(self) -> None:
        self.mutate(US, '              - "*/fnx-ue1-staging-*"\n',
                    '              - "*/fnx-ue1-staging-*"\n              - "*/fnx-uw2-prod/*"\n'
                    '              - "*/fnx-uw2-prod-*"\n')
        self.refused_unchanged(US, ("fnx", "prod", "", "us-west-2", "fnx-uw2-prod"), "already in another list")

    def test_arn_on_the_wrong_role(self) -> None:
        wrong = arn("prod", "fnx-uw2-prod", "plan")
        self.mutate(US, arn("staging", "fnx-ue1-staging", "plan"),
                    arn("staging", "fnx-ue1-staging", "plan") + wrong)
        self.refused_unchanged(US, ("fnx", "prod", "", "us-west-2", "fnx-uw2-prod"), "already in another list")

    def test_bad_arguments(self) -> None:
        self.before = self.text(US)
        cases = [
            (("fnx;id", "dev", "", "us-west-2", "fnx-uw2-dev"), "tenant"),
            (("fnx", "dev$(id)", "", "us-west-2", "fnx-uw2-dev"), "stage"),
            (("fnx", "prod", "prod-eu x", "eu-west-1", "fnx-ew1-prod"), "account"),
            (("fnx", "dev", "prod", "us-west-2", "fnx-uw2-dev"), "does not belong to stage"),
            (("fnx", "staging", "prod-eu", "eu-west-1", "fnx-ew1-staging"), "does not belong to stage"),
            (("fnx", "dev", "", "us-west-2`id`", "fnx-uw2-dev"), "region"),
            (("fnx", "prod", "prod", "eu-west-1", "fnx-ew1-prod"), "the EU regions are exactly"),
            (("fnx", "prod", "prod-eu", "us-east-1", "fnx-ue1-prod"), "the EU regions are exactly"),
            (("fnx", "dev", "", "us-west-2", "fnx-uw2-dev\n"), "stack"),
            (("fnx", "dev", "", "us-west-2", "fnx-uw2-staging"), "stack"),
            (("fnx", "dev", "", "us-west-2", "fnx-uw2-dev/../x"), "stack"),
        ]
        for args, message in cases:
            with self.subTest(args=args):
                self.refused_unchanged(US, args, message)
        self.assertEqual(self.text(EU), self.committed[EU])

    def test_main_exit_codes(self) -> None:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            self.assertEqual(wiring.main(["--root", str(self.root), "fnx", "dev", "", "us-west-2", "fnx-uw2-dev"]), 0)
            self.assertEqual(wiring.main(["--root", str(self.root), "fnx", "dev", "", "us-west-2", "fnx-uw2-dev"]), 0)
            self.assertEqual(wiring.main(["--root", str(self.root), "fnx", "dev", "", "us-west-2", "bad"]), 1)
        self.assertIn("added stacks/orgs/fnx/root/us-east-1.yaml", out.getvalue())
        self.assertIn("fnx-uw2-dev is already wired", out.getvalue())
        self.assertIn("apply backend/main in fnx-ue1-root", out.getvalue())
        self.assertIn("zone_name_servers.main", out.getvalue())
        self.assertIn("refused, nothing written", err.getvalue())


if __name__ == "__main__":
    unittest.main()

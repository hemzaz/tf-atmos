"""Tests for scripts/check-inherited-state-reads.py (stdlib only):
python3 -m unittest workflows/scripts/common/test_check_inherited_state_reads.py"""
import contextlib
import importlib.util
import io
import json
import pathlib
import unittest
from unittest import mock

_spec = importlib.util.spec_from_file_location(
    "check_inherited_state_reads",
    pathlib.Path(__file__).resolve().parents[3] / "scripts" / "check-inherited-state-reads.py",
)
check = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check)

KMS = "!terraform.state kms/main .key_arn"
REPLICA = "!terraform.state kms/main fnx-ue1-prod '.replica_keys[\"us-east-2\"].key_arn'"


def abstract(variables=None):
    return {"metadata": {"type": "abstract"}, "vars": variables or {}}


def real(variables=None, inheritance=(), **metadata):
    return {"metadata": metadata, "vars": variables or {}, "inheritance": list(inheritance)}


def stack(**instances):
    return {"components": {"terraform": instances}}


class CheckInheritedStateReadsTest(unittest.TestCase):
    def assert_errors(self, stacks, *fragments):
        errors = check.check(stacks)
        self.assertEqual(len(errors), len(fragments), errors)
        for error, fragment in zip(errors, fragments):
            self.assertIn(fragment, error)

    def test_inherited_read_with_target_present_passes(self):
        self.assert_errors({"s": stack(**{
            "kms/main": real(),
            "eks/defaults": abstract({"key": KMS}),
            "eks/main": real({"key": KMS}, ["eks/defaults"]),
        })})

    def test_inherited_read_fails_without_target_even_when_overridden(self):
        # The DR standby: the instance reads the primary's replica key, the abstract a local key.
        self.assert_errors({"dr": stack(**{
            "eks/defaults": abstract({"key": KMS}),
            "eks/main": real({"key": REPLICA}, ["eks/defaults"]),
        })}, "dr: eks/main resolves `!terraform.state kms/main .key_arn` (vars.key inherited from eks/defaults)")

    def test_every_abstract_of_the_chain_is_checked(self):
        self.assert_errors({"s": stack(**{
            "backup/defaults": abstract({"key": KMS}),
            "backup/prod": abstract({"key": KMS, "days": 35}),
            "backup/main": real({"key": REPLICA}, ["backup/prod", "backup/defaults"]),
        })}, "inherited from backup/prod", "inherited from backup/defaults")

    def test_own_local_read_without_target_fails(self):
        self.assert_errors({"s": stack(**{"a/main": real({"x": [{"y": "!terraform.output vpc/main vpc_id"}]})})},
                           "s: a/main resolves `!terraform.output vpc/main vpc_id` (vars.x[0].y), but vpc/main")

    def test_cross_stack_read_is_skipped(self):
        self.assert_errors({"s": stack(**{
            "x/defaults": abstract({"key": REPLICA}),
            "x/main": real({"key": REPLICA}, ["x/defaults"]),
        })})

    def test_target_that_is_abstract_fails(self):
        self.assert_errors({"s": stack(**{
            "kms/main": abstract(),
            "x/main": real({"key": KMS}),
        })}, "kms/main is not a real instance of s")

    def test_disabled_reader_is_checked(self):
        # Enabled later (a DR standby's components at failover), so its reads must resolve then.
        self.assert_errors({"s": stack(**{
            "x/defaults": abstract({"key": KMS}),
            "x/main": real({}, ["x/defaults"], enabled=False),
        })}, "s: x/main resolves")

    def test_disabled_target_passes(self):
        # Atmos finds a disabled instance; check-dependencies owns reads of a disabled target.
        self.assert_errors({"s": stack(**{
            "kms/main": real(enabled=False),
            "x/main": real({"key": KMS}),
        })})

    def test_settings_and_env_are_checked(self):
        self.assert_errors({"s": stack(**{"y/main": {"metadata": {}, "settings": {"a": KMS}, "env": {"B": KMS}}})},
                           "(settings.a)", "(env.B)")

    def test_abstract_readers_alone_are_not_reported(self):
        self.assert_errors({"s": stack(**{"x/defaults": abstract({"key": KMS})})})

    def test_main_exit_codes(self):
        for stacks, code in (
            ({"s": stack(**{"kms/main": real(), "x/main": real({"key": KMS})})}, 0),
            ({"s": stack(**{"x/main": real({"key": KMS})})}, 1),
        ):
            with self.subTest(code=code), mock.patch("sys.stdin", io.StringIO(json.dumps(stacks))), \
                    contextlib.redirect_stdout(io.StringIO()) as out:
                self.assertEqual(check.main(), code)
                self.assertIn("ERROR" if code else "every local", out.getvalue())


if __name__ == "__main__":
    unittest.main()

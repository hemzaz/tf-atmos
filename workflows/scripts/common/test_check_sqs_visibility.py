"""Tests for check-sqs-visibility.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import contextlib
import importlib.util
import io
import json
import pathlib
import subprocess
import sys
import unittest
from unittest import mock

_spec = importlib.util.spec_from_file_location(
    "check_sqs_visibility", pathlib.Path(__file__).with_name("check-sqs-visibility.py")
)
visibility = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(visibility)

READ = "!terraform.state sqs/work .queue_arn"


def queue(**vars):
    return {"metadata": {"component": "sqs"}, "vars": vars}


def function(timeout=None, arn=READ, enabled=True, **vars):
    if timeout is not None:
        vars["timeout"] = timeout
    return {
        "metadata": {"component": "lambda", "enabled": enabled},
        "vars": {"event_source_mappings": {"work": {"event_source_arn": arn}}, **vars},
    }


def stack(**components):
    return {"fnx-ue1-staging": {"components": {"terraform": components}}}


class SqsVisibilityTest(unittest.TestCase):
    def test_at_or_above_six_times_timeout_plus_five_passes(self):
        stacks = stack(**{"sqs/work": queue(visibility_timeout_seconds=3605), "lambda/work": function(600)})
        self.assertEqual(visibility.check(stacks), ([], []))

    def test_below_six_times_timeout_plus_five_warns(self):
        stacks = stack(**{"sqs/work": queue(visibility_timeout_seconds=3604), "lambda/work": function(600)})
        errors, warnings = visibility.check(stacks)
        self.assertEqual(errors, [])
        self.assertEqual(len(warnings), 1)
        self.assertIn("visibility_timeout_seconds 3604 is below 6 x timeout + 5 = 3605", warnings[0])

    def test_equal_to_timeout_only_warns(self):
        stacks = stack(**{"sqs/work": queue(visibility_timeout_seconds=600), "lambda/work": function(600)})
        errors, warnings = visibility.check(stacks)
        self.assertEqual((errors, len(warnings)), ([], 1))

    def test_below_function_timeout_fails(self):
        stacks = stack(**{"sqs/work": queue(visibility_timeout_seconds=599), "lambda/work": function(600)})
        errors, warnings = visibility.check(stacks)
        self.assertEqual(warnings, [])
        self.assertEqual(len(errors), 1)
        self.assertTrue(errors[0].startswith("fnx-ue1-staging: lambda/work event_source_mappings.work (queue sqs/work)"))
        self.assertIn("visibility_timeout_seconds 599 is below the function timeout 600", errors[0])

    def test_queue_no_lambda_reads_is_ignored(self):
        stacks = stack(**{"sqs/lonely": queue(visibility_timeout_seconds=1)})
        self.assertEqual(visibility.check(stacks), ([], []))

    def test_non_queue_mapping_is_ignored(self):
        for arn in (
            "!terraform.state data-pipeline/kinesis-ingest .stream_arn",
            "arn:aws:sqs:us-east-1:123456789012:work",
            None,
        ):
            stacks = stack(**{"sqs/work": queue(visibility_timeout_seconds=1), "lambda/work": function(600, arn=arn)})
            self.assertEqual(visibility.check(stacks), ([], []), arn)

    def test_omitted_values_are_the_component_defaults(self):
        # sqs default 30, lambda default 3: 30 >= 6 * 3 + 5.
        self.assertEqual(visibility.check(stack(**{"sqs/work": queue(), "lambda/work": function()})), ([], []))
        # a 10 s function with the default 30 s queue: 30 < 65 warns; a 31 s function fails.
        errors, warnings = visibility.check(stack(**{"sqs/work": queue(), "lambda/work": function(10)}))
        self.assertEqual((errors, len(warnings)), ([], 1))
        errors, _ = visibility.check(stack(**{"sqs/work": queue(), "lambda/work": function(31)}))
        self.assertEqual(len(errors), 1)

    def test_missing_queue_or_non_numeric_value_warns_and_skips(self):
        errors, warnings = visibility.check(stack(**{"lambda/work": function(600)}))
        self.assertEqual((errors, len(warnings)), ([], 1))
        self.assertIn("instances lack, skipped", warnings[0])
        other = stack(**{"sqs/work": queue(visibility_timeout_seconds="600"), "lambda/work": function(600)})
        errors, warnings = visibility.check(other)
        self.assertEqual((errors, len(warnings)), ([], 1))
        self.assertIn("not a number, skipped", warnings[0])

    def test_disabled_lambda_is_checked_and_abstract_is_not(self):
        bad = queue(visibility_timeout_seconds=1)
        errors, _ = visibility.check(stack(**{"sqs/work": bad, "lambda/work": function(600, enabled=False)}))
        self.assertEqual(len(errors), 1)
        abstract = function(600)
        abstract["metadata"]["type"] = "abstract"
        self.assertEqual(visibility.check(stack(**{"sqs/work": bad, "lambda/work": abstract})), ([], []))

    def test_three_word_read_names_a_queue_stack(self):
        same = "!terraform.state sqs/work fnx-ue1-staging .queue_arn"
        other = "!terraform.state sqs/work fnx-ue1-prod .queue_arn"
        bad = queue(visibility_timeout_seconds=1)
        errors, _ = visibility.check(stack(**{"sqs/work": bad, "lambda/work": function(600, arn=same)}))
        self.assertEqual(len(errors), 1)
        errors, warnings = visibility.check(stack(**{"sqs/work": bad, "lambda/work": function(600, arn=other)}))
        self.assertEqual((errors, len(warnings)), ([], 1))


    def test_other_read_functions_are_not_paired(self):
        arn = "!terraform.output sqs/work .queue_arn"
        stacks = stack(**{"sqs/work": queue(visibility_timeout_seconds=1), "lambda/work": function(600, arn=arn)})
        self.assertEqual(visibility.check(stacks), ([], []))

    def test_cli_exits_1_on_a_failing_queue_and_0_otherwise(self):
        script = pathlib.Path(__file__).with_name("check-sqs-visibility.py")

        def run(visibility_seconds):
            stacks = stack(**{"sqs/work": queue(visibility_timeout_seconds=visibility_seconds), "lambda/work": function(600)})
            return subprocess.run([sys.executable, str(script)], input=json.dumps(stacks),
                                  capture_output=True, text=True)

        bad = run(1)
        self.assertEqual(bad.returncode, 1)
        self.assertIn("ERROR fnx-ue1-staging: lambda/work", bad.stdout)
        self.assertIn("1 SQS visibility timeout problem(s)", bad.stdout)
        warn = run(600)
        self.assertEqual(warn.returncode, 0)
        self.assertIn("WARN fnx-ue1-staging", warn.stdout)

    def test_known_broken_fixture_errors_are_not_fatal(self):
        stacks = stack(**{"sqs/work": queue(visibility_timeout_seconds=1), "lambda/work": function(600)})
        broken = {"fnx-ue1-staging": visibility.fixtures.ALL}
        out = io.StringIO()
        with mock.patch.dict(visibility.fixtures.KNOWN_BROKEN_FIXTURES, broken), \
                mock.patch.object(sys, "stdin", io.StringIO(json.dumps(stacks))), \
                contextlib.redirect_stdout(out):
            rc = visibility.main()
        self.assertEqual(rc, 0)
        self.assertIn("KNOWN-BROKEN fnx-ue1-staging: lambda/work", out.getvalue())


if __name__ == "__main__":
    unittest.main()

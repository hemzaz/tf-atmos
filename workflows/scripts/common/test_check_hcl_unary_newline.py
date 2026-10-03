"""Tests for scripts/check-hcl-unary-newline.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common

Every "hit" case below was confirmed to fail checkov's parser (bc-python-hcl2 0.4.3, pinned
by checkov 3.3.19-3.3.22) and every "clean" case to parse, except where a test says otherwise.
"""

import contextlib
import importlib.util
import io
import os
import pathlib
import tempfile
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_hcl_unary_newline",
    pathlib.Path(__file__).resolve().parents[3]
    / "scripts"
    / "check-hcl-unary-newline.py",
)
check = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check)


def hits(src):
    return list(check.find_hits(src))


def paren(*lines):
    """`locals { x = ( <lines> ) }`, one expression line per argument."""
    body = "".join(f"    {line}\n" for line in lines)
    return f"locals {{\n  x = (\n{body}  )\n}}\n"


# The eight constructs that reached master or a PR and left a file unscanned by checkov
# (trimmed to the offending expression; the file each came from is in the test name).
HISTORICAL = {
    "batch_tests_job_definitions": paren(
        'jsondecode(aws_batch_job_definition.this["train"].container_properties).resourceRequirements == []',
        '&& !contains(keys(jsondecode(aws_batch_job_definition.this["train"].container_properties)), "privileged")',
        '&& jsondecode(aws_batch_job_definition.this["train"].container_properties).ulimits == []',
    ),
    "cloudfront_tests": paren(
        "aws_cloudfront_distribution.this[0].viewer_certificate[0].acm_certificate_arn == var.acm_certificate_arn",
        "&& !aws_cloudfront_distribution.this[0].viewer_certificate[0].cloudfront_default_certificate",
        '&& aws_cloudfront_distribution.this[0].viewer_certificate[0].ssl_support_method == "sni-only"',
    ),
    "ecs_service_variables_3cb29cc": (
        'variable "load_balancer" {\n  validation {\n'
        "    condition = try(var.load_balancer.http_header, null) == null || try(\n"
        '      can(regex("^[A-Za-z0-9-]{1,40}$", var.load_balancer.http_header.name))\n'
        '      && !contains(["host", "cookie"], lower(var.load_balancer.http_header.name))\n'
        "      && length(var.load_balancer.http_header.value_ssm_parameter_name) <= 2048,\n"
        '      false\n    )\n    error_message = "x"\n  }\n}\n'
    ),
    "ecs_service_variables_ecefaa1": (
        'variable "load_balancer" {\n  validation {\n'
        "    condition = try(\n"
        "      can(var.load_balancer.http_header.name)\n"
        '      && !contains(["host", "cookie"], lower(var.load_balancer.http_header.name))\n'
        '      && can(regex("^/?[A-Za-z0-9_./-]+$", var.load_balancer.http_header.value_ssm_parameter_name)),\n'
        '      false\n    )\n    error_message = "x"\n  }\n}\n'
    ),
    "firehose_variables": paren(
        '!strcontains(coalesce(var.s3_error_output_prefix, "-"), "!{")',
        '|| strcontains(coalesce(var.s3_error_output_prefix, "-"), "!{firehose:error-output-type}")',
    ),
    "iam_tests": paren(
        '!contains(flatten([for s in jsondecode(aws_iam_policy.p[0].policy).Statement : s.Action]), "sns:Subscribe")',
        '&& contains(flatten([for s in jsondecode(aws_iam_policy.p[0].policy).Statement : s.Action]), "sns:Publish")',
    ),
    "iam_variables": (
        "locals {\n  x = alltrue([\n    for repo in var.repos : length(repo) > 0\n"
        '      && !strcontains(repo, "*")\n'
        '      && !endswith(repo, ":pull_request")\n  ])\n}\n'
    ),
    "secretsmanager_variables": (
        "locals {\n  x = alltrue([for k, v in var.secret_data : (\n"
        '    !can(regex("(?i)(testpass|password123)", v))\n'
        '    && !can(regex("(?i)(AKIA[0-9A-Z]{16})", v))\n  )])\n}\n'
    ),
}


class HistoricalConstructs(unittest.TestCase):
    def test_every_historical_construct_is_a_hit(self):
        for name, src in HISTORICAL.items():
            with self.subTest(name):
                self.assertTrue(hits(src), name)

    def test_reports_the_line_checkov_fails_on(self):
        # checkov/lark reports UnexpectedToken on the leading-operator line.
        self.assertEqual(hits(HISTORICAL["firehose_variables"]), [(3, 4, "||")])


class Hits(unittest.TestCase):
    def test_every_leading_binary_operator_after_not_and_neg(self):
        for op in (
            "&&",
            "||",
            "==",
            "!=",
            "<",
            ">",
            "<=",
            ">=",
            "+",
            "-",
            "*",
            "/",
            "%",
        ):
            for unary in ("!", "-"):
                with self.subTest(unary=unary, op=op):
                    self.assertEqual(hits(paren(f"{unary}a", f"{op} b")), [(3, 4, op)])

    def test_leading_ternary(self):
        self.assertTrue(hits(paren("!a", "? 1 : 2")))

    def test_unary_after_a_binary_operator_on_the_same_line(self):
        self.assertTrue(hits(paren("true && !false", "&& true")))

    def test_operand_with_attributes_index_and_splat(self):
        self.assertTrue(hits(paren("!var.a[0].b", "&& c")))
        self.assertTrue(hits(paren("!a[*].b", "&& c")))

    def test_operand_spanning_lines(self):
        self.assertTrue(hits(paren("!contains(", '  ["a"], "b"', ")", "&& c")))
        self.assertTrue(hits(paren("!(a ||", "b)", "&& c")))

    def test_negative_number_literal(self):
        self.assertTrue(hits(paren("-1", "* 2")))

    def test_attribute_or_index_continuing_on_the_next_line(self):
        for lines, op in (
            (("!var", ".b"), "."),
            (("-var", ".b"), "."),
            (("!var.l", "[0]"), "["),
            (("!var.l", "[*].b"), "["),
            (("!(var.a)", ".b"), "."),
            (("!f(a)", ".b"), "."),
        ):
            with self.subTest(lines=lines):
                self.assertEqual(hits(paren(*lines)), [(3, 4, op)])

    def test_blank_and_comment_lines_between(self):
        self.assertTrue(hits(paren("!a", "", "&& c")))
        self.assertTrue(hits(paren("!a # why", "# more", "&& c")))
        self.assertTrue(hits(paren("!a /* why */", "&& c")))

    def test_for_expression_condition(self):
        self.assertTrue(
            hits('locals {\n  x = [for s in ["a"] : s if !a\n    && true]\n}\n')
        )

    def test_conservative_on_a_conditional_false_branch(self):
        # Parses in bc-python-hcl2 0.4.3, but telling a conditional's `:` from a for
        # expression's `:` needs a parser; flagging it costs one harmless rewrite.
        self.assertTrue(hits(paren("c ? a : !b", "&& d")))


class Clean(unittest.TestCase):
    def test_the_rewrites_that_parse(self):
        for lines in (
            ("contains(x, y) == false", "&& c"),
            ("(!a)", "&& c"),
            ("!a &&", "c"),
            ("true && !contains(x, y)",),
            ("(!false)", "&& true"),
        ):
            with self.subTest(lines=lines):
                self.assertEqual(hits(paren(*lines)), [])

    def test_unary_followed_by_closing_bracket_or_comma(self):
        self.assertEqual(hits(paren("true", "&& !false")), [])
        self.assertEqual(hits("locals {\n  x = [\n    !a,\n    -b\n  ]\n}\n"), [])
        self.assertEqual(hits("locals {\n  x = f(\n    !a,\n    -b\n  )\n}\n"), [])

    def test_unary_followed_by_leading_colon(self):
        self.assertEqual(hits(paren("c ? !a", ": b")), [])

    def test_unary_whose_operand_is_followed_on_its_line(self):
        self.assertEqual(hits(paren("!a && b", "&& c")), [])
        self.assertEqual(hits(paren("-a * b", "+ c")), [])

    def test_binary_minus_and_dashed_identifiers(self):
        self.assertEqual(hits(paren("a - b", "&& c")), [])
        self.assertEqual(hits(paren("a-b", "&& c")), [])

    def test_object_attributes(self):
        self.assertEqual(
            hits("locals {\n  x = {\n    a = !b\n    c = -d\n  }\n}\n"), []
        )

    def test_strings_heredocs_and_comments_are_not_code(self):
        self.assertEqual(hits(paren('"!a"', "&& true")), [])
        self.assertEqual(hits(paren('"${!a}"', "&& true")), [])
        self.assertEqual(hits(paren('"x ${join(",", [a])} !y"', "&& true")), [])
        self.assertEqual(hits("locals {\n  y = <<EOT\n!a\n&& b\nEOT\n}\n"), [])
        self.assertEqual(
            hits("locals {\n  y = <<-EOT\n    !a\n    && b\n    EOT\n}\n"), []
        )
        self.assertEqual(hits("# x = (\n#   !a\n#   && b\n# )\n"), [])
        self.assertEqual(hits("/*\n  !a\n  && b\n*/\n"), [])

    def test_heredoc_keeps_line_numbers(self):
        src = (
            "locals {\n  y = <<EOT\none\ntwo\nEOT\n  x = (\n    !a\n    && b\n  )\n}\n"
        )
        self.assertEqual(hits(src), [(7, 8, "&&")])


class Cli(unittest.TestCase):
    def run_main(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            rc = check.main(["check-hcl-unary-newline.py", *args])
        return rc, out.getvalue()

    def test_directory_scan_reports_file_line_lines_and_hint(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, "mod", ".terraform"))
            bad = os.path.join(tmp, "mod", "variables.tf")
            pathlib.Path(bad).write_text(HISTORICAL["firehose_variables"])
            pathlib.Path(tmp, "mod", "main.tf").write_text(paren("(!a)", "&& b"))
            pathlib.Path(tmp, "mod", "README.md").write_text(paren("!a", "&& b"))
            pathlib.Path(tmp, "mod", ".terraform", "vendored.tf").write_text(
                paren("!a", "&& b")
            )
            rc, out = self.run_main(tmp)
        self.assertEqual(rc, 1)
        self.assertIn(f"{bad}:4:", out)
        self.assertIn(
            '      3 |     !strcontains(coalesce(var.s3_error_output_prefix, "-"), "!{")',
            out,
        )
        self.assertIn("      4 |     || strcontains(", out)
        self.assertIn("fix: rewrite as `x == false`", out)
        self.assertIn("1 hit(s)", out)

    def test_file_argument_of_any_extension(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp, "x.tftest.hcl")
            path.write_text(HISTORICAL["iam_tests"])
            self.assertEqual(self.run_main(str(path))[0], 1)

    def test_clean_tree_exits_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            pathlib.Path(tmp, "main.tf").write_text(
                paren("contains(x, y) == false", "&& c")
            )
            self.assertEqual(self.run_main(tmp), (0, ""))

    def test_missing_path_exits_two(self):
        self.assertEqual(self.run_main("/nonexistent/path")[0], 2)

    def test_non_utf8_file_is_reported_not_a_traceback(self):
        with tempfile.TemporaryDirectory() as tmp:
            pathlib.Path(tmp, "latin1.tf").write_bytes(
                b'locals {\n  x = "caf\xe9"\n}\n'
            )
            pathlib.Path(tmp, "bad.tf").write_text(paren("!a", "&& b"))
            rc, out = self.run_main(tmp)
            self.assertEqual(rc, 1)  # the hit elsewhere still wins
            pathlib.Path(tmp, "bad.tf").unlink()
            self.assertEqual(self.run_main(tmp)[0], 2)


if __name__ == "__main__":
    unittest.main()

"""Tests for scripts/check-identity-center-override.py (stdlib only), against copies of the real files."""
import importlib.util
import pathlib
import shutil
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[3]
_spec = importlib.util.spec_from_file_location(
    "check_identity_center_override", REPO / "scripts" / "check-identity-center-override.py"
)
guard = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(guard)
COMPONENT = REPO / "components" / "terraform" / "aws-identity-center"
DESCRIBE = '''    actions = [
      "ec2:DescribeRegions",
    ]'''


class CheckIdentityCenterOverrideTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        for name in (guard.UPSTREAM, guard.OVERRIDE):
            shutil.copy(COMPONENT / name, self.dir / name)

    def mutate(self, name: str, old: str, new: str, count: int = 1) -> None:
        path = self.dir / name
        text = path.read_text()
        self.assertGreaterEqual(text.count(old), count, old)
        path.write_text(text.replace(old, new, count))

    def test_committed_override_restates_upstream(self) -> None:
        self.assertEqual(guard.check(self.dir), [])

    def test_upstream_action_added_fails(self) -> None:
        # A vendor bump widening EC2DescribeRegions in the Plan document (the first occurrence)
        self.mutate(guard.UPSTREAM, DESCRIBE, DESCRIBE.replace('"ec2:DescribeRegions",',
                                                               '"ec2:DescribeRegions", "ec2:DescribeAccountAttributes",'))
        errors = guard.check(self.dir)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("terraform_plan_access: statement EC2DescribeRegions attr:actions", errors[0])

    def test_upstream_statement_added_fails(self) -> None:
        self.mutate(guard.UPSTREAM, '''data "aws_iam_policy_document" "terraform_plan_access_additional" {
  for_each = local.tf_access_additional_backends_enabled ? var.tf_access_additional_backends : {}
''', '''data "aws_iam_policy_document" "terraform_plan_access_additional" {
  for_each = local.tf_access_additional_backends_enabled ? var.tf_access_additional_backends : {}

  statement {
    sid       = "KmsDecrypt"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
  }
''')
        self.assertIn("terraform_plan_access_additional: statement sids", guard.check(self.dir)[0])

    def test_upstream_condition_added_fails(self) -> None:
        self.mutate(guard.UPSTREAM, '''    resources = [var.tf_access_role_arn]
  }''', '''    resources = [var.tf_access_role_arn]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["us-east-1"]
    }
  }''')
        self.assertIn("statement TerraformStateBackendAssumeRole block:condition", guard.check(self.dir)[0])

    def test_upstream_second_condition_block_fails(self) -> None:
        # Bad: upstream has two condition blocks, the override only the last one; a dict keyed by block
        # name kept one condition per statement and passed this (E4c2b).
        anchor = '"${var.tf_access_bucket_arn}/*"]\n  }'
        condition = '''
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = ["%s"]
    }'''
        for name, values in ((guard.OVERRIDE, ["o-b"]), (guard.UPSTREAM, ["o-a", "o-b"])):
            blocks = "".join(condition % value for value in values)
            self.mutate(name, anchor, '"${var.tf_access_bucket_arn}/*"]' + blocks + "\n  }")
        errors = guard.check(self.dir)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("statement TerraformStateBackendS3BucketReadOnly block:condition", errors[0])

    def test_reordered_condition_blocks_pass(self) -> None:
        # Positive control: the same two condition blocks, in another order, are the same statement.
        anchor = '"${var.tf_access_bucket_arn}/*"]\n  }'
        condition = '''
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = ["%s"]
    }'''
        for name, values in ((guard.OVERRIDE, ["o-b", "o-a"]), (guard.UPSTREAM, ["o-a", "o-b"])):
            blocks = "".join(condition % value for value in values)
            self.mutate(name, anchor, '"${var.tf_access_bucket_arn}/*"]' + blocks + "\n  }")
        self.assertEqual(guard.check(self.dir), [])

    def test_upstream_dynamic_statement_for_each_changed_fails(self) -> None:
        # Bad: the same dynamic statement in both, but upstream changes its for_each.
        anchor = '"${var.tf_access_bucket_arn}/*"]\n  }'
        dynamic = '''
  dynamic "statement" {
    for_each = %s
    content {
      sid       = "Extra"
      actions   = ["s3:GetObject"]
      resources = ["*"]
    }
  }'''
        for name, for_each in ((guard.OVERRIDE, "[1]"), (guard.UPSTREAM, "local.enabled ? [1] : []")):
            self.mutate(name, anchor, anchor + "\n" + dynamic % for_each)
        errors = guard.check(self.dir)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("statement Extra dynamic.attr:for_each", errors[0])

    def test_assumed_role_is_the_one_allowed_difference(self) -> None:
        self.mutate(guard.OVERRIDE, '-read-role"]', '-other-role"]')
        self.assertEqual(guard.check(self.dir), [])

    def test_upstream_field_added_or_changed_fails(self) -> None:
        self.mutate(guard.UPSTREAM, '    role_arn           = string\n',
                    '    role_arn           = string\n    region             = optional(string)\n')
        self.assertIn("tf_access_additional_backends field region", guard.check(self.dir)[0])


if __name__ == "__main__":
    unittest.main()

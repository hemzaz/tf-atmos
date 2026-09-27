"""Tests for checkov-baseline-index-twins.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import pathlib
import tempfile
import unittest

_spec = importlib.util.spec_from_file_location(
    "index_twins", pathlib.Path(__file__).with_name("checkov-baseline-index-twins.py")
)
index_twins = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(index_twins)

MAIN_TF = '''
resource "aws_s3_bucket" "counted" {
  count  = var.enabled ? 1 : 0
  bucket = "x" # a { brace in a comment
}

resource "aws_cloudwatch_log_group" "plain" {
  name = "a { brace in a string"
  dynamic "tag" {
    for_each = var.tags
    content {
      count = 1
    }
  }
}

data "aws_ec2_managed_prefix_list" "s3" {
  count = var.enabled ? 1 : 0
}

resource "aws_security_group" "proxy" {
  count = var.enable_proxy ? 1 : 0
}
'''


def finding(resource, *check_ids):
    return {"resource": resource, "check_ids": list(check_ids)}


class IndexTwinsTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.components = pathlib.Path(self._tmp.name)
        (self.components / "comp").mkdir()
        (self.components / "comp" / "main.tf").write_text(MAIN_TF)

    def tearDown(self):
        self._tmp.cleanup()

    def run_twins(self, findings, file="/comp/main.tf"):
        data = {"failed_checks": [{"file": file, "findings": findings}]}
        added = index_twins.add_twins(data, self.components)
        return added, {f["resource"]: f["check_ids"] for f in data["failed_checks"][0]["findings"]}

    def test_counted_resources_ignores_nested_counts_and_data_blocks(self):
        self.assertEqual(
            index_twins.counted_resources(self.components / "comp" / "main.tf"),
            {"aws_s3_bucket.counted", "aws_security_group.proxy"},
        )

    def test_indexed_entry_gets_bare_twin(self):
        added, out = self.run_twins([finding("aws_s3_bucket.counted[0]", "CKV_AWS_18")])
        self.assertEqual(added, 1)
        self.assertEqual(out["aws_s3_bucket.counted"], ["CKV_AWS_18"])
        self.assertEqual(out["aws_s3_bucket.counted[0]"], ["CKV_AWS_18"])

    def test_bare_counted_entry_gets_indexed_twin(self):
        _, out = self.run_twins([finding("aws_s3_bucket.counted", "CKV_AWS_18")])
        self.assertEqual(out["aws_s3_bucket.counted[0]"], ["CKV_AWS_18"])

    def test_module_prefixed_counted_entry_gets_indexed_twin(self):
        _, out = self.run_twins([finding("module.db.aws_security_group.proxy", "CKV2_AWS_5")])
        self.assertEqual(out["module.db.aws_security_group.proxy[0]"], ["CKV2_AWS_5"])

    def test_uncounted_entry_followed_by_counted_data_block_gets_no_twin(self):
        added, out = self.run_twins([finding("aws_cloudwatch_log_group.plain", "CKV_AWS_338")])
        self.assertEqual(added, 0)
        self.assertEqual(list(out), ["aws_cloudwatch_log_group.plain"])

    def test_missing_file_still_twins_indexed_entries(self):
        _, out = self.run_twins([finding("aws_x.y[0]", "CKV_1"), finding("aws_x.z", "CKV_2")], file="/gone/main.tf")
        self.assertEqual(sorted(out), ["aws_x.y", "aws_x.y[0]", "aws_x.z"])

    def test_idempotent_and_merges_duplicate_rows(self):
        findings = [finding("aws_s3_bucket.counted", "CKV_A"), finding("aws_s3_bucket.counted", "CKV_B")]
        data = {"failed_checks": [{"file": "/comp/main.tf", "findings": findings}]}
        index_twins.add_twins(data, self.components)
        once = repr(data)
        self.assertEqual(index_twins.add_twins(data, self.components), 0)
        self.assertEqual(repr(data), once)
        by_resource = {f["resource"]: f["check_ids"] for f in data["failed_checks"][0]["findings"]}
        self.assertEqual(by_resource["aws_s3_bucket.counted"], ["CKV_A", "CKV_B"])
        self.assertEqual(by_resource["aws_s3_bucket.counted[0]"], ["CKV_A", "CKV_B"])


if __name__ == "__main__":
    unittest.main()

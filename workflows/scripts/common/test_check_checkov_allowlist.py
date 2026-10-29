"""Tests for scripts/check-checkov-allowlist.py: python3 -m unittest workflows/scripts/common/test_check_checkov_allowlist.py"""

import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_checkov_allowlist",
    pathlib.Path(__file__).resolve().parents[3] / "scripts" / "check-checkov-allowlist.py")
check = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check)

ALLOW = (
    (r"/aws-dns-primary/main\.tf", "CKV2_AWS_38", "signed by the house dns"),
    (r"/account-map/modules/iam-roles/main\.tf", "CKV_TF_1", "pinned by Cloud Posse"),
)


def finding(path, check_id, severity=None):
    return {"file_path": path, "check_id": check_id, "severity": severity,
            "resource": "r", "check_name": "n"}


def report(*failed):
    return {"results": {"failed_checks": list(failed)}, "summary": {}}


ACCEPTED = (finding("/aws-dns-primary/main.tf", "CKV2_AWS_38"),
            # A module's finding, reported once per caller: both match one entry.
            finding("/account-map/modules/iam-roles/main.tf", "CKV_TF_1"),
            finding("/account-map/modules/iam-roles/main.tf", "CKV_TF_1"))


class Gate(unittest.TestCase):
    def test_every_finding_allowlisted_passes(self):
        self.assertEqual(check.gate(report(*ACCEPTED), ALLOW), ([], []))

    def test_finding_removed_from_allowlist_fails(self):
        findings, stale = check.gate(report(*ACCEPTED), ALLOW[1:])
        self.assertEqual(len(findings), 1)
        self.assertIn("CKV2_AWS_38 /aws-dns-primary/main.tf", findings[0])
        self.assertEqual(stale, [])

    def test_stale_entry_fails(self):
        findings, stale = check.gate(report(*ACCEPTED[1:]), ALLOW)
        self.assertEqual(findings, [])
        self.assertEqual(len(stale), 1)
        self.assertIn("CKV2_AWS_38", stale[0])

    def test_entry_is_per_check_and_per_file(self):
        # The same check in another file, or another check in the same file, is not accepted.
        findings, _ = check.gate(report(*ACCEPTED,
                                        finding("/dns/main.tf", "CKV2_AWS_38"),
                                        finding("/aws-dns-primary/main.tf", "CKV2_AWS_39")), ALLOW)
        self.assertEqual(len(findings), 2)

    def test_path_is_matched_in_full(self):
        findings, _ = check.gate(report(*ACCEPTED, finding("/x/aws-dns-primary/main.tf", "CKV2_AWS_38")),
                                 ALLOW)
        self.assertEqual(len(findings), 1)

    def test_severity_semantics_kept(self):
        # --soft-fail-on LOW,MEDIUM; HIGH, CRITICAL and unknown (no API key) fail.
        failed = [finding("/vpc/main.tf", "CKV_X", s) for s in ("LOW", "MEDIUM", "HIGH", "CRITICAL", None)]
        findings, _ = check.gate(report(*ACCEPTED, *failed), ALLOW)
        self.assertEqual(len(findings), 3)

    def test_list_of_reports(self):
        self.assertEqual(check.gate([report(ACCEPTED[0]), report(*ACCEPTED[1:])], ALLOW), ([], []))

    def test_real_allowlist_is_well_formed(self):
        for pattern, check_id, reason in check.ALLOWLIST:
            self.assertTrue(pattern.startswith("/") and check_id.startswith("CKV") and reason.strip())
        self.assertEqual(len(set((p, c) for p, c, _ in check.ALLOWLIST)), len(check.ALLOWLIST))


class DropSarif(unittest.TestCase):
    def test_drops_only_allowlisted(self):
        def result(uri, rule):
            return {"ruleId": rule, "locations": [{"physicalLocation": {"artifactLocation": {"uri": uri}}}]}
        sarif = {"runs": [{"results": [result("aws-dns-primary/main.tf", "CKV2_AWS_38"),
                                       result("components/terraform/aws-dns-primary/main.tf", "CKV2_AWS_38"),
                                       result("dns/main.tf", "CKV2_AWS_38")]}]}
        self.assertEqual(check.drop_sarif(sarif, ALLOW), 2)
        self.assertEqual(sarif["runs"][0]["results"][0]["locations"][0]["physicalLocation"]
                         ["artifactLocation"]["uri"], "dns/main.tf")


if __name__ == "__main__":
    unittest.main()

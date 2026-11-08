"""Tests for workflows/scripts/security/harden.sh's component selection, against a fake atmos on
PATH (stdlib only; needs bash and jq): python3 -m unittest workflows/scripts/common/test_harden.py

Skipped without jq: the CI image ships none, and the toolchain's jqlang/jq fails its
attestation check there, so this runs locally (validate-all's unittest discover) only.

HARDEN_PHASE=plan stops after the plans, so no aws CLI call is reached.
"""
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "workflows/scripts/security/harden.sh"

FAKE_ATMOS = """#!/usr/bin/env bash
echo "atmos $*" >> "$FAKE_LOG"
case "$1 $2" in
  "describe component") cat "$FAKE_CONTEXT" ;;
  "describe stacks") cat "$FAKE_STACKS"; exit "${FAKE_STACKS_RC:-0}" ;;
  "terraform plan") exit 0 ;;
  *) exit 99 ;;
esac
"""

CONTEXT = {"settings": {"context": {"tenant": "fnx", "stage": "prod"}, "environment": {"account": "prod"}},
           "vars": {"tags": {"Environment": "ue2"}, "region": "us-east-2"},
           "backend": {"bucket": "fnx-terraform-state"}}


def stacks(stack, *instances, abstract=()):
    terraform = {name: {"metadata": {"component": name}} for name in instances}
    terraform.update({name: {"metadata": {"type": "abstract"}} for name in abstract})
    return {stack: {"components": {"terraform": terraform}}}


@unittest.skipUnless(shutil.which("bash") and shutil.which("jq"), "bash and jq are required")
class HardenSelectionTest(unittest.TestCase):
    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        (self.dir / "bin").mkdir()
        atmos = self.dir / "bin/atmos"
        atmos.write_text(FAKE_ATMOS)
        atmos.chmod(0o755)
        (self.dir / "context.json").write_text(json.dumps(CONTEXT))

    def run_harden(self, document, rc=0, stack="fnx-ue2-prod"):
        (self.dir / "stacks.json").write_text(json.dumps(document))
        log = self.dir / "atmos.log"
        log.write_text("")
        env = {
            "PATH": f"{self.dir / 'bin'}:{os.environ['PATH']}", "FAKE_LOG": str(log),
            "FAKE_CONTEXT": str(self.dir / "context.json"), "FAKE_STACKS": str(self.dir / "stacks.json"),
            "FAKE_STACKS_RC": str(rc), "STACK": stack, "HARDEN_PHASE": "plan",
        }
        result = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True)
        plans = [line.split()[3] for line in log.read_text().splitlines() if line.startswith("atmos terraform plan")]
        return result.returncode, plans, result.stdout + result.stderr

    def test_standby_without_trail_skips_it_and_plans_the_rest(self):
        rc, plans, out = self.run_harden(stacks("fnx-ue2-prod", "aws-config", "guardduty/main", "securityhub/main",
                                                "vpc/main", abstract=("aws-config/main-region",)))
        self.assertEqual(rc, 0, out)
        self.assertEqual(plans, ["aws-config", "guardduty/main", "securityhub/main"])
        self.assertIn("[SKIP]", out)
        self.assertIn("cloudtrail: fnx-ue2-prod has no such instance", out)

    def test_home_stack_plans_all_four_in_order(self):
        rc, plans, out = self.run_harden(stacks("fnx-ue2-prod", "securityhub/main", "guardduty/main", "aws-config",
                                                "cloudtrail"))
        self.assertEqual(rc, 0, out)
        self.assertEqual(plans, ["cloudtrail", "aws-config", "guardduty/main", "securityhub/main"])

    def test_core_stack_plans_only_its_recorder(self):
        rc, plans, out = self.run_harden(stacks("fnx-ue2-prod", "aws-config", "aws-account-settings"))
        self.assertEqual(rc, 0, out)
        self.assertEqual(plans, ["aws-config"])

    def test_unknown_stack_fails(self):
        rc, plans, out = self.run_harden({})
        self.assertEqual(rc, 1, out)
        self.assertEqual(plans, [])
        self.assertIn("stack fnx-ue2-prod is unknown to atmos", out)

    def test_failed_describe_fails(self):
        rc, plans, out = self.run_harden({}, rc=1)
        self.assertEqual(rc, 1, out)
        self.assertEqual(plans, [])
        self.assertIn("atmos describe stacks -s fnx-ue2-prod failed", out)

    def test_stack_without_aws_config_fails(self):
        # An abstract aws-config variant is not an instance.
        rc, plans, out = self.run_harden(stacks("fnx-ue2-prod", "cloudtrail", "guardduty/main", "securityhub/main",
                                                abstract=("aws-config", "aws-config/main")))
        self.assertEqual(rc, 1, out)
        self.assertEqual(plans, [])
        self.assertIn("fnx-ue2-prod has no aws-config instance", out)


if __name__ == "__main__":
    unittest.main()

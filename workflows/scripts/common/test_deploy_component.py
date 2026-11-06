"""Tests for deploy-component.sh against a fake atmos on PATH (stdlib only; needs bash and git):
python3 -m unittest workflows/scripts/common/test_deploy_component.py

The fake atmos exits 0 from every plan, as Atmos does with ci.enabled even
when the plan has changes (it maps -detailed-exitcode's 2 to 0), so the
script must decide from the plan JSON.
"""
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "workflows/scripts/common/deploy-component.sh"
STACK, COMPONENT = "fnx-ue1-prod", "rds/main"

FAKE_ATMOS = """#!/usr/bin/env bash
echo "atmos $*" >> "$FAKE_LOG"
case "$1 $2" in
  "terraform plan")
    for arg in "$@"; do case "$arg" in -out=*) touch "${arg#-out=}" ;; esac; done
    exit "${FAKE_PLAN_RC:-0}" ;;
  "terraform show") echo "Initializing the backend..."; cat "$FAKE_PLAN" ;;
  "describe component") echo "{\\"settings\\": $FAKE_SETTINGS}" ;;
  "terraform deploy") exit 0 ;;
  *) exit 99 ;;
esac
"""


def plan(*changes):
    return {"format_version": "1.2", "resource_changes": [
        {"address": address, "mode": "managed", "change": {"actions": list(actions)}} for address, actions in changes]}


@unittest.skipUnless(shutil.which("bash") and shutil.which("git"), "bash and git are required")
class DeployComponentTest(unittest.TestCase):
    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        (self.dir / "bin").mkdir()
        atmos = self.dir / "bin/atmos"
        atmos.write_text(FAKE_ATMOS)
        atmos.chmod(0o755)
        # A repository whose base..HEAD carries the trailers the test needs.
        self.repo = self.dir / "repo"
        shutil.copytree(ROOT / "workflows/scripts/common", self.repo / "workflows/scripts/common",
                        ignore=shutil.ignore_patterns("__pycache__", "test_*"))
        self.git("init", "-q")
        self.git("commit", "-q", "--allow-empty", "-m", "base")
        self.base = self.git("rev-parse", "HEAD").strip()

    def git(self, *args):
        return subprocess.check_output(
            ["git", "-C", str(self.repo), "-c", "user.name=t", "-c", "user.email=t@t", *args], text=True)

    def run_script(self, document, stage="prod", plan_rc=0):
        (self.dir / "plan.json").write_text(json.dumps(document) + "\n")
        log = self.dir / "atmos.log"
        log.write_text("")
        env = {
            "PATH": f"{self.dir / 'bin'}:{os.environ['PATH']}",
            "FAKE_LOG": str(log), "FAKE_PLAN": str(self.dir / "plan.json"), "FAKE_PLAN_RC": str(plan_rc),
            "FAKE_SETTINGS": json.dumps({"context": {"stage": stage}}),
            "STACK": STACK, "BASE_SHA": self.base, "GITHUB_SHA": "HEAD", "RUNNER_TEMP": str(self.dir / "tmp"),
        }
        result = subprocess.run(["bash", str(SCRIPT), COMPONENT], cwd=self.repo, env=env, capture_output=True, text=True)
        calls = [line.split()[2] for line in log.read_text().splitlines() if line.startswith("atmos terraform")]
        return result.returncode, calls, result.stdout + result.stderr

    def test_no_changes_applies_nothing(self):
        code, calls, out = self.run_script(plan(("a.n", ["no-op"])))
        self.assertEqual((code, calls), (0, ["plan", "show"]), out)

    def test_plan_exit_0_with_changes_applies_the_planfile(self):
        """The ci.enabled exit-code remap: rc 0 must not mean no changes."""
        code, calls, out = self.run_script(plan(("a.u", ["update"])), plan_rc=0)
        self.assertEqual((code, calls), (0, ["plan", "show", "deploy"]), out)
        self.assertIn("--planfile", (self.dir / "atmos.log").read_text().splitlines()[-1])

    def test_prod_delete_without_a_trailer_fails_before_apply(self):
        code, calls, out = self.run_script(plan(("aws_db_instance.this", ["delete", "create"])))
        self.assertEqual((code, calls), (1, ["plan", "show"]), out)
        self.assertIn("Destroy not allowed", out)

    def test_prod_delete_with_the_scoped_trailer_applies(self):
        self.git("commit", "-q", "--allow-empty", "-m",
                 f"drop it\n\nAllow-Destroy: {COMPONENT}/{STACK}:aws_db_instance.this")
        code, calls, out = self.run_script(plan(("aws_db_instance.this", ["delete"])))
        self.assertEqual((code, calls), (0, ["plan", "show", "deploy"]), out)

    def test_dev_delete_warns_and_applies(self):
        code, calls, out = self.run_script(plan(("aws_db_instance.this", ["delete"])), stage="dev")
        self.assertEqual((code, calls), (0, ["plan", "show", "deploy"]), out)
        self.assertIn("::warning", out)

    def test_plan_error_fails(self):
        code, calls, out = self.run_script(plan(), plan_rc=1)
        self.assertEqual((code, calls), (1, ["plan"]), out)


if __name__ == "__main__":
    unittest.main()

"""Tests for deploy-component.sh and the drift loops of drift-detection.yml and in-vpc.yml, against a
fake atmos on PATH (stdlib only; needs bash and git):
python3 -m unittest workflows/scripts/common/test_deploy_component.py

Everything runs as GitHub runs a `shell: bash` step: bash --noprofile --norc -eo pipefail.
The fake atmos exits 0 from every successful plan, as Atmos does with ci.enabled even
when the plan has changes (it maps -detailed-exitcode's 2 to 0), so the
scripts must decide from the plan JSON.
"""
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "workflows/scripts/common/deploy-component.sh"
WORKFLOWS = ROOT / ".github/workflows"
GITHUB_BASH = ["bash", "--noprofile", "--norc", "-eo", "pipefail"]
STACK, COMPONENT = "fnx-ue1-prod", "rds/main"

FAKE_ATMOS = """#!/usr/bin/env bash
echo "atmos $*" >> "$FAKE_LOG"
case "$1 $2" in
  "terraform plan")
    for arg in "$@"; do case "$arg" in -out=*) touch "${arg#-out=}" ;; esac; done
    exit "${FAKE_PLAN_RC:-0}" ;;
  "terraform show") echo "Initializing the backend..."; cat "$FAKE_PLAN"; exit "${FAKE_SHOW_RC:-0}" ;;
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

    def run_script(self, document, stage="prod", plan_rc=0, show_rc=0):
        (self.dir / "plan.json").write_text(json.dumps(document) + "\n")
        log = self.dir / "atmos.log"
        log.write_text("")
        env = {
            "PATH": f"{self.dir / 'bin'}:{os.environ['PATH']}",
            "FAKE_LOG": str(log), "FAKE_PLAN": str(self.dir / "plan.json"), "FAKE_PLAN_RC": str(plan_rc),
            "FAKE_SHOW_RC": str(show_rc),
            "FAKE_SETTINGS": json.dumps({"context": {"stage": stage}}),
            "STACK": STACK, "BASE_SHA": self.base, "GITHUB_SHA": "HEAD", "RUNNER_TEMP": str(self.dir / "tmp"),
        }
        result = subprocess.run([*GITHUB_BASH, str(SCRIPT), COMPONENT], cwd=self.repo, env=env, capture_output=True, text=True)
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

    def test_a_failed_show_fails_even_after_printing_a_no_change_plan(self):
        """pipefail alone would report the checker's 3 (no changes) and mark the stack deployed."""
        code, calls, out = self.run_script(plan(("a.n", ["no-op"])), show_rc=1)
        self.assertEqual((code, calls), (1, ["plan", "show"]), out)
        self.assertIn("show failed", out)

    def test_plan_error_fails(self):
        code, calls, out = self.run_script(plan(), plan_rc=1)
        self.assertEqual((code, calls), (1, ["plan"]), out)


# Plans and shows by component name ($3), from files in FAKE_DIR.
DRIFT_ATMOS = """#!/usr/bin/env bash
case "$1 $2" in
  "terraform plan") echo "planning $3"; exit "$(cat "$FAKE_DIR/$3.plan_rc")" ;;
  "terraform show") cat "$FAKE_DIR/$3.out"; exit "$(cat "$FAKE_DIR/$3.show_rc")" ;;
esac
exit 99
"""

# component: (plan rc, show output, show rc, expected class)
DRIFT_CASES = {
    "clean": (0, json.dumps(plan(("a.n", ["no-op"]))), 0, "clean"),
    "drifted": (0, json.dumps(plan(("a.u", ["update"]))), 0, "drifted"),
    "planfail": (1, "", 0, "failed"),
    "showfail": (0, json.dumps(plan(("a.n", ["no-op"]))), 1, "failed"),
    "notplan": (0, "Error: no planfile", 0, "failed"),
}
STEP_TAIL = 'echo "clean=${clean[*]-}"\necho "drifted=${drifted[*]-}"\necho "failed=${failed[*]-}"\n'


def drift_loop(workflow: str) -> str:
    """The per-instance plan loop of a workflow's drift step, from its arrays to `done`, dedented."""
    text = (WORKFLOWS / workflow).read_text()
    match = re.search(r'^( *)clean=\(\) drifted=\(\) failed=\(\) n=0\n.*?^\1done <<<"\$components"\n',
                      text, re.M | re.S)
    if not match:
        raise AssertionError(f"no drift loop in {workflow}")
    indent = len(match.group(1))
    return "".join(line[indent:] + "\n" for line in match.group(0).splitlines())


@unittest.skipUnless(shutil.which("bash"), "bash is required")
class DriftLoopTest(unittest.TestCase):
    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        (self.dir / "bin").mkdir()
        (self.dir / "bin/atmos").write_text(DRIFT_ATMOS)
        (self.dir / "bin/atmos").chmod(0o755)
        (self.dir / "work/drift-logs").mkdir(parents=True)
        (self.dir / "work/workflows").symlink_to(ROOT / "workflows")
        for component, (plan_rc, out, show_rc, _) in DRIFT_CASES.items():
            (self.dir / f"{component}.plan_rc").write_text(str(plan_rc))
            (self.dir / f"{component}.out").write_text(out + "\n")
            (self.dir / f"{component}.show_rc").write_text(str(show_rc))

    def classify(self, workflow: str) -> dict:
        script = self.dir / "step.sh"
        components = "\n".join(DRIFT_CASES)
        script.write_text(f"set -uo pipefail\ncomponents='{components}'\n" + drift_loop(workflow) + STEP_TAIL)
        env = {"PATH": f"{self.dir / 'bin'}:{os.environ['PATH']}", "FAKE_DIR": str(self.dir),
               "STACK": "fnx-ue1-dev", "RUNNER_TEMP": str(self.dir)}
        result = subprocess.run([*GITHUB_BASH, str(script)], cwd=self.dir / "work", env=env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, f"{workflow}: the step aborted\n{result.stdout}{result.stderr}")
        found = {}
        for line in result.stdout.splitlines():
            name, _, value = line.partition("=")
            if name in ("clean", "drifted", "failed"):
                found[name] = [entry.split("=")[0] for entry in value.split()]
        return found

    def test_both_drift_loops_classify_every_case_without_aborting(self):
        expected = {cls: [c for c, case in DRIFT_CASES.items() if case[3] == cls]
                    for cls in ("clean", "drifted", "failed")}
        for workflow in ("drift-detection.yml", "in-vpc.yml"):
            self.assertEqual(self.classify(workflow), expected, workflow)


if __name__ == "__main__":
    unittest.main()

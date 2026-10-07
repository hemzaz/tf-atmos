"""Tests for the self-hosted runner shell scripts (stdlib only; needs bash and jq):
python3 -m unittest workflows/scripts/common/test_runner_scripts.py

- components/terraform/github-runners/files/job-started.sh, the runners'
  fork guard, run as the runner runs it: with GITHUB_* and an event payload.
- workflows/scripts/common/start-runner.sh, against a fake aws on PATH.
"""
import json
import os
import pathlib
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
HOOK = ROOT / "components/terraform/github-runners/files/job-started.sh"
START = ROOT / "workflows/scripts/common/start-runner.sh"
REPO = "hemzaz/tf-atmos"


@unittest.skipUnless(shutil.which("jq"), "jq is required")
class JobStartedHookTest(unittest.TestCase):
    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        shutil.copy(HOOK, self.dir / "job-started.sh")

    def run_hook(self, event, payload=None, scope=REPO, refs="", ref="refs/heads/master", repository=REPO):
        (self.dir / "policy").write_text(f"ALLOWED_SCOPE='{scope}'\nALLOWED_REFS='{refs}'\n")
        event_path = self.dir / "event.json"
        event_path.write_text(json.dumps(payload or {}))
        env = {
            "PATH": os.environ["PATH"],
            "GITHUB_REPOSITORY": repository,
            "GITHUB_EVENT_NAME": event,
            "GITHUB_EVENT_PATH": str(event_path),
            "GITHUB_REF": ref,
        }
        result = subprocess.run(["bash", str(self.dir / "job-started.sh")], env=env, capture_output=True, text=True)
        return result.returncode, result.stdout

    @staticmethod
    def pull_request(head):
        return {"pull_request": {"head": {"repo": {"full_name": head}}}}

    def test_trusted_events_of_the_repository_run(self):
        for event in ("push", "workflow_dispatch", "schedule", "merge_group"):
            self.assertEqual(self.run_hook(event)[0], 0, event)

    def test_same_repository_pull_request_runs(self):
        code, _ = self.run_hook("pull_request", self.pull_request(REPO), ref="refs/pull/7/merge")
        self.assertEqual(code, 0)

    def test_fork_pull_request_is_refused(self):
        code, out = self.run_hook("pull_request", self.pull_request("mallory/tf-atmos"), ref="refs/pull/7/merge")
        self.assertEqual(code, 1)
        self.assertIn("a pull request from 'mallory/tf-atmos'", out)

    def test_pull_request_without_a_head_is_refused(self):
        self.assertEqual(self.run_hook("pull_request", {})[0], 1)

    def test_other_events_are_refused(self):
        for event in ("pull_request_target", "workflow_run", "issue_comment", "pull_request_review", ""):
            code, out = self.run_hook(event, self.pull_request(REPO))
            self.assertEqual(code, 1, event)
            self.assertIn(f"event '{event}'", out)

    def test_another_repository_is_refused(self):
        code, out = self.run_hook("push", repository="mallory/tf-atmos")
        self.assertEqual(code, 1)
        self.assertIn("is not hemzaz/tf-atmos", out)

    def test_organization_scope_admits_its_repositories_only(self):
        self.assertEqual(self.run_hook("push", scope="hemzaz")[0], 0)
        self.assertEqual(self.run_hook("push", scope="hemzaz", repository="mallory/tf-atmos")[0], 1)

    def test_allowed_refs_refuse_other_refs_even_for_trusted_events(self):
        self.assertEqual(self.run_hook("push", refs="refs/heads/master")[0], 0)
        code, out = self.run_hook("workflow_dispatch", refs="refs/heads/master", ref="refs/heads/feature")
        self.assertEqual(code, 1)
        self.assertIn("serves only refs/heads/master", out)
        same_repo_pr = self.run_hook("pull_request", self.pull_request(REPO), refs="refs/heads/master", ref="refs/pull/7/merge")
        self.assertEqual(same_repo_pr[0], 1)

    def test_missing_policy_fails_closed(self):
        (self.dir / "event.json").write_text("{}")
        env = {"PATH": os.environ["PATH"], "GITHUB_REPOSITORY": REPO, "GITHUB_EVENT_NAME": "push"}
        result = subprocess.run(["bash", str(self.dir / "job-started.sh")], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no policy", result.stdout)


class StartRunnerTest(unittest.TestCase):
    def run_start(self, asg, aws_exit=0, aws_output=""):
        bin_dir = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, bin_dir)
        log = bin_dir / "calls"
        aws = bin_dir / "aws"
        aws.write_text(f"#!/bin/bash\necho \"$*\" >> {log}\necho '{aws_output}'\nexit {aws_exit}\n")
        aws.chmod(aws.stat().st_mode | stat.S_IEXEC)
        env = {"PATH": f"{bin_dir}:{os.environ['PATH']}", "ASG": asg}
        result = subprocess.run(["bash", str(START)], env=env, capture_output=True, text=True)
        calls = log.read_text().splitlines() if log.exists() else []
        return result.returncode, result.stdout + result.stderr, calls

    def test_executes_the_pool_start_policy_once(self):
        code, _, calls = self.run_start("ue1-github-runners")
        self.assertEqual(code, 0)
        self.assertEqual(calls, [
            "autoscaling execute-policy --auto-scaling-group-name ue1-github-runners "
            "--policy-name ue1-github-runners-start --no-honor-cooldown"
        ])

    def test_a_full_pool_is_not_a_failure(self):
        code, out, _ = self.run_start("ue1-github-runners", 254, "New SetDesiredCapacity value 5 is above max value 4")
        self.assertEqual(code, 0)
        self.assertIn("at max_size", out)

    def test_other_errors_fail(self):
        code, out, _ = self.run_start("ue1-github-runners", 254, "AccessDenied")
        self.assertEqual(code, 1)
        self.assertIn("could not start a runner", out)

    def test_a_bad_group_name_is_refused_before_any_call(self):
        code, _, calls = self.run_start("ue1;rm -rf /")
        self.assertEqual(code, 1)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()

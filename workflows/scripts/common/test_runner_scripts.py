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
        self.marker = self.dir / "refused"
        (self.dir / "policy").write_text(
            f"ALLOWED_SCOPE='{scope}'\nALLOWED_REFS='{refs}'\nREFUSED_MARKER='{self.marker}'\n")
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

    def test_a_refused_job_leaves_the_marker_an_allowed_one_does_not(self):
        self.assertEqual(self.run_hook("pull_request", self.pull_request(REPO), ref="refs/pull/7/merge")[0], 0)
        self.assertFalse(self.marker.exists(), "an allowed job leaves no marker")
        for args in (
            ("pull_request", self.pull_request("mallory/tf-atmos")),
            ("pull_request_target", self.pull_request(REPO)),
        ):
            self.marker.unlink(missing_ok=True)
            self.assertEqual(self.run_hook(*args)[0], 1)
            self.assertTrue(self.marker.exists(), args[0])
        self.marker.unlink()
        self.assertEqual(self.run_hook("push", refs="refs/heads/master", ref="refs/heads/feature")[0], 1)
        self.assertTrue(self.marker.exists(), "a refused ref leaves the marker too")

    def test_missing_policy_fails_closed(self):
        (self.dir / "event.json").write_text("{}")
        env = {"PATH": os.environ["PATH"], "GITHUB_REPOSITORY": REPO, "GITHUB_EVENT_NAME": "push"}
        result = subprocess.run(["bash", str(self.dir / "job-started.sh")], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no policy", result.stdout)


class StartRunnerTest(unittest.TestCase):
    def run_start(self, asg, *replies):
        """Run start-runner.sh; each aws call takes the next (exit code, output) of replies (default success)."""
        bin_dir = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, bin_dir)
        for i, (code, output) in enumerate(replies):
            (bin_dir / f"reply{i}").write_text(f"{code}\n{output}\n")
        aws = bin_dir / "aws"
        aws.write_text(
            "#!/bin/bash\n"
            f"dir={bin_dir}\n"
            'n=$(ls "$dir"/call* 2>/dev/null | wc -l | tr -d " ")\n'
            'echo "$*" > "$dir/call$n"\n'
            '[ -f "$dir/reply$n" ] || exit 0\n'
            '{ read -r code; read -r output; } < "$dir/reply$n"\n'
            'echo "$output"\n'
            'exit "$code"\n'
        )
        sleep = bin_dir / "sleep"
        sleep.write_text(f'#!/bin/bash\necho "$1" >> {bin_dir}/sleeps\n')
        for script in (aws, sleep):
            script.chmod(script.stat().st_mode | stat.S_IEXEC)
        env = {"PATH": f"{bin_dir}:{os.environ['PATH']}", "ASG": asg}
        result = subprocess.run(["bash", str(START)], env=env, capture_output=True, text=True)
        calls = [(bin_dir / f"call{i}").read_text().strip() for i in range(len(list(bin_dir.glob("call*"))))]
        sleeps = (bin_dir / "sleeps").read_text().split() if (bin_dir / "sleeps").exists() else []
        return result.returncode, result.stdout + result.stderr, calls, sleeps

    DESCRIBE = ("autoscaling describe-auto-scaling-groups --auto-scaling-group-names ue1-github-runners "
                "--query AutoScalingGroups[0].[DesiredCapacity,MaxSize] --output text")
    EXECUTE = ("autoscaling execute-policy --auto-scaling-group-name ue1-github-runners "
               "--policy-name ue1-github-runners-start --no-honor-cooldown")
    BUSY = (254, "An error occurred (ScalingActivityInProgress) when calling the ExecutePolicy operation")

    def test_a_pool_with_room_executes_its_start_policy_once(self):
        code, out, calls, sleeps = self.run_start("ue1-github-runners", (0, "1\t4"))
        self.assertEqual((code, calls, sleeps), (0, [self.DESCRIBE, self.EXECUTE], []))
        self.assertIn("desired 1 of 4", out)

    def test_a_full_pool_fails_without_executing_the_policy(self):
        code, out, calls, _ = self.run_start("ue1-github-runners", (0, "4\t4"))
        self.assertEqual((code, calls), (1, [self.DESCRIBE]))
        self.assertIn("::error::runner pool ue1-github-runners is full (desired=max=4); this job would never get a runner", out)

    def test_a_missing_pool_fails(self):
        code, out, calls, _ = self.run_start("ue1-github-runners", (0, "None\tNone"))
        self.assertEqual((code, calls), (1, [self.DESCRIBE]))
        self.assertIn("not found", out)

    def test_transient_errors_are_retried_with_backoff(self):
        code, _, calls, sleeps = self.run_start(
            "ue1-github-runners",
            (254, "An error occurred (Throttling) when calling the DescribeAutoScalingGroups operation"),
            (0, "0\t4"),
            self.BUSY,
            (254, "An error occurred (ResourceContention) when calling the ExecutePolicy operation"))
        self.assertEqual(code, 0)
        self.assertEqual(calls, [self.DESCRIBE, self.DESCRIBE, self.EXECUTE, self.EXECUTE, self.EXECUTE])
        self.assertEqual(sleeps, ["5", "5", "10"])

    def test_a_lasting_transient_error_fails_after_three_retries(self):
        code, out, calls, sleeps = self.run_start("ue1-github-runners", (0, "0\t4"), *[self.BUSY] * 4)
        self.assertEqual((code, len(calls), sleeps), (1, 5, ["5", "10", "20"]))
        self.assertIn("::error::runner pool ue1-github-runners", out)

    def test_other_errors_fail_without_retry(self):
        code, _, calls, sleeps = self.run_start("ue1-github-runners", (0, "0\t4"), (254, "Max attempts exceeded"))
        self.assertEqual((code, len(calls), sleeps), (1, 2, []))

    def test_a_bad_group_name_is_refused_before_any_call(self):
        code, _, calls, _ = self.run_start("ue1;rm -rf /")
        self.assertEqual((code, calls), (1, []))


if __name__ == "__main__":
    unittest.main()

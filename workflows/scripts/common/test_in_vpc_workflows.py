"""Tests for the in-VPC gating in the workflow files (stdlib only, text checks):
python3 -m unittest workflows/scripts/common/test_in_vpc_workflows.py

Owner decision (#343, C3): in-VPC jobs run on the default branch only (push,
workflow_dispatch, schedule) with the stack's master-only apply role; a pull
request gets a ::notice:: and the CI gate accepts the skipped plan-in-vpc.
"""
import pathlib
import re
import unittest

WORKFLOWS = pathlib.Path(__file__).resolve().parents[3] / ".github/workflows"
MASTER_ONLY_IF = (
    "contains(fromJSON('[\"push\", \"workflow_dispatch\", \"schedule\"]'), github.event_name) &&\n"
    "      github.ref == format('refs/heads/{0}', github.event.repository.default_branch)"
)


def job(text: str, name: str) -> str:
    """The text of one top-level job of a workflow."""
    match = re.search(rf"^  {re.escape(name)}:\n(.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)", text, re.MULTILINE | re.DOTALL)
    if not match:
        raise AssertionError(f"no job {name}")
    return match.group(1)


class InVpcWorkflowTest(unittest.TestCase):
    in_vpc = (WORKFLOWS / "in-vpc.yml").read_text()
    ci = (WORKFLOWS / "terraform-ci.yml").read_text()

    def test_both_jobs_run_on_the_default_branch_only(self):
        for name in ("start", "run"):
            body = job(self.in_vpc, name)
            self.assertIn(MASTER_ONLY_IF, body, name)
            self.assertNotIn("pull_request", body, name)
            self.assertNotIn("merge_group", body, name)

    def test_both_jobs_assume_the_apply_role(self):
        self.assertNotIn("inputs.role", self.in_vpc)
        self.assertEqual(self.in_vpc.count("ci-apply-role-arn.py --kind apply"), 2)
        self.assertNotIn("--kind plan", self.in_vpc)

    def test_no_caller_passes_a_role_or_inherits_secrets(self):
        for path in WORKFLOWS.glob("*.yml"):
            text = path.read_text()
            for call in re.findall(r"uses: \./\.github/workflows/in-vpc\.yml\n(.*?)(?=^  \S|\Z)", text, re.M | re.S):
                self.assertNotIn("role:", call, path.name)
                self.assertNotIn("secrets: inherit", call, path.name)

    def test_plan_in_vpc_runs_on_a_push_to_the_default_branch_only(self):
        body = job(self.ci, "plan-in-vpc")
        condition = re.search(r"^    if: (.*)$", body, re.MULTILINE).group(1)
        self.assertTrue(condition.startswith(
            "${{ github.event_name == 'push' && github.ref == format('refs/heads/{0}', "
            "github.event.repository.default_branch) &&"), condition)
        self.assertNotIn("pull_request", condition)

    def test_pull_requests_get_the_notice_from_affected(self):
        body = job(self.ci, "affected")
        self.assertIn('"--event", os.environ["GITHUB_EVENT_NAME"]', body)
        self.assertIn("DEFAULT_BRANCH: ${{ github.event.repository.default_branch }}", body)
        self.assertIn("::notice title=In-VPC plans::", body)

    def test_the_gate_accepts_a_skipped_plan_in_vpc(self):
        body = job(self.ci, "gate")
        self.assertIn("plan-in-vpc", re.search(r"needs: \[(.*)\]", body).group(1))
        self.assertIn('.value.result != "skipped"', body)


if __name__ == "__main__":
    unittest.main()

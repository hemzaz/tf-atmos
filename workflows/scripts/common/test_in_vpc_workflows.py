"""Tests for the in-VPC gating in the workflow files (stdlib only, text checks):
python3 -m unittest workflows/scripts/common/test_in_vpc_workflows.py

Owner decision (#343, C3): in-VPC jobs run on the default branch only (push,
workflow_dispatch, schedule) with the stack's master-only apply role; a pull
request gets a ::notice:: and the CI gate accepts the skipped plan-in-vpc.
"""
import importlib.util
import pathlib
import re
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_cluster_api_ci", pathlib.Path(__file__).with_name("check-cluster-api-ci.py"))
check_cluster_api_ci = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_cluster_api_ci)

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

    def test_both_jobs_use_the_pool_region(self):
        """A us-east-2 pool's group exists only in us-east-2: never a repository-wide default region."""
        self.assertNotIn("vars.AWS_REGION", self.in_vpc)
        for name in ("start", "run"):
            self.assertIn("aws-region: ${{ inputs.region }}", job(self.in_vpc, name), name)

    def test_every_caller_passes_the_matrix_region(self):
        calls = 0
        for path in WORKFLOWS.glob("*.yml"):
            for call in re.findall(r"uses: \./\.github/workflows/in-vpc\.yml\n(.*?)(?=^  \S|\Z)",
                                   path.read_text(), re.M | re.S):
                calls += 1
                self.assertIn("region: ${{ matrix.region }}", call, path.name)
        self.assertEqual(calls, 4)

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


class PoolDemandTest(unittest.TestCase):
    """At most IN_VPC_JOBS_PER_POOL in-VPC jobs want one pool at once: one per concurrency family."""

    def callers(self):
        """(workflow text, caller job text) for every job that calls in-vpc.yml."""
        for path in sorted(WORKFLOWS.glob("*.yml")):
            text = path.read_text()
            for match in re.finditer(r"^  ([A-Za-z0-9_-]+):\n", text, re.MULTILINE):
                body = job(text, match.group(1))
                if "uses: ./.github/workflows/in-vpc.yml" in body:
                    yield path.name, text, match.group(1), body

    def family(self, workflow, text, name, body):
        """A caller's concurrency family: its job group without the ${{ }} parts, else its workflow's group."""
        own = re.search(r"^    concurrency:\n      group: (.*)$", body, re.MULTILINE)
        if own:
            self.assertIn("${{ matrix.stack }}-${{ matrix.asg }}", own.group(1), f"{workflow} {name}: one group per pool")
            return re.sub(r"\$\{\{[^}]*\}\}", "", own.group(1)).rstrip("-")
        workflow_group = re.search(r"^concurrency:\n  group: (\S+)$", text, re.MULTILINE)
        self.assertIsNotNone(workflow_group, f"{workflow} {name} has no concurrency group")
        self.assertIn("max-parallel: 1", body, f"{workflow} {name}: one matrix entry at a time")
        return workflow_group.group(1)

    def test_the_concurrency_families_match_the_check_constant(self):
        families = {self.family(*caller) for caller in self.callers()}
        self.assertEqual(families, {"terraform-cd-main", "in-vpc-plan", "in-vpc-drift"})
        self.assertEqual(len(families), check_cluster_api_ci.IN_VPC_JOBS_PER_POOL)

    def test_plans_cancel_superseded_runs_and_drift_waits(self):
        callers = {name: body for _, _, name, body in self.callers()}
        self.assertIn("cancel-in-progress: true", callers["plan-in-vpc"])
        self.assertIn("cancel-in-progress: false", callers["drift-in-vpc"])


if __name__ == "__main__":
    unittest.main()

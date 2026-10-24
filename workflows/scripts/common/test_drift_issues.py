"""Tests for drift-issues.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import json
import pathlib
import tempfile
import unittest
import urllib.error

_spec = importlib.util.spec_from_file_location("drift_issues", pathlib.Path(__file__).with_name("drift-issues.py"))
drift_issues = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(drift_issues)

RUN = "https://github.com/o/r/actions/runs/{}"
LOG = "\x1b[1m  # aws_s3_bucket.this\x1b[0m will be updated in-place\nnoise\nPlan: 0 to add, 1 to change, 0 to destroy.\n"


class FakeGitHub:
    """The issues and labels REST endpoints drift-issues.py calls, in memory."""

    def __init__(self):
        self.labels, self.issues, self.comments, self.mutations = set(), {}, [], []

    def api(self, method, path, body=None):
        if method != "GET":
            self.mutations.append((method, path))
        if path.startswith("/labels/"):
            if path[len("/labels/"):] not in self.labels:
                raise urllib.error.HTTPError(path, 404, "Not Found", {}, None)
            return {}
        if path == "/labels":
            self.labels.add(body["name"])
            return {}
        if path.startswith("/issues?"):
            page = int(path.rsplit("page=", 1)[1])
            found = [i for i in self.issues.values() if i["state"] == "open" and "drift" in i["labels"]]
            return found[(page - 1) * 100:page * 100]
        if path == "/issues":
            number = len(self.issues) + 1
            self.issues[number] = dict(body, number=number, state="open")
            return self.issues[number]
        number = int(path.split("/")[2])
        if path.endswith("/comments"):
            self.comments.append((number, body["body"]))
        elif path.endswith("/labels"):
            self.issues[number]["labels"] += body["labels"]
        else:
            self.issues[number].update(body)
        return {}


class SyncTest(unittest.TestCase):
    def setUp(self):
        self.gh, self.dir = FakeGitHub(), tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)

    def run_once(self, run_id, clean=(), drifted=(), failed=(), stack="fnx-ue1-dev", expected=None):
        log = pathlib.Path(self.dir.name) / "plan.log"
        log.write_text(LOG)
        args = type("Args", (), {"out": f"{self.dir.name}/{stack}.json", "stack": stack, "clean": list(clean),
                                 "drifted": [f"{c}={log}" for c in drifted], "failed": list(failed)})
        drift_issues.record(args)
        return drift_issues.sync(self.dir.name, expected or [(stack, stack)], self.gh, RUN.format(run_id))

    def test_new_drift_opens_an_issue_and_creates_the_labels_once(self):
        report, errors = self.run_once(1, clean=["kms/main"], drifted=["vpc/main"])
        self.assertEqual((report, errors), (["opened #1: fnx-ue1-dev vpc/main"], []))
        issue = self.gh.issues[1]
        self.assertEqual(issue["title"], "Drift Detected in `fnx-ue1-dev-vpc/main`")
        self.assertEqual(issue["labels"], ["drift"])
        self.assertIn("# aws_s3_bucket.this will be updated in-place\nPlan: 0 to add, 1 to change", issue["body"])
        self.assertNotIn("noise", issue["body"])
        self.assertIn(RUN.format(1), issue["body"])
        self.run_once(2, drifted=["vpc/main"])
        self.assertEqual([m for m in self.gh.mutations if m[1] == "/labels"], [("POST", "/labels")] * 2)

    def test_repeated_drift_updates_the_same_issue_and_a_rerun_changes_nothing(self):
        self.run_once(1, drifted=["vpc/main"])
        report, _ = self.run_once(2, drifted=["vpc/main"])
        self.assertEqual(report, ["updated #1: fnx-ue1-dev vpc/main"])
        self.assertEqual(len(self.gh.issues), 1)
        self.assertIn(RUN.format(2), self.gh.issues[1]["body"])
        before = len(self.gh.mutations)
        self.assertEqual(self.run_once(2, drifted=["vpc/main"]), ([], []))
        self.assertEqual(len(self.gh.mutations), before)

    def test_clean_closes_the_issue_with_a_comment_and_the_recovered_label(self):
        self.run_once(1, drifted=["vpc/main"])
        report, _ = self.run_once(2, clean=["vpc/main"])
        self.assertEqual(report, ["closed #1: fnx-ue1-dev vpc/main (planned clean)"])
        self.assertEqual(self.gh.issues[1]["state"], "closed")
        self.assertEqual(self.gh.issues[1]["labels"], ["drift", "drift-recovered"])
        self.assertIn(RUN.format(2), self.gh.comments[0][1])
        self.assertEqual(self.run_once(3, clean=["vpc/main"]), ([], []))

    def test_a_failed_plan_or_a_missing_leg_leaves_issues_open_and_is_reported(self):
        self.run_once(1, drifted=["vpc/main", "eks/main"])
        report, errors = self.run_once(2, clean=["eks/main"], failed=["vpc/main"])
        self.assertEqual(report, ["closed #1: fnx-ue1-dev eks/main (planned clean)"])
        self.assertEqual(errors, ["fnx-ue1-dev vpc/main: plan failed"])
        self.assertEqual(self.gh.issues[2]["state"], "open")
        expected = [("fnx-ue1-dev", "fnx-ue1-dev"), ("fnx-ue1-dev--pool", "fnx-ue1-dev")]
        report, errors = self.run_once(3, expected=expected)
        self.assertEqual(report, [])
        self.assertEqual(errors, ["fnx-ue1-dev--pool: no result (the leg failed before it planned)"])

    def test_a_pair_a_complete_stack_no_longer_plans_is_closed_others_untouched(self):
        self.run_once(1, drifted=["gone/main"])
        self.run_once(1, drifted=["vpc/main"], stack="fnx-ue1-prod")
        report, _ = self.run_once(2, clean=["vpc/main"])
        self.assertEqual(report, ["closed #1: fnx-ue1-dev gone/main (no longer planned (removed, disabled or "
                                  "opted out of CI))"])
        self.assertEqual(self.gh.issues[2]["state"], "open")

    def test_expected_keys_cover_hosted_and_in_vpc_legs(self):
        keys = drift_issues.expected_keys(json.dumps({"include": [{"stack": "a"}]}),
                                          json.dumps({"include": [{"stack": "a", "label": "a"}]}))
        self.assertEqual(keys, [("a", "a"), ("a--a", "a")])
        self.assertEqual(drift_issues.expected_keys("", ""), [])


if __name__ == "__main__":
    unittest.main()

"""Tests for check-plan-destroys.py (stdlib only): python3 -m unittest workflows/scripts/common/test_check_plan_destroys.py"""
import contextlib
import importlib.util
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

_spec = importlib.util.spec_from_file_location(
    "check_plan_destroys", pathlib.Path(__file__).with_name("check-plan-destroys.py")
)
guard = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(guard)

STACK, COMPONENT = "fnx-ue1-prod", "s3-bucket/logs"
PROD = {"context": {"stage": "prod"}}
STANDBY = {"context": {"stage": "prod"}, "dr": {"standby_of": "fnx-ue1-prod"}}
DEV = {"context": {"stage": "dev"}}
BUCKET = 'aws_s3_bucket.this["logs"]'
ALLOW_BUCKET = f"{COMPONENT}/{STACK}:{BUCKET}"


def change(address, *actions, mode="managed", **extra):
    return {"address": address, "mode": mode, "change": {"actions": list(actions)}, **extra}


def plan(*changes, outputs=None):
    document = {"format_version": "1.2", "resource_changes": list(changes)}
    if outputs is not None:
        document["output_changes"] = outputs
    return document


class LoadPlanTest(unittest.TestCase):
    def test_json_log_lines_before_the_plan_are_skipped(self):
        text = '{"@level":"info","@message":"Terraform 1.16"}\n{"not": "a plan"}\n' + json.dumps(plan()) + "\n"
        self.assertEqual(guard.load_plan(text), plan())

    def test_a_plan_with_planned_values_only_loads(self):
        document = {"format_version": "1.2", "planned_values": {"root_module": {}}}
        self.assertEqual(guard.load_plan(json.dumps(document)), document)

    def test_non_plan_json_is_rejected(self):
        for text in ('{"format_version": "1.2"}', '{"resource_changes": []}', "[]", "Error: no planfile"):
            with self.assertRaises(ValueError, msg=text):
                guard.load_plan(text)


class DestroysTest(unittest.TestCase):
    def test_destroy_and_both_replace_orders_are_found(self):
        found = guard.destroys(plan(
            change("a.x", "delete"), change("a.y", "delete", "create"), change("a.z", "create", "delete"),
            change("a.c", "create"), change("a.u", "update"), change("a.n", "no-op"), change("a.f", "forget"),
        ))
        self.assertEqual([address for address, _, _ in found], ["a.x", "a.y", "a.z"])

    def test_data_reads_and_an_empty_plan_are_not_destroys(self):
        self.assertEqual(guard.destroys(plan(change("data.a.b", "read", mode="data"))), [])
        self.assertEqual(guard.destroys({"format_version": "1.2"}), [])

    def test_a_moved_block_is_not_a_delete(self):
        moved = change("aws_s3_bucket.new", "no-op", previous_address="aws_s3_bucket.old")
        self.assertEqual(guard.destroys(plan(moved)), [])


class HasChangesTest(unittest.TestCase):
    def test_no_op_and_reads_only_is_no_change(self):
        self.assertFalse(guard.has_changes(plan(change("a.n", "no-op"), change("data.a.b", "read", mode="data"))))
        self.assertFalse(guard.has_changes(plan(outputs={"id": {"actions": ["no-op"]}})))
        self.assertFalse(guard.has_changes({"format_version": "1.2", "planned_values": {}}))

    def test_any_other_action_an_output_change_a_move_or_an_import_is_a_change(self):
        for document in (
            plan(change("a.u", "update")),
            plan(change("a.f", "forget")),
            plan(outputs={"id": {"actions": ["update"]}}),
            plan(change("a.new", "no-op", previous_address="a.old")),
            plan({"address": "a.i", "mode": "managed", "change": {"actions": ["no-op"], "importing": {"id": "x"}}}),
        ):
            self.assertTrue(guard.has_changes(document), document)


class ProtectedTest(unittest.TestCase):
    def test_prod_and_standbys_are_protected_others_not(self):
        self.assertTrue(guard.protected(PROD))
        self.assertTrue(guard.protected(STANDBY))
        self.assertTrue(guard.protected({"dr": {"standby_of": "fnx-ew1-prod"}}))
        self.assertFalse(guard.protected(DEV))
        self.assertFalse(guard.protected({"context": {"stage": "staging"}}))
        self.assertFalse(guard.protected({}))


class CheckTest(unittest.TestCase):
    def test_prod_destroy_without_a_trailer_fails(self):
        errors, notes = guard.check(plan(change(BUCKET, "delete")), STACK, COMPONENT, PROD, set())
        self.assertEqual(len(errors), 1)
        self.assertIn(f"Allow-Destroy: {ALLOW_BUCKET}", errors[0])
        self.assertEqual(notes, [])

    def test_prod_replace_without_a_trailer_fails(self):
        errors, _ = guard.check(plan(change("aws_kms_key.this", "create", "delete")), STACK, COMPONENT, STANDBY, set())
        self.assertIn("replace", errors[0])

    def test_the_scoped_trailer_allows(self):
        errors, notes = guard.check(plan(change(BUCKET, "delete")), STACK, COMPONENT, PROD, {ALLOW_BUCKET})
        self.assertEqual(errors, [])
        self.assertEqual(notes[0][0], "notice")

    def test_a_bare_address_or_another_scope_does_not_allow(self):
        for allow in (BUCKET, 'aws_s3_bucket.this["other"]', f"{COMPONENT}/fnx-ue2-prod:{BUCKET}",
                      f"s3-bucket/other/{STACK}:{BUCKET}"):
            errors, _ = guard.check(plan(change(BUCKET, "delete")), STACK, COMPONENT, PROD, {allow})
            self.assertEqual(len(errors), 1, allow)

    def test_each_address_needs_its_own_trailer(self):
        errors, notes = guard.check(plan(change("a.x", "delete"), change("a.y", "delete")), STACK, COMPONENT, PROD,
                                    {f"{COMPONENT}/{STACK}:a.x"})
        self.assertEqual((len(errors), len(notes)), (1, 1))
        self.assertIn("a.y", errors[0])

    def test_a_deposed_delete_only_warns(self):
        errors, notes = guard.check(plan(change(BUCKET, "delete", deposed="00aa")), STACK, COMPONENT, PROD, set())
        self.assertEqual(errors, [])
        self.assertEqual(notes[0][0], "warning")
        self.assertIn("deposed", notes[0][1])

    def test_non_prod_only_reports(self):
        errors, notes = guard.check(plan(change(BUCKET, "delete")), "fnx-ue1-dev", COMPONENT, DEV, set())
        self.assertEqual(errors, [])
        self.assertEqual(notes[0][0], "warning")

    def test_no_changes_pass(self):
        self.assertEqual(guard.check(plan(), STACK, COMPONENT, PROD, set()), ([], []))


class TrailersTest(unittest.TestCase):
    def test_parse_skips_blank_lines_between_commits(self):
        self.assertEqual(guard.parse_trailers(f"{BUCKET}\n\n\n  a.x  \n"), {BUCKET, "a.x"})

    def test_trailers_read_every_commit_in_the_range(self):
        with tempfile.TemporaryDirectory() as repo:
            git = ["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@t"]
            subprocess.run([*git, "init", "-q"], check=True)
            subprocess.run([*git, "commit", "-q", "--allow-empty", "-m", "base"], check=True)
            base = subprocess.check_output([*git, "rev-parse", "HEAD"], text=True).strip()
            subprocess.run([*git, "commit", "-q", "--allow-empty", "-m", f"one\n\nAllow-Destroy: {BUCKET}"], check=True)
            subprocess.run([*git, "commit", "-q", "--allow-empty", "-m",
                            "two\n\nbody mentioning Allow-Destroy: not.a.trailer here\n\n"
                            "Allow-Destroy: a.x\nAllow-Destroy: a.y"], check=True)
            real = subprocess.check_output
            with mock.patch.object(guard.subprocess, "check_output",
                                   lambda cmd, **kw: real([cmd[0], "-C", repo, *cmd[1:]], **kw)):
                self.assertEqual(guard.trailers(base, "HEAD"), {BUCKET, "a.x", "a.y"})
                self.assertEqual(guard.trailers("HEAD", "HEAD"), set())


class MainTest(unittest.TestCase):
    def run_main(self, text, settings=PROD, allows=frozenset(), argv=None):
        out = io.StringIO()
        argv = argv or ["x", "--stack", STACK, "--component", COMPONENT, "--base", "b", "--head", "h"]
        with mock.patch.object(sys, "argv", argv), mock.patch("sys.stdin", io.StringIO(text)), \
                mock.patch.object(guard, "component_settings", return_value=settings), \
                mock.patch.object(guard, "trailers", return_value=set(allows)), \
                mock.patch.dict("os.environ", {"GITHUB_STEP_SUMMARY": ""}), contextlib.redirect_stdout(out):
            code = guard.main()
        return code, out.getvalue()

    def test_log_lines_before_the_json_are_skipped_and_a_blocked_destroy_fails(self):
        code, out = self.run_main("Initializing...\n" + json.dumps(plan(change(BUCKET, "delete"))) + "\n")
        self.assertEqual(code, 1)
        self.assertIn("::error title=Destroy not allowed::", out)

    def test_allowed_destroy_applies_with_a_notice(self):
        code, out = self.run_main(json.dumps(plan(change(BUCKET, "delete"))), allows={ALLOW_BUCKET})
        self.assertEqual(code, 0, out)
        self.assertIn("::notice", out)

    def test_dev_destroy_applies_with_a_warning(self):
        code, out = self.run_main(json.dumps(plan(change(BUCKET, "delete"))), DEV)
        self.assertEqual(code, 0, out)
        self.assertIn("::warning", out)

    def test_no_changes_exits_3(self):
        self.assertEqual(self.run_main(json.dumps(plan(change("a.n", "no-op"))))[0], guard.NO_CHANGES)

    def test_changes_only_mode(self):
        argv = ["x", "--changes-only"]
        self.assertEqual(self.run_main(json.dumps(plan(change("a.u", "update"))), argv=argv)[0], 0)
        self.assertEqual(self.run_main(json.dumps(plan()), argv=argv)[0], guard.NO_CHANGES)
        self.assertEqual(self.run_main("Error\n", argv=argv)[0], 2)

    def test_no_plan_json_fails_closed(self):
        self.assertEqual(self.run_main("Error: no planfile\n")[0], 2)
        self.assertEqual(self.run_main('{"@level":"error"}\n')[0], 2)

    def test_a_failed_describe_fails_closed(self):
        out = io.StringIO()
        argv = ["x", "--stack", STACK, "--component", COMPONENT, "--base", "b"]
        failing = mock.Mock(side_effect=subprocess.CalledProcessError(1, ["atmos", "describe", "component"]))
        with mock.patch.object(sys, "argv", argv), mock.patch("sys.stdin", io.StringIO(json.dumps(plan()))), \
                mock.patch.object(guard, "component_settings", failing), contextlib.redirect_stdout(out):
            self.assertEqual(guard.main(), 1)

    def test_summary_is_written(self):
        with tempfile.NamedTemporaryFile("r", suffix=".md") as summary:
            argv = ["x", "--stack", STACK, "--component", COMPONENT, "--base", "b"]
            with mock.patch.object(sys, "argv", argv), \
                    mock.patch("sys.stdin", io.StringIO(json.dumps(plan(change(BUCKET, "delete"))))), \
                    mock.patch.object(guard, "component_settings", return_value=DEV), \
                    mock.patch.dict("os.environ", {"GITHUB_STEP_SUMMARY": summary.name}), \
                    contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(guard.main(), 0)
            self.assertIn(BUCKET, summary.read())


class WorkflowTest(unittest.TestCase):
    """The promotion gate and the guarded deploy stay wired (text checks, as test_in_vpc_workflows.py)."""
    workflows = pathlib.Path(__file__).resolve().parents[3] / ".github/workflows"
    cd = (workflows / "terraform-cd.yml").read_text()
    in_vpc = (workflows / "in-vpc.yml").read_text()

    def test_cd_deploy_matrices_stop_at_the_first_failure_one_leg_at_a_time(self):
        for job in ("deploy-affected", "deploy-in-vpc"):
            body = self.cd.split(f"\n  {job}:\n", 1)[1].split("\n  mark-deployed:\n", 1)[0]
            body = body.split("\n  deploy-in-vpc:\n", 1)[0]
            self.assertIn("fail-fast: true\n      max-parallel: 1\n", body, job)

    def test_push_deploys_go_through_the_guarded_script(self):
        self.assertIn('bash workflows/scripts/common/deploy-component.sh "$component"', self.cd)
        self.assertIn('bash workflows/scripts/common/deploy-component.sh "$component" || exit 1', self.in_vpc)


if __name__ == "__main__":
    unittest.main()

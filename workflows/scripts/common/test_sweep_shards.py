"""Tests for sweep-shards.py (stdlib only): python3 -m unittest workflows/scripts/common/test_sweep_shards.py"""
import contextlib
import importlib.util
import io
import json
import pathlib
import unittest
from unittest import mock

_spec = importlib.util.spec_from_file_location("sweep_shards", pathlib.Path(__file__).with_name("sweep-shards.py"))
shards = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(shards)


def stack(stage, deployable=1, abstract=0):
    settings = {"context": {"stage": stage}}
    terraform = {f"c{i}": {"settings": settings, "metadata": {}} for i in range(deployable)}
    terraform.update({f"a{i}": {"settings": settings, "metadata": {"type": "abstract"}} for i in range(abstract)})
    return {"components": {"terraform": terraform}}


STACKS = {
    "fnx-ue1-dev": stack("dev", 40, abstract=3),
    "fnx-ue1-staging": stack("staging", 38),
    "fnx-ue1-prod": stack("prod", 45),
    "fnx-ue1-audit": stack("audit", 3),
    "fnx-ue1-root": stack("root", 1),
    "fnx-ue1-fixtures-webapp": stack("fixtures", 12),
    "fnx-ue1-fixtures-batch": stack("fixtures", 9),
    "fnx-ue1-local-sandbox": stack("local", 5),
}


class WeightTest(unittest.TestCase):
    def test_counts_deployable_instances_only(self):
        self.assertEqual(shards.weight(stack("dev", 4, abstract=2)), 4)

    def test_a_stack_with_nothing_deployable_still_weighs_one(self):
        self.assertEqual(shards.weight(stack("dev", 0, abstract=2)), 1)


class BalanceTest(unittest.TestCase):
    NAMES = ["a", "b", "c", "d", "e", "f"]
    WEIGHTS = {"a": 40, "b": 38, "c": 45, "d": 3, "e": 12, "f": 9}

    def test_balances_by_pairs_not_by_stack_count(self):
        chunks = shards.balance(self.NAMES, self.WEIGHTS, 3)
        loads = sorted(sum(self.WEIGHTS[n] for n in c) for c in chunks)
        # 147 pairs over 3 legs: the heaviest leg is one 45-pair stack plus small ones, not two big ones.
        self.assertLessEqual(loads[-1], 52)
        self.assertEqual(sorted(len(c) > 0 for c in chunks), [True, True, True])

    def test_each_leg_keeps_promotion_order(self):
        for chunk in shards.balance(self.NAMES, self.WEIGHTS, 2):
            self.assertEqual(chunk, sorted(chunk, key=self.NAMES.index))

    def test_never_more_legs_than_stacks(self):
        self.assertEqual(len(shards.balance(["a", "b"], {"a": 1, "b": 1}, 6)), 2)

    def test_covers_every_stack_exactly_once(self):
        chunks = shards.balance(self.NAMES, self.WEIGHTS, 4)
        self.assertEqual(sorted(n for c in chunks for n in c), sorted(self.NAMES))


class ParityTest(unittest.TestCase):
    EXPECTED = ["fnx-ue1-dev", "fnx-ue1-prod", "fnx-ue1-fixtures-webapp"]

    def test_exact_cover_passes(self):
        self.assertEqual(shards.parity_errors(self.EXPECTED, [["fnx-ue1-dev"], ["fnx-ue1-prod", "fnx-ue1-fixtures-webapp"]]), [])

    def test_a_dropped_stack_fails(self):
        errors = shards.parity_errors(self.EXPECTED, [["fnx-ue1-dev"], ["fnx-ue1-fixtures-webapp"]])
        self.assertEqual(errors, ["stacks in no leg: fnx-ue1-prod"])

    def test_a_duplicated_stack_fails(self):
        errors = shards.parity_errors(self.EXPECTED, [["fnx-ue1-dev", "fnx-ue1-prod"], ["fnx-ue1-prod", "fnx-ue1-fixtures-webapp"]])
        self.assertEqual(errors, ["stacks in more than one leg: fnx-ue1-prod"])

    def test_an_extra_stack_fails(self):
        errors = shards.parity_errors(self.EXPECTED, [self.EXPECTED + ["fnx-ue1-local-sandbox"]])
        self.assertEqual(errors, ["stacks no --plan-sweep run selects: fnx-ue1-local-sandbox"])

    def test_an_empty_leg_fails(self):
        self.assertIn("an empty leg", shards.parity_errors(self.EXPECTED, [self.EXPECTED, []]))

    def test_no_fixtures_fails(self):
        errors = shards.parity_errors(["fnx-ue1-dev"], [["fnx-ue1-dev"]])
        self.assertEqual(len(errors), 1)
        self.assertIn("fnx-ue1-fixtures-", errors[0])


class MainTest(unittest.TestCase):
    def run_main(self, argv, stacks=STACKS, balance=None):
        out, err = io.StringIO(), io.StringIO()
        patches = [mock.patch.object(shards.ci_stacks, "describe_stacks", return_value=stacks),
                   mock.patch("sys.argv", ["sweep-shards.py", *argv])]
        if balance is not None:
            patches.append(mock.patch.object(shards, "balance", balance))
        with contextlib.ExitStack() as stack_:
            for p in patches:
                stack_.enter_context(p)
            stack_.enter_context(contextlib.redirect_stdout(out))
            stack_.enter_context(contextlib.redirect_stderr(err))
            rc = shards.main()
        return rc, out.getvalue(), err.getvalue()

    def test_matrix_is_the_plan_sweep_stacks_then_samples_and_scaffold(self):
        rc, out, _ = self.run_main(["--chunks", "3"])
        self.assertEqual(rc, 0)
        legs = json.loads(out)["include"]
        self.assertEqual([leg["args"] for leg in legs[-2:]], ["--samples", "--scaffold"])
        swept = [s for leg in legs[:-2] for s in leg["args"].removeprefix("-s ").split(",")]
        self.assertEqual(sorted(swept), sorted(shards.ci_stacks.plan_sweep_stacks(STACKS)))
        self.assertNotIn("fnx-ue1-local-sandbox", swept)
        self.assertEqual(len(legs), 5)

    def test_a_split_that_drops_a_stack_fails_the_job(self):
        rc, out, err = self.run_main([], balance=lambda names, weights, chunks: [names[1:]])
        self.assertEqual((rc, out), (1, ""))
        self.assertIn("::error::sweep shards do not cover", err)

    def test_a_selection_error_fails_the_job(self):
        broken = dict(STACKS, **{"fnx-ue1-dev": stack("dev", 0, abstract=1)})
        rc, out, err = self.run_main([], stacks=broken)
        self.assertEqual((rc, out), (1, ""))
        self.assertIn("::error::", err)


if __name__ == "__main__":
    unittest.main()

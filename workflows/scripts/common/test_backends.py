"""Tests for backends.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import backends  # noqa: E402

ROLES = {
    "root_write": {"role_name": "fnx-terraform-backend-root-role"},
    "prod_read": {"role_name": "fnx-terraform-backend-prod-read-role"},
}


def backend(bucket="fnx-terraform-state", region="us-east-1", roles=None, **metadata):
    variables = {"region": region, "access_roles": ROLES if roles is None else roles}
    if bucket is not None:
        variables["bucket_name"] = bucket
    return {"component": "backend", "metadata": metadata, "vars": variables}


def stacks_of(**by_stack):
    return {stack: {"components": {"terraform": instances}} for stack, instances in by_stack.items()}


def user(bucket="fnx-terraform-state", role_arn="arn:aws:iam::111111111111:role/fnx-terraform-backend-root-role"):
    return {"backend": {"bucket": bucket, "assume_role": {"role_arn": role_arn}}}


class BackendsTest(unittest.TestCase):
    def test_one_backend_owns_its_bucket(self):
        owned, errors = backends.owned(stacks_of(**{"fnx-ue1-root": {"backend/main": backend()}}))
        self.assertEqual(errors, [])
        self.assertEqual(owned["fnx-terraform-state"].where, "fnx-ue1-root: backend/main")
        self.assertEqual(owned["fnx-terraform-state"].region, "us-east-1")

    def test_abstract_and_disabled_instances_are_skipped(self):
        stacks = stacks_of(**{"fnx-ue1-root": {
            "backend": backend(type="abstract"),
            "backend/main": backend(),
            "backend/off": backend(enabled=False),
            "vpc/main": {"component": "vpc", "vars": {"bucket_name": "fnx-terraform-state"}},
        }})
        self.assertEqual([b.instance for b in backends.backends(stacks)], ["backend/main"])
        self.assertEqual(backends.owned(stacks)[1], [])

    def test_missing_bucket_name_fails(self):
        owned, errors = backends.owned(stacks_of(**{"fnx-ue1-root": {"backend/main": backend(bucket=None)}}))
        self.assertEqual(owned, {})
        self.assertEqual(len(errors), 2, errors)
        self.assertIn("no deployed 'backend' instance owns a state bucket", errors[0])
        self.assertIn("fnx-ue1-root: backend/main: the deployed 'backend' instance has no vars.bucket_name", errors[1])

    def test_duplicate_owner_has_no_owner(self):
        stacks = stacks_of(**{"fnx-ue1-root": {"backend/main": backend()},
                              "fnx-ew1-root": {"backend/main": backend(region="eu-west-1")}})
        owned, errors = backends.owned(stacks)
        self.assertEqual(owned, {})
        self.assertEqual(errors, ["state bucket 'fnx-terraform-state' is created by more than one backend instance: "
                                  "['fnx-ew1-root: backend/main', 'fnx-ue1-root: backend/main']"])
        self.assertIsNone(backends.owner_of(owned, user()))

    def test_invalid_region_and_missing_roles_fail(self):
        _, errors = backends.owned(stacks_of(**{"fnx-ue1-root": {"backend/main": backend(region="<no value>",
                                                                                          roles={})}}))
        self.assertEqual(len(errors), 2, errors)
        self.assertIn("region '<no value>' is not an AWS region", errors[0])
        self.assertIn("has no access_roles", errors[1])

    def test_owner_of(self):
        owned, _ = backends.owned(stacks_of(**{"fnx-ue1-root": {"backend/main": backend()},
                                               "fnx-ew1-root": {"backend/main": backend("fnx-ew1-state", "eu-west-1")}}))
        self.assertEqual(backends.owner_of(owned, user("fnx-ew1-state")).stack, "fnx-ew1-root")
        self.assertEqual(backends.owner_of(owned, user()).stack, "fnx-ue1-root")
        self.assertIsNone(backends.owner_of(owned, user("fnx-other-state")))
        self.assertIsNone(backends.owner_of(owned, {"backend": {}}))

    def test_role_arn_with_a_path(self):
        instance = user(role_arn="arn:aws:iam::111111111111:role/terraform/fnx-terraform-backend-prod-read-role")
        self.assertEqual(backends.assumed_role_name(instance), "fnx-terraform-backend-prod-read-role")
        self.assertIsNone(backends.assumed_role_name(user(role_arn="")))
        self.assertIsNone(backends.assumed_role_name({}))

    def test_assumed_role_key(self):
        owner = backends.owned(stacks_of(**{"fnx-ue1-root": {"backend/main": backend()}}))[0]["fnx-terraform-state"]
        self.assertEqual(backends.assumed_role_key(user(), owner), "root_write")
        with_path = user(role_arn="arn:aws:iam::111111111111:role/x/fnx-terraform-backend-prod-read-role")
        self.assertEqual(backends.assumed_role_key(with_path, owner), "prod_read")
        other = user(role_arn="arn:aws:iam::111111111111:role/fnx-ew1-terraform-backend-root-role")
        self.assertIsNone(backends.assumed_role_key(other, owner))
        self.assertIsNone(backends.assumed_role_key({}, owner))


if __name__ == "__main__":
    unittest.main()

"""Tests for check-state-keys.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_state_keys", pathlib.Path(__file__).with_name("check-state-keys.py")
)
check_state_keys = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_state_keys)

# The role each stage's backend assumes (stacks/orgs/fnx/_defaults.yaml, TFSTATE_ACCESS unset).
STAGE_ROLES = {"root": "fnx-terraform-backend-root-role", "prod": "fnx-terraform-backend-prod-role"}
NON_PROD_ROLE = "fnx-terraform-backend-role"


def pair(stack):
    """The exact pattern pair of one stack (stacks/orgs/fnx/root/us-east-1.yaml)."""
    return [f"*/{stack}/*", f"*/{stack}-*"]


def access_roles(non_prod=("fnx-ue1-dev", "fnx-ue1-staging"), prod=("fnx-ue1-prod",),
                 core=("fnx-ue1-root",), **patterns):
    """backend/main's access_roles as the catalog renders them; patterns overrides one role's list."""
    non_prod_keys = [p for stack in non_prod for p in pair(stack)]
    prod_keys = [p for stack in prod for p in pair(stack)]
    roles = {
        "read": ("fnx-terraform-backend-read-role", non_prod_keys),
        "prod_read": ("fnx-terraform-backend-prod-read-role", prod_keys),
        "write": (NON_PROD_ROLE, non_prod_keys),
        "prod_write": (STAGE_ROLES["prod"], prod_keys),
        "root_write": (STAGE_ROLES["root"], [p for stack in core for p in pair(stack)]),
    }
    return {
        name: {"role_name": role_name, "object_key_patterns": patterns.get(name, keys)}
        for name, (role_name, keys) in roles.items()
    }


def instance(workspace, key_prefix="vpc", stage="prod", backend_type="s3", key="terraform.tfstate",
             region="us-east-1", component=None, role=None, roles=None, **metadata):
    role_arn = f"arn:aws:iam::111111111111:role/{role or STAGE_ROLES.get(stage, NON_PROD_ROLE)}"
    return {
        "metadata": metadata,
        "component": component,
        "vars": {"region": region, **({"access_roles": roles} if roles is not None else {})},
        "backend_type": backend_type,
        "backend": {
            "workspace_key_prefix": key_prefix, "key": key, "region": region, "assume_role": {"role_arn": role_arn},
        },
        "workspace": workspace,
        "settings": {"context": {"tenant": "fnx", "stage": stage}},
    }


def core_stack(region="us-east-1", roles=None, stack="fnx-ue1-root"):
    backend = instance(stack, key_prefix="backend", stage="root", region=region, component="backend",
                       roles=access_roles() if roles is None else roles)
    return {"components": {"terraform": {"backend/main": backend}}}


def one(name, stage, region="us-east-1"):
    return {"components": {"terraform": {"vpc/main": instance(name, stage=stage, region=region)}}}


def stacks_with(roles=None, **components):
    """The four stacks of today: root, dev and staging with one instance each, prod with components."""
    return {
        "fnx-ue1-root": core_stack(roles=roles),
        "fnx-ue1-dev": one("fnx-ue1-dev", "dev"),
        "fnx-ue1-staging": one("fnx-ue1-staging", "staging"),
        "fnx-ue1-prod": {"components": {"terraform": components}},
    }


def prod(**kwargs):
    return instance("fnx-ue1-prod", **kwargs)


class CheckStateKeysTest(unittest.TestCase):
    def assert_errors(self, stacks, *fragments):
        errors = check_state_keys.check(stacks)
        self.assertEqual(len(errors), len(fragments), errors)
        for error, fragment in zip(errors, fragments):
            self.assertIn(fragment, error)

    def assert_has(self, stacks, *fragments):
        errors = check_state_keys.check(stacks)
        for fragment in fragments:
            self.assertTrue(any(fragment in error for error in errors), (fragment, errors))

    # Pattern semantics

    def test_pattern_star_spans_slash(self):
        self.assertTrue(check_state_keys.pattern_matches("*/fnx-ue1-prod/*", "a/b/fnx-ue1-prod/x/y"))
        self.assertTrue(check_state_keys.pattern_matches("*/fnx-ue1-prod-*", "iam/fnx-ue1-prod-iam-ci/t"))

    def test_pattern_is_anchored_and_literal(self):
        self.assertFalse(check_state_keys.pattern_matches("*/fnx-ue1-prod/*", "vpc/fnx-ue1-prodx/t"))
        self.assertFalse(check_state_keys.pattern_matches("*/fnx.prod/*", "vpc/fnxXprod/t"))

    def test_question_mark_is_one_character(self):
        # IAM resource ARNs: "?" matches exactly one character, "/" included
        self.assertTrue(check_state_keys.pattern_matches("*/fnx-ue?-prod/*", "vpc/fnx-ue1-prod/t"))
        self.assertTrue(check_state_keys.pattern_matches("vpc?fnx/*", "vpc/fnx/t"))
        self.assertFalse(check_state_keys.pattern_matches("*/fnx-ue?-prod/*", "vpc/fnx-ue-prod/t"))
        self.assertFalse(check_state_keys.pattern_matches("*/fnx-ue?-prod/*", "vpc/fnx-ue12-prod/t"))

    def test_question_mark_spanning_stages_fails(self):
        # "fnx-?ev-*"-style patterns are evaluated, not taken literally
        roles = access_roles(read=pair("fnx-ue1-dev") + pair("fnx-ue1-staging") + ["*/fnx-ue1-?oot/*"])
        self.assert_has(stacks_with(roles=roles, **{"vpc/main": prod()}),
                        "['read'] match state of stages 'dev' and 'root', which assume different roles")

    # The stage split

    def test_stack_workspace_passes(self):
        self.assert_errors(stacks_with(**{"vpc/main": prod()}))

    def test_derived_instance_workspace_passes(self):
        self.assert_errors(stacks_with(**{
            "vpc/main": prod(),
            "iam/ci": instance("fnx-ue1-prod-iam-ci", key_prefix="iam"),
        }))

    def test_lane_named_like_an_instance_suffix_fails(self):
        # Lane fnx-ue1-prod-main's vpc has workspace fnx-ue1-prod-main, which is
        # also fnx-ue1-prod's vpc/main workspace.
        stacks = stacks_with(**{"vpc/main": prod(), "vpc/x": instance("fnx-ue1-prod-main")})
        stacks["fnx-ue1-prod-main"] = {"components": {"terraform": {"vpc": instance("fnx-ue1-prod-main")}}}
        self.assert_has(stacks, "fnx-ue1-prod-main: vpc and fnx-ue1-prod: vpc/x share the state key "
                                "'vpc/fnx-ue1-prod-main/terraform.tfstate'")

    def test_lane_with_its_own_keys_passes(self):
        stacks = stacks_with(**{"vpc/main": prod()})
        stacks["fnx-ue1-prod-perf"] = {"components": {"terraform": {"vpc/main": instance("fnx-ue1-prod-perf")}}}
        self.assert_errors(stacks)

    def test_isolation_does_not_depend_on_where_the_stage_sits_in_the_name(self):
        # The Q4 names put the region code before the stage: the pairs still split them.
        roles = access_roles(non_prod=("fnx-ue1-dev", "fnx-ue1-staging"), prod=("fnx-ue1-prod", "fnx-ue2-prod"),
                             core=("fnx-ue1-root",))
        stacks = {
            "fnx-ue1-root": core_stack(roles=roles, stack="fnx-ue1-root"),
            "fnx-ue1-dev": one("fnx-ue1-dev", "dev"),
            "fnx-ue1-staging": one("fnx-ue1-staging", "staging"),
            "fnx-ue1-prod": one("fnx-ue1-prod", "prod"),
            "fnx-ue2-prod": one("fnx-ue2-prod", "prod"),
        }
        self.assert_errors(stacks)

    def test_stage_prefix_patterns_miss_the_q4_names(self):
        # "*/<tenant>-<stage>-*" only isolated while the stage followed the tenant.
        roles = access_roles(
            read=["*/fnx-ue1-dev-*"], write=["*/fnx-ue1-dev-*"], prod_read=["*/fnx-ue1-prod-*"], prod_write=["*/fnx-ue1-prod-*"],
            root_write=["*/fnx-ue1-root-*"],
        )
        stacks = {
            "fnx-ue1-root": core_stack(roles=roles, stack="fnx-ue1-root"),
            "fnx-ue1-dev": one("fnx-ue1-dev", "dev"),
            "fnx-ue1-prod": one("fnx-ue1-prod", "prod"),
        }
        self.assert_has(stacks, "'backend/fnx-ue1-root/terraform.tfstate' matches no access role",
                        "'vpc/fnx-ue1-prod/terraform.tfstate' matches no access role")

    def test_workspace_of_another_stage_fails(self):
        # A prod instance whose state would land under the non-prod roles' pair
        self.assert_has(
            stacks_with(**{"vpc/main": prod(), "vpc/other": instance("fnx-ue1-dev")}),
            "is outside its own role 'prod_write''s patterns",
            "match state of stages 'dev' and 'prod', which assume different roles",
        )

    def test_unlisted_workspace_fails(self):
        self.assert_has(stacks_with(**{"vpc/main": prod(), "vpc/x": instance("custom")}),
                        "'vpc/custom/terraform.tfstate' matches no access role")

    def test_name_extending_a_stack_name_is_not_that_stack(self):
        # "fnx-ue1-prodx" is not "fnx-ue1-prod" nor one of its derived instances
        self.assert_has(stacks_with(**{"vpc/main": prod(), "vpc/x": instance("fnx-ue1-prodx")}),
                        "'vpc/fnx-ue1-prodx/terraform.tfstate' matches no access role")

    def test_pattern_spanning_stages_fails(self):
        roles = access_roles(read=["*/fnx-*"])
        self.assert_has(stacks_with(roles=roles, **{"vpc/main": prod()}),
                        "['read'] match state of stages 'dev' and 'root', which assume different roles",
                        "['read'] match state of stages 'dev' and 'prod', which assume different roles")

    def test_stage_role_missing_from_a_derived_instance_fails(self):
        roles = access_roles(prod_read=["*/fnx-ue1-prod/*"])
        self.assert_errors(
            stacks_with(roles=roles, **{"vpc/main": prod(), "iam/ci": instance("fnx-ue1-prod-iam-ci")}),
            "'vpc/fnx-ue1-prod-iam-ci/terraform.tfstate' is not matched by ['prod_read']",
            "'vpc/fnx-ue1-prod-iam-ci/terraform.tfstate.tflock' is not matched by ['prod_read']",
        )

    def test_role_reaching_no_state_fails(self):
        roles = access_roles(prod_read=["*/fnx-ue1-prod-prod/*"])
        self.assert_errors(stacks_with(roles=roles, **{"vpc/main": prod()}),
                           "access role 'prod_read' matches no state object",
                           "access role 'prod_read' pattern '*/fnx-ue1-prod-prod/*' matches no state object")

    def test_dead_pair_of_a_renamed_stack_fails(self):
        # The old name's pair left beside the new one after a rename
        roles = access_roles(non_prod=("fnx-ue1-dev", "fnx-ue1-staging", "fnx-ue1-old"))
        self.assert_errors(
            stacks_with(roles=roles, **{"vpc/main": prod()}),
            "access role 'read' pattern '*/fnx-ue1-old/*' matches no state object",
            "access role 'read' pattern '*/fnx-ue1-old-*' matches no state object",
            "access role 'write' pattern '*/fnx-ue1-old/*' matches no state object",
            "access role 'write' pattern '*/fnx-ue1-old-*' matches no state object",
        )

    def test_derived_pattern_of_a_live_stack_may_match_nothing(self):
        # No derived instance anywhere: every "*/<stack>-*" matches nothing, beside its live "/*"
        self.assert_errors(stacks_with(**{"vpc/main": prod()}))

    def test_lone_derived_pattern_matching_nothing_fails(self):
        roles = access_roles(prod_read=pair("fnx-ue1-prod") + ["*/fnx-ue1-prod-other-*"],
                             prod_write=pair("fnx-ue1-prod") + ["*/fnx-ue1-prod-other-*"])
        self.assert_has(stacks_with(roles=roles, **{"vpc/main": prod()}),
                        "access role 'prod_read' pattern '*/fnx-ue1-prod-other-*' matches no state object")

    def test_own_role_outside_its_patterns_fails(self):
        # The non-prod write role lost staging: staging's apply could not write its own state
        roles = access_roles(write=pair("fnx-ue1-dev"))
        self.assert_has(stacks_with(roles=roles, **{"vpc/main": prod()}),
                        "'vpc/fnx-ue1-staging/terraform.tfstate' is outside its own role 'write''s patterns",
                        "stages 'dev' and 'staging' assume the same role but their state is matched by")

    def test_undefined_assumed_role_fails(self):
        self.assert_errors(
            stacks_with(**{"vpc/main": prod(), "vpc/x": prod(role="fnx-other-role")}),
            "assumes role 'fnx-other-role', which the backend's access_roles do not define",
        )

    def test_read_access_assumes_the_read_roles(self):
        # TFSTATE_ACCESS=read renders the read roles into every backend
        stacks = stacks_with(**{"vpc/main": prod(role="fnx-terraform-backend-prod-read-role")})
        for name in ("fnx-ue1-dev", "fnx-ue1-staging"):
            stacks[name]["components"]["terraform"]["vpc/main"] = instance(
                name, stage="dev" if "dev" in name else "staging", role="fnx-terraform-backend-read-role")
        self.assert_errors(stacks)

    def test_fixture_stage_is_skipped(self):
        stacks = stacks_with(**{"vpc/main": prod()})
        stacks["fnx-ue1-fixtures-webapp"] = one("fnx-ue1-fixtures-webapp", "fixtures")
        self.assert_errors(stacks)

    def test_missing_access_roles_fails(self):
        self.assert_errors(stacks_with(roles={}, **{"vpc/main": prod()}), "has no access_roles")

    # Layout

    def test_workspace_with_slash_fails(self):
        self.assert_has(stacks_with(**{"vpc/main": prod(), "vpc/x": instance("fnx-ue1-prod-x/fnx-ue1-dev-y")}),
                        "contains '/'")

    def test_key_prefix_with_slash_fails(self):
        self.assert_errors(
            stacks_with(**{"vpc/main": prod(key_prefix="a/vpc")}),
            "workspace_key_prefix 'a/vpc' contains '/'",
        )

    def test_missing_key_prefix_fails(self):
        self.assert_errors(stacks_with(**{"vpc/main": prod(key_prefix="")}), "no backend.workspace_key_prefix")

    def test_default_state_key_passes(self):
        self.assert_errors(stacks_with(**{"vpc/main": prod(key="terraform.tfstate")}))

    def test_state_key_with_slash_fails(self):
        # "vpc/fnx-ue1-prod/fnx-ue1-dev/terraform.tfstate" also matches the non-prod pair
        self.assert_has(
            stacks_with(**{"vpc/main": prod(key="fnx-ue1-dev/terraform.tfstate")}),
            "backend.key 'fnx-ue1-dev/terraform.tfstate' is not 'terraform.tfstate' (contains '/')",
            "match state of stages 'dev' and 'prod'",
        )

    def test_non_default_state_key_fails(self):
        self.assert_errors(
            stacks_with(**{"vpc/main": prod(key="state.tfstate")}),
            "backend.key 'state.tfstate' is not 'terraform.tfstate'",
        )

    def test_missing_state_key_fails(self):
        self.assert_errors(stacks_with(**{"vpc/main": prod(key=None)}), "backend.key None")

    # The bucket's region

    def test_backend_region_of_the_bucket_passes(self):
        self.assert_errors(stacks_with(**{"vpc/main": prod(region="us-east-1")}))

    def test_backend_region_of_the_stack_fails(self):
        # An EU/DR stack whose backend followed its own region would init against a region with no bucket
        stacks = stacks_with(**{"vpc/main": prod()})
        stacks["fnx-ue1-prod"]["components"]["terraform"]["vpc/main"]["backend"]["region"] = "eu-west-1"
        self.assert_errors(stacks, "backend.region 'eu-west-1' is not the state bucket's region 'us-east-1'")

    def test_missing_backend_stack_fails(self):
        stacks = stacks_with(**{"vpc/main": prod()})
        del stacks["fnx-ue1-root"]
        self.assert_errors(stacks, "expected exactly one deployed 'backend' region")

    def test_bucket_region_is_the_backend_stacks_own(self):
        # backend/main moved to another region: stacks still pointing at us-east-1 now fail
        stacks = stacks_with(**{"vpc/main": prod()})
        stacks["fnx-ue1-root"] = core_stack(region="eu-west-1")
        errors = check_state_keys.check(stacks)
        self.assertEqual(len(errors), 3, errors)
        self.assertTrue(all("backend.region 'us-east-1' is not the state bucket's region 'eu-west-1'" in e
                            for e in errors), errors)

    def test_non_s3_backend_region_is_ignored(self):
        self.assert_errors(stacks_with(**{
            "vpc/main": prod(),
            "local": prod(backend_type="local", region="eu-west-1"),
        }))

    def test_two_backend_regions_fail(self):
        stacks = stacks_with(**{"vpc/main": prod()})
        other = instance("fnx-ew1-root", key_prefix="backend", stage="root", region="eu-west-1", component="backend")
        stacks["fnx-ew1-root"] = {"components": {"terraform": {"backend/main": other}}}
        self.assert_errors(stacks, "expected exactly one deployed 'backend' region")

    def test_abstract_and_disabled_backend_do_not_count(self):
        stacks = stacks_with(**{"vpc/main": prod()})
        for name, flag in (("abstract", {"type": "abstract"}), ("off", {"enabled": False})):
            other = instance("fnx-ue1-root-x", key_prefix="backend", stage="root", region="eu-west-1",
                             component="backend", **flag)
            stacks["fnx-ue1-root"]["components"]["terraform"][name] = other
        self.assert_errors(stacks)

    def test_unset_region_fails(self):
        # An unset settings.tfstate.region renders "<no value>" everywhere; equal strings must not pass
        stacks = {
            "fnx-ue1-root": core_stack(region="<no value>"),
            "fnx-ue1-dev": one("fnx-ue1-dev", "dev", region="<no value>"),
            "fnx-ue1-staging": one("fnx-ue1-staging", "staging", region="<no value>"),
            "fnx-ue1-prod": one("fnx-ue1-prod", "prod", region="<no value>"),
        }
        errors = check_state_keys.check(stacks)
        self.assertEqual(len(errors), 5, errors)
        self.assertIn("state bucket's region '<no value>' is not an AWS region", errors[0])
        self.assertTrue(all("is not an AWS region" in error for error in errors), errors)

    def test_missing_context_fails(self):
        bad = prod()
        bad["settings"] = {}
        self.assert_has(stacks_with(**{"vpc/main": prod(), "vpc/x": bad}), "no settings.context stage")

    def test_non_s3_abstract_and_disabled_instances_are_skipped(self):
        self.assert_errors(stacks_with(**{
            "vpc/main": prod(),
            "local": instance("x/y", key_prefix="a/b", backend_type="local", key="a/b"),
            "base": instance("x/y", key_prefix="a/b", type="abstract", key="a/b"),
            "off": instance("x/y", key_prefix="a/b", enabled=False, key="a/b"),
        }))


if __name__ == "__main__":
    unittest.main()

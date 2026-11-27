"""Tests for check-ci-state-roles.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_ci_state_roles", pathlib.Path(__file__).with_name("check-ci-state-roles.py")
)
check_ci_state_roles = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_ci_state_roles)

ACCOUNTS = {"dev": "222222222222", "staging": "333333333333", "prod": "444444444444"}
ENVIRONMENTS = {"dev": "ue1", "staging": "ue1", "prod": "ue1"}


def arn(stage, kind, environment=None):
    return f"arn:aws:iam::{ACCOUNTS[stage]}:role/fnx-{environment or ENVIRONMENTS[stage]}-{stage}-ci-{kind}"


def access_roles(**overrides):
    roles = {
        "read": [arn("dev", "plan"), arn("staging", "plan")],
        "write": [arn("dev", "apply"), arn("staging", "apply")],
        "prod_read": [arn("prod", "plan")],
        "prod_write": [arn("prod", "apply")],
        "root_write": [],
    }
    roles.update(overrides)
    return {key: {"role_name": ROLE_NAMES[key], "allowed_principal_arns": principals}
            for key, principals in roles.items()}


# backend/main's role names; each stage's backend assumes its write role (TFSTATE_ACCESS unset).
ROLE_NAMES = {
    "read": "fnx-terraform-backend-read-role", "write": "fnx-terraform-backend-role",
    "prod_read": "fnx-terraform-backend-prod-read-role", "prod_write": "fnx-terraform-backend-prod-role",
    "root_write": "fnx-terraform-backend-root-role", "core_write": "fnx-terraform-backend-core-role",
}
ASSUMED = {"dev": "write", "staging": "write", "prod": "prod_write"}


US_BUCKET, EU_BUCKET = "fnx-terraform-state", "fnx-ew1-terraform-state"


def role_arn(name):
    return f"arn:aws:iam::111111111111:role/{name}"


def ci(stage, environment="ue1", apply=True, oidc=True, assumes=None, bucket=US_BUCKET, role=None, grants=None,
       **metadata):
    """The stack's two CI role instances (catalog/aws-iam-role/ci.yaml), {instance name: instance}."""
    role = role or ROLE_NAMES[assumes or ASSUMED.get(stage, "write")]
    # (AssumeStateReadRoles role, AssumeStateWriteRole role): the stage's own by default
    read, write = grants or [ROLE_NAMES[k] for k in check_ci_state_roles.STAGE_ROLES.get(stage, ("read", "write"))]
    statements = {"plan": {"AssumeStateReadRoles": {"effect": "Allow", "resources": [role_arn(read)]}},
                  "apply": {"AssumeStateWriteRole": {"effect": "Allow", "resources": [role_arn(write)]}}}
    roles = {}
    for kind in ("plan", "apply") if apply else ("plan",):
        roles[f"aws-iam-role/ci-{kind}"] = {
            "component": "aws-iam-role",
            "metadata": dict(metadata),
            "backend": {"bucket": bucket, "assume_role": {"role_arn": role_arn(role)}},
            "vars": {"enabled": True, "github_oidc_provider_enabled": oidc,
                     "trusted_github_repos": ["hemzaz/tf-atmos:master"],
                     "tenant": "fnx", "environment": environment, "stage": stage, "name": f"ci-{kind}",
                     "context": {"label_order": ["tenant", "environment", "stage", "name", "attributes"]},
                     "policy_statements": statements[kind]},
            "settings": {"context": {"stage": stage},
                         "environment": {"account_id": ACCOUNTS.get(stage, "555555555555")}},
        }
    return roles


def plan_of(roles):
    return roles["aws-iam-role/ci-plan"]


def apply_of(roles):
    return roles["aws-iam-role/ci-apply"]


def backend(roles, bucket=US_BUCKET, region="us-east-1"):
    return {"component": "backend", "vars": {"bucket_name": bucket, "region": region, "access_roles": roles}}


def stacks(roles=None, **cis):
    result = {"fnx-ue1-root": {"components": {"terraform": {"backend/main": backend(roles or access_roles())}}}}
    for stack, roles in cis.items():
        result[stack] = {"components": {"terraform": dict(roles)}}
    return result


# The EU backend (fnx-ew1-root) and its prod stack's CI roles.
EU_ROLE_NAMES = {"prod_read": "fnx-ew1-terraform-backend-prod-read-role",
                 "prod_write": "fnx-ew1-terraform-backend-prod-role",
                 "root_write": "fnx-ew1-terraform-backend-root-role"}


def eu_arn(kind):
    return arn("prod", kind, "ew1")


def eu_roles(**overrides):
    principals = {"prod_read": [eu_arn("plan")], "prod_write": [eu_arn("apply")], "root_write": []}
    principals.update(overrides)
    return {key: {"role_name": EU_ROLE_NAMES[key], "allowed_principal_arns": arns} for key, arns in principals.items()}


def eu_ci(**kwargs):
    kwargs.setdefault("role", EU_ROLE_NAMES["prod_write"])
    kwargs.setdefault("grants", (EU_ROLE_NAMES["prod_read"], EU_ROLE_NAMES["prod_write"]))
    return ci("prod", environment="ew1", bucket=EU_BUCKET, **kwargs)


def two_backends(us=None, eu=None, eu_instance=None):
    described = stacks(roles=us, **today(**{"fnx-ew1-prod": eu_instance or eu_ci()}))
    described["fnx-ew1-root"] = {"components": {"terraform": {
        "backend/main": backend(eu or eu_roles(), EU_BUCKET, "eu-west-1")}}}
    return described


def today(**overrides):
    cis = {"fnx-ue1-dev": ci("dev"), "fnx-ue1-staging": ci("staging"),
           "fnx-ue1-prod": ci("prod")}
    cis.update(overrides)
    return cis


class CheckCiStateRolesTest(unittest.TestCase):
    def assert_errors(self, described, *fragments):
        errors = check_ci_state_roles.check(described)
        self.assertEqual(len(errors), len(fragments), errors)
        for error, fragment in zip(errors, fragments):
            self.assertIn(fragment, error)

    def assert_has(self, described, *fragments):
        errors = check_ci_state_roles.check(described)
        for fragment in fragments:
            self.assertTrue(any(fragment in error for error in errors), (fragment, errors))

    def test_trusted_roles_pass(self):
        self.assert_errors(stacks(**today()))

    def test_renamed_prefix_fails(self):
        # A prefix rendered from the old names no longer matches the trusted ARNs,
        # and the trusted ARNs no longer match a CI role (both directions fail)
        self.assert_errors(
            stacks(**today(**{"fnx-ue1-prod": ci("prod", environment="production")})),
            "fnx-ue1-prod: aws-iam-role/ci-plan role arn:aws:iam::444444444444:role/fnx-production-prod-ci-plan "
            "is not in backend access_roles.prod_read",
            "apply role arn:aws:iam::444444444444:role/fnx-production-prod-ci-apply is not in backend "
            "access_roles.prod_write",
            f"backend access_roles.prod_read trusts {arn('prod', 'plan')}",
            f"backend access_roles.prod_write trusts {arn('prod', 'apply')}",
        )

    def test_dev_apply_role_on_prod_write_fails(self):
        roles = access_roles(prod_write=[arn("prod", "apply"), arn("dev", "apply")])
        self.assert_errors(
            stacks(roles=roles, **today()),
            f"backend access_roles.prod_write trusts {arn('dev', 'apply')}, which is no apply role of a "
            "CI role instance in a stage this role serves",
        )

    def test_stale_ci_role_arn_fails(self):
        # The old <tenant>-<stage>-<environment>-ci name left behind after a rename
        stale = "arn:aws:iam::444444444444:role/fnx-ue2-prod-ci-plan"
        roles = access_roles(prod_read=[arn("prod", "plan"), stale])
        self.assert_errors(stacks(roles=roles, **today()), f"backend access_roles.prod_read trusts {stale}")

    def test_plan_role_on_a_write_role_fails(self):
        roles = access_roles(write=[arn("dev", "apply"), arn("staging", "apply"), arn("dev", "plan")])
        self.assert_errors(stacks(roles=roles, **today()),
                           f"access_roles.write trusts {arn('dev', 'plan')}, which is no apply role")

    def test_operator_and_non_ci_roles_are_not_reverse_checked(self):
        admin = "arn:aws:iam::222222222222:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Admin_1"
        roles = access_roles(write=[arn("dev", "apply"), arn("staging", "apply"), admin])
        self.assert_errors(with_identity_center(stacks(roles=roles, **today()), {"dev": ["Admin"]}))
        shaped = "arn:aws:iam::222222222222:role/ops-ci-apply"
        roles = access_roles(write=[arn("dev", "apply"), arn("staging", "apply"), shaped])
        self.assertEqual(len(check_ci_state_roles.check(stacks(roles=roles, **today()))), 1)
        original = check_ci_state_roles.OPERATOR_ROLE_ARNS
        check_ci_state_roles.OPERATOR_ROLE_ARNS = frozenset({shaped})
        try:
            self.assert_errors(stacks(roles=roles, **today()))
        finally:
            check_ci_state_roles.OPERATOR_ROLE_ARNS = original

    def test_unmapped_stage_fails(self):
        # A new tier must not fall into the non-prod roles silently
        self.assert_errors(
            stacks(**today(**{"fnx-ue1-qa": ci("qa")})),
            "fnx-ue1-qa: aws-iam-role/ci-plan is in stage 'qa', which STAGE_ROLES does not map to backend roles",
        )

    def test_backend_assuming_another_stages_role_fails(self):
        self.assert_errors(
            stacks(**today(**{"fnx-ue1-prod": ci("prod", assumes="write")})),
            "ci-plan backend assumes access_roles.write (backend.assume_role.role_arn), not one of stage 'prod'",
            "ci-apply backend assumes access_roles.write (backend.assume_role.role_arn), not one of stage 'prod'",
        )

    def test_read_access_assumes_the_read_role(self):
        # TFSTATE_ACCESS=read renders the read roles: still the stage's own
        self.assert_errors(stacks(**today(**{"fnx-ue1-prod": ci("prod", assumes="prod_read")})))

    def test_plan_role_in_the_write_role_only_fails(self):
        roles = access_roles(read=[arn("dev", "plan")], write=[arn("dev", "apply"), arn("staging", "apply"),
                                                               arn("staging", "plan")])
        self.assert_errors(stacks(roles=roles, **today()), "fnx-ue1-staging: aws-iam-role/ci-plan role",
                           f"backend access_roles.write trusts {arn('staging', 'plan')}, which is no apply role")

    def test_prod_role_in_the_non_prod_role_fails(self):
        roles = access_roles(prod_write=[], write=[arn("dev", "apply"), arn("staging", "apply"), arn("prod", "apply")])
        self.assert_errors(stacks(roles=roles, **today()), "is not in backend access_roles.prod_write",
                           "backend access_roles.prod_write trusts no assigned Identity Center set",
                           f"backend access_roles.write trusts {arn('prod', 'apply')}")

    def test_role_without_principals_fails(self):
        roles = access_roles()
        del roles["prod_write"]["allowed_principal_arns"]
        self.assert_errors(stacks(roles=roles, **today()), "is not in backend access_roles.prod_write",
                           "backend access_roles.prod_write trusts no assigned Identity Center set")

    def test_string_false_enabled_fails_like_a_bool_false(self):
        # A template renders vars.enabled "false"; Terraform reads it as false, so the role does not exist.
        for value in (False, "false", "0"):
            with self.subTest(enabled=value):
                roles = ci("prod")
                roles["aws-iam-role/ci-apply"]["vars"]["enabled"] = value
                self.assert_has(stacks(**today(**{"fnx-ue1-prod": roles})), "aws-iam-role/ci-apply role: ")

    def test_unparseable_enabled_fails_with_its_value(self):
        roles = ci("prod")
        roles["aws-iam-role/ci-apply"]["vars"]["enabled"] = "maybe"
        self.assert_has(stacks(**today(**{"fnx-ue1-prod": roles})), "vars.enabled is 'maybe', not a boolean")

    def test_no_apply_role_needs_only_the_plan_role(self):
        roles = access_roles(prod_write=[oaar("prod")])
        self.assert_errors(stacks(roles=roles, **today(**{"fnx-ue1-prod": ci("prod", apply=False)})))

    def test_oidc_disabled_disabled_and_fixtures_are_skipped(self):
        self.assert_errors(stacks(**today(
            **{"fnx-x": ci("dev", environment="other", oidc=False), "fnx-y": ci("dev", environment="other", enabled=False),
               "fnx-ue1-fixtures-webapp": ci("fixtures", environment="ue1-webapp")},
        )))

    def test_stack_ci_never_runs_is_skipped(self):
        # The LocalEmu lane's roles: stage local, settings.github.actions_enabled false.
        local = ci("local", environment="ue1-localemu")
        for role in local.values():
            role["settings"]["github"] = {"actions_enabled": False}
        self.assert_errors(stacks(**today(**{"fnx-ue1-local-localemu": local})))
        local = ci("local", environment="ue1-localemu")
        self.assert_errors(stacks(**today(**{"fnx-ue1-local-localemu": local})),
                           "fnx-ue1-local-localemu: aws-iam-role/ci-plan is in stage 'local'")

    def test_missing_backend_fails(self):
        described = stacks(**today())
        del described["fnx-ue1-root"]
        self.assert_errors(described, "no state bucket has one deployable 'backend' instance owning it")

    def test_bucket_without_one_owner_fails(self):
        # Another bucket's backend does not stand in; a bucket created twice has no owner
        self.assert_errors(stacks(**today(**{"fnx-ue1-dev": ci("dev", bucket="fnx-other-state")})),
                           "fnx-ue1-dev: aws-iam-role/ci-plan state bucket 'fnx-other-state' has no one owning 'backend' instance",
                           f"backend access_roles.read trusts {arn('dev', 'plan')}",
                           f"backend access_roles.write trusts {arn('dev', 'apply')}")
        described = stacks(**today())
        described["fnx-ue1-copy"] = {"components": {"terraform": {"backend/main": backend(access_roles())}}}
        # Created twice: no owner
        self.assert_errors(described, "no state bucket has one deployable 'backend' instance owning it")

    def test_us_and_eu_backends_each_trusting_their_own_ci_pass(self):
        self.assert_errors(two_backends())

    def test_eu_ci_trusted_only_by_a_us_role_fails(self):
        us = access_roles(prod_read=[arn("prod", "plan"), eu_arn("plan")],
                          prod_write=[arn("prod", "apply"), eu_arn("apply")])
        self.assert_errors(
            two_backends(us=us, eu=eu_roles(prod_read=[], prod_write=[])),
            f"fnx-ew1-prod: aws-iam-role/ci-plan role {eu_arn('plan')} is not in backend access_roles.prod_read "
            "allowed_principal_arns of fnx-ew1-root: backend/main",
            f"fnx-ew1-prod: aws-iam-role/ci-apply role {eu_arn('apply')} is not in backend access_roles.prod_write",
            "fnx-ew1-root: backend/main: " + "backend access_roles.prod_write trusts no assigned Identity Center set",
            f"fnx-ue1-root: backend/main: backend access_roles.prod_read trusts {eu_arn('plan')}",
            f"fnx-ue1-root: backend/main: backend access_roles.prod_write trusts {eu_arn('apply')}",
        )

    def test_eu_ci_granted_the_us_roles_fails(self):
        # The AssumeState* statements pointed at the US backend's prod roles: not the roles of the backend owning its state
        us = (ROLE_NAMES["prod_read"], ROLE_NAMES["prod_write"])
        self.assert_errors(
            two_backends(eu_instance=eu_ci(grants=us)),
            f"fnx-ew1-prod: aws-iam-role/ci-plan role may assume ['{role_arn(us[0])}'] (policy_statements.AssumeStateReadRoles), "
            f"not fnx-ew1-root: backend/main access_roles.prod_read ({EU_ROLE_NAMES['prod_read']})",
            f"fnx-ew1-prod: aws-iam-role/ci-apply role may assume ['{role_arn(us[1])}'] (policy_statements.AssumeStateWriteRole), "
            "not fnx-ew1-root: backend/main access_roles.prod_write",
        )

    def test_grant_of_another_stage_or_none_fails(self):
        non_prod = ci("prod", grants=(ROLE_NAMES["read"], ROLE_NAMES["write"]))
        self.assert_errors(stacks(**today(**{"fnx-ue1-prod": non_prod})),
                           "fnx-ue1-prod: aws-iam-role/ci-plan role may assume", "fnx-ue1-prod: aws-iam-role/ci-apply role may assume")
        unset = ci("dev")
        plan_of(unset)["vars"]["policy_statements"]["AssumeStateReadRoles"]["resources"] = []
        apply_of(unset)["vars"]["policy_statements"]["AssumeStateWriteRole"]["resources"] = None
        self.assert_errors(stacks(**today(**{"fnx-ue1-dev": unset})),
                           "plan role may assume [] (policy_statements.AssumeStateReadRoles)",
                           "apply role may assume [] (policy_statements.AssumeStateWriteRole)")

    def test_grant_of_the_right_role_in_another_account_fails(self):
        prod = ci("prod")
        plan_of(prod)["vars"]["policy_statements"]["AssumeStateReadRoles"]["resources"] = [
            "arn:aws:iam::999999999999:role/fnx-terraform-backend-prod-read-role"]
        self.assert_errors(stacks(**today(**{"fnx-ue1-prod": prod})),
                           "fnx-ue1-prod: aws-iam-role/ci-plan role may assume ['arn:aws:iam::999999999999:role/"
                           "fnx-terraform-backend-prod-read-role'] (policy_statements.AssumeStateReadRoles), not fnx-ue1-root: "
                           "backend/main access_roles.prod_read (fnx-terraform-backend-prod-read-role) in "
                           "aws:111111111111")
        plan_of(prod)["vars"]["policy_statements"]["AssumeStateReadRoles"]["resources"] = [
            "arn:aws-us-gov:iam::111111111111:role/fnx-terraform-backend-prod-read-role"]
        self.assert_errors(stacks(**today(**{"fnx-ue1-prod": prod})), "fnx-ue1-prod: aws-iam-role/ci-plan role may assume")

    def test_grant_with_a_role_path_passes(self):
        prod = ci("prod")
        plan_of(prod)["vars"]["policy_statements"]["AssumeStateReadRoles"]["resources"] = [role_arn("path/x/fnx-terraform-backend-prod-read-role")]
        self.assert_errors(stacks(**today(**{"fnx-ue1-prod": prod})))

    def test_write_grant_is_not_checked_without_the_apply_role(self):
        roles = access_roles(prod_write=[oaar("prod")])
        for wrong in (None, role_arn(ROLE_NAMES["write"]), "arn:aws:iam::999999999999:role/x"):
            prod = ci("prod")
            apply_of(prod)["vars"]["policy_statements"]["AssumeStateWriteRole"]["resources"] = [wrong]
            del prod["aws-iam-role/ci-apply"]
            self.assert_errors(stacks(roles=roles, **today(**{"fnx-ue1-prod": prod})))

    def test_eu_ci_assuming_a_us_role_fails(self):
        # backend.assume_role.role_arn rendered from the US backend: not a role of the backend owning its state
        self.assert_errors(
            two_backends(eu_instance=eu_ci(role=ROLE_NAMES["prod_write"])),
            "fnx-ew1-prod: aws-iam-role/ci-plan backend assumes access_roles.None (backend.assume_role.role_arn), "
            "not one of stage 'prod''s ['prod_read', 'prod_write'] of fnx-ew1-root: backend/main",
            "fnx-ew1-prod: aws-iam-role/ci-apply backend assumes access_roles.None",
        )

    def test_eu_ci_assuming_a_role_of_another_stage_fails(self):
        self.assert_errors(
            two_backends(eu_instance=eu_ci(role=EU_ROLE_NAMES["root_write"])),
            "fnx-ew1-prod: aws-iam-role/ci-plan backend assumes access_roles.root_write (backend.assume_role.role_arn)",
            "fnx-ew1-prod: aws-iam-role/ci-apply backend assumes access_roles.root_write",
        )

    def test_unresolvable_arn_fails(self):
        self.assert_has(stacks(**today(**{"fnx-ue1-prod": ci("prod", environment="e" * 70, apply=False)})),
                        "ci-plan role: resolved an invalid role ARN")
        # a custom regex_replace_chars that keeps the space leaves an invalid character in the ARN
        bad = ci("prod", environment="bad name", apply=False)
        bad["aws-iam-role/ci-plan"]["vars"]["regex_replace_chars"] = "/[^-a-zA-Z0-9 ]/"
        self.assert_has(stacks(**today(**{"fnx-ue1-prod": bad})), "ci-plan role: resolved an invalid role ARN")


def sso(stage, permission_set):
    """An Identity Center role pattern, as the root files write it."""
    return f"arn:aws:iam::{account_of(stage)}:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_{permission_set}_*"


CORE_ACCOUNT = "666666666666"


def account_of(stage):
    return ACCOUNTS.get(stage, CORE_ACCOUNT)


def oaar(stage):
    return f"arn:aws:iam::{account_of(stage)}:role/OrganizationAccountAccessRole"


def with_core(described):
    """A core-account stack (stage security, no CI role) whose backend assumes core_write."""
    described["fnx-ue1-security"] = {"components": {"terraform": {"aws-account-settings": {
        "component": "aws-account-settings",
        "backend": {"bucket": US_BUCKET, "assume_role": {"role_arn": role_arn(ROLE_NAMES["core_write"])}},
        "settings": {"context": {"stage": "security"}, "environment": {"account_id": CORE_ACCOUNT}},
    }}}}
    return described


def with_identity_center(described, assigned):
    """fnx-gbl-root's (disabled) aws-identity-center: assigned is {stage: [permission set, ...]}."""
    described["fnx-gbl-root"] = {"components": {"terraform": {"aws-identity-center": {
        "component": "aws-identity-center",
        "metadata": {"enabled": False},
        "vars": {
            "account_map": {"full_account_map": {f"fnx-{stage}": account_of(stage)
                                                 for stage in ("dev", "staging", "prod", "security")}},
            "account_assignments": {f"fnx-{stage}": {"groups": {"G": {"permission_sets": sets}}}
                                    for stage, sets in assigned.items()},
            "tf_access_role_arn": role_arn(ROLE_NAMES["write"]),
            "tf_access_additional_backends": {
                "prod": {"role_arn": role_arn(ROLE_NAMES["prod_write"]),
                         "read_role_arn": role_arn(ROLE_NAMES["prod_read"])},
                "core": {"role_arn": role_arn(ROLE_NAMES["core_write"])},
            },
        },
    }}}}
    return described


# The sets account_assignments gives each account (stacks/catalog/aws-identity-center).
ASSIGNED = {
    "dev": ["TerraformApplyAccess", "AdministratorAccess"],
    "staging": ["TerraformPlanAccess", "AdministratorAccess"],
    "prod": ["TerraformPlanAccess-Prod", "AdministratorAccess"],
    "security": ["AdministratorAccess"],
}


class IdentityCenterRolesTest(unittest.TestCase):
    assert_errors = CheckCiStateRolesTest.assert_errors
    assert_has = CheckCiStateRolesTest.assert_has

    def roles(self, **overrides):
        principals = {
            "read": [arn("dev", "plan"), arn("staging", "plan"), sso("staging", "TerraformPlanAccess")],
            "write": [arn("dev", "apply"), arn("staging", "apply"), sso("dev", "TerraformApplyAccess"),
                      sso("dev", "AdministratorAccess"), sso("staging", "AdministratorAccess")],
            "prod_read": [arn("prod", "plan"), sso("prod", "TerraformPlanAccess-Prod")],
            "prod_write": [arn("prod", "apply"), sso("prod", "AdministratorAccess")],
            "core_write": [oaar("security"), sso("security", "AdministratorAccess")],
        }
        principals.update(overrides)
        return access_roles(**principals)

    def described(self, roles=None, assigned=None):
        return with_identity_center(with_core(stacks(roles=roles or self.roles(), **today())),
                                    ASSIGNED if assigned is None else assigned)

    def test_assigned_sets_on_the_roles_they_assume_pass(self):
        self.assert_errors(self.described())

    def test_plan_set_on_a_write_role_and_apply_set_on_a_read_role_fail(self):
        roles = self.roles(write=[arn("dev", "apply"), arn("staging", "apply"), sso("staging", "TerraformPlanAccess")],
                           prod_read=[arn("prod", "plan"), sso("prod", "AdministratorAccess")])
        self.assert_has(self.described(roles),
                        "access_roles.prod_read trusts permission set AdministratorAccess",
                        "access_roles.write trusts permission set TerraformPlanAccess")

    def test_set_in_another_stages_account_fails(self):
        roles = self.roles(core_write=[oaar("security"), sso("security", "AdministratorAccess"),
                                       sso("prod", "AdministratorAccess")])
        self.assert_errors(
            self.described(roles),
            f"access_roles.core_write trusts {sso('prod', 'AdministratorAccess')}, in account 444444444444, "
            f"no account of a stack whose state this role serves (['{CORE_ACCOUNT}'])",
        )

    def test_set_on_another_backends_role_fails(self):
        # Each Terraform set assumes one role (its policy): the main backend's TerraformApplyAccess
        # assumes the dev/staging write role, so on core_write it would trust a set that never reaches it.
        assigned = {**ASSIGNED, "security": ["AdministratorAccess", "TerraformApplyAccess"]}
        roles = self.roles(core_write=[oaar("security"), sso("security", "TerraformApplyAccess")])
        self.assert_errors(self.described(roles, assigned),
                           "access_roles.core_write trusts permission set TerraformApplyAccess "
                           f"({sso('security', 'TerraformApplyAccess')}), whose policy assumes "
                           "fnx-terraform-backend-role, not this role (fnx-terraform-backend-core-role)")

    def test_plan_set_without_a_read_role_is_trusted_nowhere(self):
        assigned = {**ASSIGNED, "security": ["AdministratorAccess", "TerraformPlanAccess-Core"]}
        roles = self.roles(read=[arn("dev", "plan"), arn("staging", "plan"), sso("staging", "TerraformPlanAccess"),
                                 sso("security", "TerraformPlanAccess-Core")])
        self.assert_has(self.described(roles, assigned), "whose policy assumes no state role")

    def test_unassigned_set_fails_high_1(self):
        # HIGH-1 (#491 review): core_write trusted TerraformApplyAccess-Core, which no group is assigned.
        roles = self.roles(core_write=[oaar("security"), sso("security", "TerraformApplyAccess-Core")])
        self.assert_errors(self.described(roles),
                           f"access_roles.core_write trusts {sso('security', 'TerraformApplyAccess-Core')}, which "
                           f"aws-identity-center's account_assignments do not assign in account {CORE_ACCOUNT}")

    def test_write_role_without_an_assigned_set_ci_apply_role_or_oaar_fails_high_1(self):
        # Without the OAAR (the PR enabling Identity Center removes it), HIGH-1's core_write lets nobody in.
        roles = self.roles(core_write=[sso("security", "TerraformApplyAccess-Core")])
        self.assert_has(self.described(roles),
                        "access_roles.core_write trusts no assigned Identity Center set whose policy assumes it, "
                        "CI apply role or OrganizationAccountAccessRole")
        self.assert_has(self.described(self.roles(core_write=[])), "access_roles.core_write trusts no assigned")

    def test_assigned_set_whose_policy_does_not_assume_the_role_is_no_applier(self):
        # Bad: core_write's only principal is a set assigned in security whose policy never assumes it
        # (BillingAdministratorAccess has no sts:AssumeRole; TerraformApplyAccess assumes the write role).
        assigned = {**ASSIGNED, "security": ["BillingAdministratorAccess", "TerraformApplyAccess"]}
        for permission_set in ("BillingAdministratorAccess", "TerraformApplyAccess"):
            roles = self.roles(core_write=[sso("security", permission_set)])
            self.assert_has(self.described(roles, assigned),
                            "access_roles.core_write trusts no assigned Identity Center set whose policy assumes it")

    def test_sets_that_assume_any_role_or_the_role_itself_are_appliers(self):
        # PowerUserAccess may assume any role; TerraformApplyAccess-Prod's policy assumes prod_write itself.
        assigned = {**ASSIGNED, "security": ["PowerUserAccess"], "prod": ["TerraformApplyAccess-Prod"]}
        roles = self.roles(core_write=[sso("security", "PowerUserAccess")], prod_read=[arn("prod", "plan")],
                           prod_write=[sso("prod", "TerraformApplyAccess-Prod")])
        errors = check_ci_state_roles.check(self.described(roles, assigned))
        self.assertFalse(any("trusts no assigned" in error for error in errors), errors)

    def test_set_whose_assumed_role_is_unresolvable_is_no_applier(self):
        # Bad: TerraformApplyAccess-Core's backend is gone from tf_access_additional_backends, and core_write
        # has no role_name, so None == None must not make the set an applier.
        assigned = {**ASSIGNED, "security": ["TerraformApplyAccess-Core"]}
        roles = self.roles(core_write=[sso("security", "TerraformApplyAccess-Core")])
        roles["core_write"]["role_name"] = None
        described = self.described(roles, assigned)
        ic = described["fnx-gbl-root"]["components"]["terraform"]["aws-identity-center"]
        del ic["vars"]["tf_access_additional_backends"]["core"]
        self.assert_has(described, "access_roles.core_write trusts no assigned Identity Center set")

    def test_placeholder_accounts_match_the_first_deploy_preflight(self):
        spec = importlib.util.spec_from_file_location(
            "check_first_deploy_inputs", pathlib.Path(__file__).with_name("check-first-deploy-inputs.py"))
        preflight = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(preflight)
        self.assertEqual(check_ci_state_roles.PLACEHOLDER_ACCOUNTS, preflight.PLACEHOLDER_ACCOUNTS)

    def test_account_id_shared_by_several_account_map_keys_fails(self):
        # Bad: fnx-network shares security's ID, so the two accounts' assignments merge.
        described = self.described()
        ic = described["fnx-gbl-root"]["components"]["terraform"]["aws-identity-center"]
        ic["vars"]["account_map"]["full_account_map"]["fnx-network"] = CORE_ACCOUNT
        self.assert_has(described, f"in account {CORE_ACCOUNT}, which account_map keys ['fnx-network', "
                                   "'fnx-security'] share")

    def test_shared_placeholder_account_id_is_exempt(self):
        # Every account holds the placeholder until the first deploy (check-first-deploy-inputs.py fails it).
        placeholder = "123456789012"
        described = self.described()
        ic = described["fnx-gbl-root"]["components"]["terraform"]["aws-identity-center"]
        ic["vars"]["account_map"]["full_account_map"].update({"fnx-a": placeholder, "fnx-b": placeholder})
        backend_roles = described["fnx-ue1-root"]["components"]["terraform"]["backend/main"]["vars"]["access_roles"]
        backend_roles["write"]["allowed_principal_arns"].append(
            f"arn:aws:iam::{placeholder}:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_AdministratorAccess_*")
        errors = check_ci_state_roles.check(described)
        self.assertFalse(any("share" in error for error in errors), errors)

    def test_no_identity_center_instance_assigns_nothing(self):
        described = with_core(stacks(roles=self.roles(), **today()))
        self.assert_has(described, "which aws-identity-center's account_assignments do not assign")

    def test_identity_center_role_is_never_a_ci_role(self):
        # An Identity Center role named like a CI role is still checked as a human.
        shaped = "arn:aws:iam::222222222222:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Ops-ci-apply_1"
        roles = self.roles()
        roles["write"]["allowed_principal_arns"].append(shaped)
        self.assert_errors(self.described(roles, {**ASSIGNED, "dev": ASSIGNED["dev"] + ["Ops-ci-apply"]}))


if __name__ == "__main__":
    unittest.main()

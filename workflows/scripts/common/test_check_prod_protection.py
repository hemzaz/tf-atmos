"""Tests for check-prod-protection.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import copy
import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_prod_protection", pathlib.Path(__file__).with_name("check-prod-protection.py")
)
check_prod_protection = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_prod_protection)

# The real components: defaults are read from their variables.tf.
COMPONENTS = pathlib.Path(__file__).resolve().parents[3] / "components" / "terraform"

SAFE_RDS = {"environment": "prod", "multi_az": True, "deletion_protection": True, "backup_retention_period": 30}
SAFE_CACHE = {"automatic_failover_enabled": True, "multi_az_enabled": True, "num_cache_nodes": 3,
              "snapshot_retention_limit": 7}


def instance(component, stage="prod", **variables):
    return {"component": component, "vars": variables, "metadata": {},
            "settings": {"context": {"stage": stage}}}


def stacks(**instances):
    return {"fnx-ue1-prod": {"components": {"terraform": instances}}}


def errors(described):
    return check_prod_protection.check(described, COMPONENTS)


class CheckProdProtectionTest(unittest.TestCase):
    def test_todays_prod_settings_pass(self):
        self.assertEqual(errors(stacks(**{"rds/main": instance("rds", **SAFE_RDS),
                                          "elasticache/main": instance("elasticache", **SAFE_CACHE)})), [])

    def test_template_defaults_in_prod_fail(self):
        # web-application/rds as the template ships it, in a prod stack without overrides
        found = errors(stacks(**{"web-application/rds": instance(
            "rds", multi_az=False, deletion_protection=False, skip_final_snapshot=True, backup_retention_period=7)}))
        self.assertEqual(len(found), 4, found)
        for fragment in ('environment is "dev" (the default); a prod instance needs "prod"',
                         "multi_az is false (set)", "deletion_protection is false (set)",
                         "skip_final_snapshot is true (set); a prod instance needs false"):
            self.assertTrue(any(fragment in e for e in found), (fragment, found))

    def test_cognito_without_deletion_protection_fails(self):
        found = errors(stacks(**{"cognito/main": instance("cognito", deletion_protection=False)}))
        self.assertEqual(len(found), 1, found)
        self.assertIn("(cognito) deletion_protection is false (set); a prod instance needs true", found[0])

    def test_cognito_default_deletion_protection_passes(self):
        self.assertEqual(errors(stacks(**{"cognito/main": instance("cognito")})), [])

    def test_prevent_destroy_off_fails(self):
        found = errors(stacks(**{"rds/main": instance("rds", prevent_destroy=False, **SAFE_RDS)}))
        self.assertEqual(len(found), 1, found)
        self.assertIn("prevent_destroy is false (set)", found[0])

    def test_short_backup_retention_fails(self):
        found = errors(stacks(**{"rds/main": instance("rds", **dict(SAFE_RDS, backup_retention_period=3))}))
        self.assertEqual(len(found), 1, found)
        self.assertIn("backup_retention_period is 3 (set); a prod instance needs >= 7", found[0])

    def test_single_node_cache_without_failover_fails(self):
        found = errors(stacks(**{"web-application/elasticache": instance(
            "elasticache", num_cache_nodes=1, automatic_failover_enabled=False, multi_az_enabled=False,
            snapshot_retention_limit=1)}))
        self.assertEqual(len(found), 4, found)

    def test_cluster_mode_needs_no_node_count(self):
        cache = dict(SAFE_CACHE, num_cache_nodes=1, cluster_mode_enabled=True)
        self.assertEqual(errors(stacks(**{"elasticache/main": instance("elasticache", **cache)})), [])

    def test_cache_defaults_except_retention_pass(self):
        # automatic_failover_enabled, multi_az_enabled (true) and num_cache_nodes (2) default safe
        self.assertEqual(errors(stacks(**{"elasticache/main": instance("elasticache", snapshot_retention_limit=14)})), [])

    def test_template_rendered_strings_are_normalized(self):
        rds = dict(SAFE_RDS, multi_az="true", backup_retention_period="30")
        self.assertEqual(errors(stacks(**{"rds/main": instance("rds", **rds)})), [])

    def test_non_prod_disabled_and_abstract_are_skipped(self):
        unsafe = {"multi_az": False}
        off = instance("rds", **unsafe)
        off["metadata"] = {"enabled": False}
        base = instance("rds", **unsafe)
        base["metadata"] = {"type": "abstract"}
        self.assertEqual(errors(stacks(**{
            "rds/dev": instance("rds", stage="dev", **unsafe),
            "rds/off": off,
            "rds/defaults": base,
            "vpc/main": instance("vpc"),
        })), [])

    def test_default_reader_reads_the_component(self):
        self.assertIs(check_prod_protection.variable_default(COMPONENTS, "rds", "prevent_destroy"), True)
        self.assertEqual(check_prod_protection.variable_default(COMPONENTS, "rds", "environment"), "dev")
        with self.assertRaises(KeyError):
            check_prod_protection.variable_default(COMPONENTS, "rds", "no_such_variable")



class CiTrustTest(unittest.TestCase):
    """E6a4: the house iam's trust validations, on the vendored aws-iam-role CI roles (any stage)."""
    REPO = "hemzaz/tf-atmos"
    ADMIN = "arn:aws:iam::aws:policy/AdministratorAccess"

    def role(self, kind="plan", stage="prod", repos=None, **variables):
        return instance("aws-iam-role", stage=stage, name=f"ci-{kind}", github_oidc_provider_enabled=True,
                        trusted_github_repos=[f"{self.REPO}:master"] if repos is None else repos, **variables)

    def found(self, *roles, stage="prod"):
        described = {f"fnx-ue1-{stage}": {"components": {"terraform": {
            f"aws-iam-role/x{i}": role for i, role in enumerate(roles)}}}}
        return check_prod_protection.check_ci_trust(described)

    def assert_one(self, found, fragment):
        self.assertEqual(len(found), 1, found)
        self.assertIn(fragment, found[0])

    def test_catalog_roles_pass(self):
        # catalog/aws-iam-role/ci.yaml as rendered: prod's pull_request entry collapses onto master.
        self.assertEqual(self.found(self.role(repos=[f"{self.REPO}:master", f"{self.REPO}:master"],
                                              managed_policy_arns=["arn:aws:iam::aws:policy/ReadOnlyAccess"],
                                              policy_statements=copy.deepcopy(self.STATE_READ)),
                                    self.role("apply", managed_policy_arns=[self.ADMIN])), [])
        self.assertEqual(self.found(self.role(stage="dev", repos=[f"{self.REPO}:master", f"{self.REPO}:pull_request"]),
                                    self.role("apply", stage="dev"), stage="dev"), [])

    def test_wildcard_fails_in_any_stage(self):
        # The deliberately bad case: a wildcard branch or repo, or a constraint-less entry (repo:<org>/<repo>:*).
        for stage in ("dev", "prod"):
            for bad in (f"{self.REPO}:*", "hemzaz/*:master", f"{self.REPO}:feature-?", self.REPO, "tf-atmos:master"):
                for kind in ("plan", "apply"):
                    with self.subTest(stage=stage, bad=bad, kind=kind):
                        self.assert_one(self.found(self.role(kind, stage=stage, repos=[bad]), stage=stage),
                                        "with no * or ?")

    # The plan role's state read statement as catalog/aws-iam-role/ci.yaml renders it.
    STATE_READ = {"AssumeStateReadRoles": {"effect": "Allow", "actions": ["sts:AssumeRole"], "resources": [
        "arn:aws:iam::111111111111:role/fnx-terraform-backend-read-role"]}}

    def plan(self, stage="dev", **variables):
        variables.setdefault("managed_policy_arns", [check_prod_protection.PLAN_READ_ONLY_POLICY])
        variables.setdefault("policy_statements", copy.deepcopy(self.STATE_READ))
        return self.role(stage=stage, repos=[f"{self.REPO}:master"], **variables)

    def test_catalog_plan_permissions_pass(self):
        self.assertEqual(self.found(self.plan(), stage="dev"), [])
        self.assertEqual(self.found(self.plan(managed_policy_arns=[], policy_statements={}), stage="dev"), [])

    def test_plan_managed_policies_are_an_allow_list(self):
        # The deliberately bad cases: any write-capable attachment, not only Admin/PowerUser.
        for policy in (self.ADMIN, "arn:aws:iam::aws:policy/PowerUserAccess",
                       "arn:aws:iam::aws:policy/IAMFullAccess", "arn:aws:iam::123456789012:policy/custom"):
            for stage in ("dev", "prod"):
                with self.subTest(policy=policy, stage=stage):
                    self.assert_one(self.found(self.plan(stage, managed_policy_arns=[
                        check_prod_protection.PLAN_READ_ONLY_POLICY, policy]), stage=stage),
                                    f"managed_policy_arns attaches ['{policy}']")

    def test_plan_policy_statements_are_an_allow_list(self):
        # The reviewer's case: s3:* on * passed the deny-list.
        statements = dict(self.STATE_READ, S3={"effect": "Allow", "actions": ["s3:*"], "resources": ["*"]})
        found = self.found(self.plan(policy_statements=statements), stage="dev")
        self.assert_one(found, "fnx-ue1-dev: aws-iam-role/x0 (aws-iam-role) policy_statements.S3 is not allowed")

    def test_plan_state_statement_must_be_the_catalogs(self):
        for change in ({"actions": ["sts:AssumeRole", "s3:PutObject"]}, {"resources": ["*"]},
                       {"resources": ["arn:aws:iam::111111111111:role/fnx-terraform-backend-role"]},
                       {"effect": "Deny"}, {"condition": {"Bool": {"aws:SecureTransport": "true"}}},
                       {"not_resources": ["*"]}):
            with self.subTest(change=change):
                statements = copy.deepcopy(self.STATE_READ)
                statements["AssumeStateReadRoles"].update(change)
                self.assert_one(self.found(self.plan(policy_statements=statements), stage="dev"),
                                "policy_statements.AssumeStateReadRoles is")

    def test_plan_policy_documents_fail(self):
        document = '{"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": "s3:*", "Resource": "*"}]}'
        self.assert_one(self.found(self.plan(policy_documents=[document]), stage="dev"), "sets policy_documents")

    def test_eks_oidc_trust_on_a_ci_role_fails(self):
        for kind in ("plan", "apply"):
            with self.subTest(kind=kind):
                self.assert_one(self.found(self.role(kind, stage="dev", eks_oidc_provider_enabled=True), stage="dev"),
                                "sets eks_oidc_provider_enabled: true")

    def test_admin_on_apply_passes(self):
        self.assertEqual(self.found(self.role("apply", managed_policy_arns=[self.ADMIN])), [])

    def test_prod_plan_trusts_master_only(self):
        for bad in ("pull_request", "feature-x", "environment:prod", "ref:refs/heads/master"):
            with self.subTest(bad=bad):
                self.assert_one(self.found(self.role(repos=[f"{self.REPO}:master", f"{self.REPO}:{bad}"])),
                                "trusts the master branch only")

    def test_nonprod_plan_may_trust_pull_requests_and_environments(self):
        repos = [f"{self.REPO}:master", f"{self.REPO}:pull_request", f"{self.REPO}:environment:dev"]
        self.assertEqual(self.found(self.role(stage="dev", repos=repos), stage="dev"), [])
        self.assert_one(self.found(self.role(stage="dev", repos=[f"{self.REPO}:ref:refs/tags/v1"]), stage="dev"),
                        "a plan role trusts a branch, pull_request or an environment")

    def test_apply_trusts_a_pinned_branch_only(self):
        for bad in ("pull_request", "environment:prod", "ref:refs/heads/master"):
            for stage in ("dev", "prod"):
                with self.subTest(bad=bad, stage=stage):
                    self.assert_one(self.found(self.role("apply", stage=stage, repos=[f"{self.REPO}:{bad}"]),
                                               stage=stage), "trusts a pinned branch only")

    def test_empty_trust_and_merged_trust_fail(self):
        self.assert_one(self.found(self.role(repos=[])), "with no trusted_github_repos entry")
        self.assert_one(self.found(self.role(assume_role_policy='{"Statement": []}')), "merges an assume_role_policy")

    def test_roles_without_github_trust_and_undeployed_are_skipped(self):
        dns = instance("aws-iam-role", name="dns-delegation-dev", managed_policy_arns=[self.ADMIN])
        off = self.role(repos=["*"])
        off["metadata"] = {"enabled": False}
        disabled_trust = self.role(repos=["*"])
        disabled_trust["vars"]["github_oidc_provider_enabled"] = False
        iam = instance("iam", github_oidc_enabled=True)
        self.assertEqual(self.found(dns, off, disabled_trust, iam), [])


class TrailProtectionTest(unittest.TestCase):
    """OQ-F: every trail keeps its key and its label, in any stage (core stacks are not in CD)."""

    # The `vendored` abstract as describe stacks resolves it in fnx-ue1-audit.
    VENDORED = {"enabled": True, "namespace": None, "tenant": "fnx", "environment": "ue1", "stage": "audit",
                "name": None, "delimiter": None, "attributes": [], "regex_replace_chars": None,
                "label_order": ["tenant", "environment", "stage", "name", "attributes"], "id_length_limit": None,
                "label_key_case": None, "label_value_case": None}

    def found(self, settings_stage="audit", metadata=None, context=None, vendored=True, **variables):
        stage = settings_stage
        trail = instance("aws-cloudtrail", stage=stage)  # settings.context.stage: any stage is checked
        trail["vars"] = {"enabled": True, "name": "cloudtrail", "tenant": "fnx", "environment": "ue1",
                         "stage": "audit", "context": {**self.VENDORED, **(context or {})}, **variables}
        trail["metadata"] = metadata or {}
        components = {"cloudtrail": trail}
        if vendored:
            components["vendored"] = {"metadata": {"type": "abstract"}, "vars": {"context": dict(self.VENDORED)}}
        return check_prod_protection.check_trails({"fnx-ue1-audit": {"components": {"terraform": components}}})

    def assert_label_fails(self, fragment, **kwargs):
        found = self.found(**kwargs)
        self.assertEqual(len(found), 1, found)
        self.assertIn("label differs from the vendored null-label shape", found[0])
        self.assertIn(fragment, found[0])

    def test_catalog_trail_passes(self):
        self.assertEqual(self.found(), [])
        self.assertEqual(self.found(enabled=None), [])  # null-label: null takes context.enabled (true)

    def test_disabled_trail_fails_in_any_stage(self):
        for stage in ("audit", "root", "dev"):
            with self.subTest(stage=stage):
                found = self.found(settings_stage=stage, enabled="false")
                self.assertEqual(len(found), 1, found)
                self.assertIn("schedules the trail KMS key's deletion", found[0])

    def test_context_disabled_trail_fails(self):
        # var.enabled null: null-label takes context.enabled.
        found = self.found(enabled=None, context={"enabled": False})
        self.assertEqual(len(found), 1, found)
        self.assertIn("schedules the trail KMS key's deletion", found[0])

    def test_relabelled_trail_fails(self):
        self.assert_label_fails("name 'trail'", name="trail")
        self.assert_label_fails("attributes ['v2']", attributes=["v2"])

    def test_context_attributes_fail(self):
        self.assert_label_fails("attributes ['x']", context={"attributes": ["x"]})

    def test_each_context_label_field_fails(self):
        for field, value in {
            "label_order": ["environment", "tenant", "stage", "name", "attributes"],
            "delimiter": "_",
            "id_length_limit": 32,
            "label_value_case": "upper",
            "regex_replace_chars": "/[^a-z0-9]/",
            "namespace": "acme",
        }.items():
            with self.subTest(field=field):
                self.assert_label_fails(f"{field} {value!r}", context={field: value})

    def test_tenant_or_environment_change_fails(self):
        # Through the context (top-level var null) or the top-level var.
        self.assert_label_fails("tenant 'acme'", tenant=None, context={"tenant": "acme"})
        self.assert_label_fails("environment 'ew1'", environment="ew1")
        self.assert_label_fails("stage 'prod'", stage=None, context={"stage": "prod"})

    def test_missing_vendored_abstract_fails(self):
        found = self.found(vendored=False)
        self.assertEqual(len(found), 1, found)
        self.assertIn("no resolved 'vendored' abstract", found[0])

    def test_undeployed_trail_is_skipped(self):
        # metadata.enabled false stops deploying it; Atmos destroys nothing.
        self.assertEqual(self.found(metadata={"enabled": False}, enabled=False), [])
        self.assertEqual(self.found(metadata={"type": "abstract"}, name=None), [])


if __name__ == "__main__":
    unittest.main()

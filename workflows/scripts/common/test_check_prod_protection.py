"""Tests for check-prod-protection.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import copy
import importlib.util
import json
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
        variables.setdefault("name", f"ci-{kind}")
        variables.setdefault("github_oidc_provider_enabled", True)
        return instance("aws-iam-role", stage=stage,
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

    def test_permissions_boundary_instance_profile_and_session_duration_fail(self):
        for kind in ("plan", "apply"):
            with self.subTest(kind=kind):
                self.assert_one(self.found(self.role(kind, permissions_boundary="arn:aws:iam::1:policy/b")),
                                "sets permissions_boundary")
                self.assert_one(self.found(self.role(kind, instance_profile_enabled=True)),
                                "sets instance_profile_enabled: true")
                for bad in (3599, 7200, 43201, "abc"):
                    self.assert_one(self.found(self.role(kind, max_session_duration=bad)), "sets max_session_duration")
                self.assertEqual(self.found(self.role(kind)), [])
        self.assertEqual(self.found(self.role(instance_profile_enabled=False, permissions_boundary="")), [])

    def test_ci_instance_name_hint_never_says_to_shorten_vars_name(self):
        long_role = self.role("apply", stage="dev")
        long_role["vars"]["context"] = {"namespace": "x" * 70}
        for name, expected in (("aws-iam-role/ci-apply", False), ("aws-iam-role/other", True)):
            hint = check_prod_protection.role_name_errors("w", name, long_role)[0].split("; shorten")[1]
            self.assertEqual("vars.name" in hint, expected, hint)

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
        iam = instance("aws-github-oidc-provider", github_oidc_provider_enabled=True)
        self.assertEqual(self.found(dns, off, disabled_trust, iam), [])

    # E6a5: the Lambda package uploader as catalog/aws-iam-role/lambda-uploader.yaml renders it.
    BUCKET = "arn:aws:s3:::ue1-lambda-artifacts-123456789012"
    APP = "hemzaz/app"

    def uploader_statements(self):
        return [
            {"Sid": "PutLambdaPackages", "Effect": "Allow", "Action": ["s3:PutObject"],
             "Resource": [f"{self.BUCKET}/*"], "Condition": {"Null": {"s3:if-none-match": "false"}}},
            {"Sid": "ReadLambdaPackages", "Effect": "Allow", "Action": ["s3:GetObject"],
             "Resource": [f"{self.BUCKET}/*"]},
            {"Sid": "ListLambdaPackages", "Effect": "Allow", "Action": ["s3:ListBucket"], "Resource": [self.BUCKET]},
            {"Sid": "LambdaPackageEncryption", "Effect": "Allow",
             "Action": ["kms:GenerateDataKey", "kms:Encrypt", "kms:Decrypt"], "Resource": "*",
             "Condition": {"ForAnyValue:StringEquals": {"kms:ResourceAliases": ["alias/ue1-main"]},
                           "StringEquals": {"kms:ViaService": ["s3.us-east-1.amazonaws.com"]}}},
        ]

    def uploader(self, statements=None, stage="dev", repos=None, **variables):
        document = json.dumps({"Version": "2012-10-17",
                               "Statement": self.uploader_statements() if statements is None else statements})
        variables.setdefault("policy_documents", [document])
        variables.setdefault("enabled", True)
        variables.setdefault("region", "us-east-1")
        return self.role("lambda-uploader", stage=stage,
                         repos=[f"{self.APP}:main"] if repos is None else repos, **variables)

    def test_catalog_uploader_passes(self):
        for stage in ("dev", "prod"):
            with self.subTest(stage=stage):
                self.assertEqual(self.found(self.uploader(stage=stage), stage=stage), [])

    def test_off_uploader_is_skipped(self):
        # The catalog default: enabled false and no repos (check-lambda-packages.py pairs the two).
        for off in (False, "false"):
            with self.subTest(enabled=off):
                self.assertEqual(self.found(self.uploader(repos=[], enabled=off), stage="dev"), [])

    def test_enabled_uploader_without_a_repo_fails(self):
        self.assert_one(self.found(self.uploader(repos=[]), stage="dev"),
                        "with no trusted_github_repos entry: add the")

    def test_uploader_trusts_a_pinned_branch_only(self):
        for bad in ("pull_request", "environment:prod", "ref:refs/heads/main", "*", "main*"):
            with self.subTest(bad=bad):
                self.assertEqual(len(self.found(self.uploader(repos=[f"{self.APP}:{bad}"]), stage="dev")), 1)

    def test_eks_oidc_trust_on_the_uploader_fails(self):
        self.assert_one(self.found(self.uploader(eks_oidc_provider_enabled=True), stage="dev"),
                        "sets eks_oidc_provider_enabled: true")

    def test_uploader_managed_policies_and_statements_fail(self):
        self.assert_one(self.found(self.uploader(managed_policy_arns=[self.ADMIN]), stage="dev"),
                        "attaches no managed policy")
        self.assert_one(self.found(self.uploader(policy_statements=copy.deepcopy(self.STATE_READ)), stage="dev"),
                        "the uploader's policy is its one policy_documents entry")

    def found_as(self, instances, stage="dev"):
        """check_ci_trust over instances under their real names (aws-iam-role/lambda-uploader, ...)."""
        return check_prod_protection.check_ci_trust({f"fnx-ue1-{stage}": {"components": {"terraform": instances}}})

    EXTRA = {"Sid": "X", "Effect": "Allow", "Action": "s3:*", "Resource": "*"}

    def test_renamed_uploader_keeps_its_rules(self):
        # Review MEDIUM-1: a vars.name override plus s3:* on * must not escape the allow-list.
        renamed = self.uploader(self.uploader_statements() + [self.EXTRA], name="ci-pkg-uploader")
        found = self.found_as({"aws-iam-role/lambda-uploader": renamed})
        self.assertEqual(len(found), 2, found)
        self.assertIn("sets vars.name 'ci-pkg-uploader': it must stay 'ci-lambda-uploader'", found[0])
        self.assertIn("outside the uploader's allow-list", found[1])

    def test_renamed_plan_role_keeps_its_rules(self):
        # The same bypass on ci-plan (E6a4): a renamed plan role with write access.
        renamed = self.plan(name="ci-read", managed_policy_arns=[self.ADMIN])
        found = self.found_as({"aws-iam-role/ci-plan": renamed})
        self.assertEqual(len(found), 2, found)
        self.assertIn("it must stay 'ci-plan'", found[0])
        self.assertIn("managed_policy_arns attaches", found[1])

    def test_uploader_without_github_trust_keeps_its_rules(self):
        # Review MEDIUM-2: OIDC flag off plus a hand-written trust or principals and an extra statement.
        for trust in ({"assume_role_policy": '{"Statement": []}'}, {"principals": {"AWS": ["*"]}}):
            with self.subTest(trust=trust):
                role = self.uploader(self.uploader_statements() + [self.EXTRA],
                                     github_oidc_provider_enabled=False, **trust)
                found = self.found_as({"aws-iam-role/lambda-uploader": role})
                self.assertEqual(len(found), 3, found)
                self.assertIn("sets github_oidc_provider_enabled False", found[0])
                self.assertTrue(any("merges an assume_role_policy" in e or "sets principals" in e for e in found), found)
                self.assertIn("outside the uploader's allow-list", found[-1])

    def test_principals_on_a_github_role_fail(self):
        self.assert_one(self.found(self.role("apply", principals={"AWS": ["*"]}), stage="prod"), "sets principals")

    def test_off_ci_instances_are_skipped(self):
        off = self.uploader(repos=[], enabled=False, name="other", github_oidc_provider_enabled=False)
        self.assertEqual(self.found_as({"aws-iam-role/lambda-uploader": off}), [])

    def test_role_name_over_64_characters_fails(self):
        # Review MEDIUM-3: the house iam's precondition, for every enabled aws-iam-role.
        context = {"tenant": "fnx", "environment": "ue1-" + "x" * 40, "stage": "dev",
                   "label_order": ["tenant", "environment", "stage", "name", "attributes"]}
        long_lane = self.uploader(context=context)
        found = self.found_as({"aws-iam-role/lambda-uploader": long_lane})
        self.assertEqual(len(found), 1, found)
        self.assertIn("characters), over IAM's 64: the module would truncate it and append a hash, so it would no "
                      "longer be the ARN CI and the state backend derive", found[0])
        self.assertIn("shorten the lane name (settings.prefix)", found[0])
        dns = instance("aws-iam-role", name="dns-delegation-" + "y" * 60)
        self.assert_one(self.found_as({"aws-iam-role/dns": dns}), "the module would silently truncate it and append a hash")
        short = dict(context, environment="ue1-perf")
        self.assertEqual(self.found_as({"aws-iam-role/lambda-uploader": self.uploader(context=short)}), [])

    def test_use_fullname_false_judges_vars_name_whatever_id_length_limit_says(self):
        # E6a5 review: the module never truncates var.name, so no id_length_limit exempts a long one.
        long_name = "dns-delegation-" + "y" * 60  # 75 characters
        for limit in ({}, {"id_length_limit": 32}, {"context": {"id_length_limit": 32}}, {"id_length_limit": "64"}):
            for flag in (False, "false", " False "):
                with self.subTest(limit=limit, use_fullname=flag):
                    found = self.found_as({"aws-iam-role/dns": instance(
                        "aws-iam-role", name=long_name, use_fullname=flag, **limit)})
                    self.assert_one(found, "sets use_fullname false, so the role is named by vars.name")
                    self.assertIn("(75 characters), over IAM's 64 (id_length_limit does not shorten it): the apply "
                                  "would fail; shorten vars.name", found[0])
        ok = instance("aws-iam-role", name="dns-delegation-dev", use_fullname=False, id_length_limit=100)
        self.assertEqual(self.found_as({"aws-iam-role/dns": ok}), [])

    def test_use_fullname_true_over_64_is_hashed_whatever_id_length_limit_says(self):
        # The null-label inside the module hard-codes 64, so a stack's id_length_limit changes nothing.
        long_name = "dns-delegation-" + "y" * 60
        for limit in ({}, {"id_length_limit": 100}, {"id_length_limit": 32}, {"context": {"id_length_limit": 0}}):
            for flag in ({}, {"use_fullname": True}, {"use_fullname": "true"}):
                with self.subTest(limit=limit, flag=flag):
                    found = self.found_as({"aws-iam-role/dns": instance("aws-iam-role", name=long_name, **limit, **flag)})
                    self.assert_one(found, "the module would silently truncate it and append a hash")
                    self.assertIn("(id_length_limit has no effect on it)", found[0])

    def test_id_length_limit_alone_is_not_a_finding(self):
        for limit in (64, "64", 32, 0, "0", None):
            with self.subTest(limit=limit):
                self.assertEqual(self.found_as({"aws-iam-role/lambda-uploader": self.uploader(id_length_limit=limit)}), [])

    def test_ci_instance_with_a_long_id_fails(self):
        # A hashed id is no longer the ARN ci-apply-role-arn.py derives, with or without a limit.
        long_context = {"tenant": "fnx", "environment": "ue1-" + "x" * 40, "stage": "dev",
                        "label_order": ["tenant", "environment", "stage", "name", "attributes"]}
        for limit in ({}, {"id_length_limit": 64}, {"id_length_limit": "32"}):
            with self.subTest(limit=limit):
                found = self.found_as({"aws-iam-role/lambda-uploader": self.uploader(context=long_context, **limit)})
                self.assert_one(found, "no longer be the ARN CI and the state backend derive")

    def test_uploader_kms_via_another_region_fails(self):
        # Review LOW-1: kms:ViaService pinned to the role's own region.
        statements = self.uploader_statements()
        statements[3]["Condition"]["StringEquals"]["kms:ViaService"] = ["s3.eu-west-1.amazonaws.com"]
        self.assert_one(self.found(self.uploader(statements), stage="dev"), "via s3.us-east-1.amazonaws.com only")

    def test_uploader_policy_is_an_allow_list(self):
        # The deliberately bad cases: each widens or drops one guard of the catalog's policy.
        def changed(index, **change):
            statements = self.uploader_statements()
            statements[index].update(change)
            return statements

        other = "arn:aws:s3:::ue1-other-123456789012"
        cases = {
            "unconditional put": changed(0, Condition=None),
            "put on another bucket": changed(0, Resource=[f"{other}/*"]),
            "s3 wildcard action": changed(1, Action=["s3:*"]),
            "read on every bucket": changed(1, Resource=["*"]),
            "list on a non-lambda bucket": [dict(s, Resource=[s["Resource"][0].replace(
                "lambda-artifacts", "data")]) if s["Sid"] != "LambdaPackageEncryption" else s
                for s in self.uploader_statements()],
            "kms without the alias": changed(3, Condition={"StringEquals": {
                "kms:ViaService": ["s3.us-east-1.amazonaws.com"]}}),
            "kms not via s3": changed(3, Condition={"ForAnyValue:StringEquals": {
                "kms:ResourceAliases": ["alias/ue1-main"]}}),
            "kms extra action": changed(3, Action=["kms:GenerateDataKey", "kms:Encrypt", "kms:Decrypt",
                                                   "kms:ScheduleKeyDeletion"]),
            "deny swapped in": changed(2, Effect="Deny"),
            "extra statement": self.uploader_statements() + [
                {"Sid": "Extra", "Effect": "Allow", "Action": ["iam:PassRole"], "Resource": "*"}],
            "missing statement": self.uploader_statements()[:3],
        }
        for case, statements in cases.items():
            with self.subTest(case=case):
                statements = [{k: v for k, v in s.items() if v is not None} for s in statements]
                self.assert_one(self.found(self.uploader(statements), stage="dev"),
                                "outside the uploader's allow-list")
        self.assert_one(self.found(self.uploader(policy_documents=["{not json"]), stage="dev"),
                        "is not a JSON policy")
        two = [json.dumps({"Statement": self.uploader_statements()})] * 2
        self.assert_one(self.found(self.uploader(policy_documents=two), stage="dev"),
                        "outside the uploader's allow-list")


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

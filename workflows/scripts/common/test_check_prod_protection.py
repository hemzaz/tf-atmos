"""Tests for check-prod-protection.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
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



class CiPlanTrustTest(unittest.TestCase):
    MASTER = ["repo:hemzaz/tf-atmos:ref:refs/heads/master"]
    REPO = {"github_oidc_repository": "hemzaz/tf-atmos", "github_oidc_default_branch": "master"}

    def found(self, **variables):
        return check_prod_protection.check_ci_plan_trust(stacks(**{"iam/ci": instance(
            "iam", github_oidc_enabled=True, **{**self.REPO, **variables})}), COMPONENTS)

    def test_default_branch_ref_only_passes(self):
        self.assertEqual(self.found(ci_plan_role_subjects=self.MASTER), [])

    def test_default_trusting_pull_requests_fails(self):
        found = self.found()
        self.assertEqual(len(found), 1, found)
        self.assertIn("leaves ci_plan_role_subjects unset", found[0])

    def test_pull_request_subject_fails(self):
        found = self.found(ci_plan_role_subjects=self.MASTER + ["repo:hemzaz/tf-atmos:pull_request"])
        self.assertEqual(len(found), 1, found)
        self.assertIn("trusts 'repo:hemzaz/tf-atmos:pull_request'", found[0])

    def test_other_branch_ref_fails(self):
        found = self.found(ci_plan_role_subjects=["repo:hemzaz/tf-atmos:ref:refs/heads/feature-x"])
        self.assertEqual(len(found), 1, found)
        self.assertIn("refs/heads/feature-x", found[0])

    def test_environment_subject_fails(self):
        found = self.found(ci_plan_role_subjects=["repo:hemzaz/tf-atmos:environment:x"])
        self.assertEqual(len(found), 1, found)
        self.assertIn("environment:x", found[0])

    def test_wildcard_and_other_repository_fail(self):
        self.assertEqual(len(self.found(ci_plan_role_subjects=["repo:hemzaz/tf-atmos:*"])), 1)
        self.assertEqual(len(self.found(ci_plan_role_subjects=["repo:other/repo:ref:refs/heads/master"])), 1)

    def test_branch_default_is_resolved_from_variables_tf(self):
        # github_oidc_default_branch's default is "main", not master.
        found = check_prod_protection.check_ci_plan_trust(stacks(**{"iam/ci": instance(
            "iam", github_oidc_enabled=True, github_oidc_repository="hemzaz/tf-atmos",
            ci_plan_role_subjects=self.MASTER)}), COMPONENTS)
        self.assertEqual(len(found), 1, found)
        self.assertIn("github_oidc_default_branch is 'main'", found[0])

    def test_coordinated_branch_and_subject_edit_fails(self):
        # Moving both the default branch and the subject to feature-x still fails (D3).
        found = self.found(github_oidc_default_branch="feature-x",
                           ci_plan_role_subjects=["repo:hemzaz/tf-atmos:ref:refs/heads/feature-x"])
        self.assertEqual(len(found), 2, found)
        self.assertIn("github_oidc_default_branch is 'feature-x'", found[0])
        self.assertIn("trusts the master ref only", found[1])

    def test_non_prod_and_roleless_iam_are_skipped(self):
        dev = {"fnx-ue1-dev": {"components": {"terraform": {"iam/ci": instance(
            "iam", stage="dev", github_oidc_enabled=True)}}}}
        self.assertEqual(check_prod_protection.check_ci_plan_trust(dev, COMPONENTS), [])
        self.assertEqual(check_prod_protection.check_ci_plan_trust(
            stacks(**{"iam/main": instance("iam")}), COMPONENTS), [])

if __name__ == "__main__":
    unittest.main()

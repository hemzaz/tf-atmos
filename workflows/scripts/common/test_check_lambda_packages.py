"""Tests for check-lambda-packages.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import copy
import importlib.util
import json
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_lambda_packages", pathlib.Path(__file__).with_name("check-lambda-packages.py")
)
check_lambda_packages = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_lambda_packages)

BUCKET_ARN = "arn:aws:s3:::ue1-lambda-artifacts-123456789012"


def uploader_policy(bucket=BUCKET_ARN, alias="alias/ue1-main"):
    """The policy catalog/aws-iam-role/lambda-uploader.yaml renders for fnx-ue1-dev."""
    return json.dumps({"Version": "2012-10-17", "Statement": [
        {"Sid": "PutLambdaPackages", "Effect": "Allow", "Action": ["s3:PutObject"], "Resource": [f"{bucket}/*"],
         "Condition": {"Null": {"s3:if-none-match": "false"}}},
        {"Sid": "ReadLambdaPackages", "Effect": "Allow", "Action": ["s3:GetObject"], "Resource": [f"{bucket}/*"]},
        {"Sid": "ListLambdaPackages", "Effect": "Allow", "Action": ["s3:ListBucket"], "Resource": [bucket]},
        {"Sid": "LambdaPackageEncryption", "Effect": "Allow",
         "Action": ["kms:GenerateDataKey", "kms:Encrypt", "kms:Decrypt"], "Resource": "*",
         "Condition": {"ForAnyValue:StringEquals": {"kms:ResourceAliases": [alias]},
                       "StringEquals": {"kms:ViaService": ["s3.us-east-1.amazonaws.com"]}}},
    ]})


# An enabled uploader (the catalog's off default plus the stack file's two inputs).
UPLOADER = {
    "component": "aws-iam-role",
    "metadata": {"component": "aws-iam-role"},
    "vars": {
        "enabled": True,
        "name": "ci-lambda-uploader",
        "trusted_github_repos": ["hemzaz/app:main"],
        "policy_documents": [uploader_policy()],
    },
}
BUCKET = {
    "metadata": {"component": "s3"},
    "settings": {"environment": {"account_id": "123456789012"}},
    "vars": {
        "name": "lambda-artifacts",
        "kms_key_arn": "!terraform.state kms/main .key_arn",
        "tags": {"Environment": "ue1"},
    },
}
KMS = {"metadata": {"component": "kms"}, "vars": {"alias_name": "ue1-main"}}
LAMBDA = {
    "metadata": {"component": "lambda"},
    "vars": {
        "function_name": "data-processor",
        "s3_bucket": "!terraform.state s3/lambda-artifacts .bucket_id",
        "s3_key": "data-processor/1.4.2.zip",
    },
}


def stack(**overrides):
    components = {
        "aws-iam-role/lambda-uploader": copy.deepcopy(UPLOADER),
        "s3/lambda-artifacts": copy.deepcopy(BUCKET),
        "kms/main": copy.deepcopy(KMS),
        "lambda/data-processor": copy.deepcopy(LAMBDA),
    }
    for name, change in overrides.items():
        name = name.replace("__", "/").replace("_", "-")
        if change is None:
            del components[name]
        else:
            change(components[name])
    return {"fnx-ue1-dev": {"components": {"terraform": components}}}


def set_var(key, value):
    return lambda instance: instance["vars"].__setitem__(key, value)


def disable(instance):
    instance["metadata"]["enabled"] = False


class CheckLambdaPackagesTest(unittest.TestCase):
    def assert_errors(self, stacks, *fragments):
        errors = check_lambda_packages.check(stacks)
        self.assertEqual(len(errors), len(fragments), errors)
        for error, fragment in zip(errors, fragments):
            self.assertIn(fragment, error)

    def test_matching_stack_passes(self):
        self.assert_errors(stack())

    def test_the_catalog_default_off_uploader_is_not_checked(self):
        def off(instance):
            instance["vars"]["enabled"] = False
            instance["vars"]["trusted_github_repos"] = []

        self.assert_errors(stack(aws_iam_role__lambda_uploader=off, s3__lambda_artifacts=None))

    def test_enabled_uploader_without_a_repo_fails(self):
        self.assert_errors(
            stack(aws_iam_role__lambda_uploader=set_var("trusted_github_repos", [])),
            "is enabled with no trusted_github_repos entry",
        )

    def test_repos_on_an_off_uploader_fail(self):
        for off in (False, "false", None):
            with self.subTest(enabled=off):
                self.assert_errors(
                    stack(aws_iam_role__lambda_uploader=set_var("enabled", off)), "but is off, so no role is created"
                )

    def test_templated_true_counts_as_enabled(self):
        self.assert_errors(
            stack(aws_iam_role__lambda_uploader=set_var("enabled", "true"), s3__lambda_artifacts=None),
            "has no enabled s3/lambda-artifacts",
        )

    def test_policy_on_another_bucket_fails(self):
        self.assert_errors(
            stack(aws_iam_role__lambda_uploader=set_var(
                "policy_documents", [uploader_policy(bucket="arn:aws:s3:::ue1-lambda-artifacts-999999999999")])),
            "so the uploader role writes another bucket",
        )

    def test_bucket_in_another_account_fails(self):
        def other_account(instance):
            instance["settings"]["environment"]["account_id"] = "999999999999"

        self.assert_errors(stack(s3__lambda_artifacts=other_account), "so the uploader role writes another bucket")

    def test_policy_that_is_not_json_fails(self):
        self.assert_errors(
            stack(aws_iam_role__lambda_uploader=set_var("policy_documents", ["{not json"])),
            "is not a JSON policy",
        )

    def test_missing_or_disabled_bucket_fails(self):
        self.assert_errors(stack(s3__lambda_artifacts=None), "has no enabled s3/lambda-artifacts")
        self.assert_errors(stack(s3__lambda_artifacts=disable), "has no enabled s3/lambda-artifacts")

    def test_bucket_name_override_fails(self):
        self.assert_errors(stack(s3__lambda_artifacts=set_var("bucket_name", "custom")), "overrides bucket_name")

    def test_other_bucket_name_segment_fails(self):
        self.assert_errors(stack(s3__lambda_artifacts=set_var("name", "artifacts")), "name is 'artifacts'")

    def test_environment_tag_mismatch_fails(self):
        self.assert_errors(
            stack(s3__lambda_artifacts=set_var("tags", {"Environment": "other"})),
            "so the uploader role writes another bucket",
        )

    def test_alias_mismatch_fails(self):
        self.assert_errors(
            stack(aws_iam_role__lambda_uploader=set_var("policy_documents", [uploader_policy(alias="alias/other")])),
            "are not kms/main's 'alias/ue1-main'",
        )

    def test_bucket_with_another_key_fails(self):
        self.assert_errors(
            stack(s3__lambda_artifacts=set_var("kms_key_arn", "arn:aws:kms:us-east-1:1:key/x")),
            "is not encrypted with kms/main",
        )

    def test_metadata_disabled_uploader_is_skipped(self):
        self.assert_errors(stack(aws_iam_role__lambda_uploader=disable, s3__lambda_artifacts=None))

    def test_placeholder_version_fails_only_when_enabled(self):
        unreleased = set_var("s3_key", "data-processor/unreleased.zip")
        self.assert_errors(stack(lambda__data_processor=unreleased), "set settings.package_version")

        def unreleased_and_disabled(instance):
            unreleased(instance)
            disable(instance)

        self.assert_errors(stack(lambda__data_processor=unreleased_and_disabled))

    def test_unquoted_package_version_fails(self):
        def float_version(instance):
            instance["settings"] = {"package_version": 1.1}
            instance["vars"]["s3_key"] = "data-processor/1.1.zip"

        self.assert_errors(stack(lambda__data_processor=float_version), "is a float, not a string")

    def test_quoted_package_version_passes(self):
        def string_version(instance):
            instance["settings"] = {"package_version": "1.10"}
            instance["vars"]["s3_key"] = "data-processor/1.10.zip"

        self.assert_errors(stack(lambda__data_processor=string_version))

    def test_latest_key_fails(self):
        self.assert_errors(
            stack(lambda__data_processor=set_var("s3_key", "data-processor/latest.zip")),
            "set settings.package_version",
        )

    def test_key_outside_the_function_prefix_fails(self):
        self.assert_errors(
            stack(lambda__data_processor=set_var("s3_key", "other/1.0.0.zip")),
            "is not data-processor/<version>.zip",
        )

    def test_equivalent_bucket_read_spellings_are_still_checked(self):
        spellings = (
            "!terraform.state   s3/lambda-artifacts   .bucket_id",
            "  !terraform.state s3/lambda-artifacts .bucket_id  ",
            "!terraform.state s3/lambda-artifacts bucket_id",
            '!terraform.state s3/lambda-artifacts .bucket_id // "default"',
            '!terraform.state "s3/lambda-artifacts" .bucket_id',
            "!terraform.output s3/lambda-artifacts bucket_id",
        )
        for spelling in spellings:
            with self.subTest(spelling=spelling):
                def respell(instance, spelling=spelling):
                    instance["vars"]["s3_bucket"] = spelling
                    instance["vars"]["s3_key"] = "data-processor/latest.zip"

                self.assert_errors(stack(lambda__data_processor=respell), "set settings.package_version")

    def test_equivalent_spelling_with_a_released_key_passes(self):
        self.assert_errors(
            stack(lambda__data_processor=set_var("s3_bucket", '!terraform.state s3/lambda-artifacts  .bucket_id // ""'))
        )

    def test_reads_of_other_components_or_literals_are_not_packaged(self):
        for value in (
            "!terraform.state s3/other .bucket_id",
            "!terraform.state s3/lambda-artifacts-2 .bucket_id",
            "my-literal-bucket",
            None,
        ):
            with self.subTest(value=value):
                def other(instance, value=value):
                    instance["vars"]["s3_bucket"] = value
                    instance["vars"]["s3_key"] = "data-processor/latest.zip"

                self.assert_errors(stack(lambda__data_processor=other))

    def test_lambda_not_packaged_from_the_bucket_is_skipped(self):
        def local_file(instance):
            instance["vars"] = {"function_name": "api", "filename": "api.zip"}

        self.assert_errors(stack(lambda__data_processor=local_file))


if __name__ == "__main__":
    unittest.main()

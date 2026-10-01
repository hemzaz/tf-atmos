"""Tests for check-lambda-packages.py (stdlib only): python3 -m unittest discover -s workflows/scripts/common"""
import copy
import importlib.util
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location(
    "check_lambda_packages", pathlib.Path(__file__).with_name("check-lambda-packages.py")
)
check_lambda_packages = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_lambda_packages)

IAM = {
    "metadata": {"component": "iam"},
    "vars": {
        "github_oidc_enabled": True,
        "lambda_uploader_trusted_github_repos": [],
        "lambda_uploader_kms_key_alias": "alias/testenv-01-main",
        "tags": {"Environment": "testenv-01"},
    },
}
BUCKET = {
    "metadata": {"component": "s3"},
    "vars": {
        "name": "lambda-artifacts",
        "kms_key_arn": "!terraform.state kms/main .key_arn",
        "tags": {"Environment": "testenv-01"},
    },
}
KMS = {"metadata": {"component": "kms"}, "vars": {"alias_name": "testenv-01-main"}}
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
        "iam/ci": copy.deepcopy(IAM),
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
    return {"fnx-dev-testenv-01": {"components": {"terraform": components}}}


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

    def test_iam_without_uploader_settings_is_not_checked(self):
        def strip(instance):
            del instance["vars"]["lambda_uploader_kms_key_alias"]

        self.assert_errors(stack(iam__ci=strip, s3__lambda_artifacts=None))

    def test_missing_or_disabled_bucket_fails(self):
        self.assert_errors(stack(s3__lambda_artifacts=None), "has no enabled s3/lambda-artifacts")
        self.assert_errors(stack(s3__lambda_artifacts=disable), "has no enabled s3/lambda-artifacts")

    def test_bucket_name_override_fails(self):
        self.assert_errors(stack(s3__lambda_artifacts=set_var("bucket_name", "custom")), "overrides bucket_name")

    def test_other_bucket_name_segment_fails(self):
        self.assert_errors(stack(s3__lambda_artifacts=set_var("name", "artifacts")), "name is 'artifacts'")

    def test_environment_tag_mismatch_fails(self):
        self.assert_errors(
            stack(s3__lambda_artifacts=set_var("tags", {"Environment": "other"})), "differs from s3/lambda-artifacts"
        )

    def test_alias_mismatch_fails(self):
        self.assert_errors(
            stack(iam__ci=set_var("lambda_uploader_kms_key_alias", "alias/other")),
            "is not kms/main's 'alias/testenv-01-main'",
        )

    def test_bucket_with_another_key_fails(self):
        self.assert_errors(
            stack(s3__lambda_artifacts=set_var("kms_key_arn", "arn:aws:kms:us-east-1:1:key/x")),
            "is not encrypted with kms/main",
        )

    def test_disabled_iam_is_skipped(self):
        self.assert_errors(stack(iam__ci=disable, s3__lambda_artifacts=None))

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

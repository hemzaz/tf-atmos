#!/usr/bin/env python3
"""Check the Lambda package contract between iam's uploader role, s3/lambda-artifacts and lambda.

Reads `atmos describe stacks --process-functions=false --format json` on stdin.

The iam component's lambda uploader role (components/terraform/iam/lambda-uploader.tf)
names the bucket it may write instead of reading s3/lambda-artifacts' state: iam/ci
applies before kms and storage (workflows/deploy-full-stack.yaml). It builds
"<tags.Environment>-lambda-artifacts-<account id>" and scopes KMS by
lambda_uploader_kms_key_alias. For each enabled, non-abstract iam instance that sets
lambda_uploader_kms_key_alias or lambda_uploader_trusted_github_repos, this checks that
its stack has an enabled s3/lambda-artifacts instance whose bucket name the s3 component
derives the same way (name "lambda-artifacts", no bucket_name override, the same
tags.Environment; both run in the stack's account), and that the alias is "alias/" plus
the alias_name of the kms/main instance that bucket is encrypted with.

For each enabled lambda instance packaged from s3/lambda-artifacts (any
`!terraform.state s3/lambda-artifacts ...` read of s3_bucket, whatever its spacing, quoting
or yq suffix such as `// "default"`), settings.package_version
must be a YAML string (quoted), and s3_key must be
"<function_name>/<version>.zip" with a real version: not the "unreleased" placeholder
(no package exists, so the apply would fail) and not "latest" (an overwritten key
does not redeploy the function). Exits 1 on any violation.
"""
import json
import sys

BUCKET_INSTANCE = "s3/lambda-artifacts"
BUCKET_NAME = "lambda-artifacts"
KMS_INSTANCE = "kms/main"
KMS_READ = f"!terraform.state {KMS_INSTANCE} .key_arn"
TERRAFORM_READS = ("!terraform.state", "!terraform.output")
PLACEHOLDER_VERSIONS = ("unreleased", "latest")


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def module_name(name: str, instance: dict) -> str:
    return instance.get("component") or (instance.get("metadata") or {}).get("component") or name


def environment_tag(instance: dict) -> str:
    return ((instance.get("vars") or {}).get("tags") or {}).get("Environment") or ""


def uploader_errors(where: str, iam: dict, instances: dict) -> list[str]:
    bucket = instances.get(BUCKET_INSTANCE)
    if bucket is None or not is_deployable(bucket):
        return [f"{where} configures the lambda uploader, but the stack has no enabled {BUCKET_INSTANCE}"]
    errors = []
    bucket_vars = bucket.get("vars") or {}
    if module_name(BUCKET_INSTANCE, bucket) != "s3":
        errors.append(f"{where}: {BUCKET_INSTANCE} is not an s3 instance")
    if bucket_vars.get("bucket_name"):
        errors.append(
            f"{where}: {BUCKET_INSTANCE} overrides bucket_name, so it no longer has the name "
            "the uploader role is scoped to (<Environment>-lambda-artifacts-<account id>)"
        )
    if bucket_vars.get("name") != BUCKET_NAME:
        errors.append(f"{where}: {BUCKET_INSTANCE} name is {bucket_vars.get('name')!r}, not {BUCKET_NAME!r}")
    iam_env, bucket_env = environment_tag(iam), environment_tag(bucket)
    if not iam_env or iam_env != bucket_env:
        errors.append(
            f"{where}: tags.Environment {iam_env!r} differs from {BUCKET_INSTANCE}'s {bucket_env!r}, "
            "so the uploader role names another bucket"
        )

    alias = (iam.get("vars") or {}).get("lambda_uploader_kms_key_alias")
    kms = instances.get(KMS_INSTANCE)
    if bucket_vars.get("kms_key_arn") != KMS_READ:
        errors.append(f"{where}: {BUCKET_INSTANCE} is not encrypted with {KMS_INSTANCE} ({KMS_READ})")
    elif kms is None or not is_deployable(kms):
        errors.append(f"{where}: {BUCKET_INSTANCE} reads {KMS_INSTANCE}, which is missing or disabled")
    else:
        expected = f"alias/{(kms.get('vars') or {}).get('alias_name')}"
        if alias != expected:
            errors.append(
                f"{where}: lambda_uploader_kms_key_alias {alias!r} is not {KMS_INSTANCE}'s {expected!r}, "
                f"the key {BUCKET_INSTANCE} is encrypted with"
            )
    return errors


def reads_lambda_bucket(value) -> bool:
    """True for any `!terraform.state s3/lambda-artifacts ...` read, however it is spelled.

    The first two whitespace-separated tokens decide: the function and the component, so
    `.bucket_id`, `bucket_id`, `.bucket_id // "x"` and extra spaces all count. A lambda that
    reads some other component, or sets a literal bucket name, is not packaged from here.
    """
    if not isinstance(value, str):
        return False
    tokens = value.split()
    return (
        len(tokens) >= 2
        and tokens[0] in TERRAFORM_READS
        and tokens[1].strip("\"'") == BUCKET_INSTANCE
    )


def package_errors(where: str, instance: dict) -> list[str]:
    variables = instance.get("vars") or {}
    if not reads_lambda_bucket(variables.get("s3_bucket")):
        return []
    # describe stacks keeps the YAML type of settings: an unquoted 1.10 is the
    # float 1.1 here, and the key would silently name another release.
    version_setting = (instance.get("settings") or {}).get("package_version")
    if version_setting is not None and not isinstance(version_setting, str):
        return [
            f"{where}: settings.package_version {version_setting!r} is a "
            f"{type(version_setting).__name__}, not a string: quote it (an unquoted 1.10 is 1.1)"
        ]
    key = variables.get("s3_key") or ""
    function_name = variables.get("function_name") or ""
    prefix = f"{function_name}/"
    version = key[len(prefix):-len(".zip")] if key.startswith(prefix) and key.endswith(".zip") else ""
    if not version or "/" in version:
        return [f"{where}: s3_key {key!r} is not {function_name}/<version>.zip"]
    if version in PLACEHOLDER_VERSIONS:
        return [
            f"{where} is enabled with s3_key {key!r}: set settings.package_version to an uploaded "
            "release (a placeholder has no package, and an overwritten key does not redeploy)"
        ]
    return []


def check(stacks: dict) -> list[str]:
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        instances = (stack.get("components") or {}).get("terraform") or {}
        for name, instance in sorted(instances.items()):
            if not is_deployable(instance):
                continue
            where = f"{stack_name}: {name}"
            module = module_name(name, instance)
            variables = instance.get("vars") or {}
            if module == "iam" and (
                variables.get("lambda_uploader_kms_key_alias") or variables.get("lambda_uploader_trusted_github_repos")
            ):
                errors.extend(uploader_errors(where, instance, instances))
            elif module == "lambda":
                errors.extend(package_errors(where, instance))
    return errors


def main() -> int:
    errors = check(json.load(sys.stdin))
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} lambda package problem(s)")
        return 1
    print(
        "every lambda uploader names its stack's s3/lambda-artifacts bucket and kms/main alias, "
        "and every enabled S3-packaged lambda has a released <function_name>/<version>.zip key"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

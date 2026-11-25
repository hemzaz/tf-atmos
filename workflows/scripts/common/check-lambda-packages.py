#!/usr/bin/env python3
"""Check the Lambda package contract between the uploader role, s3/lambda-artifacts and lambda.

Reads `atmos describe stacks --process-functions=false --format json` on stdin.

The Lambda package uploader is each stack's aws-iam-role/lambda-uploader (the vendored
aws-iam-role, stacks/catalog/aws-iam-role/lambda-uploader.yaml), off (vars.enabled false)
until the stack names the application repo. Its switch and its trust go together: an
uploader enabled with no trusted_github_repos entry (a role nothing can assume) fails, and
so does one that names repos while still off (the owner input would do nothing).

The uploader names the bucket it may write instead of reading s3/lambda-artifacts' state:
the iam layer applies before kms and storage (workflows/deploy-full-stack.yaml). Its
policy_documents entry renders "arn:aws:s3:::<settings.prefix>-lambda-artifacts-<account id>"
and scopes KMS by "alias/<settings.prefix>-main". For each enabled uploader, this checks
that its stack has an enabled s3/lambda-artifacts instance whose bucket name the s3
component derives the same way (name "lambda-artifacts", no bucket_name override; its
tags.Environment and settings.environment.account_id: both run in the stack's account),
that every bucket ARN in the policy is that bucket's, and that the policy's alias is
"alias/" plus the alias_name of the kms/main instance that bucket is encrypted with. The
policy's exact statements are check-prod-protection.py's allow-list.

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
from typing import Any, Optional

UPLOADER_INSTANCE = "aws-iam-role/lambda-uploader"
UPLOADER_FIX = f"the stack file's {UPLOADER_INSTANCE} vars (stacks/catalog/aws-iam-role/lambda-uploader.yaml)"
# The uploader policy's statements that name the bucket, and the suffix each puts after its ARN.
BUCKET_STATEMENTS = {"PutLambdaPackages": "/*", "ReadLambdaPackages": "/*", "ListLambdaPackages": ""}
KMS_STATEMENT = "LambdaPackageEncryption"
BUCKET_INSTANCE = "s3/lambda-artifacts"
BUCKET_NAME = "lambda-artifacts"
KMS_INSTANCE = "kms/main"
KMS_READ = f"!terraform.state {KMS_INSTANCE} .key_arn"
TERRAFORM_READS = ("!terraform.state", "!terraform.output")
PLACEHOLDER_VERSIONS = ("unreleased", "latest")


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def is_on(value: Any) -> bool:
    """vars.enabled as Terraform reads it (Atmos renders a templated bool as a string)."""
    return value is True or (isinstance(value, str) and value.strip().lower() == "true")


def module_name(name: str, instance: dict) -> str:
    return instance.get("component") or (instance.get("metadata") or {}).get("component") or name


def environment_tag(instance: dict) -> str:
    return ((instance.get("vars") or {}).get("tags") or {}).get("Environment") or ""


def switch_errors(where: str, uploader: dict) -> list[str]:
    """The uploader's enabled switch and its trusted repos, which only make sense together."""
    variables = uploader.get("vars") or {}
    enabled, repos = is_on(variables.get("enabled")), variables.get("trusted_github_repos") or []
    if enabled and not repos:
        return [f"{where} is enabled with no trusted_github_repos entry, a role nothing can assume: add "
                f"\"<org>/<app-repo>:<branch>\" to trusted_github_repos, or set enabled: false, in {UPLOADER_FIX}"]
    if repos and not enabled:
        return [f"{where} trusts {repos} but is off, so no role is created: set enabled: true in {UPLOADER_FIX}"]
    return []


def policy_targets(uploader: dict) -> tuple[set, set, Optional[str]]:
    """(bucket ARNs, KMS aliases) the uploader's policy_documents name, and a parse problem if any."""
    documents = (uploader.get("vars") or {}).get("policy_documents") or []
    try:
        statements = [s for document in documents for s in json.loads(document).get("Statement") or []]
    except (TypeError, ValueError, AttributeError) as error:
        return set(), set(), f"its policy_documents is not a JSON policy ({error})"
    buckets, aliases = set(), set()
    for statement in statements:
        sid, resources = statement.get("Sid"), statement.get("Resource")
        resources = resources if isinstance(resources, list) else [resources]
        if sid in BUCKET_STATEMENTS:
            suffix = BUCKET_STATEMENTS[sid]
            buckets |= {str(r)[: -len(suffix)] if suffix and str(r).endswith(suffix) else str(r) for r in resources}
        elif sid == KMS_STATEMENT:
            found = ((statement.get("Condition") or {}).get("ForAnyValue:StringEquals") or {}).get(
                "kms:ResourceAliases") or []
            aliases |= set(found if isinstance(found, list) else [found])
    return buckets, aliases, None


def uploader_errors(where: str, uploader: dict, instances: dict) -> list[str]:
    bucket = instances.get(BUCKET_INSTANCE)
    if bucket is None or not is_deployable(bucket):
        return [f"{where} is enabled, but the stack has no enabled {BUCKET_INSTANCE} for it to write: import "
                f"catalog/s3/lambda-artifacts in the stack file, or set enabled: false in {UPLOADER_FIX}"]
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

    buckets, aliases, problem = policy_targets(uploader)
    if problem:
        return errors + [f"{where}: {problem}"]
    account = ((bucket.get("settings") or {}).get("environment") or {}).get("account_id") or ""
    expected_bucket = f"arn:aws:s3:::{environment_tag(bucket)}-{BUCKET_NAME}-{account}"
    if buckets != {expected_bucket}:
        errors.append(
            f"{where}: its policy names bucket(s) {sorted(buckets)}, not {BUCKET_INSTANCE}'s {expected_bucket!r} "
            "(<tags.Environment>-lambda-artifacts-<account id>), so the uploader role writes another bucket"
        )

    kms = instances.get(KMS_INSTANCE)
    if bucket_vars.get("kms_key_arn") != KMS_READ:
        errors.append(f"{where}: {BUCKET_INSTANCE} is not encrypted with {KMS_INSTANCE} ({KMS_READ})")
    elif kms is None or not is_deployable(kms):
        errors.append(f"{where}: {BUCKET_INSTANCE} reads {KMS_INSTANCE}, which is missing or disabled")
    else:
        expected = f"alias/{(kms.get('vars') or {}).get('alias_name')}"
        if aliases != {expected}:
            errors.append(
                f"{where}: its policy's KMS alias(es) {sorted(aliases)} are not {KMS_INSTANCE}'s {expected!r}, "
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
            if name == UPLOADER_INSTANCE:
                errors.extend(switch_errors(where, instance))
                if is_on((instance.get("vars") or {}).get("enabled")):
                    errors.extend(uploader_errors(where, instance, instances))
            elif module_name(name, instance) == "lambda":
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
        "every enabled lambda uploader trusts an app repo and names its stack's s3/lambda-artifacts bucket "
        "and kms/main alias, and every enabled S3-packaged lambda has a released <function_name>/<version>.zip key"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

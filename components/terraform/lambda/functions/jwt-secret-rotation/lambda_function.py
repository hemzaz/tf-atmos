"""AWS Secrets Manager rotation function for the microservices platform's JWT
signing secret.

Implements the same four-step protocol as the Redis AUTH rotation function in
this repo (createSecret -> setSecret -> testSecret -> finishSecret), but this
secret has no external system to update: nothing outside Secrets Manager
holds a copy of the signing key, so setSecret is a no-op and testSecret only
confirms the new value round-trips.

Grace period / dual-key note (there is no consuming JWT verifier in this
repo, so this is documentation for whoever builds one): finishSecret moves
AWSCURRENT to the new value shortly after createSecret runs, which means
tokens signed with the now-AWSPREVIOUS secret are still unexpired but no
longer verify against AWSCURRENT alone. Any verifier for this secret MUST
accept a token signed by either AWSCURRENT or AWSPREVIOUS for at least the
token's own max lifetime after each rotation (fetch both stages with
GetSecretValue and try each), or version tokens with a `kid` claim naming
which secret version signed them, before rotation_automatically is turned on
in production -- otherwise every token issued in the rotation_days window
before a rotation is rejected the moment it lands.
"""

import boto3
from botocore.exceptions import ClientError

# Excludes characters that break naive shell/env-var handling if a consumer
# ever exports this value directly, mirroring the exclusion the Redis AUTH
# rotation function and this repo's Terraform-side random_password generator
# both use.
_EXCLUDE_CHARACTERS = '/"@\'\\'
_PASSWORD_LENGTH = 64


def lambda_handler(event, context):
    arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]

    service_client = boto3.client("secretsmanager")
    metadata = service_client.describe_secret(SecretId=arn)

    if not metadata.get("RotationEnabled", False):
        raise ValueError(f"Secret {arn} is not enabled for rotation")

    versions = metadata["VersionIdsToStages"]
    if token not in versions:
        raise ValueError(f"Secret version {token} has no stage for rotation of secret {arn}.")
    if "AWSCURRENT" in versions[token]:
        # This version is already current; nothing to do for any step.
        return
    if "AWSPENDING" not in versions[token]:
        raise ValueError(f"Secret version {token} is not set as AWSPENDING for rotation of secret {arn}.")

    if step == "createSecret":
        create_secret(service_client, arn, token)
    elif step == "setSecret":
        # Nothing outside Secrets Manager holds this key -- see the module
        # docstring's grace-period note for what a real consumer must do
        # instead.
        pass
    elif step == "testSecret":
        test_secret(service_client, arn, token)
    elif step == "finishSecret":
        finish_secret(service_client, arn, token)
    else:
        raise ValueError(f"Invalid step parameter {step} for secret {arn}")


def create_secret(service_client, arn, token):
    """Generate a new signing key and stage it as AWSPENDING (idempotent: a
    retried createSecret invocation with the same ClientRequestToken must not
    generate a second, different value for the same version)."""
    try:
        service_client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")
        return
    except ClientError as e:
        if e.response["Error"]["Code"] != "ResourceNotFoundException":
            raise

    new_key = service_client.get_random_password(
        PasswordLength=_PASSWORD_LENGTH,
        ExcludeCharacters=_EXCLUDE_CHARACTERS,
        ExcludePunctuation=False,
        RequireEachIncludedType=True,
    )["RandomPassword"]

    service_client.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=new_key,
        VersionStages=["AWSPENDING"],
    )


def test_secret(service_client, arn, token):
    """No external system to test against: confirm the staged value round-
    trips and is non-empty."""
    pending_key = service_client.get_secret_value(
        SecretId=arn, VersionId=token, VersionStage="AWSPENDING"
    )["SecretString"]

    if not pending_key or len(pending_key) < _PASSWORD_LENGTH:
        raise ValueError(f"AWSPENDING value for secret {arn} is missing or shorter than expected")


def finish_secret(service_client, arn, token):
    metadata = service_client.describe_secret(SecretId=arn)
    current_version = None
    for version_id, stages in metadata["VersionIdsToStages"].items():
        if "AWSCURRENT" in stages:
            if version_id == token:
                # Already current -- nothing left to move.
                return
            current_version = version_id
            break

    service_client.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version,
    )

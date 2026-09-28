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
which secret version signed them, before any consumer relies on this secret
(rotation is live as soon as microservices/lambda/jwt-secret-rotation is
applied -- rotation_automatically is not the switch here; see that
instance's own rotation_secret_arn wiring in microservices-platform.yaml) --
otherwise every token issued in the rotation_days window before a rotation
is rejected the moment it lands.
"""

import boto3
from botocore.exceptions import ClientError

# Excludes characters that break naive shell/env-var handling if a consumer
# ever exports this value directly. This is its own exclusion set, not a
# mirror of anything else: the Redis AUTH rotation function excludes a
# different set (its target is ElastiCache's AUTH token, with its own
# character constraints), and this repo's Terraform-side random_password
# generator uses override_special, an ALLOWLIST of which characters count as
# "special", not an exclude list -- the two are not directly comparable.
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
    trips and is non-empty.

    Deliberately NOT checking `len(pending_key) == _PASSWORD_LENGTH` here:
    when Secrets Manager tests a rotation configuration without immediately
    rotating it (`rotate_immediately = false`, this function's default in
    microservices-platform.yaml), it runs ONLY this step, against a
    temporary AWSPENDING version it manufactures itself for the test rather
    than one createSecret produced -- AWS's docs say only that this version
    is "created and then removed", but AWS's own reference templates (e.g.
    the RDS ones, which log in with it) only pass that test if it is a copy
    of AWSCURRENT. For this secret, AWSCURRENT can be whatever length the
    Terraform-side generator that first created it used (32 chars by this
    repo's secretsmanager component default), not this function's own
    64-char createSecret output. A length check keyed to _PASSWORD_LENGTH
    would then reject that copy and fail every test-only invocation --
    i.e. every `terraform apply` that (re)configures this resource -- even
    though nothing is actually wrong."""
    pending_key = service_client.get_secret_value(
        SecretId=arn, VersionId=token, VersionStage="AWSPENDING"
    )["SecretString"]

    if not pending_key:
        raise ValueError(f"AWSPENDING value for secret {arn} is missing or empty")


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

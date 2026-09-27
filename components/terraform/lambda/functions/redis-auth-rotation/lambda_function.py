"""AWS Secrets Manager rotation function for an ElastiCache Redis replication
group's AUTH token.

Implements the standard four-step rotation protocol Secrets Manager drives
(createSecret -> setSecret -> testSecret -> finishSecret; see
https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotate-secrets_lambda-function-overview.html)
following the pattern of AWS's own reference templates
(aws-samples/aws-secrets-manager-rotation-lambdas), adapted so the "test"
step needs no third-party Redis client library -- it speaks just enough of
the RESP protocol over a TLS socket (stdlib ssl/socket only, so the package
has no dependencies to vendor).

Environment variables (set by the lambda component instance in
stacks/catalog/templates/microservices-platform.yaml):
  REPLICATION_GROUP_ID   -- the ElastiCache replication group to rotate
  REDIS_HOST             -- host to AUTH-test against (the configuration/
                            primary endpoint address)
  REDIS_PORT             -- port to AUTH-test against

Two-phase AUTH token cutover, split across two steps so a bad new token never
locks out every client at once:
  setSecret:    ModifyReplicationGroup(AuthTokenUpdateStrategy="ROTATE") --
                the new (AWSPENDING) token becomes valid ALONGSIDE the
                current one; existing connections using the old token keep
                working.
  finishSecret: only after testSecret has confirmed the new token actually
                authenticates, ModifyReplicationGroup(AuthTokenUpdateStrategy
                ="SET") -- the old token stops being accepted, and the
                secret's AWSCURRENT label moves to the new version.
"""

import os
import socket
import ssl
import time

import boto3
from botocore.exceptions import ClientError

# ElastiCache AUTH tokens may contain ONLY the following punctuation:
# ! & # $ ^ < > - (ModifyReplicationGroup rejects anything else with
# InvalidParameterValue). GetRandomPassword's default punctuation set (used
# whenever ExcludePunctuation is False) is !"#$%&'()*+,-./:;<=>?@[\]^_`{|}~ --
# this excludes every character in that set EXCEPT the eight above, so
# RequireEachIncludedType's "one symbol" requirement below is always
# satisfiable with an allowed one. The Terraform-side random_password
# generator for this secret must use the same allowed set (see this
# component's random_password_override_special on the redis entry in
# stacks/catalog/templates/microservices-platform.yaml) for its initial
# value to be valid too.
_EXCLUDE_CHARACTERS = "\"%'()*+,./:;=?@[\\]_`{|}~"
_PASSWORD_LENGTH = 32

# How long to wait for ModifyReplicationGroup's async change to land before
# giving up. ElastiCache's own operation typically finishes in well under a
# minute for an AUTH token change, but a cluster-mode group rolls the token
# across every node, so this gives it generous headroom without risking the
# Lambda's own timeout (the microservices-platform instance sets
# timeout = 900s, and each of setSecret/finishSecret waits at most once
# before AND once after its own modify_replication_group call).
_MODIFY_POLL_INTERVAL_SECONDS = 10
_MODIFY_POLL_MAX_ATTEMPTS = 40


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
        set_secret(service_client, arn, token)
    elif step == "testSecret":
        test_secret(service_client, arn, token)
    elif step == "finishSecret":
        finish_secret(service_client, arn, token)
    else:
        raise ValueError(f"Invalid step parameter {step} for secret {arn}")


def create_secret(service_client, arn, token):
    """Generate a new AUTH token and stage it as AWSPENDING (idempotent: a
    retried createSecret invocation with the same ClientRequestToken must not
    generate a second, different value for the same version)."""
    try:
        service_client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")
        return
    except ClientError as e:
        if e.response["Error"]["Code"] != "ResourceNotFoundException":
            raise

    new_token = service_client.get_random_password(
        PasswordLength=_PASSWORD_LENGTH,
        ExcludeCharacters=_EXCLUDE_CHARACTERS,
        ExcludePunctuation=False,
        RequireEachIncludedType=True,
    )["RandomPassword"]

    service_client.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=new_token,
        VersionStages=["AWSPENDING"],
    )


def set_secret(service_client, arn, token):
    """Make the AWSPENDING token valid on the replication group alongside
    the current one (AuthTokenUpdateStrategy=ROTATE), then wait for the
    change to finish applying before returning control to Secrets Manager."""
    pending_token = service_client.get_secret_value(
        SecretId=arn, VersionId=token, VersionStage="AWSPENDING"
    )["SecretString"]

    replication_group_id = _require_env("REPLICATION_GROUP_ID")
    elasticache_client = boto3.client("elasticache")

    # Wait BEFORE modifying too: a retried Secrets Manager invocation (after
    # an earlier attempt's own wait timed out while the group was still
    # applying a previous change) must not immediately fail with
    # InvalidReplicationGroupState -- wait for it to settle first.
    _wait_for_replication_group_available(elasticache_client, replication_group_id)
    _modify_auth_token(elasticache_client, replication_group_id, pending_token, "ROTATE")
    _wait_for_replication_group_available(elasticache_client, replication_group_id)


def test_secret(service_client, arn, token):
    """Confirm the AWSPENDING token actually authenticates against the
    replication group before finishSecret cuts the old one off."""
    pending_token = service_client.get_secret_value(
        SecretId=arn, VersionId=token, VersionStage="AWSPENDING"
    )["SecretString"]

    host = _require_env("REDIS_HOST")
    port = int(_require_env("REDIS_PORT"))

    if not _redis_auth_succeeds(host, port, pending_token):
        raise ValueError(f"AWSPENDING auth token for secret {arn} did not authenticate against {host}:{port}")


def finish_secret(service_client, arn, token):
    """Cut the old token off (AuthTokenUpdateStrategy=SET) now that the new
    one is confirmed working, then move AWSCURRENT to this version."""
    pending_token = service_client.get_secret_value(
        SecretId=arn, VersionId=token, VersionStage="AWSPENDING"
    )["SecretString"]

    replication_group_id = _require_env("REPLICATION_GROUP_ID")
    elasticache_client = boto3.client("elasticache")

    _wait_for_replication_group_available(elasticache_client, replication_group_id)
    _modify_auth_token(elasticache_client, replication_group_id, pending_token, "SET")
    _wait_for_replication_group_available(elasticache_client, replication_group_id)

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


def _modify_auth_token(elasticache_client, replication_group_id, auth_token, strategy):
    """modify_replication_group, retried once if the group is caught mid-way
    through an earlier change (InvalidReplicationGroupState) -- the case a
    retried Secrets Manager invocation hits after a prior attempt's own call
    succeeded but its post-modify wait then timed out or the Lambda itself
    was killed. Waits for the group to settle and tries exactly once more
    before giving up, rather than raising straight back to Secrets Manager
    (which would otherwise require a THIRD invocation just to make progress)."""
    for attempt in range(2):
        try:
            elasticache_client.modify_replication_group(
                ReplicationGroupId=replication_group_id,
                AuthToken=auth_token,
                AuthTokenUpdateStrategy=strategy,
                ApplyImmediately=True,
            )
            return
        except ClientError as e:
            if e.response["Error"]["Code"] != "InvalidReplicationGroupState" or attempt == 1:
                raise
            _wait_for_replication_group_available(elasticache_client, replication_group_id)


def _wait_for_replication_group_available(elasticache_client, replication_group_id):
    for _ in range(_MODIFY_POLL_MAX_ATTEMPTS):
        response = elasticache_client.describe_replication_groups(ReplicationGroupId=replication_group_id)
        status = response["ReplicationGroups"][0]["Status"]
        if status == "available":
            return
        time.sleep(_MODIFY_POLL_INTERVAL_SECONDS)

    raise TimeoutError(
        f"Replication group {replication_group_id} did not return to 'available' "
        f"within {_MODIFY_POLL_MAX_ATTEMPTS * _MODIFY_POLL_INTERVAL_SECONDS}s of the auth token change"
    )


def _redis_auth_succeeds(host, port, auth_token):
    """Open a TLS connection (transit_encryption_enabled=true on this
    replication group) and issue a RESP AUTH command by hand, since pulling
    in redis-py would mean vendoring or layering a dependency for one
    command. Returns True only on a RESP simple-string "+OK" reply."""
    context = ssl.create_default_context()
    try:
        with socket.create_connection((host, port), timeout=10) as raw_sock:
            with context.wrap_socket(raw_sock, server_hostname=host) as tls_sock:
                command = _encode_resp_command(["AUTH", auth_token])
                tls_sock.sendall(command)
                reply = tls_sock.recv(4096)
    except (OSError, ssl.SSLError):
        return False

    return reply.startswith(b"+OK")


def _encode_resp_command(parts):
    encoded = [f"*{len(parts)}\r\n".encode()]
    for part in parts:
        raw = part.encode()
        encoded.append(f"${len(raw)}\r\n".encode() + raw + b"\r\n")
    return b"".join(encoded)


def _require_env(name):
    value = os.environ.get(name)
    if not value:
        raise ValueError(f"Required environment variable {name} is not set")
    return value

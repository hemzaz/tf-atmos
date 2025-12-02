"""
AWS Secrets Manager RDS MySQL/PostgreSQL Rotation Lambda
Implements single-user rotation strategy for RDS database credentials
"""
import json
import boto3
import logging
import os
import pymysql
import psycopg2

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Secrets Manager Rotation Handler

    Args:
        event: Lambda event containing SecretId, ClientRequestToken, and Step
        context: Lambda context object
    """
    arn = event['SecretId']
    token = event['ClientRequestToken']
    step = event['Step']

    # Setup the client
    service_client = boto3.client('secretsmanager', endpoint_url=os.environ.get('SECRETS_MANAGER_ENDPOINT'))

    # Make sure the version is staged correctly
    metadata = service_client.describe_secret(SecretId=arn)
    if not metadata['RotationEnabled']:
        logger.error(f"Secret {arn} is not enabled for rotation")
        raise ValueError(f"Secret {arn} is not enabled for rotation")

    versions = metadata['VersionIdsToStages']
    if token not in versions:
        logger.error(f"Secret version {token} has no stage for rotation of secret {arn}")
        raise ValueError(f"Secret version {token} has no stage for rotation of secret {arn}")

    if "AWSCURRENT" in versions[token]:
        logger.info(f"Secret version {token} already set as AWSCURRENT for secret {arn}")
        return
    elif "AWSPENDING" not in versions[token]:
        logger.error(f"Secret version {token} not set as AWSPENDING for rotation of secret {arn}")
        raise ValueError(f"Secret version {token} not set as AWSPENDING for rotation of secret {arn}")

    # Call the appropriate step
    if step == "createSecret":
        create_secret(service_client, arn, token)
    elif step == "setSecret":
        set_secret(service_client, arn, token)
    elif step == "testSecret":
        test_secret(service_client, arn, token)
    elif step == "finishSecret":
        finish_secret(service_client, arn, token)
    else:
        raise ValueError(f"Invalid step parameter: {step}")


def create_secret(service_client, arn, token):
    """
    Create a new secret version with a new password
    """
    # Get the current secret
    current_dict = get_secret_dict(service_client, arn, "AWSCURRENT")

    # Generate a new password
    passwd = service_client.get_random_password(
        PasswordLength=32,
        ExcludeCharacters='/@"\'\\'
    )
    current_dict['password'] = passwd['RandomPassword']

    # Put the new secret
    service_client.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=json.dumps(current_dict),
        VersionStages=['AWSPENDING']
    )

    logger.info(f"createSecret: Successfully put secret for ARN {arn} and version {token}")


def set_secret(service_client, arn, token):
    """
    Set the password in the database to the new password
    """
    # Get both current and pending secrets
    pending_dict = get_secret_dict(service_client, arn, "AWSPENDING", token)
    current_dict = get_secret_dict(service_client, arn, "AWSCURRENT")

    # Get connection parameters
    engine = pending_dict.get('engine', 'mysql')
    host = pending_dict.get('host')
    port = pending_dict.get('port', 3306 if engine == 'mysql' else 5432)
    username = pending_dict.get('username')
    new_password = pending_dict['password']
    current_password = current_dict['password']

    # Connect using current credentials and change password
    if engine == 'mysql':
        set_mysql_password(host, port, username, current_password, new_password)
    elif engine == 'postgres':
        set_postgres_password(host, port, username, current_password, new_password)
    else:
        raise ValueError(f"Unsupported engine: {engine}")

    logger.info(f"setSecret: Successfully set password in database for ARN {arn} and version {token}")


def test_secret(service_client, arn, token):
    """
    Test the new secret to ensure it works
    """
    # Get the pending secret
    pending_dict = get_secret_dict(service_client, arn, "AWSPENDING", token)

    # Get connection parameters
    engine = pending_dict.get('engine', 'mysql')
    host = pending_dict.get('host')
    port = pending_dict.get('port', 3306 if engine == 'mysql' else 5432)
    username = pending_dict.get('username')
    password = pending_dict['password']
    dbname = pending_dict.get('dbname')

    # Test the connection
    if engine == 'mysql':
        test_mysql_connection(host, port, username, password, dbname)
    elif engine == 'postgres':
        test_postgres_connection(host, port, username, password, dbname)
    else:
        raise ValueError(f"Unsupported engine: {engine}")

    logger.info(f"testSecret: Successfully tested new credentials for ARN {arn} and version {token}")


def finish_secret(service_client, arn, token):
    """
    Finish the rotation by marking the pending secret as current
    """
    # Get metadata for the secret
    metadata = service_client.describe_secret(SecretId=arn)
    current_version = None
    for version in metadata["VersionIdsToStages"]:
        if "AWSCURRENT" in metadata["VersionIdsToStages"][version]:
            if version == token:
                logger.info(f"finishSecret: Version {version} already marked as AWSCURRENT for {arn}")
                return
            current_version = version
            break

    # Finalize the rotation
    service_client.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version
    )

    logger.info(f"finishSecret: Successfully set AWSCURRENT stage to version {token} for secret {arn}")


def get_secret_dict(service_client, arn, stage, token=None):
    """
    Get secret dictionary from Secrets Manager
    """
    required_fields = ['host', 'username', 'password']

    # Get the secret value
    if token:
        secret = service_client.get_secret_value(SecretId=arn, VersionId=token, VersionStage=stage)
    else:
        secret = service_client.get_secret_value(SecretId=arn, VersionStage=stage)

    plaintext = secret['SecretString']
    secret_dict = json.loads(plaintext)

    # Validate required fields
    for field in required_fields:
        if field not in secret_dict:
            raise KeyError(f"{field} key is missing from secret JSON")

    return secret_dict


def set_mysql_password(host, port, username, current_password, new_password):
    """
    Set new password for MySQL user
    """
    conn = pymysql.connect(
        host=host,
        port=int(port),
        user=username,
        password=current_password,
        connect_timeout=5
    )
    try:
        with conn.cursor() as cursor:
            # Change the password
            cursor.execute(f"ALTER USER '{username}'@'%' IDENTIFIED BY '{new_password}'")
            cursor.execute("FLUSH PRIVILEGES")
        conn.commit()
    finally:
        conn.close()


def set_postgres_password(host, port, username, current_password, new_password):
    """
    Set new password for PostgreSQL user
    """
    conn = psycopg2.connect(
        host=host,
        port=int(port),
        user=username,
        password=current_password,
        connect_timeout=5
    )
    conn.set_session(autocommit=True)
    try:
        with conn.cursor() as cursor:
            # Change the password
            cursor.execute(f"ALTER USER {username} WITH PASSWORD %s", (new_password,))
    finally:
        conn.close()


def test_mysql_connection(host, port, username, password, dbname):
    """
    Test MySQL connection with new credentials
    """
    conn = pymysql.connect(
        host=host,
        port=int(port),
        user=username,
        password=password,
        database=dbname,
        connect_timeout=5
    )
    conn.close()


def test_postgres_connection(host, port, username, password, dbname):
    """
    Test PostgreSQL connection with new credentials
    """
    conn = psycopg2.connect(
        host=host,
        port=int(port),
        user=username,
        password=password,
        dbname=dbname,
        connect_timeout=5
    )
    conn.close()

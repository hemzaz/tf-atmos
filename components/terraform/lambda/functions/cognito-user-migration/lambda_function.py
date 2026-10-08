"""Cognito user-migration trigger: moves a user from the source pool into this one.

fnx-ue2-prod's DR user pool (us-east-2) runs this on a sign-in or forgot-password
for a user it does not have yet. It checks the user against the source pool,
fnx-ue1-prod's (us-east-1), and returns the user's attributes, so Cognito creates
the user here (https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-lambda-migrate-user.html):

  UserMigration_Authentication  AdminInitiateAuth (ADMIN_USER_PASSWORD_AUTH) on the
                                source pool verifies the password, AdminGetUser reads
                                the attributes; the user is created RESET_REQUIRED,
                                never CONFIRMED, and needs a verified email or phone.
  UserMigration_ForgotPassword  AdminGetUser only (Cognito sends no password); the
                                user needs a verified email or phone for the code.

Why RESET_REQUIRED: this pool's only MFA type is software token and TOTP secrets
do not migrate, so a CONFIRMED user's first sign-in gets MFA_SETUP, and anyone
holding only the password (an MFA challenge in the source pool already counts as
proof of it) could enrol their own authenticator: an MFA bypass and account
takeover. RESET_REQUIRED makes the first sign-in fail with
PasswordResetRequiredException; the user finishes forgot-password with a code sent
to the verified contact, and only then reaches MFA_SETUP.

It only works while the source pool answers: a user never migrated before a
us-east-1 outage cannot sign in here during it (docs/OPERATIONS.md, "Disaster
recovery"). Any failure raises, which Cognito turns into a failed sign-in.

Environment: SOURCE_USER_POOL_ID (its region is the id's prefix) and
SOURCE_CLIENT_ID, an app client of the source pool that allows
ALLOW_ADMIN_USER_PASSWORD_AUTH and has no secret.
"""
import logging
import os

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

# A sign-in with these challenges got past the password check (MFA comes after
# it). Proof of the password only, never of the second factor: see "Why
# RESET_REQUIRED" above.
PASSWORD_ACCEPTED_CHALLENGES = frozenset(
    {"SOFTWARE_TOKEN_MFA", "SMS_MFA", "EMAIL_OTP", "MFA_SETUP", "SELECT_MFA_TYPE"}
)
# Cognito assigns sub; identities is set by federation only. Neither can be written.
NOT_COPIED = frozenset({"sub", "identities"})
# Statuses each flow migrates. FORCE_CHANGE_PASSWORD (an invite never accepted) and
# UNCONFIRMED users finish in the source pool first.
SIGN_IN_STATUSES = frozenset({"CONFIRMED"})
FORGOT_PASSWORD_STATUSES = frozenset({"CONFIRMED", "RESET_REQUIRED"})

_client = None


# The only text Cognito (and so the caller) sees on any reject: the same for an unknown
# user, a wrong password, a bad status or no verified contact, so it does not tell which
# usernames exist in the source pool. The reason goes to the log only.
REJECTED = "not migrated"


class MigrationError(Exception):
    """The user is not migrated; Cognito fails the sign-in.

    sub is the source user's opaque ID once the user was found, for the audit log.
    """

    def __init__(self, reason: str, sub: str = None):
        super().__init__(reason)
        self.sub = sub


def source_client():
    """cognito-idp in the source pool's region, built once per container.

    Cognito waits about 5 seconds for a trigger, so a slow source pool fails
    fast here (one attempt, 2-second timeouts) instead of timing the trigger out.
    """
    global _client
    if _client is None:
        import boto3
        from botocore.config import Config

        region = os.environ["SOURCE_USER_POOL_ID"].split("_", 1)[0]
        _client = boto3.client(
            "cognito-idp",
            region_name=region,
            config=Config(connect_timeout=2, read_timeout=2, retries={"max_attempts": 1, "mode": "standard"}),
        )
    return _client


def error_code(error: Exception) -> str:
    return (getattr(error, "response", None) or {}).get("Error", {}).get("Code", type(error).__name__)


def verify_password(client, username: str, password: str) -> None:
    try:
        result = client.admin_initiate_auth(
            UserPoolId=os.environ["SOURCE_USER_POOL_ID"],
            ClientId=os.environ["SOURCE_CLIENT_ID"],
            AuthFlow="ADMIN_USER_PASSWORD_AUTH",
            AuthParameters={"USERNAME": username, "PASSWORD": password},
        )
    except Exception as error:  # botocore ClientError and connection errors alike
        raise MigrationError(f"source sign-in failed: {error_code(error)}") from None
    if "AuthenticationResult" in result or result.get("ChallengeName") in PASSWORD_ACCEPTED_CHALLENGES:
        return
    raise MigrationError(f"source sign-in needs {result.get('ChallengeName')}")


def source_user(client, username: str, statuses: frozenset) -> dict:
    """The user's attributes in the source pool (sub included), if it may migrate."""
    try:
        user = client.admin_get_user(UserPoolId=os.environ["SOURCE_USER_POOL_ID"], Username=username)
    except Exception as error:
        raise MigrationError(f"source lookup failed: {error_code(error)}") from None
    attributes = {a["Name"]: a["Value"] for a in user.get("UserAttributes", [])}
    if not user.get("Enabled", False) or user.get("UserStatus") not in statuses:
        raise MigrationError(
            f"source user is {user.get('UserStatus')}, enabled {user.get('Enabled')}", attributes.get("sub")
        )
    return attributes


def require_verified_contact(attributes: dict) -> None:
    """The reset code goes to a verified email or phone; without one the user cannot finish."""
    if "true" not in (attributes.get("email_verified"), attributes.get("phone_number_verified")):
        raise MigrationError("source user has no verified email or phone for the reset code", attributes.get("sub"))


def lambda_handler(event, context):
    trigger = event.get("triggerSource")
    username = event["userName"]
    client = source_client()
    try:
        if trigger == "UserMigration_Authentication":
            verify_password(client, username, event["request"]["password"])
            source = source_user(client, username, SIGN_IN_STATUSES)
            require_verified_contact(source)
            final_status = "RESET_REQUIRED"
        elif trigger == "UserMigration_ForgotPassword":
            source = source_user(client, username, FORGOT_PASSWORD_STATUSES)
            require_verified_contact(source)
            final_status = None
        else:
            raise MigrationError(f"unsupported trigger {trigger}")
    except MigrationError as error:
        # Audit: trigger, outcome, reason and (when the user was found) the opaque sub. No
        # username, email or password, so the log never says whose password was tried.
        LOGGER.warning("%s: not migrated: %s (sub %s)", trigger, error, error.sub)
        raise MigrationError(REJECTED) from None
    attributes = {name: value for name, value in source.items() if name not in NOT_COPIED}
    event["response"].update(userAttributes=attributes, messageAction="SUPPRESS")
    if final_status:
        event["response"]["finalUserStatus"] = final_status
    LOGGER.info("%s: migrated sub %s as %s", trigger, source.get("sub"), final_status or "forgot-password")
    return event

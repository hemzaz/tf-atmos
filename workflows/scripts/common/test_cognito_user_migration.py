"""Tests for the cognito-user-migration Lambda handler (stdlib only, no boto3, no AWS).

python3 -m unittest discover -s workflows/scripts/common (lint check-dependencies, validate-all).
The handler lives in components/terraform/lambda/functions/cognito-user-migration; it is
tested here so its package (source_dir) carries no test code.
"""
import importlib.util
import os
import pathlib
import unittest
from unittest import mock

_path = (pathlib.Path(__file__).resolve().parents[3] / "components" / "terraform" / "lambda" / "functions"
         / "cognito-user-migration" / "lambda_function.py")
_spec = importlib.util.spec_from_file_location("cognito_user_migration", _path)
handler = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(handler)

ENV = {"SOURCE_USER_POOL_ID": "us-east-1_Source", "SOURCE_CLIENT_ID": "client123"}
ATTRIBUTES = [
    {"Name": "sub", "Value": "0000-1111"},
    {"Name": "email", "Value": "user@example.com"},
    {"Name": "email_verified", "Value": "true"},
    {"Name": "custom:tenant_id", "Value": "t1"},
]


class ClientError(Exception):
    """botocore.exceptions.ClientError's shape: the code is in .response."""

    def __init__(self, code):
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


class FakeCognito:
    def __init__(self, auth=None, auth_error=None, user=None, user_error=None):
        self.auth, self.auth_error = auth, auth_error
        self.user, self.user_error = user, user_error
        self.calls = []

    def admin_initiate_auth(self, **kwargs):
        self.calls.append(("admin_initiate_auth", kwargs))
        if self.auth_error:
            raise self.auth_error
        return self.auth

    def admin_get_user(self, **kwargs):
        self.calls.append(("admin_get_user", kwargs))
        if self.user_error:
            raise self.user_error
        return self.user


def confirmed_user(**overrides):
    return dict({"Enabled": True, "UserStatus": "CONFIRMED", "UserAttributes": ATTRIBUTES}, **overrides)


def event(trigger, password="Correct-Horse-1"):
    request = {"password": password} if trigger == "UserMigration_Authentication" else {}
    return {"triggerSource": trigger, "userName": "user@example.com", "request": request, "response": {}}


@mock.patch.dict(os.environ, ENV)
class CognitoUserMigrationTest(unittest.TestCase):
    def run_handler(self, client, evt):
        with mock.patch.object(handler, "source_client", return_value=client):
            return handler.lambda_handler(evt, None)

    def test_sign_in_migrates_a_confirmed_user(self):
        client = FakeCognito(auth={"AuthenticationResult": {"AccessToken": "x"}}, user=confirmed_user())
        response = self.run_handler(client, event("UserMigration_Authentication"))["response"]
        self.assertEqual(response["userAttributes"],
                         {"email": "user@example.com", "email_verified": "true", "custom:tenant_id": "t1"})
        self.assertEqual(response["finalUserStatus"], "CONFIRMED")
        self.assertEqual(response["messageAction"], "SUPPRESS")
        name, auth = client.calls[0]
        self.assertEqual(name, "admin_initiate_auth")
        self.assertEqual(auth, {"UserPoolId": "us-east-1_Source", "ClientId": "client123",
                                "AuthFlow": "ADMIN_USER_PASSWORD_AUTH",
                                "AuthParameters": {"USERNAME": "user@example.com", "PASSWORD": "Correct-Horse-1"}})

    def test_an_mfa_challenge_means_the_password_was_right(self):
        client = FakeCognito(auth={"ChallengeName": "SOFTWARE_TOKEN_MFA", "Session": "s"}, user=confirmed_user())
        response = self.run_handler(client, event("UserMigration_Authentication"))["response"]
        self.assertEqual(response["finalUserStatus"], "CONFIRMED")

    def test_a_wrong_password_is_not_migrated(self):
        client = FakeCognito(auth_error=ClientError("NotAuthorizedException"))
        with self.assertRaisesRegex(handler.MigrationError, "NotAuthorizedException"):
            self.run_handler(client, event("UserMigration_Authentication", password="wrong"))
        self.assertEqual([c[0] for c in client.calls], ["admin_initiate_auth"])

    def test_an_unreachable_source_pool_fails_the_sign_in(self):
        client = FakeCognito(auth_error=TimeoutError("connect timeout"))
        with self.assertRaisesRegex(handler.MigrationError, "TimeoutError"):
            self.run_handler(client, event("UserMigration_Authentication"))

    def test_a_new_password_challenge_is_not_migrated(self):
        client = FakeCognito(auth={"ChallengeName": "NEW_PASSWORD_REQUIRED"}, user=confirmed_user())
        with self.assertRaisesRegex(handler.MigrationError, "NEW_PASSWORD_REQUIRED"):
            self.run_handler(client, event("UserMigration_Authentication"))

    def test_a_disabled_user_is_not_migrated(self):
        client = FakeCognito(auth={"AuthenticationResult": {}}, user=confirmed_user(Enabled=False))
        with self.assertRaises(handler.MigrationError):
            self.run_handler(client, event("UserMigration_Authentication"))

    def test_forgot_password_migrates_without_a_password(self):
        client = FakeCognito(user=confirmed_user(UserStatus="RESET_REQUIRED"))
        response = self.run_handler(client, event("UserMigration_ForgotPassword"))["response"]
        self.assertEqual(response["userAttributes"]["email_verified"], "true")
        self.assertEqual(response["messageAction"], "SUPPRESS")
        self.assertNotIn("finalUserStatus", response)
        self.assertEqual([c[0] for c in client.calls], ["admin_get_user"])

    def test_forgot_password_needs_a_verified_contact(self):
        unverified = [a for a in ATTRIBUTES if a["Name"] != "email_verified"]
        client = FakeCognito(user=confirmed_user(UserAttributes=unverified))
        with self.assertRaisesRegex(handler.MigrationError, "verified"):
            self.run_handler(client, event("UserMigration_ForgotPassword"))

    def test_an_unknown_user_is_not_migrated(self):
        client = FakeCognito(user_error=ClientError("UserNotFoundException"))
        with self.assertRaisesRegex(handler.MigrationError, "UserNotFoundException"):
            self.run_handler(client, event("UserMigration_ForgotPassword"))

    def test_another_trigger_is_refused(self):
        with self.assertRaisesRegex(handler.MigrationError, "unsupported trigger"):
            self.run_handler(FakeCognito(), event("PreSignUp_SignUp"))

    def test_the_password_is_never_logged(self):
        canary = "log-canary-value"
        client = FakeCognito(auth_error=ClientError("NotAuthorizedException"))
        with mock.patch.object(handler, "source_client", return_value=client), \
                self.assertLogs(handler.LOGGER, level="WARNING") as logs, \
                self.assertRaises(handler.MigrationError):
            handler.lambda_handler(event("UserMigration_Authentication", password=canary), None)
        self.assertFalse(any(canary in line or "user@example.com" in line for line in logs.output))

    def test_the_client_targets_the_source_pools_region(self):
        fake_boto3 = mock.MagicMock()
        fake_config = mock.MagicMock()
        with mock.patch.object(handler, "_client", None), \
                mock.patch.dict("sys.modules", {"boto3": fake_boto3, "botocore": mock.MagicMock(),
                                                "botocore.config": mock.MagicMock(Config=fake_config)}):
            handler.source_client()
        self.assertEqual(fake_boto3.client.call_args.kwargs["region_name"], "us-east-1")
        self.assertEqual(fake_config.call_args.kwargs["retries"]["max_attempts"], 1)


if __name__ == "__main__":
    unittest.main()

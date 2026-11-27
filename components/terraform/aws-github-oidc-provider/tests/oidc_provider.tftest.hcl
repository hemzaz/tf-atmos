# House test of the catalog's instance (stacks/catalog/aws-github-oidc-provider, E6a3; a vendored
# target admits tests/*.tftest.hcl: scripts/check-vendor.py TESTS): the account's one GitHub Actions
# OIDC provider, whose ARN catalog/aws-iam-role/ci derives (arn:aws:iam::<account>:oidc-provider/
# token.actions.githubusercontent.com) for the CI roles' trust, is created exactly once with the URL
# and audience those roles' conditions check; enabled = false (the scaffold's account_singletons=no
# branch) creates none; and the account-verification mixin refuses a run in another account.
# Mocked providers, no AWS.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "777777777777" }
  }
}

# The catalog's values (aws-github-oidc-provider/defaults, vendored, account-map-bypass) in fnx-ue1-dev.
variables {
  region      = "us-east-1"
  enabled     = true
  tenant      = "fnx"
  environment = "ue1"
  stage       = "dev"
  name        = "github-oidc-provider"

  account_map_enabled = false
  account_map = {
    full_account_map = {
      "fnx-dev"  = "777777777777"
      "fnx-prod" = "999999999999"
    }
  }
}

run "creates_the_account_provider_once" {
  command = plan

  assert {
    condition     = keys(aws_iam_openid_connect_provider.oidc) == ["github"]
    error_message = "The catalog's instance must plan exactly one OIDC provider."
  }

  # The derived ARN in catalog/aws-iam-role/ci ends in this URL's host; the CI roles' trust checks
  # token.actions.githubusercontent.com:aud == sts.amazonaws.com.
  assert {
    condition     = aws_iam_openid_connect_provider.oidc["github"].url == "https://token.actions.githubusercontent.com"
    error_message = "The provider must be GitHub Actions' token.actions.githubusercontent.com: the CI roles trust oidc-provider/token.actions.githubusercontent.com."
  }

  assert {
    condition     = aws_iam_openid_connect_provider.oidc["github"].client_id_list == toset(["sts.amazonaws.com"])
    error_message = "The provider's audience must be sts.amazonaws.com, the aud the CI roles' trust requires."
  }

  assert {
    condition     = length(terraform_data.account_verification) == 1
    error_message = "With account_map set, the account-verification mixin must check the run's account."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.oidc) == 0
    error_message = "enabled = false (null-label) must create no OIDC provider."
  }
}

run "another_account_is_refused" {
  command = plan

  variables {
    stage = "prod"
  }

  expect_failures = [terraform_data.account_verification]
}

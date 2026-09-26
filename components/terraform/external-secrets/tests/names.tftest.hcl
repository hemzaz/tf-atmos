# Mock-provider tests of the IAM names: no AWS or cluster access. Run from the
# component directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  override_data {
    target = data.aws_region.current
    values = {
      region = "eu-west-2"
    }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }
}
mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  region                              = "eu-west-2"
  host                                = "https://ABCDEF0123456789.gr7.eu-west-2.eks.amazonaws.com"
  cluster_ca_certificate              = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
  oidc_provider_arn                   = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF"
  oidc_provider_url                   = "https://oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF"
  create_default_cluster_secret_store = false
  create_certificate_secret_store     = false
  kms_key_arn                         = "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
}

run "prod_role_does_not_repeat_the_environment" {
  command = plan

  variables {
    cluster_name = "production-main"
    tags = {
      Environment = "production"
    }
  }

  assert {
    condition     = aws_iam_role.external_secrets[0].name == "production-main-external-secrets-role"
    error_message = "The role must be <cluster>-external-secrets-role, the Environment once."
  }

  assert {
    condition     = aws_iam_policy.external_secrets[0].name == "production-main-external-secrets-policy"
    error_message = "The policy must be <cluster>-external-secrets-policy."
  }

  assert {
    condition     = length(aws_iam_role.external_secrets[0].name) <= 64
    error_message = "The role name must fit IAM's 64 characters."
  }

  # The trust policy's condition key is the issuer without https://.
  assert {
    condition     = strcontains(aws_iam_role.external_secrets[0].assume_role_policy, "\"oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF:sub\"")
    error_message = "The trust policy must key on the issuer host, without https://."
  }
}

run "dev_and_staging_roles" {
  command = plan

  variables {
    cluster_name = "staging-01-data"
    tags = {
      Environment = "staging-01"
    }
  }

  assert {
    condition     = aws_iam_role.external_secrets[0].name == "staging-01-data-external-secrets-role"
    error_message = "The role must be <cluster>-external-secrets-role."
  }
}

run "cluster_name_without_the_environment_gets_it_once" {
  command = plan

  variables {
    cluster_name = "main"
    tags = {
      Environment = "testenv-01"
    }
  }

  assert {
    condition     = aws_iam_role.external_secrets[0].name == "testenv-01-main-external-secrets-role"
    error_message = "A bare cluster name is prefixed with the Environment."
  }
}

run "arn_is_rejected" {
  command = plan

  variables {
    cluster_name = "arn:aws:eks:eu-west-2:123456789012:cluster/production-main"
    tags = {
      Environment = "production"
    }
  }

  expect_failures = [var.cluster_name]
}

# Fits the role limit ("dev-" 4 + 24 + 22 = 50), so only the ARN check can fail.
run "short_arn_is_rejected_on_its_own" {
  command = plan

  variables {
    cluster_name = "arn:aws:eks::1:cluster/a"
    tags = {
      Environment = "dev"
    }
  }

  expect_failures = [var.cluster_name]
}

# A plain name whose role would be 65 characters.
run "name_over_the_role_limit_is_rejected" {
  command = plan

  variables {
    cluster_name = "production-abcdefghij-abcdefghij-abcdefghij"
    tags = {
      Environment = "production"
    }
  }

  expect_failures = [var.cluster_name]
}

# The longest plain name that fits: 42 + 22 = 64.
run "name_at_the_role_limit_is_accepted" {
  command = plan

  variables {
    cluster_name = "production-abcdefghij-abcdefghij-abcdefghi"
    tags = {
      Environment = "production"
    }
  }

  assert {
    condition     = length(aws_iam_role.external_secrets[0].name) == 64
    error_message = "A 64-character role name is within IAM's limit."
  }
}

run "null_cluster_name_is_rejected" {
  command = plan

  variables {
    cluster_name = null
    tags = {
      Environment = "production"
    }
  }

  expect_failures = [var.cluster_name]
}

# The prefix match is case-insensitive, as the eks name validation is.
run "environment_in_another_case_is_not_prefixed_again" {
  command = plan

  variables {
    cluster_name = "Production-main"
    tags = {
      Environment = "production"
    }
  }

  assert {
    condition     = aws_iam_role.external_secrets[0].name == "Production-main-external-secrets-role"
    error_message = "A cluster name starting with the Environment in another case is not prefixed again."
  }
}

# The rendered IAM policy must be scoped to this account/region (no "*:*" in
# any ARN) and must decrypt only through var.kms_key_arn, gated by
# kms:ViaService.
run "policy_is_scoped_to_account_region_and_kms_key" {
  command = plan

  variables {
    cluster_name = "production-main"
    tags = {
      Environment = "production"
    }
  }

  assert {
    condition     = !strcontains(aws_iam_policy.external_secrets[0].policy, ":*:*:")
    error_message = "The policy must not use \"*:*\" (any account, any region) anywhere in a resource ARN."
  }

  assert {
    condition     = strcontains(aws_iam_policy.external_secrets[0].policy, "arn:aws:secretsmanager:eu-west-2:123456789012:secret:")
    error_message = "Secrets Manager resources must be scoped to this region and account."
  }

  assert {
    condition     = strcontains(aws_iam_policy.external_secrets[0].policy, "arn:aws:ssm:eu-west-2:123456789012:parameter/")
    error_message = "SSM parameter resources must be scoped to this region and account."
  }

  assert {
    condition     = strcontains(aws_iam_policy.external_secrets[0].policy, var.kms_key_arn)
    error_message = "The policy must grant kms:Decrypt on var.kms_key_arn, not a wildcard key ARN."
  }

  assert {
    condition     = !strcontains(aws_iam_policy.external_secrets[0].policy, "arn:aws:kms:*:*:key/*")
    error_message = "The policy must not grant kms:Decrypt on a wildcard key ARN."
  }

  assert {
    condition     = strcontains(aws_iam_policy.external_secrets[0].policy, "\"kms:ViaService\"")
    error_message = "kms:Decrypt must be gated by a kms:ViaService condition."
  }

  assert {
    condition     = strcontains(aws_iam_policy.external_secrets[0].policy, "secretsmanager.eu-west-2.amazonaws.com") && strcontains(aws_iam_policy.external_secrets[0].policy, "ssm.eu-west-2.amazonaws.com")
    error_message = "kms:ViaService must name both secretsmanager.<region>.amazonaws.com and ssm.<region>.amazonaws.com."
  }
}

# #195 follow-up: the trust policy must also condition on :aud, as eks-addons'
# IRSA roles do (components/terraform/eks-addons).
run "trust_policy_requires_aud_sts_amazonaws_com" {
  command = plan

  variables {
    cluster_name = "production-main"
    tags = {
      Environment = "production"
    }
  }

  assert {
    condition     = strcontains(aws_iam_role.external_secrets[0].assume_role_policy, "\"oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF:aud\"")
    error_message = "The trust policy must condition on \"<issuer>:aud\"."
  }

  assert {
    condition     = strcontains(aws_iam_role.external_secrets[0].assume_role_policy, "\"sts.amazonaws.com\"")
    error_message = "The \"aud\" condition must require \"sts.amazonaws.com\"."
  }
}

# #195 follow-up: kms_key_arn must accept multi-region keys (key/mrk-<32 hex>).
run "kms_key_arn_accepts_a_multi_region_key" {
  command = plan

  variables {
    cluster_name = "production-main"
    tags = {
      Environment = "production"
    }
    kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/mrk-1234567890abcdef1234567890abcdef"
  }

  assert {
    condition     = strcontains(aws_iam_policy.external_secrets[0].policy, "arn:aws:kms:eu-west-2:123456789012:key/mrk-1234567890abcdef1234567890abcdef")
    error_message = "A multi-region KMS key ARN (key/mrk-<32 hex>) must be accepted."
  }
}

# #195 follow-up: kms_key_arn must accept other AWS partitions (aws-us-gov,
# aws-cn), not only the default "aws" partition.
run "kms_key_arn_accepts_the_govcloud_partition" {
  command = plan

  variables {
    cluster_name = "production-main"
    tags = {
      Environment = "production"
    }
    kms_key_arn = "arn:aws-us-gov:kms:us-gov-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = strcontains(aws_iam_policy.external_secrets[0].policy, "arn:aws-us-gov:kms:us-gov-west-1:123456789012:key/11111111-2222-3333-4444-555555555555")
    error_message = "A GovCloud (aws-us-gov) partition KMS key ARN must be accepted."
  }
}

# #195 follow-up: an instance disabled via var.enabled must plan even with a
# null kms_key_arn (settings.environment.use_external_secrets: false, no
# kms/main dependency needed).
run "disabled_instance_plans_with_a_null_kms_key_arn" {
  command = plan

  variables {
    enabled      = false
    kms_key_arn  = null
    cluster_name = "production-main"
    tags = {
      Environment = "production"
    }
  }

  assert {
    condition     = length(aws_iam_role.external_secrets) == 0
    error_message = "A disabled instance must not create the IAM role."
  }

  assert {
    condition     = length(aws_iam_policy.external_secrets) == 0
    error_message = "A disabled instance must not create the IAM policy."
  }
}

# An *enabled* instance still requires kms_key_arn.
run "enabled_instance_without_a_kms_key_arn_is_rejected" {
  command = plan

  variables {
    kms_key_arn  = null
    cluster_name = "production-main"
    tags = {
      Environment = "production"
    }
  }

  expect_failures = [var.kms_key_arn]
}

# #195 follow-up: the one-level-nested match must use the stack's explicit
# context prefix, never a depth-agnostic "*/<prefix>/*" wildcard.
run "context_prefix_scopes_the_nested_match_explicitly" {
  command = plan

  variables {
    cluster_name = "production-main"
    tags = {
      Environment = "production"
    }
    secret_path_context_prefixes = ["production"]
  }

  assert {
    condition     = strcontains(aws_iam_policy.external_secrets[0].policy, "secret:production/app/*")
    error_message = "A configured context prefix must produce an explicit \"<context>/<prefix>/*\" Secrets Manager resource."
  }

  assert {
    condition     = strcontains(aws_iam_policy.external_secrets[0].policy, "parameter/production/certificates/*")
    error_message = "A configured context prefix must produce an explicit \"/<context>/<prefix>/*\" SSM resource."
  }

  assert {
    condition     = !strcontains(aws_iam_policy.external_secrets[0].policy, "secret:*/") && !strcontains(aws_iam_policy.external_secrets[0].policy, "parameter/*/")
    error_message = "The policy must never use a depth-agnostic \"*/<prefix>/*\" wildcard."
  }
}

# With no context prefixes configured (the component default), only the
# top-level "<prefix>/*" match should exist -- still no "*/" wildcard.
run "no_context_prefixes_means_top_level_only" {
  command = plan

  variables {
    cluster_name = "production-main"
    tags = {
      Environment = "production"
    }
  }

  assert {
    condition     = !strcontains(aws_iam_policy.external_secrets[0].policy, "secret:*/") && !strcontains(aws_iam_policy.external_secrets[0].policy, "parameter/*/")
    error_message = "With no context prefixes configured, the policy must not contain a \"*/<prefix>/*\" wildcard."
  }

  assert {
    condition     = strcontains(aws_iam_policy.external_secrets[0].policy, "secret:app/*")
    error_message = "The top-level \"<prefix>/*\" match must still be present."
  }
}

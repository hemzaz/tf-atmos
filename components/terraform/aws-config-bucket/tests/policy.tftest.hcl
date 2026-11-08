# The rendered bucket policy (E5b4b). The real AWS provider is used, not a mock:
# aws_iam_policy_document is computed locally, and a mock returns a random string. It never
# reaches AWS: credentials are dummies, every check that would call AWS is skipped, and the data
# sources that need an API call are overridden.
# Run: terraform init -backend=false && terraform test

provider "aws" {
  region                      = "eu-west-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

override_data {
  target = data.aws_caller_identity.account_verification
  values = {
    account_id = "123456789012"
  }
}

# s3-log-storage's own lookups (its bucket ACL owner and its SQS notification policy).
override_data {
  target = module.config_bucket[0].module.aws_s3_bucket.data.aws_canonical_user_id.default[0]
  values = {
    id = "0000000000000000000000000000000000000000000000000000000000000000"
  }
}

override_data {
  target = module.config_bucket[0].data.aws_caller_identity.current[0]
  values = {
    account_id = "123456789012"
  }
}

# fnx-ew1-audit's config-bucket as its stack resolves it: the vendored null-label shape
# (stacks/catalog/_base/vendored.yaml: no namespace, tenant first) and the EU residency.
variables {
  region                = "eu-west-1"
  account_map_enabled   = false
  namespace             = null
  tenant                = "fnx"
  environment           = "ew1"
  stage                 = "audit"
  name                  = "config"
  label_order           = ["tenant", "environment", "stage", "name", "attributes"]
  kms_master_key_arn    = "arn:aws:kms:eu-west-1:123456789012:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  residency_account_ids = ["666666666666", "111111111111", "123456789012", "333333333333"]
  account_map = {
    full_account_map = {
      fnx-root     = "111111111111"
      fnx-audit    = "123456789012"
      fnx-security = "333333333333"
      fnx-prod-eu  = "666666666666"
    }
  }
}

run "grants_this_accounts_recorder_role" {
  command = plan

  assert {
    condition     = module.aws_config_label.id == "fnx-ew1-audit-config-aws-config"
    error_message = "The bucket is fnx-ew1-audit's real name under the vendored label shape."
  }

  assert {
    condition = (
      one([for s in jsondecode(data.aws_iam_policy_document.aws_config_bucket_policy[0].json).Statement : s if s.Sid == "AWSConfigRoleDelivery"]) == {
        Sid       = "AWSConfigRoleDelivery"
        Effect    = "Allow"
        Action    = "s3:PutObject"
        Resource  = "arn:aws:s3:::fnx-ew1-audit-config-aws-config/AWSLogs/*"
        Principal = { AWS = "*" }
        Condition = {
          ArnEquals  = { "aws:PrincipalArn" = "arn:aws:iam::123456789012:role/fnx-ue1-audit-aws-config-config" }
          StringLike = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    )
    error_message = "The audit account's home recorder role (also its eu-west-1 recorder's) may put under AWSLogs/ with bucket-owner-full-control."
  }

  assert {
    condition = (
      one([for s in jsondecode(data.aws_iam_policy_document.aws_config_bucket_policy[0].json).Statement : s if s.Sid == "AWSConfigRoleBucketChecks"]).Condition == {
        ArnEquals = { "aws:PrincipalArn" = "arn:aws:iam::123456789012:role/fnx-ue1-audit-aws-config-config" }
      }
      && toset(one([for s in jsondecode(data.aws_iam_policy_document.aws_config_bucket_policy[0].json).Statement : s if s.Sid == "AWSConfigRoleBucketChecks"]).Action) == toset(["s3:GetBucketAcl", "s3:ListBucket"])
    )
    error_message = "The recorder role may read the bucket ACL and list the bucket, by aws:PrincipalArn only."
  }

  assert {
    # The residency Denys stay on the service principal, so they never match the role.
    condition = alltrue([
      for s in jsondecode(data.aws_iam_policy_document.aws_config_bucket_policy[0].json).Statement :
      s.Principal == { Service = "config.amazonaws.com" } if s.Effect == "Deny"
    ]) && length([for s in jsondecode(data.aws_iam_policy_document.aws_config_bucket_policy[0].json).Statement : s if s.Effect == "Deny"]) == 2
    error_message = "Both residency Denys must remain, scoped to config.amazonaws.com."
  }
}

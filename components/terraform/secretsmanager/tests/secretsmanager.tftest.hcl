# Mock-provider tests: no AWS credentials, no network, as in elasticache's
# own tests. Run from the component directory with `terraform init
# -backend=false && terraform test`.

mock_provider "aws" {}

variables {
  region             = "eu-west-2"
  environment        = "test"
  context_name       = "microservices"
  default_kms_key_id = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "plain_secret_uses_the_non_rotating_version_resource" {
  command = plan

  variables {
    secrets = {
      redis = {
        name                     = "auth-token"
        path                     = "cache"
        generate_random_password = true
      }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret_version.this) == 1 && length(aws_secretsmanager_secret_version.rotating) == 0
    error_message = "A secret with no rotation wiring gets the plain (non-ignore_changes) version resource."
  }

  assert {
    condition     = length(aws_secretsmanager_secret_rotation.this) == 0
    error_message = "No rotation_lambda_arn/rotation_automatically means no rotation resource."
  }
}

run "rotation_wiring_uses_the_rotating_version_resource" {
  command = plan

  variables {
    secrets = {
      redis = {
        name                     = "auth-token"
        path                     = "cache"
        generate_random_password = true
        rotation_lambda_arn      = "arn:aws:lambda:eu-west-2:123456789012:function:test-redis-auth-rotation"
        rotation_automatically   = true
        rotation_days            = 30
      }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret_version.rotating) == 1 && length(aws_secretsmanager_secret_version.this) == 0
    error_message = "A secret with rotation wiring gets the ignore_changes version resource instead of the plain one."
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this["redis"].rotation_lambda_arn == "arn:aws:lambda:eu-west-2:123456789012:function:test-redis-auth-rotation"
    error_message = "rotation_lambda_arn is wired onto the rotation resource."
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this["redis"].rotation_rules[0].automatically_after_days == 30
    error_message = "rotation_days becomes automatically_after_days."
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this["redis"].rotate_immediately == false
    error_message = "rotate_immediately defaults to false (opposite of the AWS provider's own default), so enabling rotation never tries to invoke a not-yet-deployed Lambda on this component's first apply."
  }
}

run "rotate_immediately_can_be_turned_on_per_secret" {
  command = plan

  variables {
    secrets = {
      redis = {
        name                     = "auth-token"
        path                     = "cache"
        generate_random_password = true
        rotation_lambda_arn      = "arn:aws:lambda:eu-west-2:123456789012:function:test-redis-auth-rotation"
        rotation_automatically   = true
        rotate_immediately       = true
      }
    }
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this["redis"].rotate_immediately == true
    error_message = "A per-secret rotate_immediately overrides default_rotate_immediately."
  }
}

run "rotation_managed_externally_gets_the_rotating_version_resource_without_a_rotation_resource" {
  command = plan

  variables {
    secrets = {
      redis = {
        name                        = "auth-token"
        path                        = "cache"
        generate_random_password    = true
        rotation_managed_externally = true
      }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret_version.rotating) == 1 && length(aws_secretsmanager_secret_version.this) == 0
    error_message = "rotation_managed_externally alone forces the ignore_changes version resource, same as rotation_automatically + rotation_lambda_arn."
  }

  assert {
    condition     = length(aws_secretsmanager_secret_rotation.this) == 0
    error_message = "rotation_managed_externally must not create this component's own aws_secretsmanager_secret_rotation -- a separate component instance (e.g. the lambda component's rotation_secret_arn) owns rotation instead."
  }
}

run "rejects_an_invalid_rotation_lambda_arn" {
  command = plan

  variables {
    secrets = {
      redis = {
        name                     = "auth-token"
        path                     = "cache"
        generate_random_password = true
        rotation_lambda_arn      = "not-an-arn"
        rotation_automatically   = true
      }
    }
  }

  expect_failures = [aws_secretsmanager_secret_rotation.this]
}

run "rejects_rotation_days_out_of_range" {
  command = plan

  variables {
    secrets = {
      redis = {
        name                     = "auth-token"
        path                     = "cache"
        generate_random_password = true
        rotation_lambda_arn      = "arn:aws:lambda:eu-west-2:123456789012:function:test-redis-auth-rotation"
        rotation_automatically   = true
        rotation_days            = 400
      }
    }
  }

  expect_failures = [aws_secretsmanager_secret_rotation.this]
}

run "secret_access_policy_grants_exactly_one_secret_and_its_key" {
  # apply, not plan: the policy's Resource elements are the secret's own arn,
  # a computed attribute unknown until apply even under mock_provider.
  command = apply

  variables {
    secrets = {
      redis = {
        name                     = "auth-token"
        path                     = "cache"
        generate_random_password = true
      }
      jwt_signing = {
        name                     = "jwt-signing"
        path                     = "auth"
        generate_random_password = true
      }
    }
  }

  assert {
    condition     = length(jsondecode(output.secret_access_policy["redis"]).Statement) == 3
    error_message = "Each secret's policy carries exactly its own read/write, GetRandomPassword and KMS statements."
  }

  assert {
    condition = (
      one([for s in jsondecode(output.secret_access_policy["redis"]).Statement : s if s.Sid == "AllowSecretReadWrite"]).Resource
      == aws_secretsmanager_secret.this["redis"].arn
    )
    error_message = "The read/write statement's Resource is this secret's own ARN, not another secret's."
  }

  assert {
    condition = toset(one([for s in jsondecode(output.secret_access_policy["redis"]).Statement : s if s.Sid == "AllowSecretReadWrite"]).Action) == toset([
      "secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue", "secretsmanager:UpdateSecretVersionStage", "secretsmanager:DescribeSecret",
    ])
    error_message = "The read/write statement grants exactly the four actions a rotation Lambda needs."
  }

  assert {
    condition     = one([for s in jsondecode(output.secret_access_policy["redis"]).Statement : s if s.Sid == "AllowGenerateRandomPassword"]).Resource == "*"
    error_message = "GetRandomPassword has no resource-level permissions, so its Resource must be *."
  }

  assert {
    condition = (
      one([for s in jsondecode(output.secret_access_policy["redis"]).Statement : s if s.Sid == "AllowSecretKMSUse"]).Condition.StringEquals["kms:EncryptionContext:SecretARN"]
      == aws_secretsmanager_secret.this["redis"].arn
    )
    error_message = "The KMS statement is scoped by the encryption context Secrets Manager itself sets: SecretARN = this secret's own ARN."
  }

  assert {
    condition = (
      one([for s in jsondecode(output.secret_access_policy["redis"]).Statement : s if s.Sid == "AllowSecretKMSUse"]).Condition.StringEquals["kms:ViaService"]
      == "secretsmanager.eu-west-2.amazonaws.com"
    )
    error_message = "The KMS statement also requires kms:ViaService=secretsmanager, so the grant cannot be used to call KMS directly with a forged encryption context naming this secret."
  }

  assert {
    condition = (
      one([for s in jsondecode(output.secret_access_policy["jwt_signing"]).Statement : s if s.Sid == "AllowSecretReadWrite"]).Resource
      != aws_secretsmanager_secret.this["redis"].arn
    )
    error_message = "The jwt_signing secret's policy must not carry the redis secret's ARN, or the two rotation Lambdas' scoping would overlap."
  }
}

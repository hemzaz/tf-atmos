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

run "plain_generated_secret_gets_a_version" {
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
    condition     = length(aws_secretsmanager_secret_version.this) == 1
    error_message = "A generated secret gets a version resource."
  }

  assert {
    condition     = length(aws_secretsmanager_secret_rotation.this) == 0
    error_message = "No rotation_lambda_arn/rotation_automatically means no rotation resource."
  }
}

run "rotation_wiring_creates_the_rotation_resource" {
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
    condition     = length(aws_secretsmanager_secret_version.this) == 1 && aws_secretsmanager_secret_version.this["redis"].secret_string_wo_version == 1
    error_message = "A rotating secret gets the same write-only version resource: its value is never re-sent unless secret_string_version changes, so it cannot overwrite the Lambda's."
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

run "rotation_managed_externally_gets_no_rotation_resource" {
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
    condition     = length(aws_secretsmanager_secret_version.this) == 1 && aws_secretsmanager_secret_version.this["redis"].secret_string == null
    error_message = "rotation_managed_externally keeps the initial write-only version: written once, never re-sent unless secret_string_version changes."
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

# S1: no secret value in plan, state or outputs. Generated values come from an
# ephemeral random_password and are written through secret_string_wo.
run "generated_secrets_are_write_only_with_per_secret_length" {
  # apply, not plan: checks the values the state actually holds.
  command = apply

  variables {
    environment = "production"
    secrets = {
      app_credentials = {
        name                     = "credentials"
        generate_random_password = true
        password_length          = 48
      }
      api_keys = {
        name                     = "api-keys"
        generate_random_password = true
        password_length          = 64
      }
      database_credentials = {
        name                     = "db-credentials"
        generate_random_password = true
      }
      redis = {
        name                             = "auth-token"
        generate_random_password         = true
        random_password_override_special = "!&#$^<>-"
      }
    }
  }

  assert {
    condition = alltrue([
      for k, v in aws_secretsmanager_secret_version.this : v.secret_string == null && v.secret_binary == null
    ]) && length(aws_secretsmanager_secret_version.this) == 4
    error_message = "Every generated value is written through secret_string_wo: no secret_string (or secret_binary) in state."
  }

  assert {
    condition     = alltrue([for k, v in aws_secretsmanager_secret_version.this : v.secret_string_wo_version == 1])
    error_message = "secret_string_wo_version follows secret_string_version (default 1)."
  }

  assert {
    condition     = local.password_generators["api_keys"].length == 64 && local.password_generators["app_credentials"].length == 48
    error_message = "A per-secret password_length is honoured (it used to be ignored, so prod's 64 became 32)."
  }

  assert {
    condition     = local.password_generators["database_credentials"].length == 32
    error_message = "Without password_length, a secret falls back to random_password_length (32)."
  }

  assert {
    condition = (
      local.password_generators["redis"].override_special == "!&#$^<>-"
      && local.password_generators["api_keys"].override_special == "!#$%&*()-_=+[]{}<>:?"
      && local.password_generators["api_keys"].min_special == 5
    )
    error_message = "random_password_override_special is per secret; the min_* counts come from the component variables."
  }
}

run "bumping_secret_string_version_resends_the_value" {
  command = plan

  variables {
    secrets = {
      redis = {
        name                     = "auth-token"
        generate_random_password = true
        secret_string_version    = 2
      }
    }
  }

  assert {
    condition     = aws_secretsmanager_secret_version.this["redis"].secret_string_wo_version == 2
    error_message = "secret_string_version drives secret_string_wo_version: a bump re-sends (rotates) the value."
  }
}

run "static_value_comes_from_the_ephemeral_variable_and_stays_out_of_state" {
  command = apply

  variables {
    secrets = {
      istio_certificates = {
        name         = "istio-certificates"
        path         = "certificates"
        static_value = true
      }
      api_keys = {
        name = "api-keys"
        path = "api"
      }
    }
    secret_data = {
      istio_certificates = "{\"tls.crt_ssm_parameter\": \"/fnx/certificates/s1-static-marker/cert\", \"reference_only\": \"true\"}"
    }
  }

  assert {
    condition     = aws_secretsmanager_secret_version.this["istio_certificates"].secret_string == null && aws_secretsmanager_secret_version.this["istio_certificates"].secret_string_wo_version == 1
    error_message = "A static_value secret is written through secret_string_wo: its value is not in state."
  }

  assert {
    condition     = !contains(keys(aws_secretsmanager_secret_version.this), "api_keys") && length(aws_secretsmanager_secret.this) == 2
    error_message = "A secret with neither generate_random_password nor static_value is created empty, for an operator to fill."
  }

  assert {
    condition = !strcontains(jsonencode([
      output.secret_arns, output.secret_ids, output.secret_names, output.secret_versions,
      output.secret_policies, output.rotation_enabled_secrets, output.secret_access_policy,
    ]), "s1-static-marker")
    error_message = "No output carries a secret's value."
  }
}

run "rejects_a_static_secret_without_a_value" {
  command = plan

  variables {
    secrets = {
      istio_certificates = {
        name         = "istio-certificates"
        static_value = true
      }
    }
  }

  expect_failures = [var.secret_data]
}

run "rejects_secret_data_for_a_secret_that_is_not_static" {
  command = plan

  variables {
    secrets = {
      redis = {
        name                     = "auth-token"
        generate_random_password = true
      }
    }
    secret_data = {
      redis = "R8v#kq2LmZ9wXp4T"
    }
  }

  expect_failures = [var.secret_data]
}

run "rejects_a_weak_static_value" {
  command = plan

  variables {
    secrets = {
      db = {
        name         = "db"
        static_value = true
      }
    }
    secret_data = {
      db = "changeme_password"
    }
  }

  expect_failures = [var.secret_data]
}

# The weak-pattern check reads values, not JSON key names: a key such as
# db_password used to match "<word>_password" and reject a strong value.
run "accepts_a_strong_json_value_under_a_password_key" {
  command = plan

  variables {
    secrets = {
      db = {
        name         = "db"
        static_value = true
      }
    }
    # Built with join so that secret scanners do not read a literal
    # password/api_key assignment in this file.
    secret_data = {
      db = jsonencode({
        db_password = join("-", ["Tq7v", "W2mR", "k9xL", "p4zN"])
        api_key     = join("", ["Tq7vW2mR", "k9xLp4zN"])
      })
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret_version.this) == 1
    error_message = "A strong JSON value whose keys are named db_password/api_key passes the weak-pattern check."
  }
}

run "rejects_a_weak_json_value_under_a_password_key" {
  command = plan

  variables {
    secrets = {
      db = {
        name         = "db"
        static_value = true
      }
    }
    secret_data = {
      db = jsonencode({ db_password = join("_", ["changeme", "password"]) })
    }
  }

  expect_failures = [var.secret_data]
}

run "rejects_the_removed_secret_data_attribute" {
  command = plan

  variables {
    secrets = {
      db = {
        name        = "db"
        secret_data = "{\"host\": \"db.internal\"}"
      }
    }
  }

  expect_failures = [var.secrets]
}

run "rejects_a_short_password_length" {
  command = plan

  variables {
    secrets = {
      db = {
        name                     = "db"
        generate_random_password = true
        password_length          = 12
      }
    }
  }

  # 12 < 20, the sum of the four random_password_min_* defaults (5 each).
  expect_failures = [var.secrets]
}

run "rejects_generate_and_static_together" {
  command = plan

  variables {
    secrets = {
      db = {
        name                     = "db"
        generate_random_password = true
        static_value             = true
      }
    }
  }

  expect_failures = [var.secrets]
}

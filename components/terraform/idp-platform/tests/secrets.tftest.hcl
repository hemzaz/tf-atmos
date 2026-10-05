# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.
#
# The Redis AUTH token used to be read back at plan time through an ephemeral
# aws_secretsmanager_secret_version, which needs secretsmanager:GetSecretValue
# that the CI plan role (ReadOnlyAccess) lacks. These tests only run because
# the component no longer has any aws ephemeral resource: mock_provider
# rejects those, so a revert fails here before it reaches a real plan.

mock_provider "aws" {}

# The nested ../eks, ../rds and ../acm root components configure their own
# aws provider, which mock_provider cannot replace; override them whole.
override_module {
  target = module.eks_cluster
  outputs = {
    eks_cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/dev-idp"
    eks_cluster_certificate_authority_data = "Y2E="
    eks_cluster_endpoint                   = "https://example.eks.amazonaws.com"
    eks_cluster_id                         = "dev-idp"
    eks_cluster_identity_oidc_issuer_arn   = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    eks_cluster_managed_security_group_id  = "sg-0123456789abcdef0"
    eks_node_group_arns                    = {}
  }
}

override_module {
  target = module.idp_database
  outputs = {
    instance_address    = "dev-idp.example.us-east-1.rds.amazonaws.com"
    instance_endpoint   = "dev-idp.example.us-east-1.rds.amazonaws.com:5432"
    instance_id         = "dev-idp"
    instance_name       = "idp"
    password_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds-dev-idp-AbCdEf"
    security_group_id   = "sg-0123456789abcdef1"
  }
}

override_module {
  target = module.acm_certificate
  outputs = {
    certificate_arns    = { idp = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000" }
    certificate_domains = { idp = "example.com" }
  }
}

override_data {
  target = data.aws_subnets.private
  values = {
    ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  }
}

override_data {
  target = data.aws_subnets.public
  values = {
    ids = ["subnet-0123456789abcdef2", "subnet-0123456789abcdef3"]
  }
}

override_data {
  target = data.aws_vpc.selected
  values = {
    id         = "vpc-0123456789abcdef0"
    cidr_block = "10.0.0.0/16"
  }
}

variables {
  region                  = "us-east-1"
  environment             = "dev"
  domain_name             = "example.com"
  acknowledge_unsupported = true
  kms_key_arn             = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  tags = {
    Tenant      = "fnx"
    Environment = "ue1"
  }
}

run "redis_auth_token_is_generated_and_written_write_only" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.redis.auth_token == null
    error_message = "The replication group must not hold the token in state: it is set through auth_token_wo."
  }

  assert {
    condition     = aws_elasticache_replication_group.redis.auth_token_wo_version == 1 && aws_elasticache_replication_group.redis.auth_token_update_strategy == "ROTATE"
    error_message = "auth_token_wo is set with auth_token_wo_version = secrets_version (default 1) and the ROTATE strategy."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.redis_auth.secret_string == null && aws_secretsmanager_secret_version.redis_auth.secret_string_wo_version == 1
    error_message = "The Redis AUTH secret version is written only through secret_string_wo, versioned by secrets_version."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.idp_config.secret_string == null && aws_secretsmanager_secret_version.idp_config.secret_string_wo_version == 1
    error_message = "The config secret version (with the JWT secret) is written only through secret_string_wo."
  }
}

run "database_url_requires_verified_tls" {
  command = plan

  assert {
    condition     = local.database_url == "postgresql://dev-idp.example.us-east-1.rds.amazonaws.com:5432/idp?sslmode=verify-full&sslrootcert=/etc/ssl/certs/rds-global-bundle.pem"
    error_message = "The config secret's database_url must require verified TLS against the RDS CA bundle."
  }
}

run "secrets_version_rotates_both_write_only_values" {
  command = plan

  variables {
    secrets_version = 2
  }

  assert {
    condition     = aws_elasticache_replication_group.redis.auth_token_wo_version == 2 && aws_secretsmanager_secret_version.redis_auth.secret_string_wo_version == 2
    error_message = "Bumping secrets_version must re-send the token to both the replication group and its secret."
  }
}

# The ephemeral resource's own arguments cannot be asserted, so they live in
# local.redis_auth_token_generator; the replication group's precondition
# checks the generated token itself.
run "redis_auth_token_generator_meets_elasticache_constraints" {
  command = plan

  assert {
    condition     = local.redis_auth_token_generator.length >= 16 && local.redis_auth_token_generator.length <= 128
    error_message = "ElastiCache AUTH tokens are 16-128 characters."
  }

  assert {
    condition     = length(regexall("[^!&#$^<>-]", local.redis_auth_token_generator.override_special)) == 0
    error_message = "ElastiCache AUTH tokens allow punctuation only from !&#$^<>-."
  }
}

# Every CloudWatch log group this component creates is encrypted with the CMK
# passed in (kms/main), not CloudWatch Logs' default key.
run "redis_slow_log_group_uses_the_cmk" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.redis_slow_log.kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "The Redis slow-log group must be encrypted with kms_key_arn."
  }
}

run "rejects_non_arn_kms_key" {
  command = plan

  variables {
    kms_key_arn = "alias/main"
  }

  expect_failures = [var.kms_key_arn]
}

# S3 names are global: the buckets carry the full id, tenant-environment-stage.
run "storage_buckets_use_the_full_id" {
  command = plan

  assert {
    condition     = aws_s3_bucket.idp_storage["artifacts"].bucket == "fnx-ue1-dev-idp-artifacts"
    error_message = "Buckets are <Tenant>-<Environment>-<environment>-idp-<purpose>."
  }
}

# var.environment is the stage: it defaults tags.Stage, which ../eks keys
# deletion protection on (tags.Environment is the region code).
run "stage_tag_defaults_to_the_environment_variable" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = aws_s3_bucket.idp_storage["artifacts"].tags["Stage"] == "prod"
    error_message = "tags.Stage must default to var.environment."
  }
}

run "rejects_tags_without_environment" {
  command = plan

  variables {
    tags = { Tenant = "fnx" }
  }

  expect_failures = [var.tags]
}

run "rejects_a_bucket_name_over_63_characters" {
  command = plan

  variables {
    tags = { Tenant = "fnx", Environment = "a-very-long-environment-name-that-overflows-s3" }
  }

  expect_failures = [var.tags]
}

# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {}

variables {
  region     = "eu-west-2"
  cluster_id = "cache"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "default_is_one_primary_with_replicas" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.main[0].num_cache_clusters == 2
    error_message = "Without cluster mode the group is num_cache_nodes nodes."
  }

  assert {
    condition     = length(aws_elasticache_parameter_group.main) == 0
    error_message = "No parameter group is created when there is nothing to put in it."
  }
}

run "cluster_mode_creates_a_cluster_enabled_group" {
  command = plan

  variables {
    cluster_mode_enabled                 = true
    cluster_mode_num_node_groups         = 2
    cluster_mode_replicas_per_node_group = 1
    family                               = "redis7"
    parameters = [
      { name = "maxmemory-policy", value = "volatile-lru" },
    ]
  }

  assert {
    condition     = aws_elasticache_replication_group.main[0].num_node_groups == 2 && aws_elasticache_replication_group.main[0].replicas_per_node_group == 1
    error_message = "Cluster mode sets the shard and replica counts."
  }

  assert {
    condition     = aws_elasticache_parameter_group.main[0].family == "redis7" && aws_elasticache_parameter_group.main[0].name == "test-cache-redis7"
    error_message = "The parameter group is <Environment>-<cluster_id>-<family>, so a family change (which forces replacement) doesn't collide with the old group's name."
  }

  assert {
    condition = tomap({ for p in aws_elasticache_parameter_group.main[0].parameter : p.name => p.value }) == tomap({
      "maxmemory-policy" = "volatile-lru"
      "cluster-enabled"  = "yes"
    })
    error_message = "Cluster mode forces cluster-enabled=yes and keeps the other parameters."
  }

  assert {
    condition     = aws_elasticache_replication_group.main[0].parameter_group_name == "test-cache-redis7"
    error_message = "The created parameter group is attached."
  }
}

run "changing_family_changes_the_parameter_group_name" {
  command = plan

  variables {
    family     = "valkey8"
    engine     = "valkey"
    parameters = [{ name = "maxmemory-policy", value = "volatile-lru" }]
  }

  assert {
    condition     = aws_elasticache_parameter_group.main[0].name == "test-cache-valkey8"
    error_message = "A different family must produce a different parameter group name so create_before_destroy doesn't collide with the old group."
  }
}

run "rejects_user_supplied_cluster_enabled_parameter" {
  command = plan

  variables {
    family     = "redis7"
    parameters = [{ name = "cluster-enabled", value = "yes" }]
  }

  expect_failures = [var.parameters]
}

run "family_accepts_redis6_x" {
  command = plan

  variables {
    family = "redis6.x"
  }

  assert {
    condition     = length(aws_elasticache_replication_group.main) == 1
    error_message = "redis6.x is a real ElastiCache Redis 6 parameter group family and must be accepted."
  }
}

run "family_accepts_redis5_0" {
  command = plan

  variables {
    family = "redis5.0"
  }

  assert {
    condition     = length(aws_elasticache_replication_group.main) == 1
    error_message = "redis5.0 must be accepted."
  }
}

run "family_accepts_redis7" {
  command = plan

  variables {
    family = "redis7"
  }

  assert {
    condition     = length(aws_elasticache_replication_group.main) == 1
    error_message = "redis7 must be accepted."
  }
}

run "family_accepts_valkey8" {
  command = plan

  variables {
    engine = "valkey"
    family = "valkey8"
  }

  assert {
    condition     = length(aws_elasticache_replication_group.main) == 1
    error_message = "valkey8 must be accepted when engine is valkey."
  }
}

run "rejects_family_that_does_not_match_engine" {
  command = plan

  variables {
    engine = "redis"
    family = "valkey8"
  }

  expect_failures = [var.family]
}

run "existing_parameter_group_is_used_as_is" {
  command = plan

  variables {
    cluster_mode_enabled = true
    parameter_group_name = "default.redis7.cluster.on"
  }

  assert {
    condition     = length(aws_elasticache_parameter_group.main) == 0 && aws_elasticache_replication_group.main[0].parameter_group_name == "default.redis7.cluster.on"
    error_message = "A named parameter group is attached and none is created."
  }
}

run "rejects_cluster_mode_without_a_family" {
  command = plan

  variables {
    cluster_mode_enabled = true
  }

  expect_failures = [var.family]
}

run "rejects_parameters_and_a_named_group" {
  command = plan

  variables {
    family               = "redis7"
    parameter_group_name = "default.redis7"
    parameters           = [{ name = "maxmemory-policy", value = "volatile-lru" }]
  }

  expect_failures = [var.parameter_group_name]
}

run "cluster_mode_allows_zero_replicas_per_shard" {
  command = plan

  variables {
    cluster_mode_enabled                 = true
    cluster_mode_num_node_groups         = 3
    cluster_mode_replicas_per_node_group = 0
    family                               = "redis7"
  }

  assert {
    condition     = aws_elasticache_replication_group.main[0].replicas_per_node_group == 0
    error_message = "AWS allows 0 replicas per shard in cluster mode (cheaper dev/test); the component must not forbid it."
  }
}

run "ingress_open_to_everywhere_is_rejected" {
  command = plan

  variables {
    allowed_cidr_blocks = ["10.0.0.0/8", "0.0.0.0/0"]
  }

  expect_failures = [var.allowed_cidr_blocks]
}

run "ingress_ipv6_open_to_everywhere_is_rejected" {
  command = plan

  # ::/0 is as open as 0.0.0.0/0; the prefix-length check must catch both.
  variables {
    allowed_cidr_blocks = ["::/0"]
  }

  expect_failures = [var.allowed_cidr_blocks]
}

run "ingress_slash_00_is_rejected" {
  command = plan

  # AWS parses "/00" the same as "/0"; the check compares the prefix length
  # as a number, not as the literal string "0", so this must be caught too.
  variables {
    allowed_cidr_blocks = ["0.0.0.0/00"]
  }

  expect_failures = [var.allowed_cidr_blocks]
}

# apply, not plan: the state after apply is what must not hold the token.
# Terraform nulls write-only attributes in state anyway, so the
# secret_string/auth_token == null asserts guard against a revert to the
# stored attributes (secret_string, auth_token), not against *_wo leaking.
run "auth_token_is_generated_and_written_write_only" {
  command = apply

  assert {
    condition     = aws_secretsmanager_secret.auth_token[0].name == "redis-auth/test/cache"
    error_message = "The auth token secret must be named redis-auth/<Environment>/<cluster_id>."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.auth_token[0].secret_string == null && aws_secretsmanager_secret_version.auth_token[0].secret_binary == null
    error_message = "The secret version must be written through secret_string_wo: no secret_string (or secret_binary) in state."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.auth_token[0].secret_string_wo_version == 1
    error_message = "secret_string_wo_version follows auth_token_version (default 1)."
  }

  assert {
    condition     = aws_elasticache_replication_group.main[0].auth_token == null
    error_message = "The replication group must not hold the token in state: it is set through auth_token_wo."
  }

  assert {
    condition     = aws_elasticache_replication_group.main[0].auth_token_wo_version == 1 && aws_elasticache_replication_group.main[0].auth_token_update_strategy == "ROTATE"
    error_message = "auth_token_wo is set with auth_token_wo_version = auth_token_version (default 1) and the ROTATE strategy."
  }

  assert {
    condition     = output.auth_token_secret_arn == aws_secretsmanager_secret.auth_token[0].arn
    error_message = "auth_token_secret_arn (read by eks-backend-services) is the generated token's secret."
  }
}

# The ephemeral resource's own arguments cannot be asserted, so they live in
# local.auth_token_generator. The token itself is checked by the replication
# group's precondition, which every plan and apply run above has passed.
run "auth_token_generator_meets_elasticache_constraints" {
  command = plan

  assert {
    condition     = local.auth_token_generator.length >= 16 && local.auth_token_generator.length <= 128
    error_message = "ElastiCache AUTH tokens are 16-128 characters."
  }

  assert {
    condition = (
      local.auth_token_generator.special
      && local.auth_token_generator.override_special == "#^-"
      && length(regexall("[^!&#$^<>-]", local.auth_token_generator.override_special)) == 0
    )
    error_message = "The token's punctuation is Cloud Posse's #^-, a subset of the only punctuation ElastiCache accepts (!&#$^<>-; never @, \", / or space)."
  }

  assert {
    condition = (
      local.auth_token_generator.min_upper == 3 && local.auth_token_generator.min_lower == 3
      && local.auth_token_generator.min_numeric == 3 && local.auth_token_generator.min_special == 3
    )
    error_message = "As Cloud Posse, the token has at least 3 of each character class."
  }
}

run "bumping_auth_token_version_rotates_both_copies" {
  command = plan

  variables {
    auth_token_version = 2
  }

  assert {
    condition     = aws_elasticache_replication_group.main[0].auth_token_wo_version == 2 && aws_secretsmanager_secret_version.auth_token[0].secret_string_wo_version == 2
    error_message = "auth_token_version drives both write-only versions, so a bump re-sends the token to the cache and its secret together."
  }
}

run "rejects_auth_token_version_zero" {
  command = plan

  variables {
    auth_token_version = 0
  }

  expect_failures = [var.auth_token_version]
}

run "rejects_a_fractional_auth_token_version" {
  command = plan

  variables {
    auth_token_version = 1.5
  }

  expect_failures = [var.auth_token_version]
}

run "auth_token_secret_can_be_turned_off" {
  command = plan

  variables {
    store_auth_token_in_secrets_manager = false
  }

  assert {
    condition     = length(aws_secretsmanager_secret.auth_token) == 0 && length(aws_secretsmanager_secret_version.auth_token) == 0 && output.auth_token_secret_arn == null
    error_message = "store_auth_token_in_secrets_manager = false must create neither the secret nor its version."
  }

  assert {
    condition     = aws_elasticache_replication_group.main[0].auth_token == null && aws_elasticache_replication_group.main[0].auth_token_wo_version == 1
    error_message = "The generated token still reaches the cache, write-only."
  }
}

run "rotation_policy_carries_only_its_own_statement_by_default" {
  # apply, not plan: rotation_policy's Resource is the replication group's
  # arn, a computed attribute unknown until apply even under mock_provider,
  # as kinesis's own reader_policy/combined_policy tests need too.
  command = apply

  assert {
    condition     = length(jsondecode(output.rotation_policy).Statement) == 1
    error_message = "Without additional_policy_json, rotation_policy is exactly this cache's own grant."
  }

  assert {
    condition = (
      one(jsondecode(output.rotation_policy).Statement).Sid == "AllowElastiCacheAuthTokenRotation"
      && toset(one(jsondecode(output.rotation_policy).Statement).Action) == toset(["elasticache:ModifyReplicationGroup", "elasticache:DescribeReplicationGroups"])
    )
    error_message = "rotation_policy's own statement grants exactly the two rotation actions on this replication group."
  }
}

run "rotation_policy_folds_in_additional_policy_json" {
  command = apply

  variables {
    additional_policy_json = jsonencode({
      Version = "2012-10-17"
      Statement = [
        { Sid = "AllowSecretReadWrite", Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:test" },
      ]
    })
  }

  assert {
    condition     = length(jsondecode(output.rotation_policy).Statement) == 2
    error_message = "additional_policy_json's Statement entries are folded into rotation_policy alongside this cache's own."
  }

  assert {
    condition     = length([for s in jsondecode(output.rotation_policy).Statement : s if s.Sid == "AdditionalAllowSecretReadWrite0"]) == 1
    error_message = "The folded-in statement's Sid is rewritten Additional<original-Sid><index> so it can never collide with rotation_policy's own Sid."
  }
}

run "client_security_group_is_created_and_allowed_ingress_by_reference" {
  command = plan

  assert {
    condition     = length(aws_security_group.client) == 1
    error_message = "The rule-less client security group is always created alongside the cache."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_client_security_group[0].referenced_security_group_id == aws_security_group.client[0].id
    error_message = "The cache's own security group allows ingress from the client security group by reference, not a resource that reads this component's outputs back."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_client_security_group[0].from_port == var.port && aws_vpc_security_group_ingress_rule.from_client_security_group[0].to_port == var.port
    error_message = "The client ingress rule is scoped to the cache port, same as from_security_groups and from_cidr_blocks."
  }
}

run "rejects_additional_policy_json_without_a_statement_key" {
  command = plan

  variables {
    additional_policy_json = jsonencode({ Version = "2012-10-17" })
  }

  expect_failures = [var.additional_policy_json]
}

# The secret version's replace_triggered_by names main[0]: with the component
# disabled both have count 0, and the reference must not be evaluated.
run "disabled_creates_nothing" {
  command = apply

  variables {
    enabled = false
  }

  assert {
    condition = (
      length(aws_elasticache_replication_group.main) == 0
      && length(aws_secretsmanager_secret.auth_token) == 0
      && length(aws_secretsmanager_secret_version.auth_token) == 0
      && output.auth_token_secret_arn == null
    )
    error_message = "enabled = false must create no cache, secret or secret version."
  }
}

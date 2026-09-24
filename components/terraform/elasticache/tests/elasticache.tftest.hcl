# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {}

variables {
  region     = "eu-west-2"
  cluster_id = "cache"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  auth_token = "plan-only-token-0123456789"
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

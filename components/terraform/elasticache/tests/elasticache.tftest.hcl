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
      # Set by the component in cluster mode; a stack's own value is dropped.
      { name = "cluster-enabled", value = "no" },
    ]
  }

  assert {
    condition     = aws_elasticache_replication_group.main[0].num_node_groups == 2 && aws_elasticache_replication_group.main[0].replicas_per_node_group == 1
    error_message = "Cluster mode sets the shard and replica counts."
  }

  assert {
    condition     = aws_elasticache_parameter_group.main[0].family == "redis7" && aws_elasticache_parameter_group.main[0].name == "test-cache"
    error_message = "The parameter group is <Environment>-<cluster_id> in the given family."
  }

  assert {
    condition = tomap({ for p in aws_elasticache_parameter_group.main[0].parameter : p.name => p.value }) == tomap({
      "maxmemory-policy" = "volatile-lru"
      "cluster-enabled"  = "yes"
    })
    error_message = "Cluster mode forces cluster-enabled=yes and keeps the other parameters."
  }

  assert {
    condition     = aws_elasticache_replication_group.main[0].parameter_group_name == "test-cache"
    error_message = "The created parameter group is attached."
  }
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

run "rejects_cluster_mode_failover_without_replicas" {
  command = plan

  variables {
    cluster_mode_enabled                 = true
    cluster_mode_replicas_per_node_group = 0
    family                               = "redis7"
  }

  expect_failures = [var.automatic_failover_enabled]
}

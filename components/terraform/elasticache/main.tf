# components/terraform/elasticache/main.tf
#
# num_cache_nodes + automatic_failover_enabled + multi_az_enabled describe a
# replicated cache, so this is an aws_elasticache_replication_group, not a
# standalone aws_elasticache_cluster (which has neither failover nor Multi-AZ).

locals {
  enabled = var.enabled
  name    = "${var.tags["Environment"]}-${var.cluster_id}"

  # A parameter group is created when there is something to put in it, or in
  # cluster mode (which needs cluster-enabled=yes), unless one is named.
  create_parameter_group = local.enabled && var.parameter_group_name == null && (length(var.parameters) > 0 || var.cluster_mode_enabled)

  # cluster-enabled is rejected in var.parameters by validation, so this only
  # ever appends it; it never overrides a user-supplied value silently.
  parameters = var.cluster_mode_enabled ? concat(var.parameters, [{ name = "cluster-enabled", value = "yes" }]) : var.parameters

  # The family is part of the name so that changing it (e.g. an engine
  # upgrade from redis7 to valkey8, or redis6.x to redis7) creates a new
  # group instead of trying to reuse the old name: family forces replacement
  # of the parameter group, and with a fixed name create_before_destroy would
  # fail with CacheParameterGroupAlreadyExists while the old group still
  # exists under that name.
  parameter_group_name = local.create_parameter_group ? "${local.name}-${replace(var.family, ".", "-")}" : null
}

resource "aws_elasticache_parameter_group" "main" {
  count = local.create_parameter_group ? 1 : 0

  name        = local.parameter_group_name
  family      = var.family
  description = "Parameters for the ${var.cluster_id} cache"

  dynamic "parameter" {
    for_each = local.parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = { Name = local.parameter_group_name }

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = length(local.parameter_group_name) <= 255
      error_message = "The generated parameter group name \"${local.parameter_group_name}\" exceeds AWS's 255-character limit; shorten tags.Environment, cluster_id or family."
    }
  }
}

resource "aws_elasticache_subnet_group" "main" {
  count = local.enabled ? 1 : 0

  name        = "${local.name}-subnet-group"
  description = "Subnet group for the ${var.cluster_id} cache"
  subnet_ids  = var.subnet_ids

  tags = { Name = "${local.name}-subnet-group" }
}

resource "aws_security_group" "main" {
  #checkov:skip=CKV2_AWS_5:False positive, aws_elasticache_replication_group.main attaches this group; checkov's graph does not follow the count index in aws_security_group.main[0].id (the same config passes with count removed)
  count = local.enabled ? 1 : 0

  name        = "${local.name}-sg"
  description = "Security group for the ${var.cluster_id} cache"
  vpc_id      = var.vpc_id

  tags = { Name = "${local.name}-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "from_security_groups" {
  for_each = local.enabled ? toset(var.allowed_security_group_ids) : toset([])

  security_group_id            = aws_security_group.main[0].id
  description                  = "Cache access from ${each.value}"
  referenced_security_group_id = each.value
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "from_cidr_blocks" {
  for_each = local.enabled ? toset(var.allowed_cidr_blocks) : toset([])

  security_group_id = aws_security_group.main[0].id
  description       = "Cache access from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
}

# Replication between the primary and its replicas, which all share this group.
resource "aws_vpc_security_group_ingress_rule" "replication" {
  count = local.enabled ? 1 : 0

  security_group_id            = aws_security_group.main[0].id
  description                  = "Replication between cache nodes"
  referenced_security_group_id = aws_security_group.main[0].id
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "replication" {
  count = local.enabled ? 1 : 0

  security_group_id            = aws_security_group.main[0].id
  description                  = "Replication between cache nodes"
  referenced_security_group_id = aws_security_group.main[0].id
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
}

resource "aws_elasticache_replication_group" "main" {
  count = local.enabled ? 1 : 0

  replication_group_id = local.name
  description          = "${var.cluster_id} cache"

  engine               = var.engine
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = var.port
  parameter_group_name = local.create_parameter_group ? aws_elasticache_parameter_group.main[0].name : var.parameter_group_name

  # Cluster mode shards the keyspace; otherwise one primary plus replicas.
  # WARNING: toggling cluster_mode_enabled on an existing replication group is
  # not an in-place change. AWS has no online migration from a non-cluster
  # (num_cache_clusters) to a cluster-mode (num_node_groups) topology through
  # this provider, and the parameter group's cluster-enabled value can't be
  # flipped on an attached, in-use group either. Treat a change to
  # cluster_mode_enabled as requiring the cache to be replaced.
  num_cache_clusters      = var.cluster_mode_enabled ? null : var.num_cache_nodes
  num_node_groups         = var.cluster_mode_enabled ? var.cluster_mode_num_node_groups : null
  replicas_per_node_group = var.cluster_mode_enabled ? var.cluster_mode_replicas_per_node_group : null

  # Encryption. auth_token is required whenever transit encryption is on
  # (validated on the variable), so the cache is never reachable unauthenticated.
  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  transit_encryption_enabled = var.transit_encryption_enabled
  auth_token                 = var.auth_token
  auth_token_update_strategy = "ROTATE"
  kms_key_id                 = var.kms_key_id

  subnet_group_name  = aws_elasticache_subnet_group.main[0].name
  security_group_ids = [aws_security_group.main[0].id]

  automatic_failover_enabled = var.automatic_failover_enabled
  multi_az_enabled           = var.multi_az_enabled

  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = var.snapshot_window

  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  tags = { Name = local.name }
}

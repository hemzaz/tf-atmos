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

# A rule-less "client" tag security group: attach it to any OTHER resource
# (e.g. a Secrets Manager rotation Lambda) that needs cache access, instead
# of this component reading that resource's own security group back into
# from_security_groups above. The latter would create a dependency cycle for
# a consumer that (like a rotation Lambda) already reads THIS component's
# own outputs -- see client_security_group_id's own description.
resource "aws_security_group" "client" {
  #checkov:skip=CKV2_AWS_5:Intentionally rule-less; aws_vpc_security_group_ingress_rule.from_client_security_group references it by ID as a source, which is the group's entire purpose
  count = local.enabled ? 1 : 0

  name        = "${local.name}-client-sg"
  description = "Attach to any resource that needs access to the ${var.cluster_id} cache, without this component reading that resource's own security group back"
  vpc_id      = var.vpc_id

  tags = { Name = "${local.name}-client-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "from_client_security_group" {
  count = local.enabled ? 1 : 0

  security_group_id            = aws_security_group.main[0].id
  description                  = "Cache access from anything attached to the client security group"
  referenced_security_group_id = aws_security_group.client[0].id
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
  #checkov:skip=CKV_AWS_31:False positive, the check reads only auth_token; transit encryption is forced on and the token is set write-only through auth_token_wo
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

  # Encryption. Transit encryption is forced on (validated on the variable)
  # and the AUTH token is always set, so the cache is never reachable
  # unauthenticated. The token is write-only, never in plan or state. The
  # provider sends it when the cache is created (including a replacement)
  # and when auth_token_version changes; an apply that leaves the version
  # alone never re-sends it.
  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  transit_encryption_enabled = var.transit_encryption_enabled
  auth_token_wo              = local.auth_token
  auth_token_wo_version      = var.auth_token_version
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

  # Cloud Posse aws-elasticache-redis's log_delivery_configuration, into log
  # groups this component owns (aws_cloudwatch_log_group.log_delivery).
  dynamic "log_delivery_configuration" {
    for_each = aws_cloudwatch_log_group.log_delivery

    content {
      destination      = log_delivery_configuration.value.name
      destination_type = "cloudwatch-logs"
      log_format       = local.log_delivery[log_delivery_configuration.key].log_format
      log_type         = log_delivery_configuration.key
    }
  }

  tags = { Name = local.name }

  lifecycle {
    # Checks the token actually generated, every plan and apply: ElastiCache's
    # AUTH token rules (16-128 characters; punctuation only from !&#$^<>-).
    precondition {
      condition     = can(regex("^[A-Za-z0-9!&#$^<>-]{16,128}$", local.auth_token))
      error_message = "The generated AUTH token breaks ElastiCache's rules (16-128 characters, punctuation only from !&#$^<>-); check local.auth_token_generator."
    }
  }
}

# Log delivery (slow-log, engine-log). Cloud Posse's aws-elasticache-redis
# takes log_delivery_configuration entries naming an existing destination;
# deviation: here each entry names only the log type and format, and this
# component creates its CloudWatch log group, encrypted with log_kms_key_id
# (the key policy must allow logs.<region>.amazonaws.com: kms
# allow_cloudwatch_logs), so the destination cannot be left unencrypted.
locals {
  log_delivery = { for entry in var.log_delivery_configuration : entry.log_type => entry }
}

resource "aws_cloudwatch_log_group" "log_delivery" {
  #checkov:skip=CKV_AWS_338:Retention is an input (log_retention_in_days) and a per-stack cost decision, as on the repo's other log groups
  for_each = local.enabled ? local.log_delivery : {}

  name              = "/aws/elasticache/${local.name}/${each.key}"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_kms_key_id

  tags = { Name = "${local.name}-${each.key}" }
}

# AUTH token. As in Cloud Posse's aws-elasticache-redis component, the token
# is generated here, not passed in, with the same shape as its redis_cluster
# module: 128 characters, override_special "#^-", at least 3 of each class.
# ElastiCache allows 16-128 characters, with punctuation only from !&#$^<>-
# (never '@', '"', '/' or a space). Cloud Posse keeps a stored
# random_password; this one is ephemeral instead. It is regenerated on every
# run but reaches AWS only through the write-only attributes. Each is sent
# when its resource is created (or replaced) and when auth_token_version
# changes, never otherwise. Nothing holds the token in plan or state.
#
# One apply feeds the same value to the secret version and the replication
# group, so the two agree. A cache replacement (a ForceNew change such as
# kms_key_id, or a tainted create) re-creates the secret version alongside
# it (replace_triggered_by below). A secret version replaced alone or
# deleted out of band, or an apply that fails between the two, needs an
# auth_token_version bump: both are then re-sent.
#
# No ephemeral read back from Secrets Manager: the
# CI plan role (ReadOnlyAccess) has no secretsmanager:GetSecretValue, and
# mock_provider tests cannot run a module with any aws ephemeral resource.
ephemeral "random_password" "auth_token" {
  count = local.enabled ? 1 : 0

  length           = local.auth_token_generator.length
  special          = local.auth_token_generator.special
  override_special = local.auth_token_generator.override_special
  min_upper        = local.auth_token_generator.min_upper
  min_lower        = local.auth_token_generator.min_lower
  min_numeric      = local.auth_token_generator.min_numeric
  min_special      = local.auth_token_generator.min_special
}

locals {
  # A local, not inline: tests cannot assert an ephemeral resource's arguments.
  auth_token_generator = {
    length           = 128
    special          = true
    override_special = "#^-"
    min_upper        = 3
    min_lower        = 3
    min_numeric      = 3
    min_special      = 3
  }

  auth_token = one(ephemeral.random_password.auth_token[*].result)

  store_auth_token = local.enabled && var.store_auth_token_in_secrets_manager
}

# The generated token's only durable copy. A consumer (eks-backend-services)
# reads it through an ExternalSecret (JSON key auth_token), the way rds/main's
# RDS-managed master user secret is consumed.
resource "aws_secretsmanager_secret" "auth_token" {
  #checkov:skip=CKV2_AWS_57:Rotated by bumping auth_token_version, which re-sends the token to both this secret and aws_elasticache_replication_group.main; a Secrets Manager rotation alone would desync the two
  count = local.store_auth_token ? 1 : 0

  name        = "redis-auth/${var.tags["Environment"]}/${var.cluster_id}"
  description = "Redis AUTH token for the ${local.name} cache"
  kms_key_id  = var.auth_token_secret_kms_key_id

  recovery_window_in_days = var.auth_token_secret_recovery_window_in_days

  tags = { Name = "${local.name}-auth-token" }
}

resource "aws_secretsmanager_secret_version" "auth_token" {
  count = local.store_auth_token ? 1 : 0

  secret_id = aws_secretsmanager_secret.auth_token[0].id
  secret_string_wo = jsonencode({
    auth_token = local.auth_token
  })
  secret_string_wo_version = var.auth_token_version

  # A new cache gets a fresh token on create; re-create this version in the
  # same apply so the secret carries that token too. On the cache's id only:
  # an in-place update of the cache must not re-create the secret.
  depends_on = [aws_elasticache_replication_group.main]

  lifecycle {
    replace_triggered_by = [aws_elasticache_replication_group.main[0].id]
  }
}

# rotation_policy's own two statements, folding in additional_policy_json --
# see that variable's description for the full rationale.
locals {
  rotation_own_statements = local.enabled ? [{
    Sid      = "AllowElastiCacheAuthTokenRotation"
    Effect   = "Allow"
    Action   = ["elasticache:ModifyReplicationGroup", "elasticache:DescribeReplicationGroups"]
    Resource = aws_elasticache_replication_group.main[0].arn
  }] : []

  rotation_additional_statements = var.additional_policy_json != null ? [
    for i, s in jsondecode(var.additional_policy_json).Statement : merge(s, {
      Sid = "Additional${try(s.Sid, "")}${i}"
    })
  ] : []
}

locals {
  name_prefix = var.name_prefix

  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "network-firewall"
    },
    var.tags
  )
}

data "aws_region" "current" {}

#------------------------------------------------------------------------------
# Stateless Rule Groups
#------------------------------------------------------------------------------
resource "aws_networkfirewall_rule_group" "stateless" {
  for_each = var.stateless_rule_groups

  capacity    = each.value.capacity
  name        = "${local.name_prefix}-stateless-${each.key}"
  type        = "STATELESS"
  description = lookup(each.value, "description", "Stateless rule group ${each.key}")

  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {
        dynamic "stateless_rule" {
          for_each = each.value.rules

          content {
            priority = stateless_rule.value.priority

            rule_definition {
              actions = stateless_rule.value.actions

              match_attributes {
                dynamic "source" {
                  for_each = lookup(stateless_rule.value, "source_cidrs", [])
                  content {
                    address_definition = source.value
                  }
                }

                dynamic "destination" {
                  for_each = lookup(stateless_rule.value, "destination_cidrs", [])
                  content {
                    address_definition = destination.value
                  }
                }

                dynamic "source_port" {
                  for_each = lookup(stateless_rule.value, "source_ports", [])
                  content {
                    from_port = source_port.value.from_port
                    to_port   = source_port.value.to_port
                  }
                }

                dynamic "destination_port" {
                  for_each = lookup(stateless_rule.value, "destination_ports", [])
                  content {
                    from_port = destination_port.value.from_port
                    to_port   = destination_port.value.to_port
                  }
                }

                protocols = lookup(stateless_rule.value, "protocols", null)
              }
            }
          }
        }
      }
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-stateless-${each.key}"
    }
  )
}

#------------------------------------------------------------------------------
# Stateful Rule Groups - Domain List
#------------------------------------------------------------------------------
resource "aws_networkfirewall_rule_group" "stateful_domain" {
  for_each = var.stateful_domain_rule_groups

  capacity    = each.value.capacity
  name        = "${local.name_prefix}-stateful-domain-${each.key}"
  type        = "STATEFUL"
  description = lookup(each.value, "description", "Stateful domain rule group ${each.key}")

  rule_group {
    rule_variables {
      dynamic "ip_sets" {
        for_each = lookup(each.value, "ip_sets", {})
        content {
          key = ip_sets.key
          ip_set {
            definition = ip_sets.value
          }
        }
      }
    }

    rules_source {
      rules_source_list {
        generated_rules_type = each.value.generated_rules_type
        target_types         = each.value.target_types
        targets              = each.value.targets
      }
    }

    stateful_rule_options {
      rule_order = lookup(each.value, "rule_order", "DEFAULT_ACTION_ORDER")
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-stateful-domain-${each.key}"
    }
  )
}

#------------------------------------------------------------------------------
# Stateful Rule Groups - 5-Tuple
#------------------------------------------------------------------------------
resource "aws_networkfirewall_rule_group" "stateful_5tuple" {
  for_each = var.stateful_5tuple_rule_groups

  capacity    = each.value.capacity
  name        = "${local.name_prefix}-stateful-5tuple-${each.key}"
  type        = "STATEFUL"
  description = lookup(each.value, "description", "Stateful 5-tuple rule group ${each.key}")

  rule_group {
    rules_source {
      dynamic "stateful_rule" {
        for_each = each.value.rules

        content {
          action = stateful_rule.value.action
          header {
            destination      = stateful_rule.value.destination
            destination_port = stateful_rule.value.destination_port
            direction        = stateful_rule.value.direction
            protocol         = stateful_rule.value.protocol
            source           = stateful_rule.value.source
            source_port      = stateful_rule.value.source_port
          }
          rule_option {
            keyword = "sid"
            settings = [stateful_rule.value.sid]
          }
        }
      }
    }

    stateful_rule_options {
      rule_order = lookup(each.value, "rule_order", "DEFAULT_ACTION_ORDER")
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-stateful-5tuple-${each.key}"
    }
  )
}

#------------------------------------------------------------------------------
# Stateful Rule Groups - Suricata
#------------------------------------------------------------------------------
resource "aws_networkfirewall_rule_group" "stateful_suricata" {
  for_each = var.stateful_suricata_rule_groups

  capacity    = each.value.capacity
  name        = "${local.name_prefix}-stateful-suricata-${each.key}"
  type        = "STATEFUL"
  description = lookup(each.value, "description", "Stateful Suricata rule group ${each.key}")

  rule_group {
    rules_source {
      rules_string = each.value.rules_string
    }

    stateful_rule_options {
      rule_order = lookup(each.value, "rule_order", "DEFAULT_ACTION_ORDER")
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-stateful-suricata-${each.key}"
    }
  )
}

#------------------------------------------------------------------------------
# Firewall Policy
#------------------------------------------------------------------------------
resource "aws_networkfirewall_firewall_policy" "this" {
  name        = "${local.name_prefix}-policy"
  description = var.firewall_policy_description

  firewall_policy {
    # Stateless default actions
    stateless_default_actions          = var.stateless_default_actions
    stateless_fragment_default_actions = var.stateless_fragment_default_actions

    # Stateless rule group references
    dynamic "stateless_rule_group_reference" {
      for_each = aws_networkfirewall_rule_group.stateless

      content {
        priority     = stateless_rule_group_reference.value.rule_group[0].rules_source[0].stateless_rules_and_custom_actions[0].stateless_rule[0].priority
        resource_arn = stateless_rule_group_reference.value.arn
      }
    }

    # Stateful rule group references
    dynamic "stateful_rule_group_reference" {
      for_each = merge(
        { for k, v in aws_networkfirewall_rule_group.stateful_domain : k => v },
        { for k, v in aws_networkfirewall_rule_group.stateful_5tuple : k => v },
        { for k, v in aws_networkfirewall_rule_group.stateful_suricata : k => v }
      )

      content {
        resource_arn = stateful_rule_group_reference.value.arn
      }
    }

    # Stateful default actions
    stateful_default_actions = var.stateful_default_actions

    # Stateful engine options
    stateful_engine_options {
      rule_order = var.stateful_rule_order
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-policy"
    }
  )
}

#------------------------------------------------------------------------------
# Network Firewall
#------------------------------------------------------------------------------
resource "aws_networkfirewall_firewall" "this" {
  name                = "${local.name_prefix}-firewall"
  description         = var.firewall_description
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn
  vpc_id              = var.vpc_id

  # Subnet mappings for multi-AZ deployment
  dynamic "subnet_mapping" {
    for_each = var.subnet_ids

    content {
      subnet_id = subnet_mapping.value
    }
  }

  delete_protection                 = var.enable_delete_protection
  subnet_change_protection          = var.enable_subnet_change_protection
  firewall_policy_change_protection = var.enable_policy_change_protection

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-firewall"
    }
  )
}

#------------------------------------------------------------------------------
# Logging Configuration
#------------------------------------------------------------------------------
resource "aws_s3_bucket" "flow_logs" {
  count = var.enable_flow_logs_to_s3 ? 1 : 0

  bucket = "${local.name_prefix}-firewall-flow-logs"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-firewall-flow-logs"
    }
  )
}

resource "aws_s3_bucket_versioning" "flow_logs" {
  count = var.enable_flow_logs_to_s3 ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  count = var.enable_flow_logs_to_s3 ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  count = var.enable_flow_logs_to_s3 ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs_to_cloudwatch ? 1 : 0

  name              = "/aws/network-firewall/${local.name_prefix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-firewall-logs"
    }
  )
}

resource "aws_cloudwatch_log_group" "alert_logs" {
  count = var.enable_alert_logs_to_cloudwatch ? 1 : 0

  name              = "/aws/network-firewall/${local.name_prefix}/alert"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-firewall-alert-logs"
    }
  )
}

resource "aws_networkfirewall_logging_configuration" "this" {
  firewall_arn = aws_networkfirewall_firewall.this.arn

  logging_configuration {
    dynamic "log_destination_config" {
      for_each = var.enable_flow_logs_to_s3 ? [1] : []

      content {
        log_destination = {
          bucketName = aws_s3_bucket.flow_logs[0].id
          prefix     = "flow"
        }
        log_destination_type = "S3"
        log_type             = "FLOW"
      }
    }

    dynamic "log_destination_config" {
      for_each = var.enable_flow_logs_to_cloudwatch ? [1] : []

      content {
        log_destination = {
          logGroup = aws_cloudwatch_log_group.flow_logs[0].name
        }
        log_destination_type = "CloudWatchLogs"
        log_type             = "FLOW"
      }
    }

    dynamic "log_destination_config" {
      for_each = var.enable_alert_logs_to_cloudwatch ? [1] : []

      content {
        log_destination = {
          logGroup = aws_cloudwatch_log_group.alert_logs[0].name
        }
        log_destination_type = "CloudWatchLogs"
        log_type             = "ALERT"
      }
    }
  }
}

# AWS WAFv2 web ACL, modelled on Cloud Posse's aws-waf component
# (cloudposse-terraform-components/aws-waf, wrapping cloudposse/terraform-aws-waf),
# written as plain resources like the other root components (see
# components/terraform/s3).
#
# scope = CLOUDFRONT is only valid when this component's own provider region
# is us-east-1 (enforced in variables.tf), independent of where the
# CloudFront distribution itself serves traffic from. A CLOUDFRONT-scope ACL
# is attached to a distribution by setting its web_acl_id to this component's
# `arn` output; aws_wafv2_web_acl_association only supports REGIONAL.

locals {
  enabled = var.enabled

  name        = "${var.tags["Environment"]}-${var.name}"
  metric_name = var.metric_name != "" ? var.metric_name : local.name

  # WAFv2 requires this exact prefix on the log group name -- it is how AWS
  # grants WAF's logging service permission to write to it, with no explicit
  # resource policy needed from this component.
  log_group_name = "aws-waf-logs-${local.name}"
}

resource "aws_wafv2_web_acl" "this" {
  count = local.enabled ? 1 : 0

  name        = local.name
  description = "Managed by Terraform (waf component)"
  scope       = var.scope

  default_action {
    dynamic "allow" {
      for_each = var.default_action == "allow" ? [1] : []
      content {}
    }
    dynamic "block" {
      for_each = var.default_action == "block" ? [1] : []
      content {}
    }
  }

  dynamic "rule" {
    for_each = var.managed_rule_group_statement_rules
    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        dynamic "none" {
          for_each = rule.value.override_action == "none" ? [1] : []
          content {}
        }
        dynamic "count" {
          for_each = rule.value.override_action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = rule.value.vendor_name

          dynamic "rule_action_override" {
            for_each = rule.value.excluded_rules
            content {
              name = rule_action_override.value
              action_to_use {
                count {}
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
        metric_name                = "${local.metric_name}-${rule.value.name}"
        sampled_requests_enabled   = var.sampled_requests_enabled
      }
    }
  }

  dynamic "rule" {
    for_each = var.rate_based_statement_rules
    content {
      name     = rule.value.name
      priority = rule.value.priority

      action {
        dynamic "allow" {
          for_each = rule.value.action == "allow" ? [1] : []
          content {}
        }
        dynamic "block" {
          for_each = rule.value.action == "block" ? [1] : []
          content {}
        }
        dynamic "count" {
          for_each = rule.value.action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        rate_based_statement {
          limit              = rule.value.limit
          aggregate_key_type = rule.value.aggregate_key_type
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
        metric_name                = "${local.metric_name}-${rule.value.name}"
        sampled_requests_enabled   = var.sampled_requests_enabled
      }
    }
  }

  dynamic "rule" {
    for_each = var.byte_match_statement_rules
    content {
      name     = rule.value.name
      priority = rule.value.priority

      action {
        dynamic "allow" {
          for_each = rule.value.action == "allow" ? [1] : []
          content {}
        }
        dynamic "block" {
          for_each = rule.value.action == "block" ? [1] : []
          content {}
        }
        dynamic "count" {
          for_each = rule.value.action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        byte_match_statement {
          search_string         = rule.value.search_string
          positional_constraint = rule.value.positional_constraint

          field_to_match {
            dynamic "single_header" {
              for_each = rule.value.header_name != null ? [rule.value.header_name] : []
              content {
                name = single_header.value
              }
            }
            dynamic "uri_path" {
              for_each = rule.value.header_name == null ? [1] : []
              content {}
            }
          }

          text_transformation {
            priority = rule.value.text_transformation_priority
            type     = rule.value.text_transformation_type
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
        metric_name                = "${local.metric_name}-${rule.value.name}"
        sampled_requests_enabled   = var.sampled_requests_enabled
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
    metric_name                = local.metric_name
    sampled_requests_enabled   = var.sampled_requests_enabled
  }

  tags = { Name = local.name }
}

resource "aws_wafv2_web_acl_association" "this" {
  for_each = local.enabled && var.scope == "REGIONAL" ? toset(var.association_resource_arns) : toset([])

  resource_arn = each.value
  web_acl_arn  = aws_wafv2_web_acl.this[0].arn
}

resource "aws_cloudwatch_log_group" "this" {
  #checkov:skip=CKV_AWS_158:kms_key_arn is an input; unset only when the ACL's region has no matching regional key (e.g. a CLOUDFRONT/us-east-1 ACL alongside a stack-region key)
  count = local.enabled && var.enable_logging ? 1 : 0

  name              = local.log_group_name
  retention_in_days = var.log_group_retention_days
  kms_key_id        = var.kms_key_arn

  tags = { Name = local.log_group_name }
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count = local.enabled && var.enable_logging ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.this[0].arn
  log_destination_configs = [aws_cloudwatch_log_group.this[0].arn]
}

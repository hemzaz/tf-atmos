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

  # WAFv2 requires this exact prefix on the log group name; it does not by
  # itself grant WAF's logging service permission to write to it. Delivery
  # depends on the account-wide AWSWAF-LOGS CloudWatch Logs resource policy
  # that aws_wafv2_web_acl_logging_configuration.this's PutLoggingConfiguration
  # call implicitly creates or extends -- see the explicit
  # aws_cloudwatch_log_resource_policy below, which manages that grant rather
  # than leaving it to the implicit account-wide policy.
  log_group_name = "aws-waf-logs-${local.name}"
}

resource "aws_wafv2_web_acl" "this" {
  #checkov:skip=CKV_AWS_192:No rule list is hardcoded here (rules are a per-instance input); every instance of this component configures AWSManagedRulesKnownBadInputsRuleSet, which covers CVE-2021-44228 (Log4Shell) -- see stacks/catalog/templates/web-application.yaml and serverless-api.yaml
  #checkov:skip=CKV2_AWS_31:aws_wafv2_web_acl_logging_configuration.this covers this ACL via count (gated on var.enable_logging, default true); checkov's graph does not follow the count-indexed association
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
  #checkov:skip=CKV_AWS_158:kms_key_arn is an input; unset only for a CLOUDFRONT-scope (us-east-1) instance, whose region has no matching key in this stack's usual (regional) kms/main -- REGIONAL instances set it
  count = local.enabled && var.enable_logging ? 1 : 0

  name              = local.log_group_name
  retention_in_days = var.log_group_retention_days
  kms_key_id        = var.kms_key_arn

  tags = { Name = local.log_group_name }
}

# aws_wafv2_web_acl_logging_configuration's PutLoggingConfiguration call can
# manage CloudWatch Logs permissions for the aws-waf-logs- prefixed log group
# on its own, but it does so by creating or extending an account-wide,
# unmanaged "AWSWAF-LOGS" resource policy shared by every WAF logging
# configuration in the account/region -- which counts toward the 10
# resource-policy-per-region CloudWatch Logs quota and can hit that policy's
# size limit as more web ACLs are added. Managing a policy scoped to this log
# group explicitly avoids both.
data "aws_caller_identity" "current" {
  count = local.enabled && var.enable_logging ? 1 : 0
}

data "aws_partition" "current" {
  count = local.enabled && var.enable_logging ? 1 : 0
}

data "aws_iam_policy_document" "log_delivery" {
  count = local.enabled && var.enable_logging ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this[0].arn}:*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current[0].account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current[0].partition}:logs:${var.region}:${data.aws_caller_identity.current[0].account_id}:*"]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "waf_logging" {
  count = local.enabled && var.enable_logging ? 1 : 0

  policy_name     = "${local.log_group_name}-logging"
  policy_document = data.aws_iam_policy_document.log_delivery[0].json
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count = local.enabled && var.enable_logging ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.this[0].arn
  log_destination_configs = [aws_cloudwatch_log_group.this[0].arn]

  depends_on = [aws_cloudwatch_log_resource_policy.waf_logging]
}

##############################################
# WAF Web ACL
##############################################

resource "aws_wafv2_web_acl" "main" {
  name  = local.web_acl_name
  scope = var.scope

  default_action {
    dynamic "allow" {
      for_each = var.default_action == "ALLOW" ? [1] : []
      content {}
    }

    dynamic "block" {
      for_each = var.default_action == "BLOCK" ? [1] : []
      content {}
    }
  }

  # Rule: Rate Limiting (Priority 10 - Cheapest, evaluated first)
  dynamic "rule" {
    for_each = var.enable_rate_limiting ? [1] : []
    content {
      name     = "${var.name_prefix}-rate-limit"
      priority = local.priority_rate_limit

      action {
        block {
          custom_response {
            response_code = 429
          }
        }
      }

      statement {
        rate_based_statement {
          limit              = var.rate_limit_per_ip
          aggregate_key_type = "IP"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-rate-limit"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule: Geo-Blocking (Priority 20)
  dynamic "rule" {
    for_each = local.geo_blocking_enabled ? [1] : []
    content {
      name     = "${var.name_prefix}-geo-${local.geo_block_mode}"
      priority = local.priority_geo_blocking

      action {
        dynamic "allow" {
          for_each = local.geo_block_mode == "allow" ? [1] : []
          content {}
        }

        dynamic "block" {
          for_each = local.geo_block_mode == "block" ? [1] : []
          content {}
        }
      }

      statement {
        dynamic "geo_match_statement" {
          for_each = local.geo_block_mode == "block" ? [1] : []
          content {
            country_codes = local.geo_countries
          }
        }

        dynamic "not_statement" {
          for_each = local.geo_block_mode == "allow" ? [1] : []
          content {
            statement {
              geo_match_statement {
                country_codes = local.geo_countries
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-geo-${local.geo_block_mode}"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule: IP Reputation List (Priority 30)
  dynamic "rule" {
    for_each = var.enable_ip_reputation ? [1] : []
    content {
      name     = "${var.name_prefix}-ip-reputation"
      priority = local.priority_ip_reputation

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedIPReputationList"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-ip-reputation"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule: Anonymous IP List (Priority 40)
  dynamic "rule" {
    for_each = var.enable_anonymous_ip_list ? [1] : []
    content {
      name     = "${var.name_prefix}-anonymous-ip"
      priority = local.priority_anonymous_ip

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesAnonymousIpList"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-anonymous-ip"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule: Known Bad Inputs (Priority 50)
  dynamic "rule" {
    for_each = var.enable_known_bad_inputs ? [1] : []
    content {
      name     = "${var.name_prefix}-known-bad-inputs"
      priority = local.priority_known_bad_inputs

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesKnownBadInputsRuleSet"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-known-bad-inputs"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule: Core Rule Set (OWASP Top 10) (Priority 60)
  dynamic "rule" {
    for_each = var.enable_core_rule_set ? [1] : []
    content {
      name     = "${var.name_prefix}-core-rule-set"
      priority = local.priority_core_rule_set

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesCommonRuleSet"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-core-rule-set"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule: SQL Database Protection (Priority 70)
  dynamic "rule" {
    for_each = var.enable_sql_database_protection ? [1] : []
    content {
      name     = "${var.name_prefix}-sql-database"
      priority = local.priority_sql_database

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesSQLiRuleSet"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-sql-database"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule: Linux OS Protection (Priority 80)
  dynamic "rule" {
    for_each = var.enable_linux_os_protection ? [1] : []
    content {
      name     = "${var.name_prefix}-linux-os"
      priority = local.priority_linux_os

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesLinuxRuleSet"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-linux-os"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule: Unix OS Protection (Priority 90)
  dynamic "rule" {
    for_each = var.enable_unix_os_protection ? [1] : []
    content {
      name     = "${var.name_prefix}-unix-os"
      priority = local.priority_unix_os

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesUnixRuleSet"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-unix-os"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule: Windows OS Protection (Priority 100)
  dynamic "rule" {
    for_each = var.enable_windows_os_protection ? [1] : []
    content {
      name     = "${var.name_prefix}-windows-os"
      priority = local.priority_windows_os

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesWindowsRuleSet"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-windows-os"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule: PHP Application Protection (Priority 110)
  dynamic "rule" {
    for_each = var.enable_php_application_protection ? [1] : []
    content {
      name     = "${var.name_prefix}-php-app"
      priority = local.priority_php_app

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesPHPRuleSet"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-php-app"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule: WordPress Protection (Priority 120)
  dynamic "rule" {
    for_each = var.enable_wordpress_protection ? [1] : []
    content {
      name     = "${var.name_prefix}-wordpress"
      priority = local.priority_wordpress

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesWordPressRuleSet"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-wordpress"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule: Bot Control (Priority 130)
  dynamic "rule" {
    for_each = var.enable_bot_control ? [1] : []
    content {
      name     = "${var.name_prefix}-bot-control"
      priority = local.priority_bot_control

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = var.bot_control_level == "TARGETED" ? "AWSManagedRulesBotControlRuleSet" : "AWSManagedRulesBotControlRuleSet"

          managed_rule_group_configs {
            aws_managed_rules_bot_control_rule_set {
              inspection_level = var.bot_control_level
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-bot-control"
        sampled_requests_enabled   = true
      }
    }
  }

  # Custom Rules
  dynamic "rule" {
    for_each = var.custom_rules
    content {
      name     = rule.value.name
      priority = rule.value.priority

      action {
        dynamic "allow" {
          for_each = rule.value.action == "ALLOW" ? [1] : []
          content {}
        }

        dynamic "block" {
          for_each = rule.value.action == "BLOCK" ? [1] : []
          content {}
        }

        dynamic "count" {
          for_each = rule.value.action == "COUNT" ? [1] : []
          content {}
        }
      }

      statement {
        dynamic "byte_match_statement" {
          for_each = rule.value.statement.byte_match_statement != null ? [rule.value.statement.byte_match_statement] : []
          content {
            positional_constraint = byte_match_statement.value.positional_constraint
            search_string         = byte_match_statement.value.search_string

            field_to_match {
              dynamic "uri_path" {
                for_each = byte_match_statement.value.field_to_match.uri_path == true ? [1] : []
                content {}
              }

              dynamic "body" {
                for_each = byte_match_statement.value.field_to_match.body == true ? [1] : []
                content {}
              }
            }

            dynamic "text_transformation" {
              for_each = byte_match_statement.value.text_transformation
              content {
                priority = text_transformation.key
                type     = text_transformation.value
              }
            }
          }
        }

        dynamic "size_constraint_statement" {
          for_each = rule.value.statement.size_constraint_statement != null ? [rule.value.statement.size_constraint_statement] : []
          content {
            comparison_operator = size_constraint_statement.value.comparison_operator
            size                = size_constraint_statement.value.size

            field_to_match {
              dynamic "uri_path" {
                for_each = size_constraint_statement.value.field_to_match.uri_path == true ? [1] : []
                content {}
              }

              dynamic "body" {
                for_each = size_constraint_statement.value.field_to_match.body == true ? [1] : []
                content {}
              }
            }

            dynamic "text_transformation" {
              for_each = size_constraint_statement.value.text_transformation
              content {
                priority = text_transformation.key
                type     = text_transformation.value
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.value.name
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.web_acl_name
    sampled_requests_enabled   = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.web_acl_name
    }
  )
}

##############################################
# WAF Logging Configuration
##############################################

# S3 Bucket for WAF Logs
resource "aws_s3_bucket" "waf_logs" {
  count = local.create_s3_bucket ? 1 : 0

  bucket = local.s3_bucket_name

  tags = merge(
    local.common_tags,
    {
      Name = local.s3_bucket_name
    }
  )
}

resource "aws_s3_bucket_public_access_block" "waf_logs" {
  count = local.create_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.waf_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "waf_logs" {
  count = local.create_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.waf_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "waf_logs" {
  count = local.create_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.waf_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "waf_logs" {
  count = local.create_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.waf_logs[0].id

  rule {
    id     = "delete-old-logs"
    status = "Enabled"

    expiration {
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# CloudWatch Log Group for WAF Logs
resource "aws_cloudwatch_log_group" "waf_logs" {
  count = local.create_cloudwatch_log_group ? 1 : 0

  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = local.log_group_name
    }
  )
}

# WAF Logging Configuration
resource "aws_wafv2_web_acl_logging_configuration" "main" {
  count = var.enable_logging ? 1 : 0

  resource_arn = aws_wafv2_web_acl.main.arn

  log_destination_configs = [local.log_destination_arn_computed]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }

  depends_on = [
    aws_s3_bucket.waf_logs,
    aws_cloudwatch_log_group.waf_logs
  ]
}

##############################################
# Resource Associations
##############################################

resource "aws_wafv2_web_acl_association" "main" {
  count = length(var.resource_arns)

  resource_arn = var.resource_arns[count.index]
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

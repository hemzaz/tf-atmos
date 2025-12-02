##############################################
# Athena Workgroup
##############################################

resource "aws_athena_workgroup" "main" {
  name        = var.workgroup_name
  description = var.description
  state       = var.state

  configuration {
    bytes_scanned_cutoff_per_query     = var.bytes_scanned_cutoff
    enforce_workgroup_configuration    = var.enforce_workgroup_config
    publish_cloudwatch_metrics_enabled = var.enable_cloudwatch_metrics

    result_configuration {
      output_location = var.output_location

      dynamic "encryption_configuration" {
        for_each = var.encryption_option != null ? [1] : []
        content {
          encryption_option = var.encryption_option
          kms_key_arn       = var.kms_key_arn
        }
      }

      dynamic "acl_configuration" {
        for_each = var.s3_acl_option != null ? [1] : []
        content {
          s3_acl_option = var.s3_acl_option
        }
      }

      expected_bucket_owner = var.expected_bucket_owner
    }

    dynamic "engine_version" {
      for_each = var.engine_version != null ? [1] : []
      content {
        selected_engine_version = var.engine_version
      }
    }

    requester_pays_enabled = var.requester_pays_enabled
  }

  tags = merge(
    var.tags,
    {
      Name      = var.workgroup_name
      Module    = "athena-workgroup"
      ManagedBy = "terraform"
    }
  )

  force_destroy = var.force_destroy
}

##############################################
# Named Queries
##############################################

resource "aws_athena_named_query" "main" {
  for_each = var.named_queries

  name        = each.key
  workgroup   = aws_athena_workgroup.main.id
  database    = each.value.database
  query       = each.value.query
  description = lookup(each.value, "description", null)
}

##############################################
# Data Catalog
##############################################

resource "aws_athena_data_catalog" "main" {
  for_each = var.data_catalogs

  name        = each.key
  type        = each.value.type
  description = lookup(each.value, "description", null)

  parameters = merge(
    lookup(each.value, "parameters", {}),
    each.value.type == "GLUE" ? {
      catalog-id = data.aws_caller_identity.current.account_id
    } : {}
  )

  tags = merge(
    var.tags,
    {
      Name      = each.key
      ManagedBy = "terraform"
    }
  )
}

##############################################
# Prepared Statements
##############################################

resource "aws_athena_prepared_statement" "main" {
  for_each = var.prepared_statements

  name            = each.key
  workgroup       = aws_athena_workgroup.main.name
  query_statement = each.value.query
  description     = lookup(each.value, "description", null)
}

##############################################
# CloudWatch Log Group
##############################################

resource "aws_cloudwatch_log_group" "workgroup" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/athena/workgroup/${var.workgroup_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name      = "${var.workgroup_name}-logs"
      ManagedBy = "terraform"
    }
  )
}

##############################################
# CloudWatch Alarms
##############################################

resource "aws_cloudwatch_metric_alarm" "query_execution_time" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.workgroup_name}-high-query-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "EngineExecutionTime"
  namespace           = "AWS/Athena"
  period              = 300
  statistic           = "Average"
  threshold           = var.query_execution_threshold_ms
  alarm_description   = "Athena query execution time is high"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    WorkGroup = aws_athena_workgroup.main.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "data_scanned" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.workgroup_name}-high-data-scanned"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DataScannedInBytes"
  namespace           = "AWS/Athena"
  period              = 300
  statistic           = "Sum"
  threshold           = var.data_scanned_threshold_bytes
  alarm_description   = "Athena is scanning large amounts of data"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    WorkGroup = aws_athena_workgroup.main.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "query_planning_time" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.workgroup_name}-high-planning-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "QueryPlanningTime"
  namespace           = "AWS/Athena"
  period              = 300
  statistic           = "Average"
  threshold           = var.query_planning_threshold_ms
  alarm_description   = "Athena query planning time is high"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    WorkGroup = aws_athena_workgroup.main.name
  }

  tags = var.tags
}

##############################################
# Cost Control - Budget Alert
##############################################

resource "aws_cloudwatch_metric_alarm" "cost_control" {
  count = var.enable_cost_control ? 1 : 0

  alarm_name          = "${var.workgroup_name}-cost-threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DataScannedInBytes"
  namespace           = "AWS/Athena"
  period              = 86400
  statistic           = "Sum"
  threshold           = var.daily_cost_threshold_bytes
  alarm_description   = "Athena daily data scanned exceeds cost threshold"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    WorkGroup = aws_athena_workgroup.main.name
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.workgroup_name}-cost-control"
      Type = "Cost"
    }
  )
}

##############################################
# IAM Policy for Workgroup Access
##############################################

data "aws_iam_policy_document" "workgroup_access" {
  count = var.create_iam_policy ? 1 : 0

  statement {
    sid    = "AthenaWorkgroupAccess"
    effect = "Allow"
    actions = [
      "athena:GetWorkGroup",
      "athena:StartQueryExecution",
      "athena:StopQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:GetQueryResultsStream",
      "athena:ListQueryExecutions",
      "athena:ListNamedQueries",
      "athena:GetNamedQuery",
      "athena:BatchGetNamedQuery",
      "athena:BatchGetQueryExecution"
    ]
    resources = [
      aws_athena_workgroup.main.arn
    ]
  }

  statement {
    sid    = "GlueCatalogAccess"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetPartitions",
      "glue:GetPartition",
      "glue:BatchGetPartition"
    ]
    resources = [
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/*",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/*"
    ]
  }

  statement {
    sid    = "S3OutputAccess"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "${var.output_bucket_arn}",
      "${var.output_bucket_arn}/*"
    ]
  }

  dynamic "statement" {
    for_each = var.source_bucket_arns
    content {
      sid    = "S3SourceAccess${statement.key}"
      effect = "Allow"
      actions = [
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket"
      ]
      resources = [
        statement.value,
        "${statement.value}/*"
      ]
    }
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid    = "KMSAccess"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey"
      ]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_policy" "workgroup_access" {
  count = var.create_iam_policy ? 1 : 0

  name        = "${var.workgroup_name}-access"
  description = "IAM policy for Athena workgroup ${var.workgroup_name}"
  policy      = data.aws_iam_policy_document.workgroup_access[0].json

  tags = var.tags
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

##############################################
# Glue Catalog Database
##############################################

resource "aws_glue_catalog_database" "main" {
  name        = var.database_name
  description = var.database_description

  dynamic "target_database" {
    for_each = var.catalog_id != null ? [1] : []
    content {
      catalog_id    = var.catalog_id
      database_name = var.database_name
    }
  }

  tags = merge(
    var.tags,
    {
      Name      = var.database_name
      Module    = "glue-catalog"
      ManagedBy = "terraform"
    }
  )
}

##############################################
# Glue Catalog Tables
##############################################

resource "aws_glue_catalog_table" "main" {
  for_each = var.tables

  name          = each.key
  database_name = aws_glue_catalog_database.main.name
  description   = lookup(each.value, "description", null)
  table_type    = lookup(each.value, "table_type", "EXTERNAL_TABLE")
  owner         = lookup(each.value, "owner", "hadoop")

  dynamic "storage_descriptor" {
    for_each = lookup(each.value, "storage_descriptor", null) != null ? [each.value.storage_descriptor] : []
    content {
      location      = lookup(storage_descriptor.value, "location", null)
      input_format  = lookup(storage_descriptor.value, "input_format", "org.apache.hadoop.mapred.TextInputFormat")
      output_format = lookup(storage_descriptor.value, "output_format", "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat")
      compressed    = lookup(storage_descriptor.value, "compressed", false)

      dynamic "ser_de_info" {
        for_each = lookup(storage_descriptor.value, "ser_de_info", null) != null ? [storage_descriptor.value.ser_de_info] : []
        content {
          name                  = lookup(ser_de_info.value, "name", null)
          serialization_library = lookup(ser_de_info.value, "serialization_library", "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe")
          parameters            = lookup(ser_de_info.value, "parameters", {})
        }
      }

      dynamic "columns" {
        for_each = lookup(storage_descriptor.value, "columns", [])
        content {
          name    = columns.value.name
          type    = columns.value.type
          comment = lookup(columns.value, "comment", null)
        }
      }

      dynamic "sort_columns" {
        for_each = lookup(storage_descriptor.value, "sort_columns", [])
        content {
          column     = sort_columns.value.column
          sort_order = sort_columns.value.sort_order
        }
      }

      dynamic "skewed_info" {
        for_each = lookup(storage_descriptor.value, "skewed_info", null) != null ? [storage_descriptor.value.skewed_info] : []
        content {
          skewed_column_names               = lookup(skewed_info.value, "skewed_column_names", [])
          skewed_column_value_location_maps = lookup(skewed_info.value, "skewed_column_value_location_maps", {})
          skewed_column_values              = lookup(skewed_info.value, "skewed_column_values", [])
        }
      }
    }
  }

  dynamic "partition_keys" {
    for_each = lookup(each.value, "partition_keys", [])
    content {
      name    = partition_keys.value.name
      type    = partition_keys.value.type
      comment = lookup(partition_keys.value, "comment", null)
    }
  }

  parameters = lookup(each.value, "parameters", {})
}

##############################################
# Glue Crawler
##############################################

resource "aws_glue_crawler" "main" {
  for_each = var.crawlers

  name          = "${var.database_name}-${each.key}"
  database_name = aws_glue_catalog_database.main.name
  role          = aws_iam_role.crawler.arn
  description   = lookup(each.value, "description", null)

  dynamic "s3_target" {
    for_each = lookup(each.value, "s3_targets", [])
    content {
      path                = s3_target.value.path
      exclusions          = lookup(s3_target.value, "exclusions", [])
      sample_size         = lookup(s3_target.value, "sample_size", null)
      connection_name     = lookup(s3_target.value, "connection_name", null)
      event_queue_arn     = lookup(s3_target.value, "event_queue_arn", null)
      dlq_event_queue_arn = lookup(s3_target.value, "dlq_event_queue_arn", null)
    }
  }

  dynamic "jdbc_target" {
    for_each = lookup(each.value, "jdbc_targets", [])
    content {
      connection_name = jdbc_target.value.connection_name
      path            = jdbc_target.value.path
      exclusions      = lookup(jdbc_target.value, "exclusions", [])
    }
  }

  dynamic "dynamodb_target" {
    for_each = lookup(each.value, "dynamodb_targets", [])
    content {
      path      = dynamodb_target.value.path
      scan_all  = lookup(dynamodb_target.value, "scan_all", true)
      scan_rate = lookup(dynamodb_target.value, "scan_rate", null)
    }
  }

  dynamic "schema_change_policy" {
    for_each = lookup(each.value, "schema_change_policy", null) != null ? [each.value.schema_change_policy] : []
    content {
      delete_behavior = lookup(schema_change_policy.value, "delete_behavior", "LOG")
      update_behavior = lookup(schema_change_policy.value, "update_behavior", "LOG")
    }
  }

  dynamic "recrawl_policy" {
    for_each = lookup(each.value, "recrawl_policy", null) != null ? [each.value.recrawl_policy] : []
    content {
      recrawl_behavior = lookup(recrawl_policy.value, "recrawl_behavior", "CRAWL_EVERYTHING")
    }
  }

  dynamic "lineage_configuration" {
    for_each = lookup(each.value, "enable_lineage", false) ? [1] : []
    content {
      crawler_lineage_settings = "ENABLE"
    }
  }

  configuration = lookup(each.value, "configuration", null)
  schedule      = lookup(each.value, "schedule", null)

  tags = merge(
    var.tags,
    {
      Name      = "${var.database_name}-${each.key}"
      ManagedBy = "terraform"
    }
  )
}

##############################################
# IAM Role for Crawler
##############################################

resource "aws_iam_role" "crawler" {
  name = "${var.database_name}-crawler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "glue.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "crawler_s3" {
  count = length(var.s3_data_locations) > 0 ? 1 : 0

  name = "${var.database_name}-crawler-s3"
  role = aws_iam_role.crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = flatten([
          for location in var.s3_data_locations : [
            location,
            "${location}/*"
          ]
        ])
      }
    ]
  })
}

##############################################
# Glue Schema Registry
##############################################

resource "aws_glue_registry" "main" {
  count = var.create_schema_registry ? 1 : 0

  registry_name = "${var.database_name}-registry"
  description   = "Schema registry for ${var.database_name}"

  tags = merge(
    var.tags,
    {
      Name      = "${var.database_name}-registry"
      ManagedBy = "terraform"
    }
  )
}

resource "aws_glue_schema" "main" {
  for_each = var.schemas

  schema_name       = each.key
  registry_arn      = aws_glue_registry.main[0].arn
  data_format       = lookup(each.value, "data_format", "AVRO")
  compatibility     = lookup(each.value, "compatibility", "BACKWARD")
  schema_definition = each.value.schema_definition
  description       = lookup(each.value, "description", null)

  tags = merge(
    var.tags,
    {
      Name      = each.key
      ManagedBy = "terraform"
    }
  )
}

##############################################
# Data Quality Ruleset
##############################################

resource "aws_glue_data_quality_ruleset" "main" {
  for_each = var.data_quality_rulesets

  name        = "${var.database_name}-${each.key}"
  description = lookup(each.value, "description", null)
  ruleset     = each.value.ruleset

  target_table {
    database_name = aws_glue_catalog_database.main.name
    table_name    = each.value.table_name
  }

  tags = merge(
    var.tags,
    {
      Name      = "${var.database_name}-${each.key}"
      ManagedBy = "terraform"
    }
  )
}

##############################################
# CloudWatch Alarms
##############################################

resource "aws_cloudwatch_metric_alarm" "crawler_failed" {
  for_each = var.enable_monitoring ? var.crawlers : {}

  alarm_name          = "${var.database_name}-${each.key}-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  namespace           = "Glue"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Glue crawler ${each.key} has failed tasks"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobName = "${var.database_name}-${each.key}"
  }

  tags = var.tags
}

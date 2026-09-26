# One Glue catalog database and everything that populates and processes it
# per instance: catalog tables, crawlers, ETL jobs, triggers, the IAM role
# they share, a KMS security configuration and, optionally, the account's
# Data Catalog encryption settings. Modelled on Cloud Posse's aws-glue-*
# components (aws-glue-catalog-database, aws-glue-catalog-table,
# aws-glue-crawler, aws-glue-job, aws-glue-trigger, aws-glue-iam), which wrap
# the matching cloudposse/terraform-aws-glue submodules. Folded into ONE
# component (an owner decision for this repo) and written as plain
# resources, like this repo's other root components.
#
# Differences from upstream (see README.md):
# - The role gets a scoped inline policy instead of the AWS managed
#   AWSGlueServiceRole (which grants glue:* style actions and S3 access on
#   "*"-style resources): catalog actions on this database's own ARNs, logs
#   on /aws-glue/*, S3 on the buckets this instance reads/writes, KMS on
#   kms_key_arn.
# - Job scripts are uploaded by this component (aws_s3_object, SSE-KMS) to
#   assets_bucket_name, instead of taking a pre-uploaded script_location.
# - Lake Formation permissions (upstream's aws_lakeformation_permissions)
#   are not granted: this repo's accounts use the IAM_ALLOWED_PRINCIPALS
#   model (create_table_default_permissions), under which Lake Formation
#   adds nothing.

locals {
  enabled = var.enabled

  name = "${var.tags["Environment"]}-${var.name}"
  # Glue catalog database names allow only lowercase letters, digits and
  # underscores (no hyphens) - see var.name's description.
  database_name = replace(local.name, "-", "_")

  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id

  catalog_arn     = "arn:${local.partition}:glue:${local.region}:${local.account_id}:catalog"
  database_arn    = "arn:${local.partition}:glue:${local.region}:${local.account_id}:database/${local.database_name}"
  tables_arn      = "arn:${local.partition}:glue:${local.region}:${local.account_id}:table/${local.database_name}/*"
  log_group_arn   = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws-glue/*"
  log_streams_arn = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws-glue/*:log-stream:*"

  # "s3://my-bucket/prefix/" -> "my-bucket"
  s3_target_buckets = flatten([
    for c in values(var.crawlers) : [for t in c.s3_targets : split("/", trimprefix(t.path, "s3://"))[0]]
  ])
  table_buckets = [for t in values(var.tables) : split("/", trimprefix(t.location, "s3://"))[0]]

  # Read access: everything a crawler crawls (s3 targets directly, catalog
  # targets through their tables' locations) plus the job inputs.
  read_buckets  = distinct(concat(local.s3_target_buckets, local.table_buckets, var.s3_read_buckets))
  write_buckets = distinct(var.s3_write_buckets)

  has_jobs = length(var.jobs) > 0

  script_prefix = "scripts/${local.name}"
  temp_prefix   = "temporary/${local.name}"

  # Partition projection: when a table enables it and does not set its own
  # storage.location.template, derive one from the location and partition
  # keys (<location>k1=${k1}/k2=${k2}/), matching the Hive-style prefixes
  # Firehose writes.
  table_parameters = {
    for k, t in var.tables : k => merge(
      lookup(t.parameters, "projection.enabled", "false") == "true" && length(t.partition_keys) > 0 ? {
        "storage.location.template" = "${t.location}${join("/", [for p in t.partition_keys : "${p.name}=$${${p.name}}"])}/"
      } : {},
      t.parameters,
    )
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Catalog database and tables
# -----------------------------------------------------------------------------

resource "aws_glue_catalog_database" "this" {
  count = local.enabled ? 1 : 0

  name         = local.database_name
  description  = var.database_description != "" ? var.database_description : null
  location_uri = var.location_uri != "" ? var.location_uri : null

  dynamic "create_table_default_permission" {
    for_each = var.create_table_default_permissions

    content {
      permissions = create_table_default_permission.value.permissions

      principal {
        data_lake_principal_identifier = create_table_default_permission.value.principal.data_lake_principal_identifier
      }
    }
  }

  tags = { Name = local.database_name }
}

resource "aws_glue_catalog_table" "this" {
  for_each = local.enabled ? var.tables : {}

  name          = each.key
  database_name = aws_glue_catalog_database.this[0].name
  description   = each.value.description
  table_type    = each.value.table_type
  parameters    = local.table_parameters[each.key]

  storage_descriptor {
    location      = each.value.location
    input_format  = each.value.input_format
    output_format = each.value.output_format
    compressed    = each.value.compressed

    ser_de_info {
      serialization_library = each.value.serialization_library
      parameters            = each.value.ser_de_parameters
    }

    dynamic "columns" {
      for_each = each.value.columns

      content {
        name    = columns.value.name
        type    = columns.value.type
        comment = columns.value.comment
      }
    }
  }

  dynamic "partition_keys" {
    for_each = each.value.partition_keys

    content {
      name    = partition_keys.value.name
      type    = partition_keys.value.type
      comment = partition_keys.value.comment
    }
  }
}

# The Data Catalog's own encryption (metadata at rest and connection
# passwords) is ONE setting per account and region, not per database: only
# one glue instance per account/region may set enable_data_catalog_encryption,
# or two instances overwrite each other's settings on every apply.
resource "aws_glue_data_catalog_encryption_settings" "this" {
  count = local.enabled && var.enable_data_catalog_encryption ? 1 : 0

  data_catalog_encryption_settings {
    connection_password_encryption {
      return_connection_password_encrypted = true
      aws_kms_key_id                       = var.kms_key_arn
    }

    encryption_at_rest {
      catalog_encryption_mode = "SSE-KMS"
      sse_aws_kms_key_id      = var.kms_key_arn
    }
  }
}

# -----------------------------------------------------------------------------
# IAM role shared by every crawler and job in the instance
# -----------------------------------------------------------------------------

# glue.amazonaws.com trust, scoped to this account. There is no single
# crawler/job ARN to scope aws:SourceArn to (the role is shared), so
# aws:SourceAccount is the condition.
resource "aws_iam_role" "this" {
  count = local.enabled ? 1 : 0

  name = "${local.name}-glue"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "glue.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })

  tags = { Name = "${local.name}-glue" }
}

# Catalog access limited to this instance's own database and its tables
# (crawlers create/update tables and partitions; jobs read/write them via
# --enable-glue-datacatalog), CloudWatch Logs limited to the /aws-glue/*
# log groups Glue writes to (logs:AssociateKmsKey: the security
# configuration encrypts those log groups with kms_key_arn), and Glue's own
# job metrics, which have no resource ARN and are scoped by namespace.
resource "aws_iam_role_policy" "service" {
  count = local.enabled ? 1 : 0

  name = "${local.name}-glue-service"
  role = aws_iam_role.this[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowOwnCatalogDatabase"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetTables",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition",
          "glue:CreatePartition",
          "glue:BatchCreatePartition",
          "glue:UpdatePartition",
          "glue:BatchUpdatePartition",
        ]
        Resource = [local.catalog_arn, local.database_arn, local.tables_arn]
      },
      {
        Sid      = "AllowGlueLogGroups"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:AssociateKmsKey"]
        Resource = local.log_group_arn
      },
      {
        Sid      = "AllowGlueLogStreams"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = local.log_streams_arn
      },
      {
        Sid       = "AllowGlueMetrics"
        Effect    = "Allow"
        Action    = "cloudwatch:PutMetricData"
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = "Glue" } }
      },
    ]
  })
}

# The security configuration encrypts CloudWatch Logs, job bookmarks and S3
# output with kms_key_arn, and the crawlers/jobs read SSE-KMS objects and
# the (optionally KMS-encrypted) catalog. kms/main's key policy delegates to
# the account root, so this identity policy is sufficient; the logs service
# principal itself is covered by kms/main's allow_cloudwatch_logs.
resource "aws_iam_role_policy" "kms" {
  count = local.enabled ? 1 : 0

  name = "${local.name}-glue-kms"
  role = aws_iam_role.this[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowGlueKMSUsage"
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
      Resource = var.kms_key_arn
    }]
  })
}

# Read on exactly the buckets this instance crawls or reads (bucket-level
# ListBucket, object-level GetObject), write on s3_write_buckets, and - when
# there are jobs - read on this instance's own script prefix and read/write
# on its own temporary prefix in assets_bucket_name.
resource "aws_iam_role_policy" "s3" {
  count = local.enabled && (length(local.read_buckets) > 0 || length(local.write_buckets) > 0 || local.has_jobs) ? 1 : 0

  name = "${local.name}-glue-s3"
  role = aws_iam_role.this[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      length(local.read_buckets) > 0 ? [
        {
          Sid      = "AllowListReadBuckets"
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
          Resource = [for b in local.read_buckets : "arn:${local.partition}:s3:::${b}"]
        },
        {
          Sid      = "AllowReadObjects"
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = [for b in local.read_buckets : "arn:${local.partition}:s3:::${b}/*"]
        },
      ] : [],
      length(local.write_buckets) > 0 ? [
        {
          Sid      = "AllowListWriteBuckets"
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
          Resource = [for b in local.write_buckets : "arn:${local.partition}:s3:::${b}"]
        },
        {
          Sid      = "AllowWriteObjects"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          Resource = [for b in local.write_buckets : "arn:${local.partition}:s3:::${b}/*"]
        },
      ] : [],
      local.has_jobs ? [
        {
          Sid      = "AllowListAssetsBucket"
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
          Resource = "arn:${local.partition}:s3:::${var.assets_bucket_name}"
        },
        {
          Sid      = "AllowReadOwnScripts"
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = "arn:${local.partition}:s3:::${var.assets_bucket_name}/${local.script_prefix}/*"
        },
        {
          Sid      = "AllowOwnTemporaryPrefix"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          Resource = "arn:${local.partition}:s3:::${var.assets_bucket_name}/${local.temp_prefix}/*"
        },
      ] : [],
    )
  })
}

# -----------------------------------------------------------------------------
# Security configuration
# -----------------------------------------------------------------------------

resource "aws_glue_security_configuration" "this" {
  count = local.enabled ? 1 : 0

  name = "${local.name}-security-config"

  encryption_configuration {
    cloudwatch_encryption {
      cloudwatch_encryption_mode = "SSE-KMS"
      kms_key_arn                = var.kms_key_arn
    }

    job_bookmarks_encryption {
      job_bookmarks_encryption_mode = "CSE-KMS"
      kms_key_arn                   = var.kms_key_arn
    }

    s3_encryption {
      s3_encryption_mode = "SSE-KMS"
      kms_key_arn        = var.kms_key_arn
    }
  }
}

# -----------------------------------------------------------------------------
# Crawlers
# -----------------------------------------------------------------------------

resource "aws_glue_crawler" "this" {
  for_each = local.enabled ? var.crawlers : {}

  name                   = "${local.name}-${each.key}"
  description            = each.value.description
  database_name          = aws_glue_catalog_database.this[0].name
  role                   = aws_iam_role.this[0].arn
  schedule               = each.value.schedule
  table_prefix           = each.value.table_prefix
  configuration          = each.value.configuration != null ? jsonencode(each.value.configuration) : null
  security_configuration = aws_glue_security_configuration.this[0].name

  dynamic "s3_target" {
    for_each = each.value.s3_targets

    content {
      path       = s3_target.value.path
      exclusions = length(s3_target.value.exclusions) > 0 ? s3_target.value.exclusions : null
    }
  }

  dynamic "catalog_target" {
    for_each = length(each.value.catalog_tables) > 0 ? [1] : []

    content {
      database_name = aws_glue_catalog_database.this[0].name
      tables        = [for t in each.value.catalog_tables : aws_glue_catalog_table.this[t].name]
    }
  }

  dynamic "schema_change_policy" {
    for_each = each.value.schema_change_policy != null ? [each.value.schema_change_policy] : []

    content {
      delete_behavior = schema_change_policy.value.delete_behavior
      update_behavior = schema_change_policy.value.update_behavior
    }
  }

  tags = { Name = "${local.name}-${each.key}" }

  # A scheduled first crawl can fire moments after apply; ordering creation
  # after the role's policies keeps it from racing IAM propagation.
  depends_on = [
    aws_iam_role_policy.service,
    aws_iam_role_policy.kms,
    aws_iam_role_policy.s3,
  ]
}

# -----------------------------------------------------------------------------
# Jobs
# -----------------------------------------------------------------------------

resource "aws_s3_object" "script" {
  for_each = local.enabled ? var.jobs : {}

  bucket                 = var.assets_bucket_name
  key                    = "${local.script_prefix}/${each.key}.py"
  content                = each.value.script
  content_type           = "text/x-python"
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn

  tags = { Name = "${local.name}-${each.key}" }
}

resource "aws_glue_job" "this" {
  for_each = local.enabled ? var.jobs : {}

  name                   = "${local.name}-${each.key}"
  description            = each.value.description
  role_arn               = aws_iam_role.this[0].arn
  glue_version           = each.value.glue_version
  worker_type            = each.value.worker_type
  number_of_workers      = each.value.number_of_workers
  timeout                = each.value.timeout
  max_retries            = each.value.max_retries
  security_configuration = aws_glue_security_configuration.this[0].name

  command {
    name            = "glueetl"
    script_location = "s3://${var.assets_bucket_name}/${aws_s3_object.script[each.key].key}"
    python_version  = "3"
  }

  execution_property {
    max_concurrent_runs = each.value.max_concurrent_runs
  }

  default_arguments = merge(
    {
      "--job-language"                     = "python"
      "--job-bookmark-option"              = each.value.job_bookmark_option
      "--enable-glue-datacatalog"          = "true"
      "--enable-metrics"                   = "true"
      "--enable-continuous-cloudwatch-log" = "true"
      "--TempDir"                          = "s3://${var.assets_bucket_name}/${local.temp_prefix}/"
      # This instance's own database, for scripts that write through a
      # catalog-updating sink (getSink(enableUpdateCatalog=True)).
      "--catalog_database" = local.database_name
    },
    each.value.default_arguments,
  )

  tags = { Name = "${local.name}-${each.key}" }

  depends_on = [
    aws_iam_role_policy.service,
    aws_iam_role_policy.kms,
    aws_iam_role_policy.s3,
  ]
}

# -----------------------------------------------------------------------------
# Triggers
# -----------------------------------------------------------------------------

# Actions and predicate conditions name this instance's own jobs/crawlers by
# their map key; the component resolves them to the created names.
resource "aws_glue_trigger" "this" {
  for_each = local.enabled ? var.triggers : {}

  name              = "${local.name}-${each.key}"
  description       = each.value.description
  type              = each.value.type
  schedule          = each.value.schedule
  enabled           = each.value.enabled
  start_on_creation = each.value.type == "ON_DEMAND" ? null : each.value.start_on_creation

  dynamic "actions" {
    for_each = each.value.actions

    content {
      job_name               = actions.value.job != null ? aws_glue_job.this[actions.value.job].name : null
      crawler_name           = actions.value.crawler != null ? aws_glue_crawler.this[actions.value.crawler].name : null
      arguments              = actions.value.arguments
      timeout                = actions.value.timeout
      security_configuration = actions.value.job != null ? aws_glue_security_configuration.this[0].name : null
    }
  }

  dynamic "predicate" {
    for_each = each.value.predicate != null ? [each.value.predicate] : []

    content {
      logical = predicate.value.logical

      dynamic "conditions" {
        for_each = predicate.value.conditions

        content {
          job_name         = conditions.value.job != null ? aws_glue_job.this[conditions.value.job].name : null
          crawler_name     = conditions.value.crawler != null ? aws_glue_crawler.this[conditions.value.crawler].name : null
          state            = conditions.value.job != null ? conditions.value.state : null
          crawl_state      = conditions.value.crawler != null ? conditions.value.state : null
          logical_operator = "EQUALS"
        }
      }
    }
  }

  tags = { Name = "${local.name}-${each.key}" }
}

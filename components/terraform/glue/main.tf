# One Glue catalog database plus its crawlers per instance, modelled on Cloud
# Posse's aws-glue-catalog-database and aws-glue-crawler components
# (https://github.com/cloudposse-terraform-components/aws-glue-catalog-database,
# https://github.com/cloudposse-terraform-components/aws-glue-crawler, which
# wrap cloudposse/terraform-aws-glue's glue-catalog-database and glue-crawler
# submodules) and Cloud Posse's aws-glue-iam component (which attaches the
# AWS managed AWSGlueServiceRole policy to a role assumable by
# glue.amazonaws.com). Folded into ONE component (database + crawlers +
# role + security configuration), unlike Cloud Posse's four separate
# components, so a single instance is the unit of deployment for a catalog
# and everything that populates it. Written as plain resources, like this
# repo's other root components.
#
# Not implemented: Cloud Posse's aws-glue-catalog-database also grants Lake
# Formation permissions to the crawler role (aws_lakeformation_permissions),
# to avoid "Insufficient Lake Formation permission(s)" crawler failures on
# accounts that have Lake Formation's fine-grained access control switched
# on. Out of scope here: this repo's accounts use the IAM_ALLOWED_PRINCIPALS
# model (the create_table_default_permissions default in
# stacks/catalog/templates/data-pipeline.yaml), under which Lake Formation
# grants nothing extra. Turning on Lake Formation's own access control would
# need this component to grant aws_lakeformation_permissions to the crawler
# role, same as upstream.
#
# PITFALL: aws_glue_data_catalog_encryption_settings is an account-wide
# singleton (one per account per region, keyed by catalog_id, not by
# database) - deliberately not created here. An instance of this component
# would collide with every other instance's in the same account/region on
# the very first apply after the second one.

locals {
  enabled = var.enabled

  name = "${var.tags["Environment"]}-${var.name}"
  # Glue catalog database names allow only lowercase letters, digits and
  # underscores (no hyphens) - see var.name's description.
  database_name = replace(local.name, "-", "_")

  # The bucket each crawler's s3_targets points into, e.g.
  # "s3://my-bucket/prefix/" -> "my-bucket". Deduplicated across every
  # crawler, so one instance with several crawlers over the same bucket
  # (different prefixes) grants that bucket once, not once per crawler.
  crawler_bucket_names = distinct(flatten([
    for c in values(var.crawlers) : [
      for t in c.s3_targets : split("/", trimprefix(t.path, "s3://"))[0]
    ]
  ]))
  crawler_bucket_arns        = [for b in local.crawler_bucket_names : "arn:${data.aws_partition.current.partition}:s3:::${b}"]
  crawler_bucket_object_arns = [for b in local.crawler_bucket_names : "arn:${data.aws_partition.current.partition}:s3:::${b}/*"]
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

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

# glue.amazonaws.com trust, scoped to this account (Glue crawlers are not
# cross-account by default, so aws:SourceAccount is the whole condition
# available here - there is no crawler ARN to scope aws:SourceArn to before
# the crawler exists, unlike this repo's stepfunctions component, whose
# state machine ARN is derivable from its name alone).
resource "aws_iam_role" "crawler" {
  count = local.enabled ? 1 : 0

  name = "${local.name}-crawler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "glue.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  tags = { Name = "${local.name}-crawler" }
}

# AWS's own baseline for a Glue crawler/job role: CloudWatch Logs delivery,
# generic Glue API access, and S3 read/write scoped to buckets/objects
# tagged or named aws-glue-*. It grants no access to this instance's own
# target buckets (see aws_iam_role_policy.crawler_s3 below for that).
resource "aws_iam_role_policy_attachment" "glue_service_role" {
  count = local.enabled ? 1 : 0

  role       = aws_iam_role.crawler[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Least-privilege read on exactly the buckets this instance's crawlers
# target (derived from crawlers.*.s3_targets.*.path above), split into a
# ListBucket statement (bucket-level ARN) and a GetObject statement
# (object-level ARN) since the two actions apply to different ARN shapes.
resource "aws_iam_role_policy" "crawler_s3" {
  count = local.enabled && length(local.crawler_bucket_names) > 0 ? 1 : 0

  name = "${local.name}-crawler-s3"
  role = aws_iam_role.crawler[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowListTargetBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = local.crawler_bucket_arns
      },
      {
        Sid      = "AllowReadTargetBucketObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = local.crawler_bucket_object_arns
      },
    ]
  })
}

# AWS's docs for Glue security configurations
# (docs.aws.amazon.com/glue/latest/dg/set-up-encryption.html) document that
# the crawler/job role needs kms:Decrypt (source S3 objects under SSE-KMS,
# also read here) plus kms:Encrypt/kms:GenerateDataKey (the security
# configuration's own CloudWatch Logs, job bookmark and S3 output
# encryption) on the CMK; kms/main's key policy delegates to the account
# root, so this role's own IAM policy is sufficient without a key-policy
# change (as in this repo's kinesis and s3 components).
resource "aws_iam_role_policy" "crawler_kms" {
  count = local.enabled ? 1 : 0

  name = "${local.name}-crawler-kms"
  role = aws_iam_role.crawler[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowCrawlerKMSUsage"
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
      Resource = var.kms_key_arn
    }]
  })
}

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

resource "aws_glue_crawler" "this" {
  for_each = local.enabled ? var.crawlers : {}

  name                   = "${local.name}-${each.key}"
  description            = try(each.value.description, null)
  database_name          = local.database_name
  role                   = aws_iam_role.crawler[0].arn
  schedule               = try(each.value.schedule, null)
  table_prefix           = try(each.value.table_prefix, null)
  configuration          = try(each.value.configuration, null) != null ? jsonencode(each.value.configuration) : null
  security_configuration = aws_glue_security_configuration.this[0].name

  dynamic "s3_target" {
    for_each = each.value.s3_targets

    content {
      path       = s3_target.value.path
      exclusions = length(s3_target.value.exclusions) > 0 ? s3_target.value.exclusions : null
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

  # AWS validates the role's S3/KMS permissions when a crawler runs, not
  # when it is created, but ordering creation after the role's policies
  # exist keeps a first crawl (which can fire moments after apply, via
  # `schedule`) from racing an eventually-consistent IAM attachment.
  depends_on = [
    aws_iam_role_policy_attachment.glue_service_role,
    aws_iam_role_policy.crawler_s3,
    aws_iam_role_policy.crawler_kms,
  ]
}

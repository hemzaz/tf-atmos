# One Athena workgroup per instance, plus its saved (named) queries and any
# extra data catalogs, modelled on Cloud Posse's aws-athena component
# (https://github.com/cloudposse-terraform-components/aws-athena, which wraps
# cloudposse/terraform-aws-athena). Written as plain resources, like this
# repo's other root components. Differences from upstream (see README.md):
# - Result encryption is always SSE_KMS with a customer managed key and the
#   workgroup configuration is always enforced (clients cannot override the
#   output location or encryption); upstream also allows SSE_S3/CSE_KMS,
#   optional enforcement and can create its own key.
# - The results bucket is not created here: it comes from a separate `s3`
#   component instance (data-pipeline/s3-athena-results), passed in as
#   output_location, so it gets this repo's standard bucket hardening.
# - No aws_athena_database: databases come from the glue component.
#
# Athena has no service role: queries run under the caller's own identity.
# The query_policy output is a ready-made IAM policy document for such a
# caller (a Step Functions role, a Lambda, a human role), scoped to this
# workgroup, its results bucket and kms_key_arn.

locals {
  enabled = var.enabled
  name    = "${var.tags["Environment"]}-${var.name}"

  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id

  # "s3://my-bucket/prefix/" -> "my-bucket"
  results_bucket = split("/", trimprefix(var.output_location, "s3://"))[0]
  workgroup_arn  = "arn:${local.partition}:athena:${local.region}:${local.account_id}:workgroup/${local.name}"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

resource "aws_athena_workgroup" "this" {
  count = local.enabled ? 1 : 0

  name          = local.name
  description   = var.description != "" ? var.description : null
  force_destroy = var.force_destroy

  configuration {
    # Always enforced: every query uses this workgroup's own output location
    # and SSE_KMS encryption, whatever the client asks for.
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = var.publish_cloudwatch_metrics_enabled
    bytes_scanned_cutoff_per_query     = var.bytes_scanned_cutoff_per_query
    requester_pays_enabled             = var.requester_pays_enabled

    engine_version {
      selected_engine_version = var.engine_version
    }

    result_configuration {
      output_location       = var.output_location
      expected_bucket_owner = local.account_id

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = var.kms_key_arn
      }
    }
  }

  tags = { Name = local.name }
}

resource "aws_athena_named_query" "this" {
  for_each = local.enabled ? var.named_queries : {}

  name        = "${local.name}-${each.key}"
  description = each.value.description != "" ? each.value.description : null
  database    = each.value.database
  workgroup   = aws_athena_workgroup.this[0].name
  query       = each.value.query
}

# Extra data catalogs registered with Athena (upstream's data_catalogs
# input). The account's own Glue Data Catalog is always available as
# AwsDataCatalog and needs no entry here; use this for another account's
# Glue catalog (type GLUE, parameters { catalog-id = <account id> }) or a
# Lambda/Hive connector.
resource "aws_athena_data_catalog" "this" {
  for_each = local.enabled ? var.data_catalogs : {}

  name        = "${local.name}-${each.key}"
  description = each.value.description
  type        = each.value.type
  parameters  = each.value.parameters

  tags = { Name = "${local.name}-${each.key}" }
}

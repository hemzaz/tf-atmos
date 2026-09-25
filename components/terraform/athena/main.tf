# One Athena workgroup per instance, modelled on Cloud Posse's aws-athena
# component (https://github.com/cloudposse-terraform-components/aws-athena,
# which wraps cloudposse/terraform-aws-athena). Written as a plain resource,
# like this repo's other root components. Two differences from upstream:
# result encryption is always SSE_KMS with a customer managed key (upstream
# also allows SSE_S3/CSE_KMS and can create its own key), and the results
# bucket is not created here - it comes from a separate `s3` component
# instance (data-pipeline/s3-athena-results), passed in as `output_location`,
# so the results bucket gets this repo's standard bucket hardening (TLS-only
# policy, public access block, lifecycle rules) instead of the bare bucket
# upstream's `create_s3_bucket` path creates.
#
# No dedicated IAM role: unlike this repo's glue crawler role or
# stepfunctions execution role, Athena queries run under whichever IAM
# identity the caller already has (there is no Athena service role to grant
# kms_key_arn to). kms/main's key policy delegates to the account root, so
# that identity's own IAM policy is what needs
# kms:Decrypt/kms:GenerateDataKey/kms:Encrypt on kms_key_arn plus s3:PutObject
# on the results bucket - grants this component has no role of its own to
# carry, so they belong on the querying principal, outside this component
# (as with kinesis's reader_policy/writer_policy outputs, but here there is
# no fixed principal to build the policy around in advance).

locals {
  enabled = var.enabled
  name    = "${var.tags["Environment"]}-${var.name}"
}

resource "aws_athena_workgroup" "this" {
  count = local.enabled ? 1 : 0

  name          = local.name
  description   = var.description != "" ? var.description : null
  force_destroy = var.force_destroy

  configuration {
    enforce_workgroup_configuration    = var.enforce_workgroup_configuration
    publish_cloudwatch_metrics_enabled = var.publish_cloudwatch_metrics_enabled
    bytes_scanned_cutoff_per_query     = var.bytes_scanned_cutoff_per_query
    requester_pays_enabled             = var.requester_pays_enabled

    engine_version {
      selected_engine_version = var.engine_version
    }

    result_configuration {
      output_location = var.output_location

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

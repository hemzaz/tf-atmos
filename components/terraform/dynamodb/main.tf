# One DynamoDB table per instance, as in Cloud Posse's aws-dynamodb component
# (which wraps cloudposse/dynamodb/aws). Written as a plain resource here, in
# line with the other root components; see README.md for what was trimmed.

locals {
  enabled        = var.enabled
  table_name     = coalesce(var.table_name, "${var.tags["Environment"]}-${var.name}")
  is_provisioned = var.billing_mode == "PROVISIONED"

  # The table's key attributes plus any extra ones, first definition wins
  # (the Cloud Posse module builds the same list).
  key_attributes = concat(
    [{ name = var.hash_key, type = var.hash_key_type }],
    var.range_key != "" ? [{ name = var.range_key, type = var.range_key_type }] : [],
  )
  attributes = [
    for name, defs in {
      for a in concat(local.key_attributes, var.dynamodb_attributes) : a.name => a...
    } : defs[0]
  ]
}

resource "aws_dynamodb_table" "this" {
  count = local.enabled ? 1 : 0

  name                        = local.table_name
  billing_mode                = var.billing_mode
  read_capacity               = local.is_provisioned ? var.read_capacity : null
  write_capacity              = local.is_provisioned ? var.write_capacity : null
  hash_key                    = var.hash_key
  range_key                   = var.range_key != "" ? var.range_key : null
  deletion_protection_enabled = var.deletion_protection_enabled

  stream_enabled   = var.streams_enabled
  stream_view_type = var.streams_enabled ? var.stream_view_type : null

  dynamic "attribute" {
    for_each = local.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_index_map
    content {
      name               = global_secondary_index.value.name
      projection_type    = global_secondary_index.value.projection_type
      non_key_attributes = global_secondary_index.value.non_key_attributes
      read_capacity      = local.is_provisioned ? coalesce(global_secondary_index.value.read_capacity, var.read_capacity) : null
      write_capacity     = local.is_provisioned ? coalesce(global_secondary_index.value.write_capacity, var.write_capacity) : null

      # key_schema, not the GSI's hash_key/range_key arguments, which AWS
      # provider 6 deprecates.
      key_schema {
        attribute_name = global_secondary_index.value.hash_key
        key_type       = "HASH"
      }

      dynamic "key_schema" {
        for_each = global_secondary_index.value.range_key != null ? [global_secondary_index.value.range_key] : []
        content {
          attribute_name = key_schema.value
          key_type       = "RANGE"
        }
      }
    }
  }

  dynamic "local_secondary_index" {
    for_each = var.local_secondary_index_map
    content {
      name               = local_secondary_index.value.name
      range_key          = local_secondary_index.value.range_key
      projection_type    = local_secondary_index.value.projection_type
      non_key_attributes = local_secondary_index.value.non_key_attributes
    }
  }

  # Always a customer managed key: the variable rejects anything but a KMS key ARN.
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.server_side_encryption_kms_key_arn
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  dynamic "ttl" {
    for_each = var.ttl_enabled ? [1] : []
    content {
      enabled        = true
      attribute_name = var.ttl_attribute
    }
  }

  tags = { Name = local.table_name }

  lifecycle {
    precondition {
      condition = alltrue(concat(
        [for i in var.global_secondary_index_map : contains([for a in local.attributes : a.name], i.hash_key)],
        [for i in var.global_secondary_index_map : i.range_key == null || contains([for a in local.attributes : a.name], i.range_key)],
        [for i in var.local_secondary_index_map : contains([for a in local.attributes : a.name], i.range_key)],
      ))
      error_message = "Every index key must be the table's hash/range key or be declared in dynamodb_attributes."
    }

    precondition {
      condition     = length(var.local_secondary_index_map) == 0 || var.range_key != ""
      error_message = "Local secondary indexes need a table range_key."
    }
  }
}

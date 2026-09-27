# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {}

variables {
  region                             = "eu-west-2"
  name                               = "orders"
  hash_key                           = "pk"
  server_side_encryption_kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "defaults_encrypt_with_the_cmk_and_keep_pitr_on" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this[0].name == "test-orders"
    error_message = "The table is named <Environment>-<name> by default."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].billing_mode == "PAY_PER_REQUEST"
    error_message = "billing_mode defaults to PAY_PER_REQUEST."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].server_side_encryption[0].enabled
    error_message = "Server-side encryption must always be on."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].server_side_encryption[0].kms_key_arn == var.server_side_encryption_kms_key_arn
    error_message = "The table must be encrypted with the customer managed key it is given."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].point_in_time_recovery[0].enabled
    error_message = "Point-in-time recovery must be on by default."
  }

  assert {
    condition     = length(aws_dynamodb_table.this[0].ttl) == 0
    error_message = "No TTL block unless ttl_enabled."
  }
}

run "range_key_indexes_and_ttl" {
  command = plan

  variables {
    table_name = "fnx-dev-saga-state"
    range_key  = "sk"
    dynamodb_attributes = [
      { name = "status", type = "S" },
      # A duplicate of a key attribute must not produce a second attribute block.
      { name = "pk", type = "S" },
    ]
    global_secondary_index_map = [
      { name = "status-index", hash_key = "status" },
    ]
    ttl_enabled      = true
    ttl_attribute    = "expires_at"
    streams_enabled  = true
    stream_view_type = "NEW_AND_OLD_IMAGES"
  }

  assert {
    condition     = aws_dynamodb_table.this[0].name == "fnx-dev-saga-state"
    error_message = "table_name overrides the generated name."
  }

  assert {
    condition     = length(aws_dynamodb_table.this[0].attribute) == 3
    error_message = "Attributes are pk, sk and status, each declared once."
  }

  assert {
    condition     = one(aws_dynamodb_table.this[0].global_secondary_index).projection_type == "ALL"
    error_message = "GSI projection_type defaults to ALL."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].ttl[0].attribute_name == "expires_at"
    error_message = "TTL uses ttl_attribute."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].stream_view_type == "NEW_AND_OLD_IMAGES"
    error_message = "stream_view_type is passed through when streams are on."
  }

  assert {
    condition     = tolist(output.global_secondary_index_names) == tolist(["status-index"])
    error_message = "global_secondary_index_names lists the GSIs."
  }
}

run "provisioned_sets_capacity_on_table_and_gsi" {
  command = plan

  variables {
    billing_mode        = "PROVISIONED"
    read_capacity       = 10
    write_capacity      = 4
    dynamodb_attributes = [{ name = "gsi1pk", type = "S" }]
    global_secondary_index_map = [
      { name = "gsi1", hash_key = "gsi1pk", write_capacity = 2 },
    ]
  }

  assert {
    condition     = aws_dynamodb_table.this[0].read_capacity == 10 && aws_dynamodb_table.this[0].write_capacity == 4
    error_message = "PROVISIONED sets the table capacity."
  }

  assert {
    condition     = one(aws_dynamodb_table.this[0].global_secondary_index).read_capacity == 10 && one(aws_dynamodb_table.this[0].global_secondary_index).write_capacity == 2
    error_message = "A GSI inherits the table capacity unless it sets its own."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_dynamodb_table.this) == 0 && output.table_arn == null
    error_message = "enabled = false must create no table."
  }
}

run "rejects_a_non_kms_key" {
  command = plan

  variables {
    server_side_encryption_kms_key_arn = "alias/aws/dynamodb"
  }

  expect_failures = [var.server_side_encryption_kms_key_arn]
}

run "rejects_streams_without_a_view_type" {
  command = plan

  variables {
    streams_enabled = true
  }

  expect_failures = [var.stream_view_type]
}

run "rejects_ttl_without_an_attribute" {
  command = plan

  variables {
    ttl_enabled = true
  }

  expect_failures = [var.ttl_attribute]
}

run "rejects_an_index_on_an_undeclared_attribute" {
  command = plan

  variables {
    global_secondary_index_map = [
      { name = "gsi1", hash_key = "not_declared" },
    ]
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_an_unused_declared_attribute" {
  command = plan

  variables {
    # "status" is declared but used by no key or index (the reverse of the
    # check above): DynamoDB rejects it too.
    dynamodb_attributes = [
      { name = "status", type = "S" },
    ]
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_include_without_non_key_attributes" {
  command = plan

  variables {
    dynamodb_attributes = [{ name = "gsi1pk", type = "S" }]
    global_secondary_index_map = [
      { name = "gsi1", hash_key = "gsi1pk", projection_type = "INCLUDE" },
    ]
  }

  expect_failures = [var.global_secondary_index_map]
}

run "rejects_non_key_attributes_with_projection_type_all" {
  command = plan

  variables {
    # non_key_attributes need not be declared in dynamodb_attributes (AWS
    # does not require them as table attributes), so only gsi1pk is here.
    dynamodb_attributes = [{ name = "gsi1pk", type = "S" }]
    global_secondary_index_map = [
      { name = "gsi1", hash_key = "gsi1pk", projection_type = "ALL", non_key_attributes = ["extra"] },
    ]
  }

  expect_failures = [var.global_secondary_index_map]
}

run "accepts_include_with_non_key_attributes" {
  command = plan

  variables {
    dynamodb_attributes = [{ name = "gsi1pk", type = "S" }]
    global_secondary_index_map = [
      { name = "gsi1", hash_key = "gsi1pk", projection_type = "INCLUDE", non_key_attributes = ["extra"] },
    ]
  }

  assert {
    condition     = one(aws_dynamodb_table.this[0].global_secondary_index).projection_type == "INCLUDE"
    error_message = "INCLUDE with non_key_attributes must be accepted."
  }

  assert {
    condition     = tolist(one(aws_dynamodb_table.this[0].global_secondary_index).non_key_attributes) == tolist(["extra"])
    error_message = "non_key_attributes must be passed through for INCLUDE."
  }
}

run "rejects_lsi_include_without_non_key_attributes" {
  command = plan

  variables {
    range_key = "sk"
    local_secondary_index_map = [
      { name = "lsi1", range_key = "sk", projection_type = "INCLUDE" },
    ]
  }

  expect_failures = [var.local_secondary_index_map]
}

run "rejects_lsi_non_key_attributes_with_projection_type_keys_only" {
  command = plan

  variables {
    range_key = "sk"
    local_secondary_index_map = [
      { name = "lsi1", range_key = "sk", projection_type = "KEYS_ONLY", non_key_attributes = ["extra"] },
    ]
  }

  expect_failures = [var.local_secondary_index_map]
}

run "accepts_attributes_used_only_as_gsi_or_lsi_range_keys" {
  command = plan

  variables {
    # gsi1sk is used only via the GSI range_key branch of the reverse
    # precondition (main.tf's concat list, third element); lsi_sk only via
    # the LSI range_key branch (fourth element). The table's own range_key
    # ("sk") already covers the first element, so neither attribute would be
    # exercised without a dedicated GSI/LSI range key of its own. This guards
    # against a future edit accidentally dropping either branch from the
    # concat list, which would reject valid tables like
    # microservices/dynamodb/service-state (gsi1sk as a GSI range key).
    range_key = "sk"
    dynamodb_attributes = [
      { name = "gsi1sk", type = "S" },
      { name = "lsi_sk", type = "S" },
    ]
    global_secondary_index_map = [
      { name = "gsi1", hash_key = "pk", range_key = "gsi1sk" },
    ]
    local_secondary_index_map = [
      { name = "lsi1", range_key = "lsi_sk" },
    ]
  }

  assert {
    condition     = length(aws_dynamodb_table.this[0].attribute) == 4
    error_message = "Attributes are pk, sk, gsi1sk and lsi_sk, each declared once."
  }

  assert {
    condition     = one(aws_dynamodb_table.this[0].global_secondary_index).name == "gsi1"
    error_message = "The GSI using gsi1sk as its range key must be created."
  }

  assert {
    condition     = one(aws_dynamodb_table.this[0].local_secondary_index).name == "lsi1"
    error_message = "The LSI using lsi_sk as its range key must be created."
  }
}

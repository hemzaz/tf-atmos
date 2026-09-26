output "workgroup_name" {
  description = "Athena workgroup name"
  value       = one(aws_athena_workgroup.this[*].name)
}

output "workgroup_arn" {
  description = "Athena workgroup ARN"
  value       = one(aws_athena_workgroup.this[*].arn)
}

output "named_query_ids" {
  description = "Named query ID per named_queries key"
  value       = { for k, q in aws_athena_named_query.this : k => q.id }
}

output "data_catalog_names" {
  description = "Athena data catalog name per data_catalogs key"
  value       = { for k, c in aws_athena_data_catalog.this : k => c.name }
}

output "results_bucket_name" {
  description = "Bucket query results are written to (from output_location)"
  value       = local.enabled ? local.results_bucket : null
}

output "query_policy" {
  description = "IAM policy document (JSON) for a principal that runs queries in this workgroup: Athena query actions on the workgroup, read/write on the results bucket, KMS on kms_key_arn, Glue catalog read on query_database_names and S3 read on query_source_buckets. null when disabled"
  value = local.enabled ? jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "AllowWorkgroupQueries"
          Effect = "Allow"
          Action = [
            "athena:StartQueryExecution",
            "athena:StopQueryExecution",
            "athena:GetQueryExecution",
            "athena:GetQueryResults",
            "athena:GetWorkGroup",
            "athena:GetNamedQuery",
            "athena:ListNamedQueries",
          ]
          Resource = local.workgroup_arn
        },
        {
          Sid      = "AllowResultsBucket"
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
          Resource = "arn:${local.partition}:s3:::${local.results_bucket}"
        },
        {
          Sid      = "AllowResultsObjects"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
          Resource = "arn:${local.partition}:s3:::${local.results_bucket}/*"
        },
        {
          Sid      = "AllowResultsKMS"
          Effect   = "Allow"
          Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
          Resource = var.kms_key_arn
        },
      ],
      length(var.query_database_names) > 0 ? [
        {
          Sid    = "AllowCatalogRead"
          Effect = "Allow"
          Action = [
            "glue:GetDatabase",
            "glue:GetTable",
            "glue:GetTables",
            "glue:GetPartition",
            "glue:GetPartitions",
            "glue:BatchGetPartition",
          ]
          Resource = concat(
            ["arn:${local.partition}:glue:${local.region}:${local.account_id}:catalog"],
            [for d in var.query_database_names : "arn:${local.partition}:glue:${local.region}:${local.account_id}:database/${d}"],
            [for d in var.query_database_names : "arn:${local.partition}:glue:${local.region}:${local.account_id}:table/${d}/*"],
          )
        },
      ] : [],
      length(var.query_source_buckets) > 0 ? [
        {
          Sid      = "AllowListSourceBuckets"
          Effect   = "Allow"
          Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
          Resource = [for b in var.query_source_buckets : "arn:${local.partition}:s3:::${b}"]
        },
        {
          Sid      = "AllowReadSourceObjects"
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = [for b in var.query_source_buckets : "arn:${local.partition}:s3:::${b}/*"]
        },
      ] : [],
    )
  }) : null
}

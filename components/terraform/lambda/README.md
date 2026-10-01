# lambda

A generic Lambda function: execution role and custom policy, log group, optional VPC security
group, the function (Zip package), trigger permissions (API Gateway, S3, CloudWatch, SNS,
EventBridge, Secrets Manager rotation), async invoke config and destinations, provisioned
concurrency, an alias, CloudWatch alarms, an optional schedule rule, and optional Secrets Manager
rotation configuration.

## Wiring

- Instances: `lambda/data-processor` (all three AWS stacks), `lambda/data-transformer` (staging,
  prod), `lambda/report-generator` (prod), all reading `vpc/services .vpc_id` /
  `.private_subnet_ids` and packaged from S3: `s3_bucket` is `s3/lambda-artifacts .bucket_id`
  (Cloud Posse's aws-lambda takes its bucket from an s3-bucket component the same way), `s3_key`
  `<function_name>/<settings.package_version>.zip`. All are `metadata.enabled: false` until their
  first package is uploaded (`docs/OPERATIONS.md`, "Lambda packages"). `lambda/main` in
  `fnx-local-sandbox` (applied for real by the sandbox workflow)
  and `lambda/api` in `fnx-local-localemu` use `filename`.
- Used by: `apigateway` (`lambda/data-processor .function_invoke_arn` / `.function_name`),
  `monitoring` (`.function_name`).
- The `microservices-platform` template runs two rotation functions from this component
  (`functions/redis-auth-rotation`, `functions/jwt-secret-rotation`).

## Notes

- A Zip package needs exactly one of `filename`, `s3_bucket` + `s3_key`, or `source_dir` (a
  directory under this component, zipped to `.archives/<function_name>.zip`). There is no
  `image_uri` variable, so `package_type = "Image"` cannot be used.
- The S3 packages are built and uploaded by the application repo's CI with `iam/ci`'s
  `lambda_uploader_role_arn`; their sources are not here. Each key is immutable, one per
  release: a new `s3_key` is what redeploys the function (overwriting an object does not,
  without `source_code_hash` or `s3_object_version`). The principal creating the function needs
  `s3:GetObject` on it and `kms:Decrypt` on `kms/main` (the bucket's key); the CI apply role has
  both through `AdministratorAccess`.
- There is no `event_source_mappings` input: the mappings the `data-pipeline`, `batch-processing`
  and `serverless-api` templates set are not applied.
- In a VPC, egress defaults to the region's AWS-managed S3 prefix list; the built-in rules are never
  `0.0.0.0/0`. Add more with `custom_egress_rules` or confine it with
  `vpc_endpoint_prefix_list_ids`.
- Rotation for a secret this function reads is configured here (`rotation_secret_arn`,
  `rotation_days`, with `secretsmanager_source_arn` for the invoke permission), not on the
  `secretsmanager` component; see its README for why.
- With `rotate_immediately = true` (as `redis-auth-rotation` sets), any later change to the rotation
  resource triggers an unscheduled rotation at apply.
- A JWT verifier for `jwt-secret-rotation`'s secret must accept both `AWSCURRENT` and `AWSPREVIOUS`
  for a token's lifetime after each rotation.
- `additional_security_group_ids` attaches extra groups (for example a cache's
  `client_security_group_id`) so the target never reads this function's group back.

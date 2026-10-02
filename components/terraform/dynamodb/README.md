# dynamodb

One DynamoDB table per instance, always encrypted with a customer managed key, point-in-time
recovery on by default. Modelled on Cloud Posse `aws-dynamodb` (input and output names) as a plain
resource.

## Wiring

- No instance in the fnx stacks. `dynamodb/defaults` reads `kms/main .key_arn`; the
  `data-pipeline`, `microservices-platform` and `serverless-api` catalog templates and
  `templates/stacks/serverless-stack.yaml` configure tables.
- Consumers read `.table_name`, `.table_arn` and `.table_stream_arn`.
- Deploys in the `deploy-full-stack` storage layer (it reads only `kms/main`).

## Notes

- `billing_mode` defaults to `PAY_PER_REQUEST` (Cloud Posse: `PROVISIONED`), because the autoscaler
  was not ported. Global tables (`replicas`) and `import_table` were trimmed too.
- `deletion_protection_enabled` defaults to `false`; prod instances must set it `true`.
- A plan fails when an index key is not a declared attribute, when a declared attribute is used by no
  key or index (AWS rejects both), on `INCLUDE` without `non_key_attributes`, or on an LSI without a
  `range_key`.
- `streams_enabled` needs `stream_view_type`, and `ttl_enabled` needs `ttl_attribute`.

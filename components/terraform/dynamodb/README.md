# dynamodb

One `aws_dynamodb_table` per instance, modelled on Cloud Posse's
[aws-dynamodb](https://github.com/cloudposse-terraform-components/aws-dynamodb)
component: same input and output names, trimmed to what this repo uses.
The table is always encrypted with a customer managed KMS key, and
point-in-time recovery is on by default.

## Deployed instances

None in the three fnx stacks yet. The abstract base `dynamodb/defaults`
(`stacks/catalog/dynamodb/defaults.yaml`) wires the key from `kms/main`;
instances inherit it and set `name`, `hash_key` and the rest.

## Inputs / outputs

| Key | Notes |
|---|---|
| `region`, `tags`, `name`, `hash_key`, `server_side_encryption_kms_key_arn` (required) | `tags` must include a non-empty `Environment`; the table is `<Environment>-<name>` unless `table_name` is set. The key must be a KMS key ARN, so the AWS owned and AWS managed keys are refused |
| `table_name` (null) | exact name override, as in Cloud Posse |
| `billing_mode` (`PAY_PER_REQUEST`), `read_capacity` / `write_capacity` (5) | capacities apply only to `PROVISIONED`, to the table and to every GSI that sets none |
| `hash_key_type`, `range_key`, `range_key_type`, `dynamodb_attributes` | attributes are the key attributes plus `dynamodb_attributes`, each declared once |
| `global_secondary_index_map`, `local_secondary_index_map` | `projection_type` defaults to `ALL`; a plan fails if an index key is not a declared attribute, or an LSI is added to a table with no `range_key` |
| `point_in_time_recovery_enabled` (true), `deletion_protection_enabled` (false) | Cloud Posse defaults |
| `streams_enabled` (false) + `stream_view_type`, `ttl_enabled` (false) + `ttl_attribute` | each pair is validated: enabling one requires the other |
| `enabled` (true) | false creates nothing |
| out: `table_name`, `table_id`, `table_arn`, `table_stream_arn`, `table_stream_label`, `global_secondary_index_names`, `local_secondary_index_names`, `hash_key`, `range_key` | same outputs as Cloud Posse; stream outputs are null with streams off |

## Differences from Cloud Posse

- A plain resource instead of the `cloudposse/dynamodb/aws` module, like the
  other root components here; no `context.tf`/null-label, names come from
  `tags.Environment` and `default_tags` carries the tags.
- Encryption: Cloud Posse's `encryption_enabled` is gone and
  `server_side_encryption_kms_key_arn` is required. With it null, Cloud Posse
  falls back to the AWS owned key; this repo requires a customer managed key.
- `billing_mode` defaults to `PAY_PER_REQUEST` (Cloud Posse: `PROVISIONED`),
  because the autoscaler that makes `PROVISIONED` safe was trimmed.
- Trimmed: `autoscaler_*`/`autoscale_*` (application autoscaling),
  `replicas` (global tables need a KMS key per replica region) and
  `import_table`. Index objects take optional capacities and default
  `projection_type`, where Cloud Posse requires every field.
- GSIs use `key_schema` blocks, since AWS provider 6 deprecates the GSI's
  `hash_key`/`range_key` arguments.

## Tests

`tests/dynamodb.tftest.hcl` runs against a mock provider (no credentials):

```
cd components/terraform/dynamodb && terraform init -backend=false && terraform test
```

## Usage

```
atmos terraform plan <instance> -s <stack>   # after adding an instance
```

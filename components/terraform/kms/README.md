# KMS Component

_Last Updated: September 19, 2026_

## Overview

Thin root component that creates a customer managed KMS key (single-region by default)
by wrapping the library module [`_library/security/kms-multi-region`](../_library/security/kms-multi-region/README.md).
Every module input is exposed with the same name, type and default and passed straight
through; the component only adds `region` and applies `tags` as provider `default_tags`.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.16.0, < 2.0.0 |
| aws | ~> 6.65 |

## Usage

```yaml
components:
  terraform:
    kms:
      vars:
        region: "eu-west-2"
        name_prefix: "fnx-prod-production"
        description: "Platform encryption key"
        tags:
          Environment: "production"
```

Multi-region replicas: set `is_multi_region: true` and `replica_regions`. Replicas use the
AWS provider v6 per-resource `region` argument, so no provider alias is needed.

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `region` | AWS region | n/a (required) |
| `tags` | Tags for all resources (provider `default_tags` and the module) | `{}` |

All other inputs (`name_prefix` (required), `description`, `key_spec`, `key_usage`,
`customer_master_key_spec`, `is_multi_region`, `enable_key_rotation`,
`rotation_period_in_days`, `deletion_window_in_days`, `key_policy`,
`enable_default_policy`, `key_administrators`, `key_users`, `key_service_users`,
`alias_name`, `create_alias`, `replica_regions`, `replica_deletion_window_in_days`,
`grants`) are documented in the [library module README](../_library/security/kms-multi-region/README.md).

## Outputs

| Name | Description |
|------|-------------|
| `key_arn` | ARN of the primary KMS key |
| `key_id` | ID of the primary KMS key |
| `alias_name` | Name of the key alias (empty when `create_alias = false`) |
| `alias_arn` | ARN of the key alias (empty when `create_alias = false`) |
| `replica_keys` | Replica keys by region (empty for a single-region key) |

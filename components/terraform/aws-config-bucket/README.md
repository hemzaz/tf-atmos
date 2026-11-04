# aws-config-bucket

The S3 bucket AWS Config delivers configuration snapshots and history to, one per audit stack
(`fnx-ue1-audit` for the US recorders, `fnx-ew1-audit` for the EU ones). Lifecycle retention,
versioning, public-access block and TLS-only access come from Cloud Posse's
`cloudposse/config-storage/aws` 1.0.2.

## Source and deviation

A house copy of Cloud Posse's
[aws-config-bucket](https://github.com/cloudposse-terraform-components/aws-config-bucket)
`src/` at v1.535.1, with Cloud Posse's account-map-bypass providers and account-verification
mixins (mixins v0.5.0) copied unchanged. It is not vendored: upstream hardcodes SSE-S3
(`AES256`) and takes no key, and the owner chose a customer managed key (2026-11-04), which a
`*_override.tf` cannot add. The deviations are listed at the top of `main.tf`: SSE-KMS with the
required `kms_master_key_arn`, `enable_glacier_transition` wired through, TLS-only requests
(`allow_ssl_requests_only`), and upstream's unused `acl` input dropped. Inputs, defaults and outputs are otherwise upstream's; diff against the
upstream tag before a refresh.

## Wiring

- **Naming** comes from the null-label `vars.context` (the catalog entry inherits the
  `vendored` abstract, `stacks/catalog/_base/vendored.yaml`), like the vendored Cloud Posse
  components, so this root module does not validate `tags.Environment`. The bucket is
  `<id>-aws-config`.
- **Providers**: `account_map_enabled: false` with the static `account_map` (the
  `account-map-bypass` abstract); the account-verification mixin then checks the ambient
  credentials are the stack's account.
- **Key (E5a4)**: `kms_master_key_arn` has no default. Each audit stack needs its own key: a
  dedicated `kms` instance whose key policy lets `config.amazonaws.com` use it
  (`kms:GenerateDataKey*`, `kms:Decrypt`), limited by `aws:SourceAccount` to the bucket's
  residency list (the same accounts its bucket policy admits). The bucket reads it with
  `!terraform.state <kms instance> .key_arn`, which needs that instance in
  `dependencies.components` and in an earlier layer of `workflows/deploy-full-stack.yaml`.

## Gotchas

- The validation accepts only a key ARN (`...:key/<id>`): an alias ARN, `alias/aws/s3`, or an
  empty value fails the plan. An AWS managed key's own key ARN has the same shape and cannot be
  told apart statically; the catalog must name the house key.
- S3 does not check the key when the bucket is created: a key the Config service may not use
  only shows up as failed Config deliveries. Prove the key policy before the recorders land.
- No residency bucket policy: config-storage 1.0.2 declares a `policy` input but never uses it, so
  the bucket policy is its own three Allows plus TLS-only. Residency is the key's: the catalog's
  `kms/config-bucket` (`stacks/catalog/aws-config-bucket/`) lets `config.amazonaws.com` use it
  only for the residency's accounts (`allow_config`, `config_source_accounts`).
- `force_destroy` is `false`, as upstream.
- S3 Bucket Keys stay off: config-storage 1.0.2 does not expose `bucket_key_enabled`, so each
  Config delivery is its own KMS request. Small at Config volumes; not worth dropping below
  config-storage for.

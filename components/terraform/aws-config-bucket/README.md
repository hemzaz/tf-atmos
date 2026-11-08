# aws-config-bucket

The S3 bucket AWS Config delivers configuration snapshots and history to, one per audit stack
(`fnx-ue1-audit` for the US recorders, `fnx-ew1-audit` for the EU ones). Lifecycle retention,
versioning, public-access block and TLS-only access come from Cloud Posse's
`cloudposse/s3-log-storage/aws` 1.4.1, called as `cloudposse/config-storage/aws` 1.0.2 calls it;
the bucket policy adds residency Denys to config-storage's statements.

## Source and deviation

A house copy of Cloud Posse's
[aws-config-bucket](https://github.com/cloudposse-terraform-components/aws-config-bucket)
`src/` at v1.535.1, with Cloud Posse's account-map-bypass providers and account-verification
mixins (mixins v0.5.0) copied unchanged. It is not vendored: upstream hardcodes SSE-S3
(`AES256`) and takes no key, and the owner chose a customer managed key (2026-11-04), which a
`*_override.tf` cannot add. config-storage 1.0.2 is inlined (E5a4b, owner 2026-11-05): it builds
the bucket policy from its own statements only and ignores its `policy` input, so `main.tf`
calls s3-log-storage with config-storage's arguments and restates its three statements. The
deviations are listed at the top of `main.tf`: the residency Denys, SSE-KMS with the required
`kms_master_key_arn`, `enable_glacier_transition` wired through, TLS-only requests
(`allow_ssl_requests_only`), and upstream's unused `acl` input dropped. Inputs, defaults and
outputs are otherwise upstream's; diff against the upstream tag and config-storage 1.0.2 before a
refresh.

## Wiring

- **Naming** comes from the null-label `vars.context` (the catalog entry inherits the
  `vendored` abstract, `stacks/catalog/_base/vendored.yaml`), like the vendored Cloud Posse
  components, so this root module does not validate `tags.Environment`. The bucket is
  `<id>-aws-config`.
- **Providers**: `account_map_enabled: false` with the static `account_map` (the
  `account-map-bypass` abstract); the account-verification mixin then checks the ambient
  credentials are the stack's account.
- **Residency (E5a4b)**: the bucket policy denies `config.amazonaws.com` an `s3:PutObject` whose
  `aws:SourceAccount` is not in the residency (`StringNotEquals`, so a request without the key is
  denied too), and one naming any KMS key but `kms_master_key_arn`
  (`StringNotEqualsIfExists` on `s3:x-amz-server-side-encryption-aws-kms-key-id`, so a put relying
  on default encryption passes). The residency is `residency_account_ids`, or, unset, every
  account of `account_map.full_account_map` but `<tenant>-prod-eu` (the US bucket: a new account
  joins it). An `eu-` region bucket must set it (prod-eu, root, audit, security: owner OQ4).
- **Same-account recorder (E5b4b)**: AWS Config delivers to a bucket of its own account with the
  recorder's IAM role, not the service principal, so the policy also grants
  `<tenant>-ue1-<stage>-aws-config-config` of this account (the audit account's home recorder
  role, which its eu-west-1 recorder reuses) `s3:GetBucketAcl`, `s3:ListBucket` and
  `s3:PutObject` under `AWSLogs/` with `bucket-owner-full-control`. Its principal is `*` with a
  fixed `aws:PrincipalArn`, because the role is created after the bucket; the residency Denys
  name the service principal only. The key grants the same role (`config_delivery_role_arns`).
- **Key (E5a4)**: `kms_master_key_arn` has no default. Each audit stack needs its own key: a
  dedicated `kms` instance whose key policy lets `config.amazonaws.com` use it
  (`kms:GenerateDataKey*`, `kms:Decrypt`), limited by `aws:SourceAccount` to the same residency
  (`config_source_accounts`). The bucket reads it with `!terraform.state <kms instance> .key_arn`,
  which needs that instance in `dependencies.components` and in an earlier layer of
  `workflows/deploy-full-stack.yaml`. The preflight (`check-first-deploy-inputs.py`) fails a
  bucket whose residency differs from its key's `config_source_accounts`.

## Gotchas

- The validation accepts only a key ARN (`...:key/<id>`): an alias ARN, `alias/aws/s3`, or an
  empty value fails the plan. An AWS managed key's own key ARN has the same shape and cannot be
  told apart statically; the catalog must name the house key.
- S3 does not check the key when the bucket is created: a key the Config service may not use
  only shows up as failed Config deliveries. Prove the key policy before the recorders land.
- A recorder must deliver with this bucket's key or none: one whose delivery channel sets another
  `s3KmsKeyArn` is denied by the bucket policy.
- `force_destroy` is `false`, as upstream.
- S3 Bucket Keys stay off, as under config-storage 1.0.2 (which does not expose
  `bucket_key_enabled`), so each Config delivery is its own KMS request. Small at Config volumes.

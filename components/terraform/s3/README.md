# s3

One S3 bucket per instance, modelled on Cloud Posse's
[aws-s3-bucket](https://github.com/cloudposse-terraform-components/aws-s3-bucket)
component (its input and output names). Security settings Cloud Posse
leaves as inputs are fixed on here: SSE-KMS with a customer managed key and a
bucket key, all public access blocked, ACLs disabled (`BucketOwnerEnforced`),
versioning on by default and a TLS-only bucket policy.

## Deployed instances

None in the three fnx stacks yet. The abstract base `s3/defaults`
(`stacks/catalog/s3/defaults.yaml`) wires the key from `kms/main`; instances
inherit it and set `name` and, as needed, `lifecycle_configuration_rules`,
`logging`, `source_policy_documents` and `event_notification_details`.

`stacks/catalog/templates/batch-processing.yaml`'s `batch-processing/s3-input`,
`batch-processing/s3-output` and `batch-processing/s3-scripts` are the first
instances (the template is not imported by any of the three fnx stacks
either); `s3-input` sets `event_notification_details` to notify its
`batch-processing/sqs/trigger` queue and EventBridge on `s3:ObjectCreated:*`
under `incoming/`.

## Inputs / outputs

| Key | Notes |
|---|---|
| `region`, `tags`, `name`, `kms_key_arn` (required) | `tags` must include a non-empty `Environment`; the bucket is `<Environment>-<name>-<account id>` (bucket names are global), which must be a valid bucket name (precondition). The key must be a KMS key ARN |
| `bucket_name` ("") | full name overriding the generated one |
| `bucket_key_enabled` (true), `versioning_enabled` (true), `force_destroy` (false) | Cloud Posse's inputs; the bucket key default is true here (Cloud Posse: false) to cut KMS requests |
| `lifecycle_configuration_rules` ([]) | Cloud Posse's lifecycle V2 rules: `id`, `enabled`, `abort_incomplete_multipart_upload_days`, `filter_and`, `expiration`, `noncurrent_version_expiration`, `transition`, `noncurrent_version_transition`. Ids must be unique; storage classes are validated |
| `logging` (null) | `{bucket_name, prefix}`: server access logs to another bucket |
| `source_policy_documents` ([]) | policy JSON merged with the TLS-only `ForceSSLOnlyAccess` statement (e.g. a CloudFront read grant) |
| `event_notification_details` (`{enabled = false}`) | Cloud Posse's input verbatim: `enabled`, `eventbridge` (false), `lambda_list`/`queue_list`/`topic_list` — each entry `{lambda_function_arn\|queue_arn\|topic_arn, events (["s3:ObjectCreated:*"]), filter_prefix, filter_suffix}`. `enabled: false` (the default) creates no `aws_s3_bucket_notification`, whatever the lists hold |
| `enabled` (true) | false creates nothing |
| out: `bucket_id`, `bucket_arn`, `bucket_domain_name`, `bucket_regional_domain_name`, `bucket_region` | Cloud Posse's outputs |
| out: `bucket_name` | the bucket name (same value as `bucket_id`) |

## Dependencies / gotchas

- **Key access.** Readers and writers need `kms:Decrypt`/`kms:GenerateDataKey`
  on the key in their own IAM policies; kms/main's root-account statement
  delegates that to IAM. A service principal reading objects (for example
  CloudFront with origin access control) needs its own key-policy statement,
  which kms/main does not have yet.
- **Access log target.** S3 delivers server access logs only to buckets with
  SSE-S3 default encryption, so `logging.bucket_name` cannot be a bucket from
  this component; use a dedicated SSE-S3 log bucket (see
  `backend/s3-backend.tf` for one).
- The bucket policy is built from the bucket name, so it is known at plan
  time. `source_policy_documents` statements need unique `Sid`s.
- **Notification destinations must already trust S3.** `PutBucketNotificationConfiguration`
  validates every queue/topic/lambda destination's resource policy at apply
  time, so the destination's policy admitting `s3.amazonaws.com` (and, if it
  is KMS-encrypted, a key grant for `s3.amazonaws.com` — `kms/main`'s
  `allow_s3`, scoped by `aws:SourceAccount`/`aws:SourceArn`, already covers
  SQS/SNS destinations that use it) must exist first. List the destination's
  component in `dependencies.components` so Atmos applies it before this one.

## Differences from Cloud Posse

- Plain resources instead of the `cloudposse/s3-bucket` module; no
  `context.tf`/null-label. The generated name adds the account id instead of
  namespace/tenant/stage, and `default_tags` carries the tags.
- Fixed instead of inputs: `sse_algorithm` (`aws:kms`, with the required
  `kms_key_arn` in place of `kms_master_key_arn`), `allow_ssl_requests_only`
  (always on), the four public access block flags (all true) and
  `s3_object_ownership` (`BucketOwnerEnforced`, Cloud Posse: `ObjectWriter`),
  which makes `acl` and `grants` meaningless, so they are dropped.
- `source_policy_documents` (the underlying module's input) replaces
  `iam_policy_statements`/`custom_policy_*`.
- `event_notification_details` is the one Cloud Posse input ported verbatim
  (same field names, types and defaults), because it is what
  [`aws-s3-bucket`](https://github.com/cloudposse-terraform-components/aws-s3-bucket)
  passes straight through to
  [`cloudposse/terraform-aws-s3-bucket`](https://github.com/cloudposse/terraform-aws-s3-bucket)'s
  `aws_s3_bucket_notification.bucket_notification`; this component's resource
  is that same block, ported as-is.
- Trimmed: replication, object lock, CORS, website, transfer acceleration,
  intelligent tiering, the IAM user, privileged principals and the
  account-map lookups for logging names.
- A lifecycle `filter_and` with an empty `tags` map sends no `tags` (the
  provider rejects an empty map, which Cloud Posse's code sends).
- Validations Cloud Posse does not have: the key ARN, `name` and
  `bucket_name` formats, unique lifecycle ids and storage classes, JSON
  policy documents.

## Tests

`tests/s3.tftest.hcl` and `tests/notifications.tftest.hcl` run offline
against the real provider with dummy credentials, so the bucket policy and
notification blocks are rendered and asserted:

```
cd components/terraform/s3 && terraform init -backend=false && terraform test
```

## Usage

```yaml
components:
  terraform:
    s3/assets:
      metadata:
        component: s3
        inherits: [s3/defaults]
      vars:
        name: assets
        lifecycle_configuration_rules:
          - id: noncurrent
            abort_incomplete_multipart_upload_days: 7
            noncurrent_version_expiration:
              noncurrent_days: 30
        event_notification_details:
          enabled: true
          eventbridge: true
          queue_list:
            - queue_arn: !terraform.state sqs/trigger .queue_arn
              events: ["s3:ObjectCreated:*"]
              filter_prefix: "incoming/"
      dependencies:
        components:
          - component: kms/main
          - component: sqs/trigger
```

```
atmos terraform plan s3/assets -s <stack>
```

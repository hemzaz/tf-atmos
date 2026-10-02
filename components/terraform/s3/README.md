# s3

One S3 bucket per instance, modelled on Cloud Posse `aws-s3-bucket` (input and output names) as
plain resources. Security settings Cloud Posse leaves as inputs are fixed: SSE-KMS with a customer
managed key and bucket key, all public access blocked, `BucketOwnerEnforced`, versioning on by
default, TLS-only bucket policy.

## Wiring

- `s3/defaults` reads `kms/main .key_arn`. `s3/lambda-artifacts` (`stacks/catalog/s3/lambda-artifacts.yaml`,
  imported by each AWS stack's `components/services.yaml`, the `microservices-platform` template
  and `templates/stacks/serverless-stack.yaml`) is the lambda package bucket, deployed in the
  `deploy-full-stack` storage layer. The `batch-processing` and `data-pipeline` templates create
  buckets from `s3/defaults` too (`serverless-api` also declares one).
- Consumers read `.bucket_id`, `.bucket_name`, `.bucket_arn` or `.bucket_regional_domain_name`;
  `lambda/*` reads `s3/lambda-artifacts .bucket_id`.
- A CloudFront origin bucket sets `allow_cloudfront_oac_read: true` (any distribution of the
  account may read objects through OAC); a `cloudfront` instance's `s3_origin_policy_json` in
  `source_policy_documents` is the optional single-distribution alternative.

## Notes

- The bucket is `<Environment>-<name>-<account id>` unless `bucket_name` is set.
- Readers and writers need `kms:Decrypt` / `kms:GenerateDataKey` in their own IAM policies. A
  service principal reading objects needs a key-policy statement: for CloudFront with origin
  access control, kms `allow_cloudfront` (off in `kms/defaults`).
- S3 server access logs only go to SSE-S3 buckets, so `logging.bucket_name` cannot be a bucket from
  this component.
- Notification destinations (`event_notification_details`, ported verbatim from Cloud Posse) must
  already trust `s3.amazonaws.com` at apply time; list them in `dependencies.components`.
  `kms/main`'s `allow_s3` covers encrypted SQS/SNS destinations.
- `source_policy_documents` statements need unique `Sid`s.
- `cors_configuration` is Cloud Posse's input verbatim (browser uploads with presigned URLs need
  it); methods are limited to the five S3 accepts and each rule needs an origin (validated).
- Trimmed from Cloud Posse: replication, object lock, website, acceleration, intelligent
  tiering, the IAM user and ACLs.

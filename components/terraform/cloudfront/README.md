# cloudfront

One CloudFront distribution per instance in front of an S3 bucket it does not own, reached through
origin access control (sigv4, always signed). Modelled on Cloud Posse
`terraform-aws-cloudfront-s3-cdn` (the module behind `aws-spa-s3-cloudfront`) as plain resources;
the deviations are listed at the top of `main.tf`. Covers aliases with a us-east-1 ACM
certificate (SNI, TLSv1.2_2021 by default), managed or custom cache / origin request / response
headers policies (CachingOptimized and SecurityHeadersPolicy by default), custom error responses
and an SPA fallback, a CLOUDFRONT WAF web ACL, geo restriction, standard logging v2 to S3, and
optional Route 53 alias records.

Not yet supported (part 2): custom origins (ALB, API Gateway), ordered cache behaviors and
CloudFront Functions / Lambda@Edge.

## Wiring

- No instance in the fnx stacks. `cloudfront/defaults` (`stacks/catalog/cloudfront/defaults.yaml`)
  carries an example instance. It deploys in the `services` layer of
  `workflows/deploy-full-stack.yaml`, after the `s3` (storage), `kms`, `dns` and `acm`
  (certificates) instances it relies on.
- Inputs: `origin_bucket_regional_domain_name` from an s3 instance's
  `.bucket_regional_domain_name`, `acm_certificate_arn` from an acm instance's
  `.certificate_arns.<key>`, `parent_zone_id` from a dns instance's `.zone_ids.<key>`, `web_acl_id`
  from a CLOUDFRONT-scope waf instance's `.arn` (list it in `dependencies.components`).
- Origin access: the origin s3 instance sets `allow_cloudfront_oac_read: true` and the stack's
  `kms/main` sets `allow_cloudfront: true` (s3 buckets are SSE-KMS with it). Both trust any
  distribution of the account, need no distribution ARN, and deploy in earlier layers, so the
  first deploy works in one pass.
- Optional tightening: `s3_origin_policy_json` grants this distribution only; add it to the origin
  s3 instance's `source_policy_documents` (and drop `allow_cloudfront_oac_read`) once the
  distribution exists.
- `stacks/catalog/templates/serverless-api.yaml` (`serverless-api/cloudfront`) and
  `web-application.yaml` predate this component and still use the old nested
  `origins`/`viewer_certificate` inputs; they need porting (the web-application ALB origin needs
  part 2). Their separate dns records that read the distribution become `dns_alias_enabled`.
- Consumers read `.distribution_id` (invalidations, the `AWS/CloudFront` `DistributionId`
  dimension), `.distribution_arn`, `.distribution_domain_name` and `.distribution_hosted_zone_id`.

## Notes

- The trust boundary is the account, not the distribution (a deliberate deviation from Cloud
  Posse, see `main.tf`): any CloudFront distribution in the account can read an origin bucket with
  `allow_cloudfront_oac_read` and decrypt with a key with `allow_cloudfront`.
- The ACM certificate and the WAF web ACL must be in us-east-1 (validated). Aliases need the
  certificate (validated).
- `enable_spa_fallback` answers S3's 403 and 404 with 200 and `/<default_root_object>`; it cannot
  be combined with a `custom_error_response` for 403 or 404.
- Logging v2 resources are created in us-east-1 whatever the stack region, named
  `<Environment>-<name>-cloudfront[-s3]` (60 characters of `[A-Za-z0-9_-]`, checked at plan).
  CloudWatch Logs adds a `delivery.logs.amazonaws.com` statement to the log bucket's policy when
  it creates the delivery, which the s3 component would revert: give the log bucket that statement
  through its `source_policy_documents`. A log bucket encrypted with a CMK needs a key policy
  allowing `delivery.logs.amazonaws.com` to `kms:GenerateDataKey`.
- Managed policy names are mapped to their AWS IDs in `main.tf`; any other value must be a policy
  ID.

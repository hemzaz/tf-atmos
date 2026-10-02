# cloudfront

One CloudFront distribution per instance in front of an optional S3 bucket it does not own
(reached through origin access control: sigv4, always signed) and custom origins (ALB, API
Gateway, any HTTPS server). Modelled on Cloud Posse `terraform-aws-cloudfront-s3-cdn` (the module
behind `aws-spa-s3-cloudfront`) as plain resources; the deviations are listed at the top of
`main.tf` and beside `custom_origins` / `ordered_cache` in `variables.tf`. Covers aliases with a
us-east-1 ACM certificate (SNI, TLSv1.2_2021 by default), managed or custom cache / origin request
/ response headers policies (CachingOptimized and SecurityHeadersPolicy by default) on the default
and ordered cache behaviors (`ordered_cache`), CloudFront Functions and Lambda@Edge associations,
custom error responses and an SPA fallback, a CLOUDFRONT WAF web ACL, geo restriction, standard
logging v2 to S3, and optional Route 53 alias records.

## Wiring

- No instance in the fnx stacks. `cloudfront/defaults` (`stacks/catalog/cloudfront/defaults.yaml`)
  carries an example instance. It deploys in the `services` layer of
  `workflows/deploy-full-stack.yaml`, after the `s3` (storage), `kms`, `dns`, `acm`
  (certificates) and `alb` instances it relies on.
- Inputs: `origin_bucket_regional_domain_name` from an s3 instance's
  `.bucket_regional_domain_name`, `acm_certificate_arn` from an acm instance's
  `.certificate_arns.<key>`, `parent_zone_id` from a dns instance's `.zone_ids.<key>`, `web_acl_id`
  from a CLOUDFRONT-scope waf instance's `.arn` (list it in `dependencies.components`).
- Origins: the S3 origin exists when `origin_bucket_regional_domain_name` is set; `custom_origins`
  add others. `default_origin_id` picks the default behavior's origin and each `ordered_cache`
  entry's `target_origin_id` its own: `""` is the S3 origin, anything else a custom `origin_id`.
  A custom-origin-only distribution (an ALB-backed web app) leaves the bucket null and sets
  `default_origin_id`.
- S3 origin access: the origin s3 instance sets `allow_cloudfront_oac_read: true` and the stack's
  `kms/main` sets `allow_cloudfront: true` (s3 buckets are SSE-KMS with it). Both trust any
  distribution of the account, need no distribution ARN, and deploy in earlier layers, so the
  first deploy works in one pass.
- Optional tightening: `s3_origin_policy_json` grants this distribution only; add it to the origin
  s3 instance's `source_policy_documents` (and drop `allow_cloudfront_oac_read`) once the
  distribution exists.
- ALB origins: send a secret origin-verify header (`custom_headers`, e.g. `X-Origin-Verify`) and
  have the alb instance's HTTPS listener forward only requests carrying it (a listener rule on
  that header; the default action returns 403). Without it the ALB answers anyone who finds its
  DNS name, bypassing the CloudFront WAF. Read the value from Secrets Manager or SSM (`!store`),
  never a literal in a stack. The ALB side is the alb component's job.
- `stacks/catalog/templates/serverless-api.yaml` (`serverless-api/cloudfront`) and
  `web-application.yaml` predate this component and still use the old nested
  `origins`/`viewer_certificate`/`ordered_cache_behaviors` inputs; they need porting (TTL blocks
  become cache policies). Their separate dns records that read the distribution become
  `dns_alias_enabled`.
- Consumers read `.distribution_id` (invalidations, the `AWS/CloudFront` `DistributionId`
  dimension), `.distribution_arn`, `.distribution_domain_name` and `.distribution_hosted_zone_id`.

## Notes

- The trust boundary is the account, not the distribution (a deliberate deviation from Cloud
  Posse, see `main.tf`): any CloudFront distribution in the account can read an origin bucket with
  `allow_cloudfront_oac_read` and decrypt with a key with `allow_cloudfront`.
- The ACM certificate and the WAF web ACL must be in us-east-1 (validated). Aliases need the
  certificate (validated).
- Origin TLS: custom origins default to `https-only` with TLSv1.2 (SSLv3 is rejected). CloudFront
  checks the origin certificate against the origin `domain_name`, or against the viewer `Host`
  when the origin request policy forwards it (`AllViewer`). An ALB's `*.elb.amazonaws.com` name is
  not on its certificate: point `domain_name` at a record the ALB certificate covers (e.g.
  `origin.<domain>`), and use `AllViewerExceptHostHeader` unless the certificate also covers the
  aliases.
- Custom header values are redacted from plan output (`sensitive()`) but are stored in state, as
  is every distribution attribute.
- Timeouts: `origin_read_timeout` (default 30 s) and `origin_keepalive_timeout` (default 5 s) are
  validated to 1-180 s; above 60 s needs a CloudFront quota increase first.
- Lambda@Edge ARNs must be in us-east-1 and version-qualified (`:<version>`, not `$LATEST` or an
  alias); a behavior takes one function per event type, CloudFront Functions only on viewer
  events, and a viewer event cannot have both kinds (all validated).
- `default_root_object` defaults to `index.html` only when the default behavior targets the S3
  origin; a custom default origin serves `/` itself unless one is set.
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

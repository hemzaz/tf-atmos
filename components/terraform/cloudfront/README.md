# cloudfront

One CloudFront distribution per instance in front of an optional S3 bucket it does not own
(reached through origin access control: sigv4, always signed) and custom origins (ALB, API
Gateway, any HTTPS server), each optionally a VPC origin (an internal ALB, an NLB or an EC2
instance in private subnets). Modelled on Cloud Posse `terraform-aws-cloudfront-s3-cdn` (the module
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
- ALB origins, preferred: a VPC origin. Make the alb instance `internal: true` in private
  subnets and give the custom origin `vpc_origin.arn` from the alb's `.alb_arn` (list the alb in
  `dependencies.components`; it deploys in addons, before this component). The component creates
  the `aws_cloudfront_vpc_origin`; CloudFront reaches the ALB through service-managed ENIs, so the
  ALB has no internet path and needs no shared secret. `web-application/cloudfront` is wired this
  way. Not in Cloud Posse (no VPC-origin input upstream): an accepted deviation.
- ALB origins, public: an internet-facing ALB answers anyone who finds its DNS name, bypassing
  the CloudFront WAF, unless it requires a secret origin-verify header (`custom_headers` with
  `value_ssm_parameter_name`, never a literal `value` in a stack; the alb's
  `listener_https_fixed_response` 403 and the `ecs-service` listener rule's
  `load_balancer.http_header` on the same parameter). The secret is then readable by the plan role
  and in plan and state; use it only where a VPC origin cannot work.
- `stacks/catalog/templates/serverless-api.yaml` (`serverless-api/cloudfront`) predates this
  component and still uses the old nested `origins`/`viewer_certificate`/`ordered_cache_behaviors`
  inputs; it needs porting (TTL blocks become cache policies), its separate dns records that read
  the distribution becoming `dns_alias_enabled`.
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
- VPC origins (AWS Developer Guide, "Restrict access with VPC origins"):
  - a VPC origin takes up to 15 minutes to deploy. AWS refuses to update one a distribution uses
    (`CannotUpdateEntityWhileInUse`), so any endpoint change (ARN, ports, protocol, TLS versions)
    replaces it instead: create a new one, named `<Environment>-<name>-<origin_id>-<config
    hash>` so the two names never collide, repoint the distribution, delete the old one. Each step
    waits for deployment, so expect a long apply. Not verified against AWS: whether a second VPC
    origin for the same ARN may exist while the old one is still there;
  - replacing the ALB (alb component, addons layer, e.g. a name or subnet change) while the VPC
    origin (this component, services layer) still points at it may be refused by AWS, or leave the
    origin broken until this component is re-applied: plan the cloudfront instance right after
    such an alb change;
  - the target's VPC needs an internet gateway (it marks the VPC as reachable; traffic does not
    use it) and a free IPv4 address in the target's subnets for CloudFront's ENI;
  - the first VPC origin in a VPC creates the service-managed `CloudFront-VPCOrigins-Service-SG`.
    It does not exist before this component applies, so a target security group deployed earlier
    admits the CloudFront origin-facing prefix list instead (the alb component always does);
    never create a group whose name starts with that prefix;
  - unsupported: Lambda@Edge origin-request and origin-response triggers on a behavior targeting
    the origin (validated), gRPC, Gateway Load Balancers and NLBs with TLS listeners; inbound NACL
    rules are not evaluated, outbound ones must allow ephemeral ports back;
  - not every AZ: us-east-1 excludes `use1-az3` (also `usw1-az2`, `apne1-az3`, `cac1-az3`); keep
    the target's subnets out of them;
  - HTTPS still checks the origin certificate against `domain_name` (above): keep a covered name
    such as `origin.<domain>` (a Route 53 alias to the internal ALB) rather than its
    `internal-*.elb.amazonaws.com` name;
  - custom headers still work, but are no longer needed for access control.
- A `value_ssm_parameter_name` header is read at plan (`data.aws_ssm_parameter`, decrypted): the
  planning role needs `ssm:GetParameter` on it, and `kms:Decrypt` for a customer managed key;
  keep it on the default `aws/ssm` key, which `ReadOnlyAccess` (the CI plan role) can use through
  SSM. Changing the parameter changes the distribution at the next apply.
- Custom header values are marked `sensitive()`. With any custom header, Terraform hides the whole
  `origin` set in plan diffs (every origin's details, not only the header values), so review origin
  changes with `terraform show -json` on the plan. The values are still stored in state, as is
  every distribution attribute. Header names CloudFront refuses to add (Host, Cookie,
  Cache-Control, `X-Amz-*`, `X-Edge-*` and the rest of the AWS list) are rejected.
- Timeouts: `origin_read_timeout` (default 30 s) and `origin_keepalive_timeout` (default 5 s) are
  validated to 1-180 s; above 60 s needs a CloudFront quota increase first.
- Lambda@Edge ARNs must be in us-east-1 and version-qualified (`:<version>`, not `$LATEST` or an
  alias); a behavior takes one function per event type, CloudFront Functions only on viewer
  events, and a behavior with any CloudFront Function can use Lambda@Edge on origin events only,
  as AWS does not combine the two in viewer events (all validated). `cached_methods` must be a
  subset of `allowed_methods`.
- `default_root_object` defaults to `index.html` only when the default behavior targets the S3
  origin; a custom default origin serves `/` itself unless one is set.
- `enable_spa_fallback` answers S3's 403 and 404 with 200 and `/<default_root_object>`; it cannot
  be combined with a `custom_error_response` for 403 or 404.
- Custom error responses, the SPA fallback included, apply to the whole distribution, not one
  behavior: with an S3 SPA default and an `/api/*` behavior, the API's own 403 and 404 also become
  200 `/index.html`. Serve such APIs from a separate distribution, or skip the fallback and route
  client-side paths another way (e.g. a viewer-request CloudFront Function).
- Logging v2 resources are created in us-east-1 whatever the stack region, named
  `<Environment>-<name>-cloudfront[-s3]` (60 characters of `[A-Za-z0-9_-]`, checked at plan).
  CloudWatch Logs adds a `delivery.logs.amazonaws.com` statement to the log bucket's policy when
  it creates the delivery, which the s3 component would revert: give the log bucket that statement
  through its `source_policy_documents`. A log bucket encrypted with a CMK needs a key policy
  allowing `delivery.logs.amazonaws.com` to `kms:GenerateDataKey`.
- Managed policy names are mapped to their AWS IDs in `main.tf`; any other value must be a policy
  ID.

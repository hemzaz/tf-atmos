# waf

A WAFv2 web ACL with managed rule group, rate-based and byte-match rules, optional associations,
and a CloudWatch log group with its own scoped log resource policy. Modelled on Cloud Posse
`aws-waf` (typed rule lists), written as plain resources.

## Wiring

- Used only by stack templates: `web-application/waf` (REGIONAL, associated with
  `web-application/alb .alb_arn`), `web-application/waf-cloudfront` (CLOUDFRONT), and
  `serverless-api/waf` (REGIONAL, associated with `serverless-api/apigateway .rest_api_stage_arn`).
  REGIONAL instances read `kms/main .key_arn`.
- A CloudFront distribution uses the `arn` output as its `web_acl_id`.

## Notes

- `scope = CLOUDFRONT` requires `region = us-east-1` (validated) and takes no
  `association_resource_arns`. Leave `kms_key_arn` null there: the stack's regional key cannot
  encrypt a us-east-1 log group. That is why REGIONAL instances set the key themselves instead of
  inheriting it from `waf/defaults` (a `null` override cannot beat a non-null default).
- The log group is always `aws-waf-logs-<Environment>-<name>` (WAFv2 requires the prefix).
- Each logging instance creates its own CloudWatch Logs resource policy, which counts against the
  10-per-region quota; set `manage_log_resource_policy = false` to fall back to the shared
  `AWSWAF-LOGS` policy.
- The logging configuration redacts the `authorization` and `cookie` headers (`redacted_fields`,
  Cloud Posse's shape); the component rejects a map that drops either. Extend it per instance:
  `waf/defaults` repeats the default so Atmos deep-merges an instance's extra entries onto it.
  Each field becomes its own `redacted_fields` block, as AWS requires.
- Rule priorities must be unique across all three rule lists. Rate rules accept only `IP` or
  `CONSTANT` aggregation and a `limit` of at least 10.

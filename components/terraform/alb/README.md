# alb

An Application Load Balancer (internet-facing by default) with its own security group, an
HTTPS-only listener forwarding to a catch-all default target group (or answering with
`listener_https_fixed_response`), an access-logs bucket and optional Route 53 alias records.
Modelled on Cloud Posse `aws-alb`, written as plain resources.

## Wiring

- Used by the `idp-platform` template (`idp-platform/alb`, internet-facing, no CloudFront
  ingress, logs expiring) and the `web-application` template: `web-application/alb` (addons layer, `internal:
  true`) reads the template's `vpc` (private subnets), `acm` certificate, the dns instance's zone (`parent_zone_id`
  for `origin.<app_domain>`) and the `securitygroups` instance's `alb` group
  (`security_group_ids`), which the application group admits.
- Consumers: `web-application/waf` associates with `.alb_arn`, `web-application/cloudfront` makes
  `.alb_arn` a CloudFront VPC origin, `ecs-service` adds its listener rule to
  `.https_listener_arn`, `monitoring` uses `.alb_arn_suffix`.

## Notes

- The security group admits only the CloudFront origin-facing prefix list on 443 (plus
  `additional_ingress_*`); there is no CIDR ingress input. No port 80 listener: CloudFront
  redirects at the edge. `cloudfront_ingress_enabled: false` drops the prefix-list rule for an ALB
  reached directly (the `idp-platform` template); it then needs another source, such as a
  `securitygroup` group with CIDR ingress attached through `security_group_ids`.
- `route53_health_check_ingress_enabled` admits the Route 53 health checkers on 443 from their
  AWS-managed prefix list (`com.amazonaws.<region>.route53-healthchecks`, weight 25), for a Route 53
  health check on an alias of this ALB. With CloudFront ingress on as well, the two lists weigh about
  80 against the default 60 rules per group: raise that quota first.
- `lifecycle_rule_enabled` (Cloud Posse's, off by default) expires the access logs after
  `expiration_days` (90), their noncurrent versions after `noncurrent_version_expiration_days`
  (90), and aborts incomplete uploads after `abort_incomplete_multipart_upload_days` (5).
- `security_group_ids` attaches groups defined elsewhere (Cloud Posse's input) beside the
  component's own: a target admits the ALB by one of them, defined in an earlier layer, instead
  of by `.security_group_id`, which only exists after this component applies.
- A prefix-list rule counts as the list's max entries against the security group rule quota (60 by
  default); the CloudFront list alone weighs about 55, so one more prefix list can fail apply.
  Prefer `additional_ingress_security_group_ids` or raise the quota first.
- CloudFront validates the origin certificate by hostname, and ACM cannot issue for
  `*.elb.amazonaws.com`: point the origin at a name in `dns_aliases` (e.g. `origin.<app_domain>`)
  that `certificate_arn` covers.
- Behind CloudFront, prefer `internal: true` in private subnets with the cloudfront instance's
  `vpc_origin` on `.alb_arn`: the ALB has no internet path and needs no shared secret. The
  CloudFront prefix-list rule is what admits the VPC origin's traffic: AWS allows either that list
  or the service-managed `CloudFront-VPCOrigins-Service-SG`, which only exists after the first
  VPC origin (cloudfront, a later layer) is created. Keep the subnets out of `use1-az3` (no VPC
  origins there). An internet-facing ALB behind CloudFront instead needs
  `listener_https_fixed_response` 403 plus a secret origin-verify header condition on each
  listener rule (`ecs-service` `load_balancer.http_header`), so the ALB refuses requests that
  bypass the distribution and its WAF. A 403 default action is worth keeping either way.
- Access logs use this component's own SSE-S3 bucket (ALB log delivery does not support SSE-KMS),
  named `<Environment>-<name>-access-logs-<account-id>`.
- Keep `name` short: ALB and target group names are limited to 32 characters.

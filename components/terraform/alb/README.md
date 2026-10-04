# alb

An Application Load Balancer (internet-facing by default) with its own security group, an
HTTPS-only listener forwarding to a catch-all default target group (or answering with
`listener_https_fixed_response`), an access-logs bucket and optional Route 53 alias records.
Modelled on Cloud Posse `aws-alb`, written as plain resources.

## Wiring

- Used only by the `web-application` template: `web-application/alb` (addons layer) reads the
  template's `vpc` (public subnets), `acm` certificate, the dns instance's zone (`parent_zone_id`
  for `origin.<app_domain>`) and the `securitygroups` instance's `alb` group
  (`security_group_ids`), which the application group admits.
- Consumers: `web-application/waf` associates with `.alb_arn`, `ecs-service` adds its listener
  rule to `.https_listener_arn`, `monitoring` uses `.alb_arn_suffix`.

## Notes

- The security group admits only the CloudFront origin-facing prefix list on 443 (plus
  `additional_ingress_*`); there is no CIDR ingress input. No port 80 listener: CloudFront
  redirects at the edge.
- `security_group_ids` attaches groups defined elsewhere (Cloud Posse's input) beside the
  component's own: a target admits the ALB by one of them, defined in an earlier layer, instead
  of by `.security_group_id`, which only exists after this component applies.
- A prefix-list rule counts as the list's max entries against the security group rule quota (60 by
  default); the CloudFront list alone weighs about 55, so one more prefix list can fail apply.
  Prefer `additional_ingress_security_group_ids` or raise the quota first.
- CloudFront validates the origin certificate by hostname, and ACM cannot issue for
  `*.elb.amazonaws.com`: point the origin at a name in `dns_aliases` (e.g. `origin.<app_domain>`)
  that `certificate_arn` covers.
- Behind CloudFront, set `listener_https_fixed_response` to a 403 and give each listener rule the
  distribution's secret origin-verify header as a condition (`ecs-service`
  `load_balancer.http_header`), so the ALB refuses requests that bypass the distribution and its
  WAF. The default target group then receives nothing.
- Access logs use this component's own SSE-S3 bucket (ALB log delivery does not support SSE-KMS),
  named `<Environment>-<name>-access-logs-<account-id>`.
- Keep `name` short: ALB and target group names are limited to 32 characters.

# alb

An Application Load Balancer (internet-facing by default) with its own security group, an
HTTPS-only listener forwarding to a catch-all default target group, and an access-logs bucket.
Modelled on Cloud Posse `aws-alb`, written as plain resources.

## Wiring

- Used only by the `web-application` template: `web-application/alb` reads the template's `vpc`
  (public subnets) and `acm` certificate. `web-application/waf` associates with `.alb_arn`,
  `ecs-service` uses `.default_target_group_arn`, `cloudfront` uses `.alb_dns_name` as its origin,
  `monitoring` uses `.alb_arn_suffix`, and the app security group admits `.security_group_id`.

## Notes

- The security group admits only the CloudFront origin-facing prefix list on 443 (plus
  `additional_ingress_*`); there is no CIDR ingress input. No port 80 listener: CloudFront
  redirects at the edge.
- A prefix-list rule counts as the list's max entries against the security group rule quota (60 by
  default); the CloudFront list alone weighs about 55, so one more prefix list can fail apply.
  Prefer `additional_ingress_security_group_ids` or raise the quota first.
- CloudFront validates the origin certificate by hostname, and ACM cannot issue for
  `*.elb.amazonaws.com`: point the origin at a DNS alias such as `origin.<app_domain>`.
- Access logs use this component's own SSE-S3 bucket (ALB log delivery does not support SSE-KMS),
  named `<Environment>-<name>-access-logs-<account-id>`.
- Keep `name` short: ALB and target group names are limited to 32 characters.

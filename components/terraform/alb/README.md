# alb

An internet-facing (or internal) Application Load Balancer with its own security group,
an HTTPS-only listener and a dedicated access-logs bucket. Modelled on Cloud Posse's
[`aws-alb`](https://github.com/cloudposse-terraform-components/aws-alb) component,
which wraps [`cloudposse/terraform-aws-alb`](https://github.com/cloudposse/terraform-aws-alb).
Written as plain resources, like the other root components in this repo (see
`components/terraform/s3`), rather than as a wrapper around the Cloud Posse module.

## Design decisions (this repo, not the Cloud Posse default)

- **The ALB owns its security group.** Cloud Posse's `aws-alb` takes caller-supplied
  security group ids; this component creates its own and admits only the CloudFront
  origin-facing managed prefix list (`com.amazonaws.global.cloudfront.origin-facing`)
  on port 443. `additional_ingress_prefix_list_ids` and
  `additional_ingress_security_group_ids` can widen that further, but there is no
  CIDR-based ingress input at all -- this repo never opens an ALB to `0.0.0.0/0`.
- **No port 80 listener.** CloudFront performs the `http -> https` redirect at the
  edge, so the ALB only needs to answer HTTPS.
- **Access logs use a component-created bucket, not the repo's `s3` component.**
  ALB access log delivery only supports SSE-S3, and the `s3` component always
  encrypts with a customer-managed KMS key. This component's `access_logs`
  bucket is therefore separate: SSE-S3, fully public-access-blocked, TLS-only,
  and its policy grants only the `logdelivery.elasticloadbalancing.amazonaws.com`
  service principal `s3:PutObject` under its own prefix, scoped with an
  `aws:SourceAccount` condition -- AWS's current recommendation for every
  region, superseding the legacy per-region `aws_elb_service_account`
  principal (which cannot take that condition). The bucket is named
  `<Environment>-<name>-access-logs-<account-id>`: S3 bucket names are global
  across every AWS account, so the account id keeps it unique, the way the
  repo's other component-created buckets do (`awsconfig`, `cloudtrail`).

## HTTPS listener default action

The listener's default action forwards to a catch-all default target group
(Cloud Posse's `aws-alb` pattern), rather than returning a fixed response. This
gives later components something to depend on immediately (`default_target_group_arn`)
and lets a later component add its own target group plus a higher-priority
listener rule without recreating the listener.

## Consumers this component's outputs are meant for (built in later tasks)

- **`ecs-service`**: add its own target group (matching the container port) and an
  `aws_lb_listener_rule` on `https_listener_arn`, instead of relying on the
  catch-all `default_target_group_arn`.
- **`web-application/cloudfront`**: use `alb_dns_name` as the distribution's
  custom origin domain name, and `waf-cloudfront`'s `arn` as the distribution's
  `web_acl_id`.
- **`monitoring`**: `alb_arn_suffix` for `AWS/ApplicationELB` CloudWatch alarm
  dimensions.

### Pitfall: security group rule quota when adding prefix lists

A security group ingress rule that references a managed prefix list counts
against the account's "Rules per security group" quota (default 60 inbound)
as that prefix list's **max-entries** weight, not as a single rule. The
CloudFront origin-facing prefix list (`com.amazonaws.global.cloudfront.origin-facing`)
alone weighs roughly 55 of that default 60, so even one entry in
`additional_ingress_prefix_list_ids` can push the security group over the
limit at apply time. If you need to add another prefix list, either request
a quota increase for "Inbound or outbound rules per security group" first,
or prefer `additional_ingress_security_group_ids` (a plain security-group
reference, which counts as 1 rule) where it fits the use case.

### Pitfall for the CloudFront work: the origin certificate

An HTTPS-only CloudFront origin validates the origin's certificate against the
hostname CloudFront connects with. `certificate_arn` here is (or covers) the
application's real domain, not `*.elb.amazonaws.com` -- ACM cannot issue a
certificate for the AWS-owned ALB DNS name. The CloudFront distribution's
origin should therefore be a DNS alias such as `origin.<app_domain>` pointed at
`alb_dns_name` / `alb_zone_id`, never the raw `*.elb.amazonaws.com` name.

## Example

```yaml
web-application/alb:
  metadata:
    component: alb
    type: real
  vars:
    name: "webapp-alb"
    vpc_id: !terraform.state web-application/vpc .vpc_id
    subnets: !terraform.state web-application/vpc .public_subnet_ids
    certificate_arn: !terraform.state web-application/acm .certificate_arns.main
  dependencies:
    components:
      - component: web-application/vpc
      - component: web-application/acm
```

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `region` | AWS region | - |
| `tags` | Tags; must include `Environment` | - |
| `enabled` | Set to `false` to create nothing | `true` |
| `name` | Short name; resources are named `<Environment>-<name>` (kept short: combined with a suffix under the 32-character ALB/target-group limit) | - |
| `vpc_id` | VPC id | - |
| `subnets` | Subnet ids (public subnets for an internet-facing ALB) | - |
| `internal` | Internal (no public IP) vs internet-facing | `false` |
| `additional_ingress_prefix_list_ids` | Extra managed prefix lists allowed on 443 (see the security-group rule-quota pitfall above) | `[]` |
| `additional_ingress_security_group_ids` | Extra security groups allowed on 443 | `[]` |
| `certificate_arn` | ACM certificate ARN for the HTTPS listener | - |
| `ssl_policy` | HTTPS listener SSL policy | `ELBSecurityPolicy-TLS13-1-2-2021-06` |
| `idle_timeout` | Connection idle timeout (seconds) | `60` |
| `deletion_protection` | Enable deletion protection | `false` |
| `drop_invalid_header_fields` | Drop invalid HTTP header fields | `true` |
| `desync_mitigation_mode` | `monitor` \| `defensive` \| `strictest` | `defensive` |
| `enable_http2` | Enable HTTP/2 | `true` |
| `default_target_group_port` | Catch-all target group port | `80` |
| `default_target_group_protocol` | Catch-all target group protocol | `HTTP` |
| `default_target_group_deregistration_delay` | Deregistration delay (seconds) | `30` |
| `access_logs_enabled` | Create the access-logs bucket and enable logging | `true` |
| `access_logs_prefix` | Key prefix for delivered log objects | `""` |
| `access_logs_force_destroy` | Allow destroying the access-logs bucket with objects in it | `false` |

## Outputs

| Name | Description |
|------|-------------|
| `alb_arn` | Load balancer ARN |
| `alb_arn_suffix` | Load balancer ARN suffix (CloudWatch dimension) |
| `alb_dns_name` | Load balancer DNS name |
| `alb_zone_id` | Load balancer's Route 53 hosted zone id |
| `https_listener_arn` | HTTPS listener ARN |
| `default_target_group_arn` | Catch-all default target group ARN |
| `security_group_id` | Security group id attached to the load balancer |
| `access_logs_bucket_id` | Access-logs bucket id, or `null` when disabled |

## Tests

`tests/alb.tftest.hcl` asserts (real provider with dummy credentials and
`override_data` for every data source that would otherwise call AWS, as in
`kms/tests` and `s3/tests` -- every run is a plan, so nothing reaches AWS):

- the security group has no CIDR ingress and admits only the CloudFront
  origin-facing prefix list on 443, plus any explicitly added prefix
  lists/security groups;
- there is no listener on port 80;
- the default action forwards to the default target group.

Run with `workflows/scripts/common/terraform-test.sh alb`.

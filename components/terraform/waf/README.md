# waf

An AWS WAFv2 web ACL, with its own CloudWatch log group. Modelled on Cloud Posse's
[`aws-waf`](https://github.com/cloudposse-terraform-components/aws-waf) component,
which wraps [`cloudposse/terraform-aws-waf`](https://github.com/cloudposse/terraform-aws-waf).
Written as plain resources, like the other root components in this repo (see
`components/terraform/s3`), rather than as a wrapper around the Cloud Posse module.

## scope: REGIONAL vs CLOUDFRONT

- `REGIONAL` protects a resource in this stack's own region (ALB, API Gateway,
  AppSync, Cognito, App Runner). Attach it with `association_resource_arns`,
  which creates one `aws_wafv2_web_acl_association` per ARN.
- `CLOUDFRONT` protects a CloudFront distribution. **The web ACL itself must be
  created with `region = us-east-1`**, even when the distribution's origins
  (and every other component in the stack) live elsewhere -- this is an AWS
  requirement for CloudFront web ACLs, not a choice this component makes. The
  component's `region` variable validation enforces it. `aws_wafv2_web_acl_association`
  does not support `CLOUDFRONT`; instead, set the distribution's `web_acl_id`
  to this component's `arn` output. `association_resource_arns` is therefore
  rejected (by validation) when `scope = CLOUDFRONT`.

An Atmos instance that needs a CLOUDFRONT-scope ACL sets `region: us-east-1` on
that instance directly (see `stacks/catalog/templates/web-application.yaml`'s
`web-application/waf-cloudfront`); every other instance's `region` comes from
the stack as usual.

### Pitfall: KMS keys are regional

`kms_key_arn` encrypts the log group when set. A CLOUDFRONT-scope ACL's log
group lives in `us-east-1`; this stack's own customer-managed key (e.g.
`kms/main`) lives in the stack's usual region and cannot encrypt a `us-east-1`
resource. Leave `kms_key_arn` unset for a CLOUDFRONT instance -- the log group
then uses CloudWatch Logs' default encryption. Every `REGIONAL` instance sets
`kms_key_arn` from `kms/main` directly (not via `waf/defaults`: Atmos's deep
merge does not let a `null` override win over a non-null default, which a
CLOUDFRONT instance needs to do).

## Logging

`enable_logging` (default `true`) creates a CloudWatch log group and a
`aws_wafv2_web_acl_logging_configuration`. The log group is always named
`aws-waf-logs-<Environment>-<name>`: WAFv2 requires this exact prefix.

That prefix alone does **not** grant AWS WAF permission to write to the log
group. `PutLoggingConfiguration` (which the `aws_wafv2_web_acl_logging_configuration`
resource calls) auto-manages this by creating or extending an account-wide,
unmanaged CloudWatch Logs resource policy named `AWSWAF-LOGS`, shared by
every WAF logging configuration in the account and region. That policy
counts toward CloudWatch Logs' 10-resource-policy-per-region quota and can
hit its own size limit as more web ACLs are added. This component avoids
both by managing its own `aws_cloudwatch_log_resource_policy`, scoped to
just its log group, granting `delivery.logs.amazonaws.com`
`logs:CreateLogStream` and `logs:PutLogEvents` with `aws:SourceAccount` and
`aws:SourceArn` conditions.

## Rules

Rules are Cloud Posse-style typed lists, one per statement type:

- `managed_rule_group_statement_rules` -- AWS (or Marketplace) managed rule
  groups, e.g. `AWSManagedRulesCommonRuleSet`.
- `rate_based_statement_rules` -- requests-per-5-minutes rate limiting.
- `byte_match_statement_rules` -- a literal match against a request header
  (set `header_name`) or the URI path (leave it unset).

Every rule across all three lists needs a **priority unique within the whole
web ACL** (an AWS requirement); the component validates this across all three
lists together, not just within each one.

## Example

```yaml
web-application/waf:
  metadata:
    component: waf
    type: real
  vars:
    name: "webapp-waf"
    scope: "REGIONAL"
    association_resource_arns:
      - !terraform.state web-application/alb .alb_arn
    managed_rule_group_statement_rules:
      - name: "AWSManagedRulesCommonRuleSet"
        priority: 10
  dependencies:
    components:
      - component: web-application/alb

web-application/waf-cloudfront:
  metadata:
    component: waf
    type: real
  vars:
    region: "us-east-1"
    name: "webapp-waf-cf"
    scope: "CLOUDFRONT"
    kms_key_arn: null # us-east-1 has no matching regional key in this stack
```

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `region` | AWS region; must be `us-east-1` when `scope = CLOUDFRONT` | - |
| `tags` | Tags; must include `Environment` | - |
| `enabled` | Set to `false` to create nothing | `true` |
| `name` | Short name; resources are named `<Environment>-<name>` | - |
| `scope` | `REGIONAL` or `CLOUDFRONT` | - |
| `default_action` | `allow` or `block` for unmatched requests | `allow` |
| `association_resource_arns` | ARNs to associate (REGIONAL only) | `[]` |
| `managed_rule_group_statement_rules` | Managed rule groups | `[]` |
| `rate_based_statement_rules` | Rate-limiting rules | `[]` |
| `byte_match_statement_rules` | Header/URI byte-match rules | `[]` |
| `cloudwatch_metrics_enabled` | CloudWatch metrics for the ACL and every rule | `true` |
| `sampled_requests_enabled` | Sample matching requests | `true` |
| `metric_name` | Web ACL's own metric name | `<Environment>-<name>` |
| `enable_logging` | Create the log group and logging configuration | `true` |
| `log_group_retention_days` | Log group retention | `365` |
| `kms_key_arn` | KMS key to encrypt the log group | `null` |

## Outputs

| Name | Description |
|------|-------------|
| `arn` | Web ACL ARN (set a CloudFront distribution's `web_acl_id` to this) |
| `id` | Web ACL id |
| `name` | Web ACL name |
| `log_group_arn` | CloudWatch log group ARN, or `null` when `enable_logging` is `false` |

## Tests

`tests/waf.tftest.hcl` asserts (mock provider, no AWS calls):

- `scope = CLOUDFRONT` is rejected unless `region = us-east-1`;
- an association is only created for `scope = REGIONAL`;
- the log group name always starts with `aws-waf-logs-`;
- rule priorities must be unique across all three rule lists.

Run with `workflows/scripts/common/terraform-test.sh waf`.

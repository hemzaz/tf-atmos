# security-monitoring

Routes security findings to one KMS-encrypted SNS topic: EventBridge rules for GuardDuty findings
of severity 4.0 and above, new active failed HIGH/CRITICAL Security Hub control findings and
HIGH/CRITICAL Inspector findings; every security group
create, delete and rule change not made by automation (CloudTrail EC2 API calls); plus the four
CIS v1.2.0 metric filters and alarms on the CloudTrail log group, email subscriptions, and an
optional Slack/PagerDuty enrichment Lambda. It creates no detector, hub or Inspector enabler: the
account is a member of the organization's (vendored `aws-guardduty`, `aws-security-hub`,
`aws-inspector2`, delegated administrator in the region's `<tenant>-<env>-security` stack), and a
member's detector and hub still publish its findings to its own EventBridge.

## Wiring

- Instance: `security-monitoring/main` in the three AWS stacks, `fnx-ue2-prod` and `fnx-ec1-prod`
  (no CIS filters: no trail there) and `fnx-ew1-prod` (on its own trail's log group). A scaffolded
  nonprod stack in an account's second region (`account_singletons=no`) imports
  `catalog/security-monitoring/main-region`: no trail and no CIS filters there either, since a
  metric filter must be in its log group's region and the home stack's multi-region trail delivers
  this region's events to the home region, where its filters run.
- Reads: `cloudtrail .cloudtrail_logs_log_group_name` (the vendored `aws-cloudtrail` trail),
  `kms/main .key_arn`, `aws-iam-role/ci-apply .role.arn`. No service state (owner OQ-AL): one flag per
  route, `enable_guardduty_route`, `enable_securityhub_route`, `enable_inspector2_route`, all on.

## Notes

- Apply `kms/main` and the account's trail (`cloudtrail`) first. The routes match nothing until
  the region's org-settings enrolls the account (`deploy-security-org`, docs/OPERATIONS.md,
  Bootstrap order). Turning the GuardDuty or Security Hub route off also takes its
  `require_*_route` flag (on by default), or the plan fails: alerting is never off by one override.
- `check-data-residency.py` fails a route that is on in an account no org-settings of its tenant
  and region enrolls (an all-GDPR account in a US region, or one left out of the account map).
- `kms/main` needs `allow_eventbridge` and `allow_cloudwatch_alarms` (on in `kms/defaults`) so
  the rules and alarms can publish to the encrypted topic.
- The Security Hub rule matches `RecordState: ACTIVE` and `Workflow.Status: NEW`: a finding left in
  NEW re-alerts on each re-import until triaged.
- There is no GuardDuty CloudWatch alarm (GuardDuty publishes no findings metric); the EventBridge
  rule is the route.
- The Inspector route is on but matches nothing while `aws-inspector2/org-settings` stays
  `metadata.enabled: false` (owner OQ-IN), so there is no `require_inspector_route`.
- Security group changes alert twice by design: the EventBridge rule sends each change as it
  happens (`ModifySecurityGroupRules` included), the CIS `SecurityGroupChanges` alarm fires when
  more than `sg_changes_threshold` changes land in 5 minutes. `UpdateSecurityGroupRuleDescriptions*`
  calls are intentionally not alerted: they change a description, not what a group allows.
- The rule skips calls by the roles in `security_group_change_excluded_role_arns`; the alarm still
  counts them. The catalog lists the cluster roles and AWS Load Balancer Controller IRSA roles of
  both EKS instances (`eks/main`, `eks/data`), the EKS service-linked roles (by naming
  convention: `eks` and `eks-addons` deploy later) and the `aws-iam-role/ci-apply` role (from state). To
  exclude another role, add its exact ARN, path included, to that list in
  `stacks/catalog/security-monitoring/defaults.yaml`; wildcards are rejected. A new `eks`
  instance needs its cluster role and controller role ARNs added there.
- The enrichment Lambda posts each finding (source IPs, principals) to Slack and PagerDuty:
  `check-data-residency.py` fails `enable_alert_enrichment` in a GDPR-scoped stack.
- Root, IAM user and AWSService-type calls (`userIdentity.type` `AWSService`) carry no
  `sessionIssuer` (service-linked-role calls do), and an `anything-but` never matches
  a missing field, so the pattern is an `$or` with an `exists: false` branch that keeps them
  alerting. Renaming an excluded role (e.g. the cluster's `name`) silently re-enables its alerts.

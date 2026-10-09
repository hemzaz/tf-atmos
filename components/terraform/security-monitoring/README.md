# security-monitoring

Routes security findings to one KMS-encrypted SNS topic: EventBridge rules for GuardDuty findings
of severity 4.0 and above, new active failed HIGH/CRITICAL Security Hub control findings and,
while the inspector2 component is enabled, HIGH/CRITICAL Inspector findings; every security group
create, delete and rule change not made by automation (CloudTrail EC2 API calls); plus the four
CIS v1.2.0 metric filters and alarms on the CloudTrail log group, email subscriptions, and an
optional Slack/PagerDuty enrichment Lambda. It creates no detector, hub or Inspector enabler (one
component per service, the Cloud Posse model).

## Wiring

- Instance: `security-monitoring/main` in the three AWS stacks, `fnx-ue2-prod` (no CIS filters:
  no trail there) and `fnx-ew1-prod` (on its own trail's log group).
- Reads: `guardduty/main .detector_id`, `securityhub/main .account_arn`,
  `inspector2/main .account_id`, `cloudtrail/main .cloudtrail_logs_log_group_name`,
  `kms/main .key_arn`, `iam/ci .ci_apply_role_arn`.

## Notes

- Apply `kms/main`, `cloudtrail/main`, `guardduty/main` and `securityhub/main` first. A null input
  fails the plan on the `require_*_route` preconditions (on by default) instead of silently
  turning alerting off.
- `kms/main` needs `allow_eventbridge` and `allow_cloudwatch_alarms` (on in `kms/defaults`) so
  the rules and alarms can publish to the encrypted topic.
- The Security Hub rule matches `RecordState: ACTIVE` and `Workflow.Status: NEW`: a finding left in
  NEW re-alerts on each re-import until triaged.
- There is no GuardDuty CloudWatch alarm (GuardDuty publishes no findings metric); the EventBridge
  rule is the route.
- The Inspector route follows `inspector2_account_id`: null (inspector2 disabled, the catalog
  default) turns it off without failing the plan, so there is no `require_inspector_route`.
- Security group changes alert twice by design: the EventBridge rule sends each change as it
  happens (`ModifySecurityGroupRules` included), the CIS `SecurityGroupChanges` alarm fires when
  more than `sg_changes_threshold` changes land in 5 minutes. `UpdateSecurityGroupRuleDescriptions*`
  calls are intentionally not alerted: they change a description, not what a group allows.
- The rule skips calls by the roles in `security_group_change_excluded_role_arns`; the alarm still
  counts them. The catalog lists the cluster roles and AWS Load Balancer Controller IRSA roles of
  both EKS instances (`eks/main`, `eks/data`), the EKS service-linked roles (by naming
  convention: `eks` and `eks-addons` deploy later) and the `iam/ci` apply role (from state). To
  exclude another role, add its exact ARN, path included, to that list in
  `stacks/catalog/security-monitoring/defaults.yaml`; wildcards are rejected. A new `eks`
  instance needs its cluster role and controller role ARNs added there.
- The enrichment Lambda posts each finding (source IPs, principals) to Slack and PagerDuty:
  `check-data-residency.py` fails `enable_alert_enrichment` in a GDPR-scoped stack.
- Root, IAM user and AWSService-type calls (`userIdentity.type` `AWSService`) carry no
  `sessionIssuer` (service-linked-role calls do), and an `anything-but` never matches
  a missing field, so the pattern is an `$or` with an `exists: false` branch that keeps them
  alerting. Renaming an excluded role (e.g. the cluster's `name`) silently re-enables its alerts.

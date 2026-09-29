# cloudtrail

The account's multi-region CloudTrail trail (log file validation, global service events), its
SSE-KMS delivery bucket, and a CloudWatch log group with the IAM role the trail writes to it with.
Modelled on Cloud Posse `aws-cloudtrail` with `aws-cloudtrail-bucket` folded in; input and output
names follow Cloud Posse's.

## Wiring

- Instance: `cloudtrail/main` in the three AWS stacks; reads `kms/main .key_arn`.
- Used by: `security-monitoring` (`.cloudtrail_logs_log_group_name`, CIS metric filters and
  alarms).

## Notes

- `kms/main` must have `allow_cloudtrail` and `allow_cloudwatch_logs` (on in `kms/defaults`), or
  the trail or the log group fails to create.
- One trail per account: if two stacks ever share an account, keep `cloudtrail/main` in only one
  (a second multi-region trail duplicates every management event and its cost).
- Policy ARNs are built from names, so the bucket policy and role trust exist before the trail
  they are scoped to.
- Deploy before `security-monitoring`, whose plan fails while the log group name is null.

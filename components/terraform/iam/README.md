# iam

Creates one cross-account IAM role assumable by `trusted_account_ids` (gated
by org ID / external ID / MFA conditions), a fixed cross-account policy
(read-only discovery, prefixed S3 bucket management, explicit denies for IAM
privilege escalation and Terraform state bucket policy changes), and a
resource-management policy scoped to caller-supplied S3/DynamoDB/CloudWatch
Logs/SNS ARNs.

## Deployed

`iam/main` in fnx-staging-staging-01 and fnx-prod-production; `iam/dev` in
fnx-dev-testenv-01. `iam/ci` (all 3 stacks) and `iam/eks-node`/`iam/eks-cluster`
(staging/prod) also exist in the stack YAML but are explicitly
`enabled: false` — the stack comment says this module only manages a
cross-account role and CI/EKS roles need their own module. Don't confuse
these disabled stubs with the real `iam/main`/`iam/dev` instances.

| Inputs (required) | Inputs (behavior) | Outputs |
|---|---|---|
| region, cross_account_role_name, trusted_account_ids, policy_name, account_id, environment | require_mfa, trusted_principal_org_id, external_id, managed_s3_bucket_arns / managed_dynamodb_table_arns / managed_sns_topic_arns | cross_account_role_arn/name, cross_account_policy_arn/name — not consumed via `!terraform.state` by any current stack |

## Dependencies & gotchas

- Depends on `backend/main` (all instances).
- Trusting an account other than the current one requires org ID,
  external_id, or MFA, or the role precondition fails.
- The resource-management policy precondition requires at least one of
  managed_s3_bucket_arns/managed_dynamodb_table_arns/managed_sns_topic_arns.
- `iam/rds-monitoring`, referenced in prod's services.yaml, belongs to the
  disabled `infrastructure` component, not this module.

## Usage

```
atmos terraform plan iam/main -s fnx-prod-production
atmos terraform plan iam/dev -s fnx-dev-testenv-01
```

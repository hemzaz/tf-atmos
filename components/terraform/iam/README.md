# iam

Creates one cross-account IAM role assumable by `trusted_account_ids` (gated
by org ID / external ID / MFA conditions), a fixed cross-account policy
(read-only discovery, prefixed S3 bucket management, explicit denies for IAM
privilege escalation and Terraform state bucket policy changes), and a
resource-management policy scoped to caller-supplied S3/DynamoDB/CloudWatch
Logs/SNS ARNs. Optionally also the GitHub Actions OIDC CI roles.

## Deployed

`iam/main` in fnx-staging-staging-01 and fnx-prod-production; `iam/dev` in
fnx-dev-testenv-01. The `iam/ci` and `iam/eks-*` stack entries are still
`enabled: false`. Enabling `iam/ci` (`github_oidc_enabled: true` plus
`create_cross_account_role: false`) fills the repository variable
`AWS_PLAN_ROLE_ARN` that gates every AWS job in `.github/workflows`.

| Inputs (required) | Inputs (behavior) | Outputs |
|---|---|---|
| region, cross_account_role_name, trusted_account_ids, policy_name, account_id, environment | create_cross_account_role, require_mfa, trusted_principal_org_id, external_id, managed_s3_bucket_arns / managed_dynamodb_table_arns / managed_sns_topic_arns | cross_account_role_arn/name, cross_account_policy_arn/name — not consumed via `!terraform.state` by any current stack |
| — (every CI input is optional and inert until `github_oidc_enabled`) | github_oidc_enabled, github_oidc_repository, github_oidc_create_provider / github_oidc_provider_arn, github_oidc_default_branch, ci_role_name_prefix, ci_plan_role_subjects, ci_plan_policy_arns, ci_apply_role_enabled, ci_apply_role_environments, ci_apply_policy_arns, ci_state_bucket_name, ci_state_kms_key_arn, ci_role_max_session_duration, enable_autoscaling_service_linked_role | ci_plan_role_arn/name, ci_apply_role_arn/name, github_oidc_provider_arn, autoscaling_service_linked_role_arn |

## Dependencies & gotchas

- Depends on `backend/main` (all instances). Trusting an account other than
  the current one requires org ID, external_id, or MFA.
- The resource-management policy precondition requires at least one managed
  ARN list, so a CI-only instance must set `create_cross_account_role: false`.
- Plan and apply are deliberately separate roles: the plan role trusts
  `pull_request`, runs PR-controlled code, and must stay read-only
  (AdministratorAccess/PowerUserAccess are rejected); the apply role trusts
  only `repo:<org>/<repo>:environment:<stack>`. Wildcard subjects are rejected.
- `iam/rds-monitoring` (prod services.yaml) belongs to the disabled
  `infrastructure` component, not this module.
- `enable_autoscaling_service_linked_role` (default `false`) provisions the
  AWS Auto Scaling service-linked role that `kms/main`'s
  `allow_autoscaling_ebs` grant (see `../kms/README.md`) names directly as a
  key-policy principal. It is set `true` on exactly one instance per
  account — `iam/dev` in dev, `iam/main` in staging and prod — never on
  `iam/ci` or any second instance in the same account, and each stack's
  `kms/main` declares a `dependencies.components` edge to that instance so
  the role exists before `kms/main`'s first apply.
  **If the role already exists** (any account that has ever run an ASG or
  an EKS managed node group outside this repo has it — check first with
  `aws iam get-role --role-name AWSServiceRoleForAutoScaling`), note that
  the committed stacks already set the flag `true` on that one instance per
  account (`iam/dev` in dev, `iam/main` in staging and prod —
  `stacks/orgs/fnx/<stage>/.../components/security.yaml`), so you have two
  correct options. (a) Set `enable_autoscaling_service_linked_role: false`
  on that stack's `iam` instance in its `security.yaml` and do nothing
  else: `kms/main` only needs the role to exist, not to be managed by this
  resource, so the `dependencies.components` edge is satisfied either way.
  (b) Leave the flag `true` and instead import the role into that same
  instance first, at the indexed address — the resource sits behind
  `count`, so the unindexed address does not exist. Use `iam/dev` in dev or
  `iam/main` in staging and prod:
  ```
  atmos terraform import iam/dev 'aws_iam_service_linked_role.autoscaling[0]' \
    arn:<partition>:iam::<account>:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling \
    -s <stack>   # iam/dev in dev; iam/main in staging and prod
  ```
  Once imported, never flip the flag back to `false` afterward — the next
  plan would destroy the imported role.

## Usage

`atmos terraform plan iam/main -s fnx-prod-production` (or `iam/ci`).

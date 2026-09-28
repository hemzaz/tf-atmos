# iam

Creates one cross-account IAM role assumable by `trusted_account_ids` (gated
by org ID / external ID / MFA conditions), a fixed cross-account policy
(read-only discovery, prefixed S3 bucket management, explicit denies for IAM
privilege escalation and Terraform state bucket policy changes), and a
resource-management policy scoped to caller-supplied S3/DynamoDB/CloudWatch
Logs/SNS ARNs. Optionally also the GitHub Actions OIDC CI roles.

## Deployed

`iam/main` in fnx-staging-staging-01 and fnx-prod-production; `iam/dev` in
fnx-dev-testenv-01. `iam/ci` is enabled (no `enabled: false` override) in all
three stacks: `github_oidc_enabled: true` plus `create_cross_account_role:
false` fills the repository variable `AWS_PLAN_ROLE_ARN` that gates every AWS
job in `.github/workflows`. There is no `iam/eks-*` instance anywhere in this
repo; EKS node groups use the managed `aws_iam_role.node` that
`components/terraform/eks` itself creates, not a separate `iam` instance.

| Inputs (required) | Inputs (behavior) | Outputs |
|---|---|---|
| region, cross_account_role_name, trusted_account_ids, policy_name, account_id, environment | create_cross_account_role, require_mfa, trusted_principal_org_id, external_id, managed_s3_bucket_arns / managed_dynamodb_table_arns / managed_sns_topic_arns | cross_account_role_arn/name, cross_account_policy_arn/name — not consumed via `!terraform.state` by any current stack |
| — (every CI input is optional and inert until `github_oidc_enabled`) | github_oidc_enabled, github_oidc_repository, github_oidc_create_provider / github_oidc_provider_arn, github_oidc_default_branch, ci_role_name_prefix, ci_plan_role_subjects, ci_plan_policy_arns, ci_apply_role_enabled, ci_apply_role_environments, ci_apply_policy_arns, ci_backend_read_role_arn, ci_backend_write_role_arn, ci_apply_kms_key_aliases, ci_role_max_session_duration, enable_autoscaling_service_linked_role | ci_plan_role_arn/name, ci_apply_role_arn/name, github_oidc_provider_arn, autoscaling_service_linked_role_arn |

## Dependencies & gotchas

- Depends on `backend/main` in `fnx-core-root` (all instances; a cross-stack
  `dependencies.components` entry with `stack: fnx-core-root`). Trusting an
  account other than the current one requires org ID, external_id, or MFA.
- State access for the CI roles is only `sts:AssumeRole` on the single state
  backend's access roles (`../backend/README.md`): the plan role on the
  read-only role (`ci_backend_read_role_arn`), the apply role on the
  read/write role (`ci_backend_write_role_arn`). Each `iam/ci` reads both from
  `!terraform.state backend/main fnx-core-root .backend_read_role_arn` /
  `.backend_role_arn`. There is no S3/KMS grant on the bucket itself, so a
  plan cannot write or delete a `.tflock` object: CI plans run with
  `-lock=false`. The backend, in turn, trusts these roles by name
  (`<ci_role_name_prefix>-plan` / `-apply`), not by reading this component's
  outputs, which is what keeps the two out of a dependency cycle.
- `ci_plan_role_subjects` in production is the default-branch subject only
  (owner decision D3): prod is planned from master, never from a PR.
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
- `ci_apply_kms_key_aliases` (default `null`, list of `alias/...` names)
  grants the apply role `kms:DescribeKey`/`Encrypt`/`Decrypt`/`ReEncrypt*`/
  `GenerateDataKey*` on the named key(s), plus `CreateGrant`/`ListGrants`/
  `RevokeGrant` in a second statement scoped by `kms:GrantIsForAWSResource`
  (AWS's own pattern for AWS-service-managed grants), inert on the same
  `ci_apply_role_enabled` gate as `ci_backend_write_role_arn` above. Set it to
  `["alias/<kms/main's alias_name>"]` (e.g. `["alias/production-main"]`),
  never a key ARN via `!terraform.state kms/main .key_arn`: this component's
  `iam/ci` instance plans and applies in the layer *before* `kms/main`
  (`workflows/deploy-full-stack.yaml`), so on a first deploy the key's ARN
  does not exist yet, and reading it here would make `iam` depend on `kms`
  while `kms/main` already depends on `iam` (`allow_autoscaling_ebs`'s
  service-linked role) — a cycle `check-deploy-layers.py` rejects. The
  policy scopes `resources = ["*"]` with a `kms:ResourceAliases` condition
  instead: AWS derives that condition key from the KMS key an operation
  actually acts on, regardless of how the request named it, so this is still
  an exact-match grant, not a wildcard one. AWS requires the principal that
  calls `eks:CreateCluster`/`UpdateClusterConfig` — not the EKS cluster's own
  service role — to hold `DescribeKey`/`CreateGrant`/`Encrypt` on the key
  named in `cluster_encryption_config_kms_key_id` ("Encrypting Kubernetes
  secrets", AWS EKS docs); other `kms/main` consumers this role deploys
  (secretsmanager, rds, elasticache, ec2) need `Encrypt`/`Decrypt`/
  `GenerateDataKey*` on it too. This is the Cloud Posse pattern of a
  consumer's own IAM policy, never a key-policy `key_users` entry
  (`../kms/README.md`; see `cloudposse/terraform-aws-kms-key`'s default
  root-delegation key policy for the upstream analog — `cloudposse-
  terraform-components/aws-eks-cluster`'s `github-actions-iam-policy.mixin.tf`
  `AllowKMSAccess` statement is prior art for a CI role holding its own
  scoped KMS IAM statement, not for this specific EKS grant).

## Usage

`atmos terraform plan iam/main -s fnx-prod-production` (or `iam/ci`).

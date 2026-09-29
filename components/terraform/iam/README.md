# iam

An optional cross-account role (trust gated by org ID, external ID or MFA) with a fixed
cross-account policy and a resource-management policy scoped to caller-supplied ARNs, and
optionally the GitHub Actions OIDC provider with separate CI plan and apply roles.

## Wiring

- Instances: `iam/ci` in the three AWS stacks (OIDC roles only, `create_cross_account_role:
  false`); `iam/dev` in dev; `iam/main` in staging, prod and `fnx-local-localemu`. The AWS-stack
  instances depend on `backend/main` in `fnx-core-root` for ordering only (localemu's does not).
- Used by: `eks` (`iam/ci .ci_plan_role_arn` / `.ci_apply_role_arn` as access entries), `kms/main`
  (dependency on the instance that creates the Auto Scaling service-linked role). The backend
  trusts the CI roles by name (`<ci_role_name_prefix>-plan` / `-apply`), not by reading state.

## Notes

- Plan role: trusts `pull_request` and branch subjects, stays read-only (AdministratorAccess and
  PowerUserAccess are rejected). In prod it trusts the default branch only.
- Apply role: `AdministratorAccess`, trusted only for `repo:<org>/<repo>:ref:refs/heads/<branch>`
  from `ci_apply_role_trusted_github_repos` (Cloud Posse's `trusted_github_repos` shape). There is
  no GitHub Environment approval: every merge to master applies, prod included. Branch
  protection is the gate.
- State access is only `sts:AssumeRole` on the backend's stage access roles
  (`ci_backend_read_role_arns`, `ci_backend_write_role_arn`); no direct bucket grant, so CI plans
  run with `-lock=false`.
- `ci_apply_kms_key_aliases` takes `alias/...` names, never a key ARN: `iam/ci` applies before
  `kms/main`, and reading its state would create a cycle `check-deploy-layers.py` rejects.
- `enable_autoscaling_service_linked_role` is `true` on exactly one instance per account
  (`iam/dev`, `iam/main`). If `AWSServiceRoleForAutoScaling` already exists
  (`aws iam get-role --role-name AWSServiceRoleForAutoScaling`), the create fails: set the flag
  `false`, or import it at `'aws_iam_service_linked_role.autoscaling[0]'` and never flip it back.
- A resource-management precondition requires at least one managed ARN list, so a CI-only
  instance must set `create_cross_account_role: false`.

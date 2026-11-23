# iam

The GitHub Actions OIDC provider with separate CI plan and apply roles, and a Lambda package
uploader role for an application repo's CI. The account's Auto Scaling service-linked role is the
vendored `aws-iam-service-linked-roles` (`catalog/aws-iam-service-linked-roles`, E6a2). Human access
is IAM Identity Center (`catalog/aws-identity-center`), Cloud Posse's model, so there is no
cross-account operator role.

## Wiring

- Instances: `iam/ci` in the AWS stacks (OIDC roles only). It depends on `backend/main` in
  `fnx-ue1-root` for ordering only.
- Used by: `eks` (`iam/ci .ci_plan_role_arn` / `.ci_apply_role_arn` as access entries). The backend
  trusts the CI roles by name (`<ci_role_name_prefix>-plan` / `-apply`), not by reading state.

## Notes

- Plan role: trusts `pull_request` and branch subjects, stays read-only (AdministratorAccess and
  PowerUserAccess are rejected). In prod it trusts the default branch only.
- Apply role: `AdministratorAccess`, trusted only for `repo:<org>/<repo>:ref:refs/heads/<branch>`
  from `ci_apply_role_trusted_github_repos` (Cloud Posse's `trusted_github_repos` shape). There is
  no GitHub Environment approval: every merge to master applies, prod included. Branch
  protection is the gate.
- The CI apply role may `autoscaling:ExecutePolicy` on the groups named in `ci_runner_pool_names`
  (this stack's github-runners pools) and nothing else: CI starts an ephemeral in-VPC runner per
  in-cluster job through the pool's `+1` start policy (`ci-runner-pools.tf`) and cannot set a
  capacity. Every in-VPC job runs on the default branch with the apply role, so the plan role
  (which trusts pull requests) gets no write.
- State access is only `sts:AssumeRole` on the backend's stage access roles
  (`ci_backend_read_role_arns`, `ci_backend_write_role_arn`); no direct bucket grant, so CI plans
  run with `-lock=false`.
- `ci_apply_kms_key_aliases` takes `alias/...` names, never a key ARN: `iam/ci` applies before
  `kms/main`, and reading its state would create a cycle `check-deploy-layers.py` rejects.
- Lambda uploader (`lambda-uploader.tf`): `<ci_role_name_prefix>-lambda-uploader`, created only
  when `lambda_uploader_trusted_github_repos` names an app repo (`<org>/<repo>:<branch>`, same
  validation as the apply role's). It may put/get objects in, and list, the stage's
  `s3/lambda-artifacts` bucket and use `lambda_uploader_kms_key_alias` via S3 only. The bucket
  is named, not read (`<tags.Environment>-lambda-artifacts-<account id>`, the s3 component's
  convention), because `iam/ci` applies before storage; `check-lambda-packages.py` fails lint
  when the stack's bucket or `kms/main` alias stops matching. Puts are allowed only when
  conditional (`If-None-Match: *`, e.g. `aws s3api put-object --if-none-match '*'`), so
  re-uploading a released version fails by design: ship a new version instead.

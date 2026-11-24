# iam

A Lambda package uploader role for an application repo's CI, until E6a5 moves it to the vendored
`aws-iam-role`. The GitHub Actions OIDC CI plan and apply roles are the vendored `aws-iam-role`'s
`aws-iam-role/ci-plan` and `aws-iam-role/ci-apply` (`catalog/aws-iam-role/ci.yaml`, E6a4). The
uploader trusts the account's GitHub OIDC provider, the vendored `aws-github-oidc-provider`
(`catalog/aws-github-oidc-provider`, E6a3), by the ARN that `catalog/iam/defaults.yaml` derives
from the account ID. The account's Auto Scaling service-linked role is the vendored
`aws-iam-service-linked-roles` (`catalog/aws-iam-service-linked-roles`, E6a2). Human access is IAM
Identity Center (`catalog/aws-identity-center`), Cloud Posse's model, so there is no cross-account
operator role.

## Wiring

- Instances: `iam/ci` in the AWS stacks (the uploader only). It depends on `backend/main` in
  `fnx-ue1-root` and on its account's `aws-github-oidc-provider` (a DR standby on its primary's,
  `settings.dr.standby_of`), for ordering only; the iam layer applies both.
- Used by: nothing reads its state.

## Notes

- Lambda uploader (`lambda-uploader.tf`): `<ci_role_name_prefix>-lambda-uploader`, created only
  when `lambda_uploader_trusted_github_repos` names an app repo (`<org>/<repo>:<branch>`; wildcards,
  `pull_request` and `environment:` subjects are rejected). It may put/get objects in, and list, the
  stage's `s3/lambda-artifacts` bucket and use `lambda_uploader_kms_key_alias` via S3 only. The
  bucket is named, not read (`<tags.Environment>-lambda-artifacts-<account id>`, the s3
  component's convention), because `iam/ci` applies before storage; `check-lambda-packages.py`
  fails lint when the stack's bucket or `kms/main` alias stops matching. Puts are allowed only
  when conditional (`If-None-Match: *`, e.g. `aws s3api put-object --if-none-match '*'`), so
  re-uploading a released version fails by design: ship a new version instead.
- `lambda_uploader_kms_key_alias` takes an `alias/...` name, never a key ARN: `iam/ci` applies
  before `kms/main`, and reading its state would create a cycle `check-deploy-layers.py` rejects.

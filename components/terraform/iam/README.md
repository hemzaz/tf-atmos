# iam

Empty: every role it created is now a vendored Cloud Posse component's, and E6a6 deletes it and
the `iam/ci` instances. The GitHub Actions OIDC CI plan and apply roles and the Lambda package
uploader are the vendored `aws-iam-role`'s `aws-iam-role/ci-plan`, `aws-iam-role/ci-apply`
(`catalog/aws-iam-role/ci.yaml`, E6a4) and `aws-iam-role/lambda-uploader`
(`catalog/aws-iam-role/lambda-uploader.yaml`, E6a5); the account's GitHub OIDC provider is the
vendored `aws-github-oidc-provider` (E6a3) and its Auto Scaling service-linked role the vendored
`aws-iam-service-linked-roles` (E6a2). Human access is IAM Identity Center
(`catalog/aws-identity-center`), Cloud Posse's model.

## Wiring

- Instances: `iam/ci` in the AWS stacks, which creates nothing. It keeps its dependencies on
  `backend/main` and the account's `aws-github-oidc-provider` until E6a6 removes it.
- Used by: nothing reads its state.

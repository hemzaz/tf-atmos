# The GitHub Actions OIDC provider the Lambda uploader role (lambda-uploader.tf)
# trusts. The CI plan and apply roles are the vendored aws-iam-role's
# aws-iam-role/ci-plan and aws-iam-role/ci-apply (stacks/catalog/aws-iam-role/ci.yaml,
# E6a4), and the uploader moves there in E6a5.

locals {
  # The account's provider is the vendored aws-github-oidc-provider's (E6a3);
  # its ARN is derived in the catalog (stacks/catalog/iam/defaults.yaml).
  github_oidc_provider_arn = var.github_oidc_provider_arn
}

# Integrations

CI/CD integrations for running Atmos outside GitHub Actions. Both take `TENANT`/`STAGE` (or
`ACCOUNT`)/`ENVIRONMENT`/`COMPONENT` parameters and derive the stack name and account from them.

## Atlantis

`atlantis.yaml`: a custom `atmos` workflow (plan/apply) plus a `production` workflow with extra
checks (blocks `aws_iam_user`/`aws_access_key` and public-access/ACL misconfiguration in `*.tf`,
adds a confirmation pause) for stacks whose name contains `-prod-`. Plans go through Atlantis'
`$PLANFILE`; apply retries with exponential backoff and runs a post-apply `plan` to catch drift.
`apply_requirements` add `approved-by-security-team:prod` for production. See
`atlantis/scripts/atmos-wrapper.sh` for the account-resolution logic and `atlantis/Dockerfile` for
the image (Atmos + Terraform + AWS CLI + jq).

## Jenkins

`Jenkinsfile`: a parameterized pipeline (`TENANT`, `STAGE`, `ACCOUNT`, `ENVIRONMENT`, `COMPONENT`,
plus an action choice) with stages Setup → Repository Structure Detection → Lint and Validate →
Plan → Approval → Apply → Destroy → Validation Tests. Setup resolves the target account with
`atmos describe stacks --process-functions=false` and assumes a per-account role from Jenkins
credentials (`<account>-role-arn`) unless the account is `dev`.

## Setup

Both need a working Atmos config, AWS credentials for the CI system (cross-account IAM roles, not
long-lived keys), and the repository checked out. Atlantis also needs its webhook installed on the
repo; Jenkins needs the per-account credential IDs referenced above created first.

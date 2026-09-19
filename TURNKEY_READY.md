# Readiness Status

What works today, what is deliberately switched off, and what still needs a human before the first
`apply`. Verify any line here with `atmos list stacks`, `atmos list components`,
`atmos list workflows` and `atmos describe component <component> -s <stack>`.

## Ready

- **Toolchain**: Atmos >= 1.229.0 is enforced by `atmos.yaml`. Terraform 1.16.3 and the lint, scan
  and AWS CLI tools are pinned in `dependencies.tools` and installed by Atmos.
- **Providers**: root modules use AWS provider `~> 6.65` (shared modules `>= 6.0, < 7.0`),
  Kubernetes and Helm providers 3.x. Every root module has `versions.tf` and a `provider.tf` with
  `default_tags`.
- **Stacks**: `fnx-dev-testenv-01`, `fnx-staging-staging-01` and `fnx-prod-production` validate
  offline (`atmos validate stacks`, `atmos workflow validate-all -f validate-enhanced`).
- **State**: one S3 bucket (`fnx-terraform-state`) with native lockfiles (`use_lockfile`), no
  DynamoDB. Bootstrap, lock and state-version workflows exist (`bootstrap`, `state-operations`,
  `disaster-recovery`).
- **CI/CD**: Atmos Native CI in GitHub Actions with OIDC. PRs get lint, validation, a security gate
  against committed baselines, and plans of affected components. Merges deploy affected components
  per stack, gated by GitHub Environments and tracked with `deployed/<stack>` tags. Hourly drift
  detection and a nightly security scan run on a schedule.
- **Workflows**: layered deployment, per-stack plan/apply, drift, imports, DR runbooks, security
  hardening, compliance reports, certificate rotation, stack templates. See
  `atmos list workflows`.

## Deliberately not deployed

| Item | State | Why |
|------|-------|-----|
| `idp-platform` | Not in any stack; `plan` fails unless `acknowledge_unsupported = true` | It nests root modules that have their own provider blocks. See its [README](./components/terraform/idp-platform/README.md) |
| `iam/ci`, `iam/eks-node`, `iam/eks-cluster` | `metadata.enabled: false` | The `iam` module only manages a cross-account role; CI and EKS roles need their own module |
| `infrastructure/main`, `infrastructure/data`, `vpc-flow-logs-bucket` | Disabled in all stacks | Neither an `infrastructure` nor a `vpc-flow-logs-bucket` root module exists yet |
| `guardduty/main`, `securityhub/main`, `network/vpc-peering` (prod) | Disabled | No matching root modules; GuardDuty and Security Hub are enabled by `atmos workflow harden -f security-hardening` |
| Stack templates | Present in `stacks/catalog/templates/`, imported by no stack | Opt-in; see [Quick Deploy](./docs/QUICK_DEPLOY.md#deploying-a-stack-template) |

## Needs a human before the first apply

The full list, with file locations, is in
[Manual prerequisites before first apply](./docs/DEPLOYMENT_GUIDE.md#manual-prerequisites-before-first-apply).
In short: real account IDs, the management account ID, the AWS Organization ID (`o-xxxxxxxxxx`),
domains and hosted zones (`example.com`), alert recipients and prod alarm SNS topic ARNs, `kms/main`
key users, the backend role, GitHub Environments and variables with OIDC trust, `deployed/<stack>`
tags pointing after the stack-reconcile merge, and migration of any existing state.

## Known gaps

- Every stack defines a `backend/main` instance for the same global bucket name; manage the bucket
  from one stack only.
- The layered `deploy-full-stack` workflow does not include `kms`; in production deploy
  `kms/main` before the compute layer.
- Nothing has been applied from this configuration yet, so the first plans against real accounts
  are the real test.

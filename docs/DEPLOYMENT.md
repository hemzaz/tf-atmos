# Deployment Guide

How to take one of the three stacks (`fnx-dev-testenv-01`, `fnx-staging-staging-01`,
`fnx-prod-production`) from nothing to deployed.

## Manual prerequisites before first apply

The stack configuration still contains placeholders. Replace every item below before running
`apply` or `deploy` against a real account.

| Input | Where | Placeholder today |
|-------|-------|-------------------|
| Workload account IDs | `settings.environment.account_id` in `stacks/orgs/fnx/{dev,staging,prod}/_defaults.yaml`; `settings.environment.aws_account_id` in `staging-01.yaml` and `production.yaml` | `123456789012` |
| Dev account ID | `testenv-01.yaml` reads it from the `AWS_ACCOUNT_ID` environment variable | export `AWS_ACCOUNT_ID` before running Atmos for dev |
| Management account ID | `settings.environment.management_account_id` in `stacks/orgs/fnx/_defaults.yaml` (backend role ARN, IAM trust) | `123456789012` |
| AWS Organization ID | `trusted_principal_org_id` in `stacks/catalog/iam/defaults.yaml` | `o-xxxxxxxxxx` |
| Domains and hosted zones | `domain_name`/`hosted_zone_id` in each stack's `components/globals.yaml`; `root_domain` and zone names in `components/networking.yaml` | `example.com`, `Z1234567890EXAMPLE` |
| Alert recipients | `alarm_email_subscriptions` on the monitoring instances, and notification lists in `components/globals.yaml`; every address must confirm its SNS subscription | `*@example.com` |
| Prod alarm SNS topic ARNs | Prod alarms that must reach an existing paging/on-call topic, e.g. `rds`'s `sns_topic_arn` | not set |
| KMS key users | `key_users`/`key_administrators` of `kms/main` in `stacks/orgs/fnx/prod/eu-west-2/production/components/security.yaml`; the roles must exist first (`iam/ci` and `iam/eks-node` are disabled, so use the real role ARNs) | placeholder role names |
| Backend role | `fnx-terraform-backend-role` in the management account; every backend config assumes it, so it must exist and trust the deploy/plan roles before the first `terraform init` | created by the `backend` component |
| GitHub Environments | One per stack, named exactly like the stack, with `vars.AWS_ROLE_ARN` (deploy role); deployment branches: default branch only; add required reviewers to `fnx-prod-production` | none |
| GitHub repo variables | `AWS_PLAN_ROLE_ARN` (read-only plan role for PR plans, drift detection, DR checks); optional `ATMOS_VERSION`, `AWS_REGION` | none |
| OIDC trust | Deploy role: `sub = repo:<org>/<repo>:environment:<stack>`. Plan role: `sub = repo:<org>/<repo>:pull_request` and `...:ref:refs/heads/<default branch>`. Both: `aud = sts.amazonaws.com` | none |
| Deploy marker tags | One `deployed/<stack>` tag per stack, so CD knows what's already live | none |
| Existing state | If state exists under an older bucket/key layout, migrate it first (below) | n/a |

```bash
# Bootstrap the deploy tags once per stack
git tag deployed/fnx-dev-testenv-01 <last-deployed-sha>
git push origin deployed/fnx-dev-testenv-01
```

### Migrating existing state

State lives in one S3 bucket, `fnx-terraform-state`, with native lockfiles and no DynamoDB table.

```bash
atmos describe component vpc/main -s fnx-dev-testenv-01   # .backend (bucket, workspace_key_prefix), .workspace
```

If an instance already has state under a different bucket/key, copy it to the new location first,
or Terraform will plan to recreate the resources:

```bash
aws s3 cp s3://<old-bucket>/<old-key> ./old.tfstate
atmos terraform state push vpc/main -s fnx-dev-testenv-01 ./old.tfstate
atmos terraform plan vpc/main -s fnx-dev-testenv-01   # expect no resource replacements
```

The `network/*` instances use the `dns` root module; state from a different module won't match its
addresses, so import the existing zones instead (`atmos workflow import -f import -s <stack>`).

## Bootstrap the state backend

```bash
atmos workflow full -f bootstrap -s fnx-dev-testenv-01           # backend, IAM, VPCs
atmos workflow backend-only -f bootstrap -s fnx-dev-testenv-01   # backend only
atmos workflow verify -f bootstrap -s fnx-dev-testenv-01         # backend describe + outputs
```

All three stacks share one bucket, `fnx-terraform-state` (S3 bucket names are global), reached
through `fnx-terraform-backend-role`. Manage the bucket from one stack only; the `backend/main`
instance in the other stacks will otherwise conflict with it.

## Deploy the stack

`workflows/deploy-full-stack.yaml` deploys in layers. Each layer selects instances by root module
(`metadata.component`), plans them, shows the plans, asks for confirmation, then applies exactly
those planfiles (`terraform deploy --from-plan`).

| Layer | Workflow | Root modules |
|-------|----------|--------------|
| foundation | `deploy-foundation` | `backend`, `iam` |
| kms | `deploy-kms` | `kms` |
| networking | `deploy-networking` | `vpc`, `dns`, `securitygroup` |
| security | `deploy-security` | `acm`, `secretsmanager`, `security-monitoring` |
| compute | `deploy-compute` | `eks`, `ec2`, `ecs` |
| platform | `deploy-platform` | `eks-addons`, `external-secrets` |
| data | `deploy-data` | `rds`, `backup` |
| services | `deploy-services` | `apigateway`, `lambda`, `eks-backend-services` |
| monitoring | `deploy-monitoring` | `monitoring`, `cost-optimization` |

```bash
atmos workflow deploy -f deploy-full-stack -s fnx-dev-testenv-01                 # all layers
atmos workflow deploy-networking -f deploy-full-stack -s fnx-dev-testenv-01      # one layer
```

The `kms` layer only has work in stacks with an enabled `kms` component (today
`fnx-prod-production`, whose EKS/EC2/RDS read the key via `!terraform.state`); elsewhere it plans
nothing and the prompt just asks to continue.

Other ways to deploy:

```bash
atmos workflow apply -f apply-environment -s <stack>      # whole stack: plan, one confirmation, deploy
atmos terraform plan <component> -s <stack>               # one instance
atmos terraform deploy <component> -s <stack>              # one instance: plan + apply
atmos workflow component -f deploy-application -s <stack> # one instance, name entered at a prompt
```

Disabled instances (`metadata.enabled: false`) are skipped: `iam/ci`, `iam/eks-node`,
`iam/eks-cluster`, `infrastructure/*`, `vpc-flow-logs-bucket`, and in prod `guardduty/main`,
`securityhub/main` and `network/vpc-peering`. No stack deploys `idp-platform`.

## Deploying a stack template

`stacks/catalog/templates/` has five opt-in templates (`web-application`, `microservices-platform`,
`serverless-api`, `data-pipeline`, `batch-processing`); none of the three existing stacks imports
one today. A stack uses one by importing it and setting its required variables — see
[stacks/README.md](../stacks/README.md#stack-templates). Then:

```bash
atmos workflow deploy -f deploy-template -s <stack>              # choose, plan, confirm, deploy, verify
atmos workflow deploy-serverless -f deploy-template -s <stack>   # quick deploy, no confirmation
atmos workflow deploy-parallel -f deploy-template -s <stack>     # independent components concurrently
```

## Deploy through CI/CD

After the GitHub prerequisites above are in place:

- **Pull requests** (`terraform-ci.yml`): lint, validation, a security gate (fails only on new
  HIGH/CRITICAL Trivy/Checkov findings not already in `.trivyignore.yaml`/`.checkov.baseline`), and
  a plan of every affected component with the read-only plan role, posted as PR comments.
- **Merges to the default branch** (`terraform-cd.yml`): for each stack in turn (dev, staging,
  prod), runs `atmos terraform deploy --affected` against the stack's `deployed/<stack>` tag inside
  its GitHub Environment, then moves the tag.
- **Manual runs**: `terraform-cd.yml` can plan or deploy one stack (optionally one component) from
  the default branch.

Destroy is not exposed in CI; use `atmos workflow destroy -f destroy-environment` locally.

## Applies clean, does not serve traffic

These are deliberate, not defects. Each one will `apply` green and then not do the thing its
name suggests, because the missing piece is a real-world consumer this repo does not manage.
Nothing here blocks a deploy; all of it blocks a working system.

| What | Where | Why it is empty | To make it work |
|------|-------|-----------------|-----------------|
| Prod Redis reachable by nothing | `elasticache/main` in `stacks/orgs/fnx/prod/eu-west-2/production/components/services.yaml` — `allowed_security_group_ids: []`, `allowed_cidr_blocks: []` | Fail-closed on purpose. The `ecs` component is cluster-only (no service, no security group output) and `securitygroup` is instantiated nowhere, so there is no consumer group to name. | Add the consuming service's security group id once one exists. The component exports `security_group_id` for the reverse direction. `0.0.0.0/0` is rejected by validation. |
| Cognito pool with no way in | `cognito/main` in every stack | The pool has clients but no users and no federated identity provider. `/api` sits behind `COGNITO_USER_POOLS`, so every request is rejected. | Create users, or configure a federated IdP — both need real credentials that do not belong in this repo. |
| `/` returns a canned 200 | `apigateway/main`, `apigateway/data` — the `/` method stays `MOCK` | Intentional. `/` is a liveness endpoint and a canned 200 is the correct answer for one. | Nothing. `/api` and `/data` are the real Lambda-backed routes. |
| Lambda has no deployment package | every `lambda/*` instance | No instance sets `filename`, `s3_bucket`+`s3_key`, or `image_uri`, and the component does not cross-validate that one is set. Whether this fails at apply is **unverified** — `terraform validate` and `plan` both pass. | Set a package source before the first real apply, and check the result. |
| CI never plans anything | `.github/workflows/terraform-ci.yml` gates the plan job on `vars.AWS_PLAN_ROLE_ARN != ''` | The variable is unset, so every run reports Plan SKIPPED. | Set `AWS_PLAN_ROLE_ARN` to a read-only role (see the prerequisites table). Highest-value change here: it needs no apply, and it would have caught the Lambda VPC egress defect fixed in v1.1.0. |

## Verify and rollback

```bash
atmos workflow verify -f bootstrap -s <stack>
atmos terraform output eks/main -s <stack>
atmos workflow drift-detection -f drift-detection -s <stack>   # should report no changes
```

- **Configuration change**: revert the commit and merge; CD redeploys the affected components.
- **State**: the bucket is versioned — see [Operations Guide](./OPERATIONS.md#state-recovery).
- **Whole stack**: `atmos workflow destroy -f destroy-environment` (type the stack name to confirm)
  removes every component in reverse dependency order.

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `This repository requires Atmos >= 1.229.0` | Upgrade Atmos |
| `init` fails to assume `fnx-terraform-backend-role` | Role doesn't exist yet, or isn't trusted — see prerequisites above |
| `Error acquiring the state lock` | Another run holds the lockfile; see [Operations Guide](./OPERATIONS.md#state-locks) |
| `!terraform.state` returns nothing | Referenced component hasn't been deployed in that stack yet; deploy in layer order |
| Plan wants to recreate existing resources | State wasn't migrated to the new backend layout; see above |

See the [Operations Guide](./OPERATIONS.md) for day-2 tasks.

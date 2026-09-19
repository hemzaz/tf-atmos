# Deployment Guide

How to take one of the three stacks (`fnx-dev-testenv-01`, `fnx-staging-staging-01`,
`fnx-prod-production`) from nothing to deployed, and how to roll back.

1. [Tooling](#tooling)
2. [Manual prerequisites before first apply](#manual-prerequisites-before-first-apply)
3. [Validate offline](#validate-offline)
4. [Bootstrap the state backend](#bootstrap-the-state-backend)
5. [Deploy the stack](#deploy-the-stack)
6. [Deploy through CI/CD](#deploy-through-cicd)
7. [Verify](#verify)
8. [Rollback](#rollback)
9. [Troubleshooting](#troubleshooting)

---

## Tooling

| Tool | Version | Notes |
|------|---------|-------|
| Atmos | >= 1.229.0 | Enforced by `atmos.yaml` (`version.constraint`, fatal) |
| Terraform | 1.16.3 | Installed by Atmos from `terraform.dependencies.tools` in `stacks/orgs/fnx/_defaults.yaml` |
| AWS provider | `~> 6.65` | Root modules; shared modules accept `>= 6.0, < 7.0` |
| kubectl | any recent | Only to inspect EKS clusters after deployment |

Workflows that need tflint, yamllint, trivy, checkov, the AWS CLI or jq declare them in
`dependencies.tools`, and Atmos installs them on first use.

```bash
atmos version
atmos list stacks
atmos list workflows
```

---

## Manual prerequisites before first apply

The stack configuration still contains placeholders. Replace every item below before running
`apply` or `deploy` against a real account.

| Input | Where | Placeholder today |
|-------|-------|-------------------|
| Workload account IDs | `settings.environment.account_id` in `stacks/orgs/fnx/{dev,staging,prod}/_defaults.yaml`; `settings.environment.aws_account_id` in `staging-01.yaml` and `production.yaml` | `123456789012` |
| Dev account ID | `aws_account_id` in `testenv-01.yaml` is read from the `AWS_ACCOUNT_ID` environment variable | set `AWS_ACCOUNT_ID` when running Atmos for dev |
| Management account ID | `settings.environment.management_account_id` in `stacks/orgs/fnx/_defaults.yaml` (backend role ARN and IAM trust) | `123456789012` |
| AWS Organization ID | `trusted_principal_org_id` in `stacks/catalog/iam/defaults.yaml` | `o-xxxxxxxxxx` |
| Domains and hosted zones | `domain_name` and `hosted_zone_id` in each stack's `components/globals.yaml`; `root_domain` and zone names in `components/networking.yaml` | `example.com`, `fnx.example.com`, `Z1234567890EXAMPLE`, ... |
| Alert recipients | `alarm_email_subscriptions` of the monitoring instances in each stack's `components/services.yaml`, and the notification lists in `components/globals.yaml`. The monitoring component creates the SNS topics (`create_sns_topic: true`); every address must confirm its subscription | `*@example.com` |
| Production alarm SNS topic ARNs | Prod alarms that must reach an existing SNS topic (paging or on-call tooling) need that topic's ARN, e.g. the `rds` component's `sns_topic_arn` input | not set anywhere |
| KMS key users | `key_users` (and `key_administrators`) of `kms/main` in `stacks/orgs/fnx/prod/eu-west-2/production/components/security.yaml`. The roles must exist before apply; `iam/ci` and `iam/eks-node` are disabled, so use the real EKS node role and CI role ARNs | `production-eks-node-role`, `production-ci-role`, `Admin` |
| Backend role | `fnx-terraform-backend-role` in the management account. Every backend configuration (including `backend/main`'s own) assumes it, so it must exist and trust your deploy and plan roles before the first `terraform init` | created by the `backend` component |
| GitHub Environments | One Environment per stack, named exactly like the stack, with `vars.AWS_ROLE_ARN` (deploy role). Deployment branches: the default branch only. Add required reviewers to `fnx-prod-production` | none |
| GitHub repository variables | `AWS_PLAN_ROLE_ARN` (read-only plan role for PR plans, drift detection and DR checks); optional `ATMOS_VERSION`, `AWS_REGION` | none |
| OIDC trust | Deploy role: `sub = repo:<org>/<repo>:environment:<stack>`. Plan role: `sub = repo:<org>/<repo>:pull_request` and `repo:<org>/<repo>:ref:refs/heads/<default branch>`. Both: `aud = sts.amazonaws.com`. See the headers of `.github/workflows/terraform-ci.yml` and `terraform-cd.yml` | none |
| Deploy marker tags | One `deployed/<stack>` tag per stack. It must point at a commit **after** the stack-reconcile merge (`68f8153`), otherwise the first CD run diffs against pre-modernization config. Add a tag ruleset so only GitHub Actions can move `refs/tags/deployed/**` | none |
| Existing state | If state already exists under an older bucket or key layout, migrate it first (see below) | n/a |

Bootstrap the tags once per stack:

```bash
git tag deployed/fnx-dev-testenv-01 <last-deployed-sha>
git push origin deployed/fnx-dev-testenv-01
```

### Migrating existing state

The backend is now one S3 bucket, `fnx-terraform-state`, with native lockfiles and no DynamoDB
table. Atmos computes each instance's state location. To see it:

```bash
atmos describe component vpc/main -s fnx-dev-testenv-01   # see .backend (bucket, workspace_key_prefix) and .workspace
```

If an instance already has state under a different bucket or key, copy that state to the new
location before the first plan. Otherwise Terraform starts from an empty state and plans to
recreate the resources. One way to do it per instance:

```bash
aws s3 cp s3://<old-bucket>/<old-key> ./old.tfstate
atmos terraform state push vpc/main -s fnx-dev-testenv-01 ./old.tfstate
atmos terraform plan vpc/main -s fnx-dev-testenv-01   # expect no resource replacements
```

The `network/*` instances now use the `dns` root module. State written by a different module does
not match its resource addresses; import the existing zones instead
(`atmos workflow import -f import -s <stack>`).

---

## Validate offline

None of these need AWS credentials:

```bash
atmos validate config
atmos validate stacks
atmos workflow validate-all -f validate-enhanced   # schema, stacks, yamllint, fmt, terraform validate per root module
atmos workflow lint -f lint                        # fmt, yamllint, tflint, trivy
```

`atmos workflow validate -f validate -s <stack>` runs the same checks scoped to one stack.

---

## Bootstrap the state backend

`workflows/bootstrap.yaml` creates the bucket with `atmos terraform backend create backend/main`
(versioning, encryption, public-access block), brings it under Terraform with the `backend`
component, and then deploys the IAM and VPC instances. Each apply step asks for confirmation.

```bash
atmos workflow full -f bootstrap -s fnx-dev-testenv-01           # backend, IAM, VPCs
atmos workflow backend-only -f bootstrap -s fnx-dev-testenv-01   # backend only
atmos workflow verify -f bootstrap -s fnx-dev-testenv-01         # backend describe + outputs
```

All three stacks use the same bucket name, `fnx-terraform-state`, reached through
`fnx-terraform-backend-role` in the management account. S3 bucket names are global, so this is a
single bucket. Every stack still defines a `backend/main` instance for it (and the foundation
layer below includes it); create and manage the bucket from one stack only, and expect
`backend/main` in the other stacks to conflict with it.

---

## Deploy the stack

`workflows/deploy-full-stack.yaml` deploys a stack in layers. Each layer selects instances by
their root module (`metadata.component`), plans them, shows the plans, asks for confirmation and
applies exactly those planfiles (`terraform deploy --from-plan`). Within a layer, Atmos orders
instances by `dependencies.components`.

| Layer | Workflow | Root modules |
|-------|----------|--------------|
| foundation | `deploy-foundation` | `backend`, `iam` |
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

The layers do not include `kms`. In production, EKS, EC2 and RDS read the key ARN from
`kms/main`, so deploy it before the compute layer:

```bash
atmos terraform deploy kms/main -s fnx-prod-production
```

Other ways to deploy:

```bash
atmos workflow apply -f apply-environment -s <stack>      # whole stack: plan, one confirmation, deploy
atmos terraform deploy <component> -s <stack>             # one instance
atmos workflow component -f deploy-application -s <stack> # one instance, name entered at a prompt
```

Disabled instances (`metadata.enabled: false`) are skipped: `iam/ci`, `iam/eks-node`,
`iam/eks-cluster`, `infrastructure/*`, `vpc-flow-logs-bucket`, and in prod `guardduty/main`,
`securityhub/main` and `network/vpc-peering`. No stack deploys `idp-platform`.

---

## Deploy through CI/CD

After the GitHub prerequisites above are in place:

- **Pull requests** (`terraform-ci.yml`): lint and validation, a security gate that fails on new
  HIGH/CRITICAL Trivy/Checkov findings (findings already in `.trivyignore.yaml` and
  `.checkov.baseline` are tolerated), and a plan of every affected component
  (`atmos describe affected --include-dependents`) with the read-only plan role. Plan summaries
  are posted as PR comments.
- **Merges to the default branch** (`terraform-cd.yml`): for each stack in turn (dev, staging,
  prod), runs `atmos terraform deploy --affected` against the stack's `deployed/<stack>` tag
  inside the stack's GitHub Environment, then moves the tag to the deployed commit.
- **Manual runs**: `terraform-cd.yml` can plan or deploy one stack (optionally one component)
  from the default branch.

Destroy is not exposed in CI. Use `atmos workflow destroy -f destroy-environment` locally.

---

## Verify

```bash
atmos workflow verify -f bootstrap -s <stack>                  # backend
atmos terraform output vpc/main -s <stack>
atmos terraform output eks/main -s <stack>
atmos workflow drift-detection -f drift-detection -s <stack>   # should report no changes
```

To reach an EKS cluster, take the cluster name from `atmos terraform output eks/main -s <stack>`
and run `aws eks update-kubeconfig --name <cluster> --region eu-west-2`.

---

## Rollback

- **Configuration change**: revert the commit and merge; CD redeploys the affected components.
  Locally: `atmos terraform deploy <component> -s <stack>` from the reverted checkout.
- **State**: the state bucket is versioned. List the versions of one component's state with
  `STACK=<stack> COMPONENT_PREFIX=<component>/ atmos workflow recover-state -f disaster-recovery`
  and restore a version as described in the [Operations Guide](./OPERATIONS_GUIDE.md#state-recovery).
- **Whole stack**: `atmos workflow destroy -f destroy-environment` (you type the stack name to
  confirm) removes every component in reverse dependency order.

---

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `This repository requires Atmos >= 1.229.0` | Upgrade Atmos |
| `init` fails to assume `fnx-terraform-backend-role` | The role does not exist yet, or your credentials are not trusted by it. See [Manual prerequisites](#manual-prerequisites-before-first-apply) |
| `Error acquiring the state lock` | Another run holds the lockfile. `STACK=<stack> atmos workflow list-locks -f state-operations` shows it; `atmos workflow force-unlock -f state-operations -s <stack>` releases it once you are sure no run is active |
| `!terraform.state` returns nothing | The referenced component has not been deployed yet in that stack. Deploy in layer order |
| `idp-platform is unsupported` | Expected; see `components/terraform/idp-platform/README.md` |
| Plan wants to recreate existing resources | State was not migrated to the new backend layout; see [Migrating existing state](#migrating-existing-state) |

See the [Operations Guide](./OPERATIONS_GUIDE.md) for day-2 tasks.

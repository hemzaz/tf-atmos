# GitHub OIDC, hub and spoke

A worked setup for running CI against several AWS accounts with **one** OIDC
provider. Copy the YAML, replace the placeholders, delete what you do not need.

Templates: [`stacks/catalog/iam/oidc-hub.yaml`](../../stacks/catalog/iam/oidc-hub.yaml)
and [`stacks/catalog/iam/oidc-spoke.yaml`](../../stacks/catalog/iam/oidc-spoke.yaml).

```
GitHub Actions
      │  OIDC token (sub = repo:<org>/<repo>:pull_request, …)
      ▼
┌──────────────────────────┐
│ HUB account 111111111111 │  the OIDC provider lives here, once
│  <prefix>-ci-plan        │  holds NO service permissions
│  <prefix>-ci-apply       │  only sts:AssumeRole into the spokes
└───────────┬──────────────┘
            │ sts:AssumeRole
   ┌────────┼────────┐
   ▼        ▼        ▼
 dev      staging   prod          each: a cross-account role trusting the hub
 2222…    3333…     4444…         no OIDC provider, no OIDC role
```

## Why not a provider per account

An account can hold exactly **one** OIDC provider for
`token.actions.githubusercontent.com`. If several stacks each set
`github_oidc_create_provider: true` and land in the same account, the second
apply fails with `EntityAlreadyExists`.

**An OIDC provider is account-local.** A role in a spoke *cannot* federate
against the hub's provider. Do not set `github_oidc_provider_arn` in a spoke to
the hub's ARN — the component's regex accepts any 12-digit account, so nothing
rejects it, and it fails later at AWS. `github_oidc_provider_arn` exists only
for "this *same* account already has a provider something else created".

## 1. Hub stack

`stacks/orgs/<tenant>/mgmt/<region>/hub.yaml`

```yaml
---
import:
  - catalog/iam/oidc-hub

settings:
  environment:
    account: mgmt
    account_id: "111111111111"
  context:
    tenant: fnx
    environment: hub
    stage: prod

vars:
  region: eu-west-2

components:
  terraform:
    iam/oidc-hub:
      metadata:
        inherits:
          - iam/oidc-hub        # REQUIRED. Importing the file alone does nothing.
      vars:
        github_oidc_repository: "<org>/<repo>"
        github_oidc_default_branch: "main"
        ci_plan_policy_arns:
          - "arn:aws:iam::111111111111:policy/fnx-ci-assume-spoke-plan"
```

## 2. The policy that makes the hop possible

The component grants the CI roles nothing beyond `ci_*_policy_arns`. Create this
customer-managed policy in the **hub** account and reference its ARN above.
`AdministratorAccess` and `PowerUserAccess` are rejected for the plan role by
`iam/variables.tf:295`, because pull-request code assumes it.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sts:AssumeRole",
    "Resource": [
      "arn:aws:iam::222222222222:role/fnx-dev-testenv-01-ci-exec",
      "arn:aws:iam::333333333333:role/fnx-staging-staging-01-ci-exec",
      "arn:aws:iam::444444444444:role/fnx-prod-production-ci-exec"
    ]
  }]
}
```

List the roles explicitly. A wildcard here hands CI every role in the
organisation and is the whole reason to run a hub.

## 3. Spoke stacks

One per workload account. Add to each existing stack file:

```yaml
import:
  - catalog/iam/oidc-spoke

components:
  terraform:
    iam/oidc-spoke:
      metadata:
        inherits:
          - iam/oidc-spoke      # REQUIRED.
      vars:
        trusted_account_ids:
          - "111111111111"      # the hub, and only the hub
        external_id: "<shared secret, per account>"
        managed_s3_bucket_arns:
          - "arn:aws:s3:::fnx-prod-artifacts"
```

`external_id` and `managed_s3_bucket_arns` are not optional decoration — they
satisfy two `lifecycle` preconditions (`cross-account-roles.tf:59` and
`resource-management-policy.tf:105`). Strip either and the component cannot
plan. Use `trusted_principal_org_id` instead of `external_id` if you prefer an
org-wide condition; `require_mfa` also satisfies it, but CI cannot present MFA.

Do **not** set `trusted_account_ids` to the spoke's own account id. That makes
`local.trusts_other_accounts` false, short-circuits the precondition, goes green
and leaves the guard unexercised.

## 4. GitHub side

| Setting | Value |
|---|---|
| Repo variable `AWS_PLAN_ROLE_ARN` | `arn:aws:iam::111111111111:role/<prefix>-ci-plan` |
| Environment per stack, `vars.AWS_ROLE_ARN` | `arn:aws:iam::111111111111:role/<prefix>-ci-apply` |
| Environment deployment branches | default branch only |
| Prod environment | add required reviewers |

Both roles live in the **hub**. Nothing in GitHub points at a spoke.

## 5. Order of operations

1. Create the hub account's state backend (`backend/main`) — the bases read
   `ci_state_bucket_name` and `ci_state_kms_key_arn` from it.
2. Apply `iam/oidc-hub`. This creates the provider and the plan role.
3. Create the assume-spoke policy (step 2) and re-apply the hub so
   `ci_plan_policy_arns` picks it up.
4. Apply `iam/oidc-spoke` in each workload account.
5. Set the GitHub repo variable and environments.
6. Turn on `ci_apply_role_enabled` only once steps 1–5 are verified.

## Before you enable the apply role

`ci_apply_policy_arns` has **no** guardrail — the `AdministratorAccess` denylist
covers the plan role only. In hub-and-spoke the apply role should hold nothing
but `sts:AssumeRole` into the spoke roles, exactly like the plan role. Giving it
a service policy in the hub defeats the topology; giving it
`PowerUserAccess + IAMFullAccess` is administrator access with extra steps,
since these stacks deploy the `iam` component itself.

## Checking your work without an AWS account

```bash
bash scripts/plan-sweep.sh <your-stack>
```

It binds each stack's resolved variables to the component and plans. Variable
validations run before the provider authenticates, so `InvalidClientTokenId` is
expected. Read `INCONCLUSIVE` as "not checked", never as a pass — it means
Terraform stopped at a missing required variable before reaching any validation.

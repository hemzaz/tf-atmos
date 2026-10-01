# GitHub OIDC, hub and spoke

CI for several AWS accounts from **one** OIDC provider. An account can hold only one provider for
`token.actions.githubusercontent.com`, and a provider is account-local, so the provider and both
CI roles (`<prefix>-ci-plan`, `<prefix>-ci-apply`) live in a hub account and reach each workload
account's `<tenant>-<account>-<environment>-ci-exec` role with `sts:AssumeRole`.

Templates, with usage in their header comments: `stacks/catalog/iam/oidc-hub.yaml` and
`stacks/catalog/iam/oidc-spoke.yaml`. Both are abstract: a stack must `import` the file **and**
list it in the instance's `metadata.inherits`.

1. Add the hub's plan/apply role ARNs to `access_roles` in `stacks/orgs/fnx/core/eu-west-2/root.yaml`
   (`read`/`write`, or `prod_read`/`prod_write` for prod) and deploy the backend.
2. Hub stack: `iam/oidc-hub` with `github_oidc_repository: "<org>/<repo>"` and
   `ci_apply_role_trusted_github_repos: ["<org>/<repo>:master"]`. Apply it.
3. In the hub, create a customer-managed policy allowing `sts:AssumeRole` on each spoke's
   `-ci-exec` role ARN, listed explicitly (a wildcard hands CI every role in the organisation).
   Set it in `ci_plan_policy_arns` and re-apply. `AdministratorAccess`/`PowerUserAccess` are
   rejected for the plan role; give the apply role the same assume-only policy.
4. Each workload stack: `iam/oidc-spoke` with `trusted_account_ids: ["<hub account id>"]`,
   `trusted_principal_arns` (the hub's `-ci-plan`/`-ci-apply` role ARNs, exact, no wildcard) and
   `external_id` (or `trusted_principal_org_id`); its preconditions require all three. Never set
   `github_oidc_provider_arn` in a spoke to the hub's provider, and never trust the spoke's own
   account id.
5. Set the repository variable `AWS_PLAN_ROLE_ARN` to the hub plan role. `terraform-cd.yml`
   gets the apply role from `workflows/scripts/common/ci-apply-role-arn.py`, which builds
   `arn:aws:iam::<settings.environment.account_id>:role/<ci_role_name_prefix>-apply` from each
   stack's `iam/ci`, i.e. the workload account's own role. Nothing points it at a hub: change the
   script to return the hub's `-ci-apply` ARN.
6. Enable `ci_apply_role_enabled` only after steps 1-5 work.

Check without AWS: `bash scripts/plan-sweep.sh <stack>`. `InvalidClientTokenId` is expected;
`INCONCLUSIVE` means not checked, not passed.

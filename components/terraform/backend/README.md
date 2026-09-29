# backend

The Terraform state backend itself: an S3 bucket for state (`prevent_destroy`, versioned,
SSE-KMS, TLS-only policy) plus a `-logs` and (if `enable_access_logging`) a `-access-logs`
bucket, a dedicated KMS key with rotation, and the **state access roles**. Uses Terraform
>= 1.10's native S3 `use_lockfile` locking — no DynamoDB lock table is created.

Modelled on Cloud Posse's
[`aws-tfstate-backend`](https://github.com/cloudposse-terraform-components/aws-tfstate-backend)
component (`src/iam.tf`, `access_roles`):

| Cloud Posse | here |
|---|---|
| `access_roles` map, one IAM role per entry, `write_enabled` | same; each entry also carries `role_name` because every stack's backend assumes a fixed name (below) |
| S3 policy: `ListBucket`+`GetObject`, plus `PutObject`/`DeleteObject` when `write_enabled` | same, plus KMS: `Decrypt`/`DescribeKey`, and `Encrypt`/`GenerateDataKey` when `write_enabled` (the state bucket is SSE-KMS) |
| Trust: account-root principals narrowed by an `aws:PrincipalArn` condition, so not-yet-created roles can be trusted | same, `ArnEquals` instead of `ArnLike` — wildcards are rejected here |
| The caller running Terraform is always allowed | same (`aws_iam_session_context` turns the assumed-role ARN into the role ARN, path included); a root-user caller is never added |
| `allowed_roles`/`allowed_permission_sets` resolved through `account-map` | not ported: this repo has no account-map, so principals are exact ARNs |

## Deployed as

**One** instance, `backend/main` in `fnx-core-root` (`stacks/orgs/fnx/core/eu-west-2/root.yaml`,
the management account's stack; owner decision D1). Bucket `fnx-terraform-state`, roles:

| `access_roles` key | Role | Objects (`object_key_patterns`) | Trusted principals | Used by |
|---|---|---|---|---|
| `read` | `fnx-terraform-backend-read-role` | `*/fnx-dev-*`, `*/fnx-staging-*`, `*/fnx-core-*` | the CI **plan** roles of every stack (`<tenant>-<account>-<environment>-ci-plan`); prod's only for `fnx-core-root` reads | PR plans and dev/staging drift (`TFSTATE_ACCESS=read`, `-lock=false`) |
| `prod_read` | `fnx-terraform-backend-prod-read-role` | `*/fnx-prod-*` | **only** prod's plan role (trusts the master subject alone, D3) | prod plans on push to master and prod drift |
| `write` | `fnx-terraform-backend-role` | every object | the CI **apply** roles (`...-ci-apply`, GitHub Environment subjects only) | deploys (`terraform-cd.yml`) and every local run without `TFSTATE_ACCESS` |

Every stack's backend (`stacks/orgs/fnx/_defaults.yaml`) assumes
`arn:aws:iam::<management_account_id>:role/fnx-terraform-backend-role`; with
`TFSTATE_ACCESS=read` it assumes `fnx-terraform-backend-prod-read-role` in a stage-`prod` stack
and `fnx-terraform-backend-read-role` in any other stack (including `fnx-core-root`, which is why
prod's plan role is also trusted by the non-prod read role: prod's `iam/ci` reads `backend/main`
there, and that role grants no prod object).

**Prefix split.** State keys are `<workspace_key_prefix>/<workspace>/terraform.tfstate` (plus
`.tflock`): Atmos sets `workspace_key_prefix` to the component (`iam`, `eks`, `backend`, ...) and
the workspace to the stack name `<tenant>-<stage>-<environment>` (`atmos.yaml` `name_template`),
with `-<instance>` appended for a derived instance (e.g. `iam/fnx-prod-production-iam-ci/...`). So
`*/fnx-<stage>-*` matches one stage's objects (S3's `*` also spans `/`; no component name contains
`/fnx-<stage>-`). The patterns are in `stacks/catalog/backend/defaults.yaml`; the tests match them
against real keys.

**What `s3:ListBucket` still shows.** It is not prefix-scoped. Terraform's S3 backend finds
workspaces by listing `<workspace_key_prefix>/` — the component prefix that every stack's workspace
of that component shares — during `init`/workspace selection, so an `s3:prefix` condition per stage
would break it (the list request's prefix is `iam/`, not `iam/fnx-dev-`). Both read roles can
therefore see key **names** across stages (component and stack/instance names, e.g.
`eks/fnx-prod-production-eks-main/terraform.tfstate`), never object contents: `GetObject` and KMS
use are limited as above (the key is SSE-KMS, but `kms:Decrypt` alone is useless without the
object). The principal lists are strings built
from `iam/ci`'s naming pattern, not `!terraform.state`, because `iam/ci` reads this instance's
role ARNs (`!terraform.state backend/main fnx-core-root .backend_read_role_arn` /
`.backend_role_arn`); reading back would be a dependency cycle. Adding a stack means adding its
two CI role ARNs here. Any human/admin role other than the applying administrator must be listed
explicitly.

`fnx-core-root` sets `settings.github.actions_enabled: false`: CI never plans or applies the
backend; a management-account administrator does.

## Inputs / Outputs

| Input | Notes |
|---|---|
| `bucket_name` | required; `-logs`/`-access-logs` bucket names derive from it |
| `access_roles` | required map of `{ role_name, write_enabled, allowed_principal_arns, object_key_patterns = ["*"] }`; at least one role, unique names, every principal an exact IAM role/user ARN — `*`, wildcards and `arn:aws:iam::<account>:root` are rejected; `object_key_patterns` non-empty |
| `enable_access_logging` | default true |

Outputs: `backend_bucket`, `backend_bucket_arn`, `backend_kms_key_arn`, `access_role_arns` /
`access_role_names` (maps by key), `backend_role_arn`/`backend_role_name` (key `write`),
`backend_read_role_arn`/`backend_read_role_name` (key `read`),
`backend_prod_read_role_arn`/`backend_prod_read_role_name` (key `prod_read`). `iam/ci` in every
workload stack reads `backend_read_role_arn` and `backend_role_arn`; prod's also
`backend_prod_read_role_arn`.

## Bootstrap

The backend's own state lives in the bucket it creates, through the role it creates — so the first
apply is a cold start, as in Cloud Posse's tfstate-backend guide:

```bash
atmos workflow backend-cold-start -f bootstrap
```

which, with management-account administrator credentials, runs

```bash
atmos terraform deploy backend/main -s fnx-core-root --auto-generate-backend-file=false   # local state
atmos terraform init backend/main -s fnx-core-root --init-reconfigure=never -- -migrate-state -force-copy
```

The first apply trusts the caller in both roles, so the second command can assume the write role
and copy the local state into the bucket. Delete `terraform.tfstate.d/` afterwards. Later changes:
`atmos workflow backend-only -f bootstrap`.

**If the bucket already exists** — created by `atmos terraform backend create backend/main -s
fnx-core-root` (Atmos backend provisioning) or by hand — import it before the first apply instead
of letting Terraform try to create it. Add a temporary `imports.tf` to this component:

```hcl
import {
  to = aws_s3_bucket.terraform_state
  id = "fnx-terraform-state"
}
```

then run the two commands above (the cold-start workflow refuses to start while the bucket exists)
and delete `imports.tf` once the apply has succeeded. Its versioning, encryption, public-access
block and policy need no import: Terraform overwrites them in place. Equivalent one-off command:
`atmos terraform import backend/main aws_s3_bucket.terraform_state fnx-terraform-state -s
fnx-core-root --auto-generate-backend-file=false`.

## Gotchas

- All 3 buckets have `lifecycle { prevent_destroy = true }`; `terraform destroy` fails until that
  block is removed. Destroying the backend destroys every stack's state.
- The KMS key policy grants `kms:*` only to the account root, i.e. delegates to IAM: the access
  roles' own policies grant key use.
- A read-only plan cannot create a workspace: the S3 backend writes an empty state object (and a
  lock) the first time a workspace is selected, so a CI plan of an instance that has never been
  applied fails at `workspace new` until its first deploy creates that workspace.
- Every principal in `allowed_principal_arns` must name the account its role lives in; the
  committed ARNs use the repository's placeholder account IDs (docs/DEPLOYMENT.md).

## Usage

```
atmos terraform plan backend/main -s fnx-core-root
TFSTATE_ACCESS=read atmos terraform plan vpc/main -s fnx-dev-testenv-01 -- -lock=false   # plan through the read-only role
```

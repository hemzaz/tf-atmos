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

| `access_roles` key | Role | Objects (`object_key_patterns`) | Trusted principals (plus the caller) | Used by |
|---|---|---|---|---|
| `read` | `fnx-terraform-backend-read-role` | `*/fnx-dev-*`, `*/fnx-staging-*` | the dev/staging CI **plan** roles (`<tenant>-<account>-<environment>-ci-plan`) | PR plans, dev/staging drift and DR checks (`TFSTATE_ACCESS=read`, `-lock=false`) |
| `write` | `fnx-terraform-backend-role` | `*/fnx-dev-*`, `*/fnx-staging-*` | the dev/staging CI **apply** roles (`...-ci-apply`) | dev/staging deploys (`terraform-cd.yml`) and local runs without `TFSTATE_ACCESS` |
| `prod_read` | `fnx-terraform-backend-prod-read-role` | `*/fnx-prod-*` | **only** prod's plan role (master subject alone, D3) | prod plans on push to master, prod drift and DR checks |
| `prod_write` | `fnx-terraform-backend-prod-role` | `*/fnx-prod-*` | **only** prod's apply role | prod deploys and local runs |
| `core_write` | `fnx-terraform-backend-core-role` | `*/fnx-core-*` | **nobody listed**: only the administrator who applies `backend/main` (Cloud Posse's caller rule) | `fnx-core-root`'s own backend, read and write |

Every stack's backend (`stacks/orgs/fnx/_defaults.yaml`) assumes its stage's role:
`fnx-terraform-backend[-prod]-role`, or with `TFSTATE_ACCESS=read` `fnx-terraform-backend[-prod]-read-role`
(`-prod` in a stage-`prod` stack); a stage-`core` stack always assumes
`fnx-terraform-backend-core-role`. No CI role can read or write `fnx-core-root` state, so no CI
role reads `backend/main`'s outputs: `iam/ci` names its stage's roles by the same convention.

**Read-only roles and DR.** The read roles also get `s3:ListBucketVersions`,
`s3:GetBucketVersioning` and `s3:GetReplicationConfiguration` on the bucket: the DR scripts
(`workflows/scripts/dr`, run by `disaster-recovery.yml` with the plan roles) read the bucket only
through the stack's read role (`workflows/scripts/common/state-read-role.sh`) - `recover-state`
lists state object versions to pick one to restore, `dr-status` checks versioning and replication.
No role gets `s3:GetObjectVersion`, so old versions' contents stay unreadable; restoring one needs
the stage's write role.

**Prefix split** (reads and writes). State keys are `<workspace_key_prefix>/<workspace>/terraform.tfstate` (plus
`.tflock`): Atmos sets `workspace_key_prefix` to the component (`iam`, `eks`, `backend`, ...) and
the workspace to the stack name `<tenant>-<stage>-<environment>` (`atmos.yaml` `name_template`),
with `-<instance>` appended for a derived instance (e.g. `iam/fnx-prod-production-iam-ci/...`). So
`*/fnx-<stage>-*` matches one stage's objects (S3's `*` also spans `/`; no component name contains
`/fnx-<stage>-`). The patterns are in `stacks/catalog/backend/defaults.yaml`; the tests match them
against real keys. `workflows/scripts/common/check-state-keys.py` (run by `validate-all` and `lint`)
fails any s3-backend instance whose workspace does not start with its own stack's `<tenant>-<stage>-`
or contains `/`, or whose `workspace_key_prefix` contains `/` - the cases that would put a key
under another stage's pattern.

**What `s3:ListBucket` still shows.** It is not prefix-scoped. Terraform's S3 backend finds
workspaces by listing `<workspace_key_prefix>/` — the component prefix that every stack's workspace
of that component shares — during `init`/workspace selection, so an `s3:prefix` condition per stage
would break it (the list request's prefix is `iam/`, not `iam/fnx-dev-`). Every role can
therefore see key **names** across stages (component and stack/instance names, e.g.
`eks/fnx-prod-production-eks-main/terraform.tfstate`), never object contents: `GetObject` and KMS
use are limited as above (the key is SSE-KMS, but `kms:Decrypt` alone is useless without the
object). The principal lists are strings built
from `iam/ci`'s naming pattern, not `!terraform.state` (`iam/ci` deploys after this instance and
names these roles by convention in turn). Adding a stack means adding its two CI role ARNs to its
stage's entries here. Any human/admin role other than the applying administrator must be listed
explicitly.

`fnx-core-root` sets `settings.github.actions_enabled: false`: CI never plans or applies the
backend; a management-account administrator does.

## Inputs / Outputs

| Input | Notes |
|---|---|
| `bucket_name` | required; `-logs`/`-access-logs` bucket names derive from it |
| `access_roles` | required map of `{ role_name, write_enabled, allowed_principal_arns = [], object_key_patterns = ["*"] }`; at least one role, unique names, every principal an exact IAM role/user ARN (an empty list, upstream's default, trusts only the caller; a root-user caller then fails the role's precondition) — `*`, wildcards and `arn:aws:iam::<account>:root` are rejected; `object_key_patterns` non-empty |
| `enable_access_logging` | default true |

Outputs: `backend_bucket`, `backend_bucket_arn`, `backend_kms_key_arn`, `access_role_arns` /
`access_role_names` (maps by key), `backend_role_arn`/`backend_role_name` (key `write`),
`backend_read_role_arn`/`backend_read_role_name` (key `read`),
`backend_prod_role_arn`/`backend_prod_role_name` (key `prod_write`),
`backend_prod_read_role_arn`/`backend_prod_read_role_name` (key `prod_read`),
`backend_core_role_arn`/`backend_core_role_name` (key `core_write`). No stack reads them
cross-stack today (`iam/ci` names the roles by convention); they are for operators and `verify`.

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

The first apply trusts the caller in every role and makes it the only principal of the core role
(`fnx-terraform-backend-core-role`), which `fnx-core-root`'s backend assumes, so the second command
can copy the local state into the bucket. The workflow's `wait-for-core-role` step first polls
`sts:AssumeRole` on that role (backoff, up to ~60s): IAM is eventually consistent, and a role
created seconds ago can refuse the migration. Delete `terraform.tfstate.d/` afterwards. Later changes:
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
- A stack of a NEW stage (anything but dev, staging, prod, core) gets the non-prod roles from the
  backend template, whose patterns cover only `*/fnx-dev-*` and `*/fnx-staging-*`: add its
  `*/fnx-<stage>-*` pattern to `read`/`write` (or give it its own roles and template branch)
  before its first `init`.
- Every principal in `allowed_principal_arns` must name the account its role lives in; the
  committed ARNs use the repository's placeholder account IDs (docs/DEPLOYMENT.md).

## Usage

```
atmos terraform plan backend/main -s fnx-core-root
TFSTATE_ACCESS=read atmos terraform plan vpc/main -s fnx-dev-testenv-01 -- -lock=false   # plan through the read-only role
```

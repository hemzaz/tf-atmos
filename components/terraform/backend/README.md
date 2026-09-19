# backend

Bootstraps the Terraform state backend itself: an S3 bucket for state
(`prevent_destroy`, versioned, SSE-KMS, TLS-only policy) plus a `-logs` and (if
`enable_access_logging`) a `-access-logs` bucket, a dedicated KMS key with rotation, and
an IAM role scoped to `s3:GetObject/PutObject/DeleteObject` + `kms:Decrypt/Encrypt/...`
on that bucket/key. Uses Terraform >= 1.10's native S3 `use_lockfile` locking — no
DynamoDB lock table is created.

## Deployed as

Real instance `backend/main` in all 3 stacks: `fnx-dev-testenv-01` (bucket
`fnx-terraform-state`), `fnx-staging-staging-01` (`fnx-staging-terraform-state`),
`fnx-prod-production` (`fnx-production-terraform-state`). All inherit abstract `backend`.

## Inputs / Outputs

| Input | Notes |
|---|---|
| `bucket_name` | required; `-logs`/`-access-logs` bucket names derive from it |
| `iam_role_name` | required |
| `enable_access_logging` | default true |

Outputs `backend_bucket`, `backend_bucket_arn`, `backend_kms_key_arn`, `backend_role_arn`
are not read via `!terraform.state` anywhere — the root of the state chain, not consumed.

## Dependencies / gotchas

- `iam`, `iam/ci`, `iam/dev`, `iam/eks-cluster`, `iam/eks-node`, `iam/main` all declare
  `dependencies.components: backend/main` — ordering only, no output is actually read.
- All 3 buckets have `lifecycle { prevent_destroy = true }`; `terraform destroy` fails
  until that block is removed.
- KMS key policy grants `kms:*` only to the account root — no CI/cross-account principal.

## Usage

```
atmos terraform plan backend/main -s fnx-dev-testenv-01
atmos terraform plan backend/main -s fnx-prod-production
```

# backend

The Terraform state backend: the `fnx-terraform-state` S3 bucket (versioned, SSE-KMS with its own
key, TLS-only), log buckets, and the state access roles. Locking is S3-native `use_lockfile`; there
is no DynamoDB table. Modelled on Cloud Posse `aws-tfstate-backend`'s `access_roles` (account-root
trust narrowed by exact `aws:PrincipalArn`, so not-yet-created roles can be trusted; the applying
caller is always trusted).

## Wiring

- One instance, `backend/main` in `fnx-core-root` (management account). CI never plans or applies
  it (`settings.github.actions_enabled: false`); a management-account administrator does.
- Every stack's backend (`stacks/orgs/fnx/_defaults.yaml`) assumes a role by naming convention;
  `iam/ci` names the same roles. Nothing reads this instance's state.

## Access roles

- `read` / `write` (`fnx-terraform-backend-read-role` / `-role`): dev and staging objects
  (`*/fnx-dev-*`, `*/fnx-staging-*`), trusted by those stages' CI plan / apply roles.
- `prod_read` / `prod_write` (`fnx-terraform-backend-prod-read-role` / `-prod-role`): `*/fnx-prod-*`
  only, trusted by prod's plan / apply role only.
- `core_write` (`fnx-terraform-backend-core-role`): `*/fnx-core-*`, trusted by nobody but the
  administrator who applies `backend/main`.

`TFSTATE_ACCESS=read` selects the read role (run plans with `-lock=false`).

## Notes

- The stage split only holds when the workload account IDs differ from
  `management_account_id`. In the same account, any principal with broad IAM permissions reaches
  the bucket directly, bypassing the access roles.
- Restoring an old state version needs management-account admin credentials: no access role has
  `s3:GetObjectVersion`, by design. The read roles can list versions (`ListBucketVersions`) for the
  DR scripts, not read them.
- `s3:ListBucket` is not prefix-scoped (the S3 backend lists `<component>/` across stacks), so every
  role sees key names of other stages, never contents.
- A read-only plan cannot create a workspace: a CI plan of a never-applied instance fails at
  `workspace new` until its first deploy.
- A new stage must get its `*/fnx-<stage>-*` pattern (or its own roles) before its first `init`.
  `check-state-keys.py` fails any instance whose workspace would land under another stage's pattern.
- Every `allowed_principal_arns` entry must name the account its role lives in; the committed ARNs
  use placeholder account IDs (see [docs/OPERATIONS.md](../../../docs/OPERATIONS.md#first-deploy-inputs)).
- All three buckets are `prevent_destroy`. Destroying the backend destroys every stack's state.

## Bootstrap

The backend's state lives in the bucket it creates, so the first apply is a cold start (as in Cloud
Posse's tfstate-backend guide). With management-account admin credentials:

```bash
atmos workflow backend-cold-start -f bootstrap   # apply with local state, then migrate it into the bucket
atmos workflow backend-only -f bootstrap         # later changes
```

The first apply trusts the caller in every role and makes it the core role's only principal; the
workflow waits for that role to become assumable before migrating. Delete `terraform.tfstate.d/`
afterwards.

If the bucket already exists (created by `atmos terraform backend create` or by hand), the
cold-start workflow refuses to run. Import the bucket, then run the workflow's two steps by hand:

```bash
atmos terraform import backend/main aws_s3_bucket.terraform_state fnx-terraform-state -s fnx-core-root --auto-generate-backend-file=false
atmos terraform deploy backend/main -s fnx-core-root --auto-generate-backend-file=false
atmos terraform init backend/main -s fnx-core-root --init-reconfigure=never -- -migrate-state -force-copy
```

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
- Cold start (state lives in the bucket it creates): `atmos workflow backend-cold-start -f bootstrap`
  with management-account admin credentials; later changes: `atmos workflow backend-only -f bootstrap`.
  If the bucket already exists, import `aws_s3_bucket.terraform_state` first.
- All three buckets are `prevent_destroy`. Destroying the backend destroys every stack's state.

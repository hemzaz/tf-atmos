# backend

The Terraform state backend: the `fnx-terraform-state` S3 bucket (versioned, SSE-KMS with its own
key, TLS-only), log buckets, the state access roles, and, with `s3_replication_enabled`, a
cross-region replica of the state bucket. Locking is S3-native `use_lockfile`; there
is no DynamoDB table. Modelled on Cloud Posse `aws-tfstate-backend`'s `access_roles` (account-root
trust narrowed by exact `aws:PrincipalArn`, so not-yet-created roles can be trusted; the applying
caller is always trusted).

## Wiring

- One instance per root stack in the management account: `backend/main` in `fnx-ue1-root` (the US
  stacks' bucket) and in `fnx-ew1-root` (the EU stacks', `fnx-ew1-terraform-state`, replicated to
  `eu-central-1`). Names derive from `settings.tfstate` (bucket, role prefix), so the two never
  collide. CI never plans or applies them (`settings.github.actions_enabled: false`); a
  management-account administrator does (`atmos workflow backend-cold-start -f bootstrap [-s fnx-ew1-root]`).
- `catalog/backend/defaults` defines only `root_write`; `catalog/backend/stage-roles` adds the
  stage roles for a bucket that holds workload state (`fnx-ue1-root`).
- Every stack's backend (`stacks/orgs/fnx/_defaults.yaml`) assumes a role by naming convention;
  `iam/ci` names the same roles. Nothing reads this instance's state.

## Access roles

Each stack's objects are an exact pattern pair, `*/<stack>/*` and `*/<stack>-*` (its derived
instances), listed on its stage's roles in `stacks/orgs/fnx/root/us-east-1.yaml`.

- `read` / `write` (`fnx-terraform-backend-read-role` / `-role`): the dev and staging stacks'
  objects, trusted by those stages' CI plan / apply roles.
- `prod_read` / `prod_write` (`fnx-terraform-backend-prod-read-role` / `-prod-role`): the prod
  stacks' objects only, trusted by prod's plan / apply role only.
- `root_write` (`fnx-terraform-backend-root-role`, EU `fnx-ew1-terraform-backend-root-role`): the
  root stack's own objects, trusted by nobody but the administrator who applies `backend/main`.

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
- A new stack must get its pattern pair on its stage's roles (a new stage, its own roles) before its
  first `init`. `check-state-keys.py` evaluates the patterns against every state key, with IAM's
  `*` and `?` wildcards, and fails a key no role matches, or one matched by another stage's role.
  It also fails a pattern that matches no state key, such as a pair left behind by a renamed or
  removed stack; a `*/<stack>-*` pattern is exempt while its `*/<stack>/*` pattern matches. The
  pairs don't depend on where the stage sits in the stack name.
- `*/<stack>-*` also matches a lane's objects (`fnx-ue1-dev-perf` is a sibling of `fnx-ue1-dev`), so
  the parent's roles reach its lanes. That stays inside the stage, since a lane shares its parent's
  stage. A lane still gets its own pair. A lane named like one of the parent's instance suffixes
  (`main`) would share its state keys (`vpc/fnx-ue1-dev-main/...`), and `check-state-keys.py` fails that.
- Every `allowed_principal_arns` entry must name the account its role lives in; the committed ARNs
  use placeholder account IDs (see [docs/OPERATIONS.md](../../../docs/OPERATIONS.md#first-deploy-inputs)).
- All the buckets are `prevent_destroy`. Destroying the backend destroys every stack's state.
- Replication (`s3_replication_enabled`, `replica_region`; Cloud Posse tfstate-backend's
  `s3_replication_enabled`): every object, `.tflock` files and delete markers included, goes to
  `<bucket_name>-replica` in `replica_region`, encrypted with a replica of the state key (the key
  is multi-region, always: switching that on later would replace the key the state is encrypted
  with). Cloud Posse replicates into a bucket a second tfstate-backend instance creates; here the
  one instance creates it through the provider's per-resource `region`, since a second instance
  would collide on the access roles' names. The replication role is least privilege (source
  versions read, replicas written, each key through S3 in its region). Every access role may read
  the replica and none may write it; the replica's bucket policy also denies object writes, tags
  and deletes to every principal but the replication role (replication writes with
  `s3:Replicate*` only). A run against it (`TFSTATE_SOURCE=replica`,
  [docs/OPERATIONS.md](../../../docs/OPERATIONS.md#state-during-a-us-east-1-outage)) can only
  plan with `-lock=false`. The replica has no server access logs (they need a target bucket in its
  region).

## Bootstrap

The backend's state lives in the bucket it creates, so the first apply is a cold start (as in Cloud
Posse's tfstate-backend guide). With management-account admin credentials:

```bash
atmos workflow backend-cold-start -f bootstrap   # apply with local state, then migrate it into the bucket
atmos workflow backend-only -f bootstrap         # later changes
# the EU backend: the same workflows with -s fnx-ew1-root
```

The first apply trusts the caller in every role and makes it the root role's only principal; the
workflow waits for that role to become assumable before migrating. Delete `terraform.tfstate.d/`
afterwards.

If the bucket already exists (created by `atmos terraform backend create` or by hand), the
cold-start workflow refuses to run. Import the bucket, then run the workflow's two steps by hand:

```bash
atmos terraform import backend/main aws_s3_bucket.terraform_state fnx-terraform-state -s fnx-ue1-root --auto-generate-backend-file=false
atmos terraform deploy backend/main -s fnx-ue1-root --auto-generate-backend-file=false
atmos terraform init backend/main -s fnx-ue1-root --init-reconfigure=never -- -migrate-state -force-copy
```

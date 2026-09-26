# external-secrets

Installs the external-secrets-operator Helm chart into an EKS cluster and wires
it to AWS Secrets Manager via IRSA: creates an IAM role/policy for the
operator's service account (assumable via the cluster's OIDC provider),
installs the Helm release, waits for its CRDs to register, and optionally
creates `ClusterSecretStore` resources for AWS Secrets Manager and for
certificates.

## Deployed

`external-secrets/main` and `external-secrets/data` in all 3 real stacks
(fnx-dev-testenv-01, fnx-staging-staging-01, fnx-prod-production), paired
1:1 with `eks/main` and `eks/data`. `enabled` is templated from
`settings.environment.use_external_secrets`, so an instance can exist but
deploy nothing if that flag is false.

| Inputs (required) | Inputs (behavior) | Outputs |
|---|---|---|
| region, cluster_name, host, cluster_ca_certificate, oidc_provider_arn, oidc_provider_url, tags (must have a non-empty `Environment` value), kms_key_arn (required only when `enabled` is true; null/empty is accepted on a disabled instance) | chart_version, create_default_cluster_secret_store, create_certificate_secret_store, namespace/service_account_name, secret_path_prefixes, ssm_parameter_path_prefixes, secret_path_context_prefixes | external_secrets_role_arn/name, policy_arn/name (not consumed elsewhere via `!terraform.state`) |

## IAM policy

The operator's IAM policy (`policies/external-secrets-policy.json.tpl`, rendered
with `templatefile()`) is scoped to this account, region and partition via
`data.aws_region`, `data.aws_caller_identity` and `data.aws_partition`, instead
of the `arn:aws:secretsmanager:*:*:secret:*` wildcards a static policy would
need. The Secrets Manager/SSM resource ARNs use `data.aws_partition.current.partition`
(not a hardcoded `"aws"`), matching `kms_key_arn`'s own partition support
below — a hardcoded `"aws"` here would grant nothing on secrets/parameters in
a GovCloud (`aws-us-gov`) or China (`aws-cn`) account even though `kms:Decrypt`
worked:

- Secrets Manager reads (`GetSecretValue`, `DescribeSecret`, etc.) and SSM reads
  (`GetParameter*`) are scoped to `var.secret_path_prefixes` /
  `var.ssm_parameter_path_prefixes`, each matched as a top-level prefix
  (`<prefix>/*`), plus `<context>/<prefix>/*` for every entry in
  `var.secret_path_context_prefixes`, since `secretsmanager`'s `full_path`
  nests `context_name/environment/path/name` (e.g.
  `production/app/prod/production/app/credentials`). The nested match
  used to be a depth-agnostic `*/<prefix>/*` wildcard, which would also match
  an unrelated secret that merely *contains* `/<prefix>/` further down its
  name (e.g. `x/y/app/z`); `secret_path_context_prefixes` (set in
  `stacks/catalog/external-secrets/defaults.yaml` to
  `settings.environment.stage`, the descriptive stage name — `production`,
  `staging`, `dev` — each stack's `secretsmanager/app`/`secretsmanager/infra`
  instances already hardcode as the leading segment of their `context_name`;
  this is *not* the same as Atmos's own `settings.context.stage`, the short
  stage-folder name `secretsmanager/defaults` uses for its own `environment`
  var, a different segment of `full_path`) scopes it to this stack's real
  context instead. It defaults to `[]`, so a component instance with no
  catalog override gets only the top-level match.
  Defaults (`certificates`, `ssh-key`, `app`, `infra` for Secrets Manager;
  `certificates` for SSM) cover this repo's certificate secrets
  (`components/terraform/secretsmanager`), bastion SSH keys
  (`ssh-key/<Environment>/<name>` from `components/terraform/ec2`), and the
  app/infra secretsmanager instances (`context_name` `app`/`infra` in dev,
  `<stage>/app`/`<stage>/infra` in staging and prod).
  **Deliberately not covered**: each stack's `settings.environment.secrets_manager_path_prefix`
  convention (e.g. `production/fnx/certificates`) and the tenant (`settings.context.tenant`,
  e.g. `fnx`) segment it implies. Neither has a Terraform consumer today — no
  resource or data source in this repo reads `secrets_manager_path_prefix`,
  and the `tls.crt_ssm_parameter` string some `secretsmanager` secrets embed
  in their JSON value (e.g. `security.yaml`'s `istio_certificates`) is
  `"reference_only"` data, not a live SSM Parameter Store resource ESO
  reads. If a future `secretsmanager`/SSM instance is wired to a real
  tenant-prefixed path, add the tenant (`{{ .settings.context.tenant }}`) as
  its own `secret_path_context_prefixes` entry in
  `stacks/catalog/external-secrets/defaults.yaml` at that time.
- `secretsmanager:ListSecrets` stays on `"*"`: AWS does not support
  resource-level restriction for that action.
- `kms:Decrypt` is scoped to `var.kms_key_arn` (the stack's `kms/main` key, fed
  by `!terraform.state kms/main .key_arn` in the catalog defaults — the same key
  `secretsmanager/defaults` uses as `default_kms_key_id`), with a
  `kms:ViaService` condition restricting it to `secretsmanager.<region>.amazonaws.com`
  and `ssm.<region>.amazonaws.com`. `kms_key_arn` accepts single-region
  (`key/<uuid>`) and multi-region (`key/mrk-<32 hex>`) keys in any AWS
  partition (`aws`, `aws-us-gov`, `aws-cn`); it is required only when
  `enabled` is true, so a disabled instance's `kms/main` dependency doesn't
  need to resolve to a real key.

## IRSA trust policy

The role's `AssumeRoleWithWebIdentity` trust policy conditions on both the
service account (`<issuer>:sub = system:serviceaccount:<namespace>:<name>`) and
the audience (`<issuer>:aud = sts.amazonaws.com`), matching the IRSA roles in
`components/terraform/eks-addons`. The `:aud` condition stops another OIDC
audience (or the same issuer used for a different STS-compatible purpose) from
satisfying the trust; `:sub` alone is not sufficient.

## Dependencies & gotchas

- Depends on `eks/main` (main instance) / `eks/data` (data instance) for
  cluster_name (`.eks_cluster_id`), host (`.eks_cluster_endpoint`), the CA cert
  (`.eks_cluster_certificate_authority_data`, base64, decoded here) and the OIDC
  provider (`.eks_cluster_identity_oidc_issuer_arn`, and
  `.eks_cluster_identity_oidc_issuer` with `https://`, stripped here).
- Also depends on `kms/main` for `kms_key_arn` (`.key_arn`). Both dependencies
  are declared per-instance in the stacks (`dependencies.components`), not only
  on the abstract `external-secrets/defaults` catalog entry: `list_merge_strategy:
  replace` means each instance's own `dependencies.components` (which names
  `eks/main`/`eks/data`) replaces, rather than merges with, the abstract's.
- IAM names are `<cluster_name>-external-secrets-{role,policy}`. The eks cluster
  name already starts with the Environment, so it is not prefixed again (it was:
  `production-production-production-main-external-secrets-role`); a bare cluster
  name gets `<Environment>-`. Prod: `production-main-external-secrets-role` (37 of
  IAM's 64 characters). The Environment match is case-insensitive, as in the eks
  name validation. Validations reject a role name over 64 characters, a cluster
  ARN in `cluster_name`, and a null `cluster_name` (the eks instance is disabled),
  each with its own message. `tests/names.tftest.hcl` covers this with mock
  providers.
- `tags` must have a non-empty `Environment` value (validated).
- The CRD-wait step shells out to `kubectl` via `local-exec`; the apply host
  needs `kubectl` configured for the target cluster.

## Usage

```
atmos terraform plan external-secrets/main -s fnx-dev-testenv-01
atmos terraform plan external-secrets/data -s fnx-prod-production
```

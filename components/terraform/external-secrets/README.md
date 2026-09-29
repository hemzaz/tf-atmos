# external-secrets

Installs the external-secrets-operator Helm chart into an EKS cluster with an IRSA role for AWS
Secrets Manager and SSM, waits for its CRDs, and optionally creates `ClusterSecretStore`s for
Secrets Manager and for certificates.

## Wiring

- Instances: `external-secrets/main` and `external-secrets/data` in the three AWS stacks, paired
  with `eks/main` and `eks/data`.
- Reads: the eks instance's `.eks_cluster_id`, `.eks_cluster_endpoint`,
  `.eks_cluster_certificate_authority_data`, `.eks_cluster_identity_oidc_issuer(_arn)`, and
  `kms/main .key_arn`.
- Used by: `eks-backend-services` (`.default_cluster_secret_store_name`).

## Notes

- The IAM policy reads only secrets under `secret_path_prefixes` (and
  `<stage>/<prefix>/*` via `secret_path_context_prefixes`) and SSM under
  `ssm_parameter_path_prefixes`. `kms:Decrypt` is limited to `kms_key_arn` through Secrets
  Manager and SSM. `ListSecrets` stays on `*` (AWS has no resource-level support).
- `rds_managed_secret_access` adds RDS-managed `rds!db-*` secrets (used by
  `eks-backend-services`); every stack that enables it also sets `allowed_namespaces:
  ["backend-services"]` so other namespaces cannot bind the store.
- The IRSA trust checks both `:sub` and `:aud`.
- IAM names are `<cluster_name>-external-secrets-{role,policy}` (64-character limit validated).
- Each instance lists its own `dependencies.components`: `list_merge_strategy: replace` drops the
  catalog base's list.
- The CRD wait runs `kubectl` through `local-exec`: the apply host needs `kubectl` configured for the
  cluster.
- In dev, `enabled` follows `settings.environment.use_external_secrets`.

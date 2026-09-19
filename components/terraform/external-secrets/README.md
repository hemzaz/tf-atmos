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
| region, cluster_name, host, cluster_ca_certificate, oidc_provider_arn, oidc_provider_url, tags (must have a non-empty `Environment` value) | chart_version, create_default_cluster_secret_store, create_certificate_secret_store, namespace/service_account_name | external_secrets_role_arn/name, policy_arn/name (not consumed elsewhere via `!terraform.state`) |

## Dependencies & gotchas

- Depends on `eks/main` (main instance) / `eks/data` (data instance) for
  cluster_name, host, CA cert, OIDC provider.
- `tags` must have a non-empty `Environment` value (validated).
- The CRD-wait step shells out to `kubectl` via `local-exec`; the apply host
  needs `kubectl` configured for the target cluster.

## Usage

```
atmos terraform plan external-secrets/main -s fnx-dev-testenv-01
atmos terraform plan external-secrets/data -s fnx-prod-production
```

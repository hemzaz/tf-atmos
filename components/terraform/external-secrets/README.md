# external-secrets

Installs the external-secrets-operator Helm chart into an EKS cluster, then, from the local chart
`charts/cluster-secret-stores` in a second release, the AWS Secrets Manager `ClusterSecretStore`s
`aws-secretsmanager` (default) and `aws-certificate-store`, each with its own service account and
IRSA role. Cloud Posse's `eks/external-secrets-operator` uses the same two-release shape.

## Wiring

- Instances: `external-secrets/main` and `external-secrets/data` in the three AWS stacks, paired
  with `eks/main` and `eks/data`. The `data` instances create no stores: nothing on `eks/data`
  consumes one yet.
- Reads: the eks instance's `.eks_cluster_id`, `.eks_cluster_endpoint`,
  `.eks_cluster_certificate_authority_data`, `.eks_cluster_identity_oidc_issuer(_arn)`, and
  `kms/main .key_arn`.
- Used by: `eks-backend-services` (`.default_cluster_secret_store_name`, namespace
  `backend-services`) and `eks-addons`' Istio certificate ExternalSecret (`aws-certificate-store`,
  namespace `istio-ingress`).

## Notes

- Every store has `spec.conditions[].namespaces`: `allowed_namespaces` (required while
  `aws-secretsmanager` is created) and `certificate_allowed_namespaces` (default
  `["istio-ingress"]`). An ExternalSecret in any other namespace is refused.
- The operator's own service account has no IAM role, so a namespaced `SecretStore` without auth
  gets no AWS credentials, and a namespaced store cannot reference the stores' service accounts.
- Each role reads Secrets Manager only, on its own prefixes: `secret_path_prefixes` (plus
  `rds!db-*` with `rds_managed_secret_access`) or `certificate_secret_path_prefixes`, each also
  under `<stage>/` via `secret_path_context_prefixes`. The two lists may not overlap. `kms:Decrypt`
  is on `kms_key_arn` through Secrets Manager only. There is no SSM access and no `ListSecrets`, so
  `dataFrom.find` does not work.
- Deliberate deviation from Cloud Posse, which puts the IRSA role on the operator's service
  account: per-store roles keep a namespaced `SecretStore` with no auth from inheriting the
  operator's credentials.
- The stores need the CRDs only at apply time, after the operator release (`wait = true`); a plan
  on a fresh cluster needs no CRDs. If the stores release hits the rare race where the webhook's
  endpoint has not propagated yet, re-apply.
- `chart_version` is pinned once, in the catalog (2.11.0, tested on Kubernetes 1.36). 2.x serves
  only `external-secrets.io/v1`; validation rejects 0.x.
- IAM names are `<cluster_name>-external-secrets-{role,policy}` and
  `<cluster_name>-external-secrets-cert-{role,policy}` (64-character limit validated).
- Each instance lists its own `dependencies.components`: `list_merge_strategy: replace` drops the
  catalog base's list.
- In dev, `enabled` follows `settings.environment.use_external_secrets`.

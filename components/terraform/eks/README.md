# eks

Creates one or more EKS clusters from `var.clusters`, each with its own KMS key for
secrets encryption, a CloudWatch log group, an IAM cluster role and node-group role
(SSM/CNI/ECR-read-only policies attached), EKS managed node groups
(`aws_eks_node_group`), and an IAM OIDC provider for IRSA.

## Deployed instances

- `eks/main`, `eks/data` — dev, staging, prod (all 3 real stacks)
- `eks/defaults` — abstract catalog entry only, not a real cluster, inherited by
  `eks/main`/`eks/data`

## Inputs / Outputs

| Required inputs | Behavior-changing | Outputs |
|---|---|---|
| `subnet_ids` (>= 2, `subnet-*` format), `clusters` map (each needs a valid `X.Y` `kubernetes_version`), `tags.Environment` | `default_kubernetes_version`, `enable_cluster_protection`, `default_cluster_log_retention_days` | `cluster_ids`, `cluster_endpoints`, `cluster_ca_data`, `oidc_provider_arns`, `node_role_arns` (all maps keyed by cluster name) |

## Dependencies & gotchas

- `eks/main` depends on `vpc/main`, `kms/main`; `eks/data` depends on
  `vpc/services`, `kms/main`.
- `external-secrets/main` and `external-secrets/data` stack configs read
  `!terraform.state eks/main .cluster_name` / `.cluster_endpoint` /
  `.cluster_ca_certificate` / `.oidc_provider_arn` / `.oidc_provider_url`, but
  outputs.tf only exposes map-valued outputs (`cluster_ids`, `cluster_endpoints`,
  `cluster_ca_data`, `oidc_provider_arns`) keyed by cluster name — those flat
  singular output names don't exist in this component.
- `deletion_protection` is only enabled when `enable_cluster_protection = true`
  AND `tags.Environment` (case-insensitive) is `prod` or `production`.

## Usage

```
atmos terraform plan eks/main -s fnx-prod-production
atmos terraform plan eks/data -s fnx-staging-staging-01
```

# eks

Creates one or more EKS clusters from `var.clusters`, each with its own KMS key
encrypting both its secrets and its control-plane log group, an IAM cluster role and
node-group role (SSM/CNI/ECR-read-only policies attached), EKS managed node groups
(`aws_eks_node_group`) behind one launch template per group, and an IAM OIDC provider
for IRSA.

## Deployed instances

- `eks/main`, `eks/data` — dev, staging, prod (all 3 real stacks)
- `eks/defaults` — abstract catalog entry only, not a real cluster, inherited by
  `eks/main`/`eks/data`

## Inputs / Outputs

| Required inputs | Behavior-changing | Outputs |
|---|---|---|
| `subnet_ids` (>= 2, `subnet-*` format), `clusters` map (each needs a valid `X.Y` `kubernetes_version`), `tags.Environment` | `default_kubernetes_version`, `enable_cluster_protection`, `default_cluster_log_retention_days`; a cluster with `endpoint_public_access` must set `public_access_cidrs` (non-empty, no `0.0.0.0/0`) | `cluster_ids`, `cluster_endpoints`, `cluster_ca_data`, `oidc_provider_arns`, `node_role_arns` (all maps keyed by cluster name) |

## Node groups

`clusters[*].node_groups` is a typed object schema, not `map(any)`, and the
per-node-group instance settings follow `cloudposse/terraform-aws-eks-node-group`.

- **Root volumes live in `block_device_map`**, not in `disk_size`/`disk_type`/
  `disk_encrypted`. Those keys no longer exist: `aws_eks_node_group` has no
  argument for volume type or encryption, so the component attaches a launch
  template instead. Defaults give an encrypted gp3 50 GB root volume, so a stack
  that wants the secure baseline sets nothing.
- **Unknown keys are rejected, not ignored.** Terraform silently drops object
  attributes a type constraint does not declare, which is how prod's
  `disk_type: gp3` and `disk_encrypted: true` were accepted and had no effect.
  The camel case spellings (`volumeSize`, `kmsKeyId`, ...) are declared purely so
  a typo fails validation instead of falling back to the default.
- **IMDSv2 is required by default** and the hop limit is 2, which is what AWS
  requires for a container off the host network to reach IMDS. Prefer IRSA and
  set `metadata_http_put_response_hop_limit = 1` where no pod needs IMDS.
- **Attaching the launch template replaces existing node groups.**
  `launch_template.id` is ForceNew, and AWS does not let a node group created
  without a custom launch template adopt one. `create_before_destroy` plus the
  name prefix make the rollout safe, but it is a rolling replacement.

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

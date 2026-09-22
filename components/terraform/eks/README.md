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
  `disk_encrypted`. `aws_eks_node_group` has no argument for volume type or
  encryption, so the component attaches a launch template instead. Defaults give
  an encrypted gp3 50 GB root volume, so a stack that wants the secure baseline
  sets nothing. The launch template tags the instances, volumes and network
  interfaces it launches with `tags`.
- **Known stale keys are rejected, not ignored.** Terraform silently drops object
  attributes a type constraint does not declare, which is how prod's
  `disk_type: gp3` and `disk_encrypted: true` were accepted and had no effect.
  `disk_size`, `disk_type`, `disk_encrypted`, `disk_encryption_enabled` and the
  camel case spellings in `block_device_map` (`volumeSize`, `kmsKeyId`, ...) are
  declared only so that a validation can reject them. Other unknown keys are
  still dropped.
- **Node group names** are `<Environment>-<cluster key>-<node group key>-<pet>`.
  The Environment is omitted when the cluster key already starts with it, so
  prod's names look like `production-main-memory-optimized-<pet>`. The `random_pet` suffix
  changes whenever an input that forces replacement changes (node role, subnets,
  instance types, AMI type, capacity type, launch template). That lets
  `create_before_destroy` start the replacement next to the live group under a
  new name, the way `cloudposse/terraform-aws-eks-node-group` does. The part
  before the pet may be at most 54, 45, 34 or 23 characters for a
  `random_pet_length` of 1, 2, 3 or 4 (54 by default). The pet is a name,
  an adjective and a name, or adverbs followed by an adjective and a name.
  Names and adjectives are at most 8 characters and adverbs at most 10, each
  after a `-`. This is
  enforced by variable validation, so it fails without AWS credentials. The
  node group, its launch template and everything the template launches share
  one `Name` tag, the name without the pet.
- **Cloud Posse's per-node-group knobs**, with their defaults:
  `random_pet_length` (1) and `immediately_apply_lt_changes` (null, which
  follows `create_before_destroy` and is therefore true here). With the
  default, **any launch template change** (disk size, IMDS settings,
  monitoring, tags) replaces the node group blue/green. Set it to `false` to
  have such a change roll onto the existing group as a new template version.
- **IMDSv2 is required by default** and the hop limit is 2, which is what AWS
  requires for a container off the host network to reach IMDS. Prefer IRSA and
  set `metadata_http_put_response_hop_limit = 1` where no pod needs IMDS.
- **Attaching the launch template replaces existing node groups.**
  `launch_template.id` is ForceNew, and AWS does not let a node group created
  without a custom launch template adopt one. `create_before_destroy` plus the
  pet suffix make the rollout safe, but each new group comes up at full size
  before the old one drains, so capacity doubles for the length of the rollout.

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

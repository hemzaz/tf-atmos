# eks

Creates **one** EKS cluster per component instance, the model of
`cloudposse-terraform-components/aws-eks-cluster`: the cluster with its own KMS key
(always for the control-plane log group; for Kubernetes secrets too unless
`cluster_encryption_config_kms_key_id` names a caller key, as prod does), an IAM cluster role and
node-group role (worker/CNI/ECR-read-only policies attached), EKS managed node groups
(`aws_eks_node_group`) behind one launch template per group, and an IAM OIDC provider
for IRSA. Every resource is `count = enabled ? 1 : 0` (node groups: one per
`node_groups` entry), so `enabled = false` plans nothing.

## Deployed instances

| Stack | `eks/main` | `eks/data` |
|---|---|---|
| `fnx-dev-testenv-01` | `testenv-01-main` | `testenv-01-data` |
| `fnx-staging-staging-01` | `staging-01-main` | `staging-01-data` |
| `fnx-prod-production` | `production-main` | `production-data` |

`eks/defaults` is the abstract catalog entry both inherit.

## Names

Every name is `<tags.Environment>-<name>` (the repo's `name_prefix` convention):
the cluster, `<prefix>-cluster-role`, `<prefix>-node-role`, `<prefix>-kms-key`,
`/aws/eks/<prefix>/cluster`, and node groups `<prefix>-<node group key>-<pet>`.
`name` must not start with the Environment (a validation rejects
`name: production-main` in prod), so no name repeats it. A second validation keeps
`<prefix>-cluster-role` within IAM's 64 characters.

## Inputs

Cloud Posse names where `aws-eks-cluster` has the setting.

| Input | Default | Notes |
|---|---|---|
| `name` | required | cluster name without the Environment |
| `enabled` | `true` | |
| `subnet_ids` | required | >= 2, `subnet-*` |
| `tags` | required | must contain `Environment` |
| `cluster_kubernetes_version` | `null` | `X.Y`; the catalog sets it from `settings.environment.eks_kubernetes_version` (1.36) |
| `cluster_endpoint_private_access` | `true` | Cloud Posse defaults to `false`; at least one endpoint must be on (validated) |
| `cluster_endpoint_public_access` | `false` | a public endpoint must set `public_access_cidrs` |
| `public_access_cidrs` | `null` | who may reach the API server (inbound). With a public endpoint: non-empty (AWS reads `[]` as `0.0.0.0/0`), valid CIDRs, never a `/0` (`0.0.0.0/0` is Cloud Posse's default; `::/0` too), because the repo never opens inbound access to everywhere. All are variable validations, so they fail without credentials |
| `associated_security_group_ids` | `[]` | extra security groups on the cluster ENIs |
| `cluster_encryption_config_kms_key_id` | `""` | secrets key; empty: the component's own key. The log group always uses the component key (a caller key would need a CloudWatch Logs grant for it) |
| `enabled_cluster_log_types` | all five | Cloud Posse defaults to `[]` |
| `cluster_log_retention_period` | `7` | prod pins 90 in its stack file |
| `enable_cluster_protection` | `true` | deletion protection when `tags.Environment` is `prod`/`production` |
| `node_groups` | `{}` | map keyed by node group name, see below |

## Outputs

Cloud Posse names and formats (`one(<resource>[*].<attr>)`, null when disabled):

| Output | Value |
|---|---|
| `eks_cluster_id` | the cluster **name** |
| `eks_cluster_arn`, `eks_cluster_endpoint`, `eks_cluster_version` | |
| `eks_cluster_certificate_authority_data` | the CA, **base64** as EKS returns it (external-secrets decodes it) |
| `eks_cluster_identity_oidc_issuer` | the issuer URL **with `https://`** (eks-addons requires it; external-secrets strips it) |
| `eks_cluster_identity_oidc_issuer_arn` | the IAM OIDC provider ARN, for IRSA trust policies |
| `eks_cluster_managed_security_group_id` | the security group EKS created |
| `eks_node_group_arns`, `eks_node_group_ids`, `eks_managed_node_workers_role_arns` | lists |
| `cloudwatch_log_group_name` | `/aws/eks/<cluster>/cluster` |

## Node groups

`node_groups` is a typed map; the per-node-group fields follow
`cloudposse/terraform-aws-eks-node-group` (`desired_group_size`, `min_group_size`,
`max_group_size`, `kubernetes_labels`, `kubernetes_taints`, `instance_types`,
`ami_type`, `capacity_type`, `subnet_ids`, `update_config`, `block_device_map`,
`metadata_*`, `detailed_monitoring_enabled`, `random_pet_length`,
`immediately_apply_lt_changes`, `tags`, `enabled`).

- **AMI type defaults to `AL2023_x86_64_STANDARD`**, a deviation:
  `cloudposse/terraform-aws-eks-node-group` defaults to `AL2_x86_64` and
  `aws-eks-cluster` leaves it null. AWS publishes no Amazon Linux 2 EKS AMIs for
  Kubernetes 1.33 and later (see the EKS user guide, kubernetes-versions-extended,
  1.32 notes), and the stacks pin 1.36, so a validation rejects an `AL2_*`
  `ami_type` on such a cluster.

- **Root volumes live in `block_device_map`**, not in `disk_size`/`disk_type`/
  `disk_encrypted`. `aws_eks_node_group` has no argument for volume type or
  encryption, so the component attaches a launch template instead. Defaults give
  an encrypted gp3 50 GB root volume, so a stack that wants the secure baseline
  sets nothing. The launch template tags the instances, volumes and network
  interfaces it launches with `tags`.
- **Known stale keys are rejected, not ignored.** Terraform silently drops object
  attributes a type constraint does not declare. `disk_size`, `disk_type`,
  `disk_encrypted`, `disk_encryption_enabled` and the camel case spellings in
  `block_device_map` (`volumeSize`, `kmsKeyId`, ...) are declared only so that a
  validation can reject them. Other unknown keys are still dropped.
- **Node group names** are `<Environment>-<name>-<node group key>-<pet>`. The
  `random_pet` suffix changes whenever an input that forces replacement changes
  (node role, subnets, instance types, AMI type, capacity type, launch template).
  That lets `create_before_destroy` start the replacement next to the live group
  under a new name, the way `cloudposse/terraform-aws-eks-node-group` does. The
  part before the pet may be at most 54, 45, 34 or 23 characters for a
  `random_pet_length` of 1, 2, 3 or 4 (54 by default), enforced by variable
  validation, so it fails without AWS credentials. The node group, its launch
  template and everything the template launches share one `Name` tag, the name
  without the pet.
- **Cloud Posse's per-node-group knobs**, with their defaults:
  `random_pet_length` (1) and `immediately_apply_lt_changes` (null, which
  follows `create_before_destroy` and is therefore true here). With the
  default, **any launch template change** (disk size, IMDS settings,
  monitoring, tags) replaces the node group blue/green. Set it to `false` to
  have such a change roll onto the existing group as a new template version.
- **IMDSv2 is required by default** and the hop limit is 2, which is what AWS
  requires for a container off the host network to reach IMDS. Prefer IRSA and
  set `metadata_http_put_response_hop_limit = 1` where no pod needs IMDS.

## Dependencies

- `eks/main` depends on `vpc/main` (and `kms/main` in prod); `eks/data` on
  `vpc/services` (and `kms/main` in prod).
- `external-secrets/main` and `external-secrets/data` read `eks_cluster_id`,
  `eks_cluster_endpoint`, `eks_cluster_certificate_authority_data`,
  `eks_cluster_identity_oidc_issuer_arn` and `eks_cluster_identity_oidc_issuer`.
- `idp-platform` calls this component as a module (`source = "../eks"`).

## Tests

`tests/eks.tftest.hcl` runs with mock providers (no credentials): names per
Environment, no doubled Environment (and no false positives), IAM and node group
length limits at their boundaries, the output formats consumers rely on, the
endpoint rules, the KMS split, the AL2023 default for 1.36, and `enabled = false`.

```
terraform init -backend=false && terraform test
```

## Usage

```
atmos terraform plan eks/main -s fnx-prod-production
atmos terraform plan eks/data -s fnx-staging-staging-01
```

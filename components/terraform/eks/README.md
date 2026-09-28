# eks

Creates **one** EKS cluster per component instance, the model of
`cloudposse-terraform-components/aws-eks-cluster`: the cluster with its own KMS key,
created only when `cluster_encryption_config_kms_key_id` names no caller key (all 3
stacks now pass `kms/main`, so this component key goes uncreated everywhere in
practice) — that key, or the caller's, encrypts both Kubernetes secrets and the
control-plane log group; an IAM cluster role and node-group role
(worker/ECR-read-only policies attached, no CNI policy); the `vpc-cni` managed addon
with its own IRSA role; EKS access entries for the principals that may use the
Kubernetes API (see [Access model](#access-model)); EKS managed node groups
(`aws_eks_node_group`) behind one launch template per group, whose block devices
default to `node_group_ebs_kms_key_id` (also `kms/main`) unless a device sets its own
`ebs.kms_key_id`; and an IAM OIDC provider for IRSA. Every resource is
`count = enabled ? 1 : 0` (node groups: one per `node_groups` entry), so
`enabled = false` plans nothing.

## Deployed instances

| Stack | `eks/main` | `eks/data` |
|---|---|---|
| `fnx-dev-testenv-01` | `testenv-01-main` | `testenv-01-data` |
| `fnx-staging-staging-01` | `staging-01-main` | `staging-01-data` |
| `fnx-prod-production` | `production-main` | `production-data` |

`eks/defaults` is the abstract catalog entry both inherit.

## Names

Every name is `<tags.Environment>-<name>` (the repo's `name_prefix` convention):
the cluster, `<prefix>-cluster-role`, `<prefix>-node-role`, `<prefix>-vpc-cni-role`
(the same length as `-cluster-role`), `<prefix>-kms-key`,
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
| `cluster_encryption_config_kms_key_id` | `""` | secrets key; empty creates and uses the component's own key. All 3 stacks pass `kms/main` here, so the log group (which always follows this same key) uses it too, and the component's own key is not created at all — `kms/main`'s `allow_cloudwatch_logs` already grants every log group in the account and region, so no per-log-group grant is needed |
| `node_group_ebs_kms_key_id` | `""` | default key for a node group's `block_device_map` volumes that set no `ebs.kms_key_id` of their own; empty leaves them on the AWS managed `aws/ebs` key. `eks/defaults` sets this to `kms/main`, whose `allow_autoscaling_ebs` grants the AWS Auto Scaling service-linked role the `kms:CreateGrant` (`kms:GrantIsForAWSResource`) and crypto actions EC2 needs to launch encrypted volumes from it |
| `enabled_cluster_log_types` | all five | Cloud Posse defaults to `[]` |
| `cluster_log_retention_period` | `7` | prod pins 90 in its stack file |
| `enable_cluster_protection` | `true` | deletion protection when `tags.Environment` is `prod`/`production` |
| `node_groups` | `{}` | map keyed by node group name, see below |
| `access_config` | `{ authentication_mode = "API", bootstrap_cluster_creator_admin_permissions = false }` | Cloud Posse's type and default. `API` or `API_AND_CONFIG_MAP` (`CONFIG_MAP` rejected). The bootstrap flag only applies at creation and is ignored afterwards |
| `access_entry_map` | `{}` | Cloud Posse's map: principal ARN => `{ user_name, kubernetes_groups, type, access_policy_associations = { <policy> = { access_scope = { type, namespaces } } } }`. Keys must be literal (see below) |
| `access_entries` | `[]` | Cloud Posse's list of STANDARD entries: `{ principal_arn, user_name, kubernetes_groups }`. A null `principal_arn` is skipped |
| `access_policy_associations` | `[]` | Cloud Posse's list: `{ principal_arn, policy_arn, access_scope = { type, namespaces } }`. A null `principal_arn` is skipped |
| `upgrade_policy` | `{ support_type = "STANDARD" }` | `STANDARD` or `EXTENDED`. Cloud Posse defaults to null, which AWS treats as `EXTENDED` (paid); `STANDARD` fails closed |
| `vpc_cni_addon` | `{}` | the `vpc-cni` addon: `addon_version` (null: EKS default for the cluster version), `configuration_values`, `resolve_conflicts_on_create`/`_on_update` (`OVERWRITE`), `service_account_role_arn` (null: this component creates the IRSA role), `*_timeout`, `preserve` (`true`). Fields of an entry in Cloud Posse's `addons` map |

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
| `eks_addons_versions` | `{ "vpc-cni" = <version> }` (Cloud Posse's name; the other addons belong to eks-addons) |
| `vpc_cni_service_account_role_arn` | the `aws-node` IRSA role, created here or passed in |
| `eks_access_entry_principal_arns` | principals with an access entry from this component (Cloud Posse has no such output) |

## Access model

The cluster uses EKS access entries, as `cloudposse/terraform-aws-eks-cluster` does
(`auth.tf` here mirrors its `auth.tf`):

- **Authentication mode `API`.** There is no `aws-auth` ConfigMap. Managed node groups
  get their `EC2_LINUX` access entries from EKS itself.
- **No hidden admin.** `bootstrap_cluster_creator_admin_permissions` is `false`, so
  whoever creates the cluster gets no Kubernetes permissions of their own. Every
  principal with access is an access entry in this component's inputs, and removing it
  revokes the access. IAM principals with `eks:CreateAccessEntry` can still add
  entries through the AWS API, so this cannot lock the account out.
- **Policies.** An association names an EKS access policy by short name (`Admin`,
  `ClusterAdmin`, `Edit`, `View`), full name (`AmazonEKSViewPolicy`, and also
  `AmazonEKSAdminViewPolicy`, `AmazonEMRJobPolicy`) or ARN. Anything else, an IAM
  policy ARN included, is rejected by validation. `access_scope.type` is `cluster` or
  `namespace`; a `namespace` scope must list its namespaces, a `cluster` scope must not.
- **`system:masters`** in an `access_entry_map` STANDARD entry becomes a `ClusterAdmin`
  association (Cloud Posse's translation). Other `system:*` groups are rejected.
- **Map or lists.** `access_entry_map` is keyed by principal ARN and must be written
  literally: an Atmos YAML function such as `!terraform.state` produces a value, never
  a map key. Principals read from another component's state go in the lists instead.

The stacks (`stacks/catalog/eks/defaults.yaml`, inherited by every `eks/*` instance)
use the lists:

| Principal | Source | Access policy | Scope |
|---|---|---|---|
| CI plan role | `!terraform.state iam/ci .ci_plan_role_arn` | `AmazonEKSViewPolicy` | cluster |
| CI apply role | `!terraform.state iam/ci .ci_apply_role_arn` | `AmazonEKSClusterAdminPolicy` | cluster |

`iam/ci` returns a null `ci_apply_role_arn` while its apply role is disabled (every
stack today); the component skips null principals, so the stack then plans with the
plan role only. No human or break-glass admin principal is defined anywhere in the
stacks yet; add one to `access_entries`/`access_policy_associations` when it exists.

## vpc-cni and the node role

The node role has no `AmazonEKS_CNI_Policy`, as AWS recommends. The `vpc-cni` managed
addon gets it through its own IRSA role (`<cluster>-vpc-cni-role`, trusted only by
`kube-system/aws-node` through the cluster's OIDC provider), the pattern of Cloud
Posse's `aws-eks-cluster` (`vpc_cni_eks_iam_role`, `aws_iam_role_policy_attachment.vpc_cni`).
The addon adopts the self-managed `aws-node` EKS installs (`OVERWRITE`) and is created
**before** the node groups, so the first nodes already run `aws-node` with the role and
pod networking works in the same apply. Cloud Posse installs addons after the node
groups by default; that works for them because their node role keeps the CNI policy.
`vpc-cni` is owned by this component: do not also list it in an eks-addons instance's
`addons`.

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
- **IMDSv2 is required by default** and the hop limit is 1, as on the ec2
  component (Cloud Posse defaults to 2): only processes on the host network reach
  IMDS, and pods use IRSA. A node group whose pods need IMDS sets
  `metadata_http_put_response_hop_limit = 2`, the minimum AWS requires for a
  container off the host network.

## Dependencies

- `eks/main` depends on `vpc/main` and `kms/main` (`cluster_encryption_config_kms_key_id`
  and `node_group_ebs_kms_key_id`, both set from `kms/main` in every stack); `eks/data`
  on `vpc/services` and `kms/main`. Every instance also depends on `iam/ci`, whose
  CI role ARNs become access entries.
- `external-secrets/main` and `external-secrets/data` read `eks_cluster_id`,
  `eks_cluster_endpoint`, `eks_cluster_certificate_authority_data`,
  `eks_cluster_identity_oidc_issuer_arn` and `eks_cluster_identity_oidc_issuer`.
- `idp-platform` calls this component as a module (`source = "../eks"`).

## Tests

`tests/eks.tftest.hcl` runs with mock providers (no credentials): names per
Environment, no doubled Environment (and no false positives), IAM and node group
length limits at their boundaries, the output formats consumers rely on, the
endpoint rules, the KMS split (including that a caller key leaves the component key
uncreated), `node_group_ebs_kms_key_id` defaulting and being overridden per device,
the AL2023 default for 1.36, and `enabled = false`.

`tests/access.tftest.hcl` covers the access model and node defaults: `API` mode with no
bootstrap admin and `STANDARD` support by default; the CI-role list wiring and policy
name expansion; null principals skipped; `access_entry_map` expansion and the
`system:masters` translation; rejection of a namespace scope without namespaces (map
and list), a cluster scope with namespaces, unknown scope types, unknown or IAM
policies, `system:*` groups, `CONFIG_MAP`, and unknown support types; the CNI policy on
the vpc-cni IRSA role and not the node role, the addon's `service_account_role_arn`
and trust policy, a caller-supplied role; the hop limit default of 1.

```
terraform init -backend=false && terraform test
```

## Usage

```
atmos terraform plan eks/main -s fnx-prod-production
atmos terraform plan eks/data -s fnx-staging-staging-01
```

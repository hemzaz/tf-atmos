# eks

One EKS cluster per instance, modelled on Cloud Posse `aws-eks-cluster`: the cluster, IAM cluster
and node roles, the `vpc-cni` managed addon with its own IRSA role, EKS access entries, managed
node groups behind one launch template each, and the IAM OIDC provider for IRSA. Input and output
names follow Cloud Posse's; node-group fields follow `terraform-aws-eks-node-group`.

## Wiring

- Instances: `eks/main` (reads `vpc/main .private_subnet_ids`) and `eks/data` (reads
  `vpc/services .private_subnet_ids`) in the three AWS stacks. Both read `kms/main .key_arn`
  (secrets, control-plane logs, node EBS), `iam/ci .ci_plan_role_arn` / `.ci_apply_role_arn` and
  `ec2/bastion .security_group_id` (`allowed_security_group_ids`).
- Used by: `eks-addons`, `external-secrets`, `eks-backend-services` (cluster ID, endpoint, base64 CA,
  OIDC issuer with `https://` and its provider ARN), `rds/main` and `elasticache/main`
  (`.eks_cluster_managed_security_group_id`), `monitoring` (`.eks_cluster_id`).
- `idp-platform` calls this component as a module (`source = "../eks"`).

## Access model

- Authentication mode `API`: no `aws-auth` ConfigMap. Node groups get their access entries from EKS.
- `bootstrap_cluster_creator_admin_permissions = false`: whoever creates the cluster gets nothing
  implicitly. Every principal is an access entry in the inputs.
- `stacks/catalog/eks/defaults.yaml` grants the CI plan role `AmazonEKSViewPolicy` and the CI apply
  role `AmazonEKSClusterAdminPolicy`, both cluster-scoped.
- Human admins (the operators of the in-cluster components): Cloud Posse's
  `map_additional_iam_roles`, set per stack in `components/globals.yaml` on `eks/defaults`;
  `groups: ["system:masters"]` becomes a cluster-scoped `AmazonEKSClusterAdminPolicy` entry. The
  `rolearn` keeps its path (access entries need it, unlike `aws-auth`): an IAM Identity Center role is
  `role/aws-reserved/sso.amazonaws.com/<region>/AWSReservedSSO_<set>_<hash>`, and a stripped one is
  rejected. `check-cluster-api-ci.py` warns while a private stack has none. They reach the private
  endpoint through `ec2/bastion`'s SSM port-forward (docs/OPERATIONS.md "In-cluster components"):
  each instance sets `allowed_security_group_ids` to the bastion's security group, and `eks/data`
  (in `vpc/services`) is reached over `network/vpc-peering`.
- `allowed_security_group_ids` / `allowed_cidr_blocks` (Cloud Posse's names; the aws-eks-cluster
  component calls the first `allowed_security_groups`) add ingress rules on the EKS-managed cluster
  security group, TCP 443 only where Cloud Posse opens all protocols. A `/0` is rejected.
- Principals read with `!terraform.state` must go in those lists: `access_entry_map` keys must be
  literal. Null principals are skipped.

## Notes

- `vpc-cni` is created before the node groups and gets `AmazonEKS_CNI_Policy` through its IRSA role;
  the node role has no CNI policy. Do not also list `vpc-cni` in eks-addons.
- IMDSv2 is required with hop limit 1 (Cloud Posse uses 2): pods use IRSA. A node group whose pods
  need IMDS sets `metadata_http_put_response_hop_limit = 2`.
- `ami_type` defaults to `AL2023_x86_64_STANDARD`; `AL2_*` is rejected on Kubernetes 1.33+ (the
  stacks pin 1.36).
- Root volumes are set in `block_device_map` (encrypted gp3 50 GB by default). `disk_size` and other
  stale keys are rejected by validation, not silently dropped.
- Any launch template change replaces the node group blue/green (`create_before_destroy` with a
  `random_pet` name suffix) unless `immediately_apply_lt_changes = false`.
- `name` must not start with the Environment; resource names are `<Environment>-<name>`.
- A public endpoint needs non-empty `public_access_cidrs` without `/0`.
- `upgrade_policy` defaults to `STANDARD` (AWS treats null as paid `EXTENDED`).

# EKS access entries, as in cloudposse/terraform-aws-eks-cluster (auth.tf):
# the cluster runs in `API` authentication mode (var.access_config), and every
# principal that may use the Kubernetes API is an access entry with access
# policy associations. There is no aws-auth ConfigMap.
#
# Two ways to declare a principal, both Cloud Posse's:
# - var.access_entry_map, keyed by principal ARN. Keys must be known at plan
#   time and literal: Atmos YAML functions (!terraform.state) cannot produce a
#   map key.
# - var.access_entries plus var.access_policy_associations, lists with a
#   principal_arn field. The stacks use these, because the CI role ARNs come
#   from `!terraform.state aws-iam-role/ci-apply`.
#
# Divergences from Cloud Posse:
# - No `access_entries_for_nodes`: every node group here is a managed node
#   group, and EKS creates their EC2_LINUX access entries itself.
#
# Human admins: var.map_additional_iam_roles, the Cloud Posse eks/cluster
# component's input (cloudposse-terraform-components/aws-eks-cluster,
# src/main.tf iam_roles_access_entry_map). Each role becomes an
# access_entry_map entry below, merged under var.access_entry_map as upstream
# merges it under overridable_access_map. Or by permission set name:
# var.aws_sso_permission_sets_rbac, upstream's aws-sso.tf, resolved at plan
# time by data.aws_iam_roles.sso_roles below.

locals {
  # A full policy name that is not in the abbreviation map below (for example
  # AmazonEKSAdminViewPolicy) becomes this prefix plus the name. Cloud Posse
  # passes such a name through unchanged, which AWS rejects.
  eks_access_policy_arn_prefix = "arn:aws:eks::aws:cluster-access-policy/"

  eks_policy_short_abbreviation_map = {
    # List available policies with `aws eks list-access-policies --output table`
    Admin        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
    ClusterAdmin = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    Edit         = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
    View         = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  }

  eks_policy_abbreviation_map = merge(
    { for k, v in local.eks_policy_short_abbreviation_map : format("AmazonEKS%sPolicy", k) => v },
    local.eks_policy_short_abbreviation_map,
  )

  # Cloud Posse's iam_roles_access_entry_map, in access_entry_map's full shape
  # (the object defaults Terraform fills in for var.access_entry_map), so the
  # two merge into one map. `username` is ignored, as upstream.
  iam_roles_access_entry_map = {
    for role in var.map_additional_iam_roles : role.rolearn => {
      user_name                  = null
      kubernetes_groups          = role.groups
      type                       = "STANDARD"
      access_policy_associations = {}
    }
  }

  # Cloud Posse's aws_sso_access_entry_map (aws-eks-cluster, src/aws-sso.tf):
  # the role of each var.aws_sso_permission_sets_rbac set, resolved by
  # data.aws_iam_roles.sso_roles below, in the same full shape. As upstream,
  # it merges first, so map_additional_iam_roles and access_entry_map win on
  # the same ARN.
  aws_sso_access_entry_map = {
    for role in var.aws_sso_permission_sets_rbac : tolist(data.aws_iam_roles.sso_roles[role.aws_sso_permission_set].arns)[0] => {
      user_name                  = null
      kubernetes_groups          = role.groups
      type                       = "STANDARD"
      access_policy_associations = {}
    } if local.enabled
  }

  # Expand abbreviated access policies to full ARNs
  access_entry_expanded_map = { for k, v in merge(local.aws_sso_access_entry_map, local.iam_roles_access_entry_map, var.access_entry_map) : k => merge({
    access_policy_associations = {
      for kk, vv in v.access_policy_associations :
      try(local.eks_policy_abbreviation_map[kk], startswith(kk, "arn:") ? kk : "${local.eks_access_policy_arn_prefix}${kk}") => vv
    }
  }, { for kk, vv in v : kk => vv if kk != "access_policy_associations" }) }

  # Replace membership in "system:masters" with an association to the
  # ClusterAdmin policy, as Cloud Posse does for STANDARD entries.
  access_entry_map = { for k, v in local.access_entry_expanded_map : k => merge({
    kubernetes_groups = [for group in v.kubernetes_groups : group if group != "system:masters" || v.type != "STANDARD"]
    access_policy_associations = merge(
      v.access_policy_associations,
      contains(v.kubernetes_groups, "system:masters") && v.type == "STANDARD" ? {
        (local.eks_policy_short_abbreviation_map.ClusterAdmin) = {
          access_scope = {
            type       = "cluster"
            namespaces = null
          }
        }
      } : {}
    )
  }, { for kk, vv in v : kk => vv if kk != "kubernetes_groups" && kk != "access_policy_associations" }) }

  # Divergence: Cloud Posse's for_each is
  # `local.enabled ? local.access_entry_map : {}`. A conditional converts
  # both results to one map type, and that fails ("Inconsistent conditional
  # result types ... attribute types must all match for conversion to map")
  # as soon as two entries have different access_policy_associations keys:
  # the merge() above makes each entry an object of its own type. These two
  # maps give every element the same shape, the access scope included, and
  # filter on local.enabled inside the for expression instead.
  access_entry_resource_map = {
    for k, v in local.access_entry_map : k => {
      kubernetes_groups = tolist(v.kubernetes_groups)
      type              = v.type
      user_name         = v.user_name
    } if local.enabled
  }

  eks_access_policy_association_product_map = {
    for a in flatten([
      for k, v in local.access_entry_map : [for kk, vv in v.access_policy_associations : {
        key               = format("%s-%s", k, kk)
        principal_arn     = k
        policy_arn        = kk
        access_scope_type = vv.access_scope.type
        namespaces        = vv.access_scope.namespaces == null ? null : tolist(vv.access_scope.namespaces)
      }]
    ]) : a.key => a if local.enabled
  }

  access_entries             = local.enabled ? var.access_entries : []
  access_policy_associations = local.enabled ? var.access_policy_associations : []

  # Every principal that gets an access entry, from both forms. Cloud Posse
  # only documents "do not duplicate entries"; the preconditions below
  # enforce it. !terraform.state ARNs are literal by plan time (Atmos resolves
  # them before Terraform runs), so these preconditions fail the plan; they
  # are preconditions rather than check blocks so they block instead of
  # warn. A check block would let the apply go on to EKS's 409
  # (ResourceInUseException) or a policy association without an entry.
  map_entry_principal_arns = keys(local.access_entry_resource_map)
  entry_principal_arns     = concat(local.map_entry_principal_arns, [for e in local.access_entries : e.principal_arn])
}

# Cloud Posse's data "aws_iam_roles" "sso_roles" (aws-eks-cluster,
# src/aws-sso.tf), with its postcondition: the plan fails, naming the set,
# unless exactly one role matches. Divergences:
# - name_regex is anchored and ends in the hex hash
#   ("^AWSReservedSSO_<set>_[0-9a-f]{16}$", with `.` and `+` in the set name
#   escaped) where upstream has "AWSReservedSSO_<set>_.*": upstream's matches
#   set "Admin" against a set "Admin_ReadOnly" too and then fails as "more
#   than one".
# - for_each is empty while var.enabled is false (upstream reads anyway), so a
#   disabled instance or the default [] reads nothing.
data "aws_iam_roles" "sso_roles" {
  for_each    = local.enabled ? toset(var.aws_sso_permission_sets_rbac[*].aws_sso_permission_set) : toset([])
  name_regex  = format("^AWSReservedSSO_%s_[0-9a-f]{16}$", replace(each.value, "/([.+])/", "\\$1"))
  path_prefix = "/aws-reserved/sso.amazonaws.com/"

  lifecycle {
    postcondition {
      condition = length(self.arns) == 1
      error_message = length(self.arns) == 0 ? "Could not find Role ARN for the AWS SSO permission set: ${each.value}" : (
        "Found more than one (${length(self.arns)}) Role ARN for the AWS SSO permission set: ${each.value}"
      )
    }
  }
}

# The preferred way to keep track of entries is by key, but the list form is
# supported too, because keys need to be known at plan time.
resource "aws_eks_access_entry" "map" {
  for_each = local.access_entry_resource_map

  cluster_name      = aws_eks_cluster.default[0].name
  principal_arn     = each.key
  kubernetes_groups = each.value.kubernetes_groups
  type              = each.value.type
  user_name         = each.value.user_name

  tags = var.tags
}

resource "aws_eks_access_policy_association" "map" {
  for_each = local.eks_access_policy_association_product_map

  cluster_name  = aws_eks_cluster.default[0].name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.access_scope_type
    namespaces = each.value.namespaces
  }

  depends_on = [
    aws_eks_access_entry.map,
    aws_eks_access_entry.standard,
  ]
}

resource "aws_eks_access_entry" "standard" {
  count = length(local.access_entries)

  cluster_name      = aws_eks_cluster.default[0].name
  principal_arn     = local.access_entries[count.index].principal_arn
  kubernetes_groups = local.access_entries[count.index].kubernetes_groups
  user_name         = local.access_entries[count.index].user_name
  type              = "STANDARD"

  tags = var.tags

  lifecycle {
    # One access entry per principal (EKS: "An IAM principal can't be
    # included in more than one access entry").
    precondition {
      condition = (
        !contains(local.map_entry_principal_arns, local.access_entries[count.index].principal_arn) &&
        length([for e in local.access_entries : e if e.principal_arn == local.access_entries[count.index].principal_arn]) == 1
      )
      error_message = "access_entries principal ${local.access_entries[count.index].principal_arn} already has an access entry (access_entry_map, map_additional_iam_roles, aws_sso_permission_sets_rbac or another access_entries item); EKS allows one per principal."
    }
  }
}

resource "aws_eks_access_policy_association" "list" {
  count = length(local.access_policy_associations)

  cluster_name  = aws_eks_cluster.default[0].name
  principal_arn = local.access_policy_associations[count.index].principal_arn
  policy_arn = try(
    local.eks_policy_abbreviation_map[local.access_policy_associations[count.index].policy_arn],
    startswith(local.access_policy_associations[count.index].policy_arn, "arn:")
    ? local.access_policy_associations[count.index].policy_arn
    : "${local.eks_access_policy_arn_prefix}${local.access_policy_associations[count.index].policy_arn}",
  )

  access_scope {
    type       = local.access_policy_associations[count.index].access_scope.type
    namespaces = local.access_policy_associations[count.index].access_scope.namespaces
  }

  lifecycle {
    # EKS associates access policies with an existing access entry only.
    precondition {
      condition     = contains(local.entry_principal_arns, local.access_policy_associations[count.index].principal_arn)
      error_message = "access_policy_associations principal ${local.access_policy_associations[count.index].principal_arn} has no access entry: add it to access_entries, access_entry_map, map_additional_iam_roles or aws_sso_permission_sets_rbac."
    }
  }

  depends_on = [
    aws_eks_access_entry.map,
    aws_eks_access_entry.standard,
  ]
}

provider "aws" {
  region = var.region

  dynamic "assume_role" {
    for_each = var.assume_role_arn != null ? [var.assume_role_arn] : []
    content {
      role_arn = assume_role.value
    }
  }

  default_tags {
    tags = var.tags
  }
}

# No aws CLI exec plugin (eks-addons/external-secrets use one; the CI image
# that runs `terraform validate`/`terraform test` has no aws CLI, see
# CLAUDE.md's CI image parity note): the token comes from a plain data
# source instead.
provider "kubernetes" {
  host                   = var.host
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
  token                  = try(one(data.aws_eks_cluster_auth.this[*].token), "")
}

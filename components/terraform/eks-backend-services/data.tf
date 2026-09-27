data "aws_eks_cluster_auth" "this" {
  count = 1

  name = var.cluster_name
}

# Ingress on the EKS-managed cluster security group, as in
# cloudposse/terraform-aws-eks-cluster security-group.tf
# (managed_ingress_security_groups / managed_ingress_cidr_blocks): the group
# EKS creates and puts on the control-plane ENIs, which otherwise admits only
# itself. This is how an operator (the bastion's SSM port-forward,
# docs/OPERATIONS.md "In-cluster components") reaches a private endpoint.
#
# Deviation from Cloud Posse, which opens all protocols (ip_protocol = "-1"):
# only TCP 443, the Kubernetes API. Nothing else on the control plane is meant
# for these callers, and the repo keeps ingress to what a caller needs.
# Cloud Posse's managed_security_group_rules_enabled toggle is not carried:
# empty lists (the default) create no rules.

locals {
  cluster_security_group_id = one(aws_eks_cluster.default[*].vpc_config[0].cluster_security_group_id)
  cluster_api_port          = 443
}

resource "aws_vpc_security_group_ingress_rule" "managed_ingress_security_groups" {
  count = local.enabled ? length(var.allowed_security_group_ids) : 0

  description                  = "Kubernetes API from an allowed security group"
  ip_protocol                  = "tcp"
  from_port                    = local.cluster_api_port
  to_port                      = local.cluster_api_port
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  security_group_id            = local.cluster_security_group_id

  tags = { Name = "${local.cluster_name}-api-sg-${count.index}" }
}

resource "aws_vpc_security_group_ingress_rule" "managed_ingress_cidr_blocks" {
  count = local.enabled ? length(var.allowed_cidr_blocks) : 0

  description       = "Kubernetes API from an allowed CIDR block"
  ip_protocol       = "tcp"
  from_port         = local.cluster_api_port
  to_port           = local.cluster_api_port
  cidr_ipv4         = var.allowed_cidr_blocks[count.index]
  security_group_id = local.cluster_security_group_id

  tags = { Name = "${local.cluster_name}-api-cidr-${count.index}" }
}

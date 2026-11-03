locals {
  read_only_access_permission_set = local.enabled ? [{
    name             = "ReadOnlyAccess",
    description      = "Allow Read Only access to the account",
    relay_state      = "",
    session_duration = var.session_duration,
    tags             = module.this.tags,
    inline_policy    = one(data.aws_iam_policy_document.eks_read_only[*].json),
    policy_attachments = [
      "arn:${local.aws_partition}:iam::aws:policy/ReadOnlyAccess",
      "arn:${local.aws_partition}:iam::aws:policy/AWSSupportAccess"
    ]
    customer_managed_policy_attachments = []
  }] : []
}

data "aws_iam_policy_document" "eks_read_only" {
  count = local.enabled ? 1 : 0

  statement {
    sid    = "AllowEKSView"
    effect = "Allow"
    actions = [
      "eks:Get*",
      "eks:Describe*",
      "eks:List*",
      "eks:Access*"
    ]
    resources = [
      "*"
    ]
  }
}

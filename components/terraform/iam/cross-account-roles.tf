data "aws_iam_policy_document" "cross_account_assume_role" {
  statement {
    sid     = "TrustedAccountsAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [for id in var.trusted_account_ids : "arn:aws:iam::${id}:root"]
    }
  }
}

resource "aws_iam_role" "cross_account_role" {
  name               = var.cross_account_role_name
  assume_role_policy = data.aws_iam_policy_document.cross_account_assume_role.json
}

resource "aws_iam_policy" "cross_account_policy" {
  name        = var.policy_name
  path        = "/"
  description = "Cross-account access policy"

  policy = file("${path.module}/policies/account-setup-policies.json")
}

resource "aws_iam_role_policy_attachment" "cross_account_policy_attachment" {
  role       = aws_iam_role.cross_account_role.name
  policy_arn = aws_iam_policy.cross_account_policy.arn
}
resource "aws_iam_role" "cross_account_role" {
  name               = var.cross_account_role_name
  assume_role_policy = file("${path.module}/policies/assume-role-policy.json")
}

resource "aws_iam_policy" "cross_account_policy" {
  name        = var.policy_name
  path        = "/"
  description = "Cross-account access policy"
  policy      = file("${path.module}/policies/account-setup-policies.json")
}

resource "aws_iam_role_policy_attachment" "cross_account_policy_attachment" {
  role       = aws_iam_role.cross_account_role.name
  policy_arn = aws_iam_policy.cross_account_policy.arn
}
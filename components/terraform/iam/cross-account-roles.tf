resource "aws_iam_role" "cross_account_role" {
  name = var.cross_account_role_name

  # Use templatefile instead of file to enable customization
  assume_role_policy = templatefile(
    "${path.module}/policies/assume-role-policy.json.tpl",
    {
      trusted_account_ids = var.trusted_account_ids
      # Additional variables can be passed in as needed
    }
  )
}

resource "aws_iam_policy" "cross_account_policy" {
  name        = var.policy_name
  path        = "/"
  description = "Cross-account access policy"

  # Use templatefile instead of file to enable customization
  policy = templatefile(
    "${path.module}/policies/account-setup-policies.json.tpl",
    {
      resources = var.policy_resources
      # Additional variables can be passed in as needed
    }
  )
}

resource "aws_iam_role_policy_attachment" "cross_account_policy_attachment" {
  role       = aws_iam_role.cross_account_role.name
  policy_arn = aws_iam_policy.cross_account_policy.arn
}
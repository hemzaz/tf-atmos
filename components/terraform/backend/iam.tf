resource "aws_iam_role" "terraform_backend" {
  name               = var.iam_role_name
  assume_role_policy = file("${path.module}/policies/assume-role.json")
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "terraform_backend" {
  name = "TerraformBackendPolicy"
  role = aws_iam_role.terraform_backend.id
  policy = templatefile("${path.module}/policies/backend.json.tpl", {
    bucket_name         = var.bucket_name
    region              = var.region
    account_id          = data.aws_caller_identity.current.account_id
    dynamodb_table_name = var.dynamodb_table_name
  })
}
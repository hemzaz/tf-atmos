resource "aws_iam_role" "terraform_backend" {
  name               = var.iam_role_name
  assume_role_policy = file("${path.module}/policies/assume-role.json")
}

resource "aws_iam_role_policy" "terraform_backend" {
  name   = "TerraformBackendPolicy"
  role   = aws_iam_role.terraform_backend.id
  policy = file("${path.module}/policies/backend.json")
}
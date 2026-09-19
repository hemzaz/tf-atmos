data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "terraform_backend_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "terraform_backend" {
  name               = var.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.terraform_backend_assume_role.json
}

# State read/write plus S3-native locking ("<key>.tflock" objects in the same bucket)
data "aws_iam_policy_document" "terraform_backend" {
  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.terraform_state.arn]
  }

  statement {
    sid       = "ReadWriteStateAndLockFiles"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.terraform_state.arn}/*"]
  }

  statement {
    sid       = "UseStateKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.terraform_state_key.arn]
  }
}

resource "aws_iam_role_policy" "terraform_backend" {
  name   = "TerraformBackendPolicy"
  role   = aws_iam_role.terraform_backend.id
  policy = data.aws_iam_policy_document.terraform_backend.json
}

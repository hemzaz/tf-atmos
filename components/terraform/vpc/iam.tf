# vpc/iam.tf

resource "aws_iam_role" "vpc_management_role" {
  name = "${var.tags["Environment"]}-vpc-management-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-vpc-management-role"
    }
  )
}

resource "aws_iam_role_policy" "vpc_management_policy" {
  name = "${var.tags["Environment"]}-vpc-management-policy"
  role = aws_iam_role.vpc_management_role.id

  policy = file("${path.module}/policies/vpc-policies.json")
}

resource "aws_iam_instance_profile" "vpc_management_profile" {
  name = "${var.tags["Environment"]}-vpc-management-profile"
  role = aws_iam_role.vpc_management_role.name

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-vpc-management-profile"
    }
  )
}
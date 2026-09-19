# vpc/iam.tf

resource "aws_iam_role" "vpc_management_role" {
  count = var.create_vpc_iam_role ? 1 : 0

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

  tags = { Name = "${var.tags["Environment"]}-vpc-management-role" }
}

resource "aws_iam_role_policy" "vpc_management_policy" {
  count = var.create_vpc_iam_role ? 1 : 0

  name = "${var.tags["Environment"]}-vpc-management-policy"
  role = aws_iam_role.vpc_management_role[0].id

  policy = file("${path.module}/policies/vpc-policies.json")
}

resource "aws_iam_instance_profile" "vpc_management_profile" {
  count = var.create_vpc_iam_role ? 1 : 0

  name = "${var.tags["Environment"]}-vpc-management-profile"
  role = aws_iam_role.vpc_management_role[0].name

  tags = { Name = "${var.tags["Environment"]}-vpc-management-profile" }
}
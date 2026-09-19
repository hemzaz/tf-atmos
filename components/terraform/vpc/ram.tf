resource "aws_ram_resource_association" "vpc_subnets" {
  for_each           = var.ram_resource_share_arn != "" ? aws_subnet.private : {}
  resource_arn       = each.value.arn
  resource_share_arn = var.ram_resource_share_arn
}
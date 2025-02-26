resource "aws_ram_resource_association" "vpc_subnets" {
  count              = var.ram_resource_share_arn != "" ? length(aws_subnet.private) : 0
  resource_arn       = aws_subnet.private[count.index].arn
  resource_share_arn = var.ram_resource_share_arn
}
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? length(var.public_subnets) : 0
  vpc   = true

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-nat-eip-${count.index + 1}"
    }
  )
}

resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? length(var.public_subnets) : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-nat-gw-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}
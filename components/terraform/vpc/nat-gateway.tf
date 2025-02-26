locals {
  # Determine how many NAT gateways to create based on the NAT strategy
  nat_gateway_count = var.enable_nat_gateway ? (
    var.nat_gateway_strategy == "one_per_az" ? length(var.public_subnets) : (
      var.nat_gateway_strategy == "single" ? 1 : 0
    )
  ) : 0
}

resource "aws_eip" "nat" {
  count = local.nat_gateway_count
  vpc   = true

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-nat-eip-${count.index + 1}"
    }
  )
}

resource "aws_nat_gateway" "main" {
  count         = local.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  # Place NAT gateways in public subnets, distributing them based on the strategy
  subnet_id     = aws_subnet.public[count.index % length(var.public_subnets)].id

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-nat-gw-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}
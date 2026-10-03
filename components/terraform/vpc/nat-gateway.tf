locals {
  # Determine how many NAT gateways to create based on the NAT strategy
  nat_gateway_count = var.nat_gateway_enabled ? (
    var.nat_gateway_strategy == "one_per_az" ? length(var.public_subnets) : (
      var.nat_gateway_strategy == "single" ? 1 : 0
    )
  ) : 0

  # Determine the list of explicit subnet IDs to use for NAT gateways based on strategy.
  # Derived from nat_gateway_count so nat_gateway_enabled = false always wins: the
  # "single" strategy is the default, and testing the strategy first meant a
  # disabled NAT gateway was still created.
  nat_gateway_subnet_indices = local.nat_gateway_count == 0 ? [] : (
    var.nat_gateway_strategy == "one_per_az" ? [for i in range(local.nat_gateway_count) : i] : [0]
  )

  # NAT gateways keyed by the CIDR of the public subnet hosting them
  nat_gateways = {
    for n, i in local.nat_gateway_subnet_indices : var.public_subnets[i] => { number = n, subnet_index = i }
  }
}

resource "aws_eip" "nat" {
  for_each = local.nat_gateways
  domain   = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-nat-eip-${each.value.number + 1}"
      # The AZ of the public subnet hosting the gateway, not an assumed index.
      AZ = aws_subnet.public[each.key].availability_zone
    }
  )
}

resource "aws_nat_gateway" "main" {
  for_each      = local.nat_gateways
  allocation_id = aws_eip.nat[each.key].id
  # Place NAT gateways in public subnets with explicit AZ mapping for better control
  subnet_id = aws_subnet.public[each.key].id

  tags = { Name = "${var.tags["Environment"]}-nat-gw-${each.value.number + 1}" }

  depends_on = [aws_internet_gateway.main]
}
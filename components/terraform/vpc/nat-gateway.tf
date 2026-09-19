locals {
  # Determine how many NAT gateways to create based on the NAT strategy
  nat_gateway_count = var.enable_nat_gateway ? (
    var.nat_gateway_strategy == "one_per_az" ? length(var.public_subnets) : (
      var.nat_gateway_strategy == "single" ? 1 : 0
    )
  ) : 0

  # Determine the list of explicit subnet IDs to use for NAT gateways based on strategy
  nat_gateway_subnet_indices = var.nat_gateway_strategy == "one_per_az" ? [for i in range(local.nat_gateway_count) : i] : (var.nat_gateway_strategy == "single" ? [0] : [])

  # NAT gateways keyed by the CIDR of the public subnet hosting them
  nat_gateways = {
    for n, i in local.nat_gateway_subnet_indices : var.public_subnets[i] => { number = n, subnet_index = i }
  }
}

# Get available AZs for better NAT gateway placement
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_availability_zone" "available" {
  count = length(var.public_subnets)
  name  = var.nat_gateway_azs != null && length(var.nat_gateway_azs) > count.index ? var.nat_gateway_azs[count.index] : data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]
}

resource "aws_eip" "nat" {
  for_each = local.nat_gateways
  domain   = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-nat-eip-${each.value.number + 1}"
      AZ   = data.aws_availability_zone.available[each.value.subnet_index].name
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
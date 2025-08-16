locals {
  # Determine how many NAT gateways to create based on the NAT strategy
  nat_gateway_count = var.enable_nat_gateway ? (
    var.nat_gateway_strategy == "one_per_az" ? length(var.public_subnets) : (
      var.nat_gateway_strategy == "single" ? 1 : 0
    )
  ) : 0

  # Create a map of AZ to public subnet ID for explicit NAT gateway placement
  public_subnet_az_map = {
    for i, subnet in var.public_subnets :
    data.aws_availability_zone.available[i % length(data.aws_availability_zone.available)].name => i
  }

  # Determine the list of explicit subnet IDs to use for NAT gateways based on strategy
  nat_gateway_subnet_indices = var.nat_gateway_strategy == "one_per_az" ? [for i in range(local.nat_gateway_count) : i] : (var.nat_gateway_strategy == "single" ? [0] : [])
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
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-nat-eip-${count.index + 1}"
      AZ   = data.aws_availability_zone.available[local.nat_gateway_subnet_indices[count.index]].name
    }
  )
}

resource "aws_nat_gateway" "main" {
  count         = local.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  # Place NAT gateways in public subnets with explicit AZ mapping for better control
  subnet_id = aws_subnet.public[local.nat_gateway_subnet_indices[count.index]].id

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-nat-gw-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}
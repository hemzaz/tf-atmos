resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-public-rt"
    }
  )
}

resource "aws_route_table" "private" {
  count  = length(var.private_subnets)
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-private-rt-${count.index + 1}"
    }
  )
}

resource "aws_route" "private_nat_gateway" {
  # Only create routes if NAT gateway is enabled and we have at least one NAT gateway
  count = (var.enable_nat_gateway && local.nat_gateway_count > 0) ? length(var.private_subnets) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"

  # Fix NAT gateway routing bug: reference the appropriate NAT gateway based on strategy
  # For "single" strategy, all routes point to the single NAT gateway [0]
  # For "one_per_az" strategy, routes point to respective NAT gateways using modulo
  nat_gateway_id = var.nat_gateway_strategy == "single" ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index % max(local.nat_gateway_count, 1)].id

  # Explicitly depend on NAT gateways to ensure they exist before creating routes
  depends_on = [aws_nat_gateway.main]

  # Add validation for NAT gateway strategy
  lifecycle {
    precondition {
      condition     = contains(["single", "one_per_az"], var.nat_gateway_strategy)
      error_message = "NAT gateway strategy must be either 'single' or 'one_per_az'."
    }

    # Ensure nat_gateway_count > 0 if NAT is enabled
    precondition {
      condition     = !var.enable_nat_gateway || local.nat_gateway_count > 0
      error_message = "When NAT gateway is enabled, nat_gateway_count must be greater than 0."
    }
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id

  # Ensure route tables exist before creating associations
  depends_on = [aws_route_table.private]
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id

  # Ensure route table exists before creating associations
  depends_on = [aws_route_table.public]
}
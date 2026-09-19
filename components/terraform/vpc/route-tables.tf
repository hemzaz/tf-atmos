resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.tags["Environment"]}-public-rt" }
}

resource "aws_route_table" "private" {
  for_each = local.private_subnets
  vpc_id   = aws_vpc.main.id

  tags = { Name = "${var.tags["Environment"]}-private-rt-${each.value.index + 1}" }
}

resource "aws_route" "private_nat_gateway" {
  # Only create routes if NAT gateway is enabled and we have at least one NAT gateway
  for_each = (var.enable_nat_gateway && local.nat_gateway_count > 0) ? local.private_subnets : {}

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"

  # "single": every route uses the only NAT gateway; "one_per_az": private subnet i uses
  # NAT gateway i modulo the NAT gateway count
  nat_gateway_id = aws_nat_gateway.main[var.public_subnets[local.nat_gateway_subnet_indices[each.value.index % max(local.nat_gateway_count, 1)]]].id

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
  for_each       = local.private_subnets
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id

  # Ensure route tables exist before creating associations
  depends_on = [aws_route_table.private]
}

resource "aws_route_table_association" "public" {
  for_each       = local.public_subnets
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id

  # Ensure route table exists before creating associations
  depends_on = [aws_route_table.public]
}
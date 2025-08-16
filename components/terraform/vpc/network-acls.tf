# Network ACLs for additional subnet-level security
# These provide defense-in-depth beyond security groups

# Public subnet NACL - More restrictive for internet-facing resources
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.public[*].id

  # Allow inbound HTTP from internet
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Allow inbound HTTPS from internet
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Allow inbound ephemeral ports for return traffic
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 32768
    to_port    = 65535
  }

  # Allow inbound traffic from VPC CIDR
  ingress {
    protocol   = "-1"
    rule_no    = 130
    action     = "allow"
    cidr_block = coalesce(var.cidr_block, var.vpc_cidr)
    from_port  = 0
    to_port    = 0
  }

  # Allow SSH from management CIDR only (if specified)
  dynamic "ingress" {
    for_each = var.management_cidr != null ? [1] : []
    content {
      protocol   = "tcp"
      rule_no    = 140
      action     = "allow"
      cidr_block = var.management_cidr
      from_port  = 22
      to_port    = 22
    }
  }

  # Allow all outbound traffic
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-public-nacl"
      Type = "Public"
    }
  )
}

# Private subnet NACL - Only allow traffic from within VPC and specific outbound
resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id

  # Allow all inbound traffic from VPC CIDR
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = coalesce(var.cidr_block, var.vpc_cidr)
    from_port  = 0
    to_port    = 0
  }

  # Allow inbound ephemeral ports for return traffic (for NAT Gateway)
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 32768
    to_port    = 65535
  }

  # Allow HTTPS outbound (for package downloads, API calls)
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Allow HTTP outbound (for package downloads)
  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Allow DNS outbound
  egress {
    protocol   = "udp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 53
    to_port    = 53
  }

  # Allow all traffic within VPC
  egress {
    protocol   = "-1"
    rule_no    = 130
    action     = "allow"
    cidr_block = coalesce(var.cidr_block, var.vpc_cidr)
    from_port  = 0
    to_port    = 0
  }

  # Allow NTP outbound
  egress {
    protocol   = "udp"
    rule_no    = 140
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 123
    to_port    = 123
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-private-nacl"
      Type = "Private"
    }
  )
}

# Database subnet NACL - Most restrictive, only allow specific database traffic
resource "aws_network_acl" "database" {
  count      = length(var.database_subnets) > 0 ? 1 : 0
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.database[*].id

  # Allow inbound database traffic from private subnets only
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = coalesce(var.cidr_block, var.vpc_cidr)
    from_port  = 5432 # PostgreSQL
    to_port    = 5432
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = coalesce(var.cidr_block, var.vpc_cidr)
    from_port  = 3306 # MySQL
    to_port    = 3306
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = coalesce(var.cidr_block, var.vpc_cidr)
    from_port  = 6379 # Redis
    to_port    = 6379
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 130
    action     = "allow"
    cidr_block = coalesce(var.cidr_block, var.vpc_cidr)
    from_port  = 27017 # MongoDB
    to_port    = 27017
  }

  # Allow ephemeral ports for return traffic
  ingress {
    protocol   = "tcp"
    rule_no    = 140
    action     = "allow"
    cidr_block = coalesce(var.cidr_block, var.vpc_cidr)
    from_port  = 32768
    to_port    = 65535
  }

  # Allow minimal outbound traffic
  # Database traffic back to application subnets
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = coalesce(var.cidr_block, var.vpc_cidr)
    from_port  = 32768
    to_port    = 65535
  }

  # Allow HTTPS for updates and monitoring
  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Allow DNS
  egress {
    protocol   = "udp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 53
    to_port    = 53
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-database-nacl"
      Type = "Database"
    }
  )
}
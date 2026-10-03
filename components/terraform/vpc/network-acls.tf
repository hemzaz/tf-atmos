# Network ACLs for additional subnet-level security
# These provide defense-in-depth beyond security groups
#
# EXCEPTION to the repo rule "no inbound from 0.0.0.0/0": the inbound
# 0.0.0.0/0 entries below are deliberate and must stay. NACLs are stateless,
# so the reply to any outbound connection (NAT gateway egress, package
# downloads, AWS APIs) comes back from an internet address to an ephemeral
# port; without the 32768-65535 /0 ingress entries on the public and private
# NACLs that return traffic is dropped. The public NACL's 80/443 /0 entries
# are what lets internet-facing load balancers (placed by the kubernetes.io/role/elb
# subnet tag) receive traffic at all. Access control for workloads is done by
# security groups, which are stateful and never open inbound to /0.

# Public subnet NACL - More restrictive for internet-facing resources
resource "aws_network_acl" "public" {
  count      = var.manage_network_acls ? 1 : 0
  vpc_id     = aws_vpc.main.id
  subnet_ids = [for subnet in aws_subnet.public : subnet.id]

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
    cidr_block = var.ipv4_primary_cidr_block
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
  count      = var.manage_network_acls ? 1 : 0
  vpc_id     = aws_vpc.main.id
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]

  # Allow all inbound traffic from VPC CIDR
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.ipv4_primary_cidr_block
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
    cidr_block = var.ipv4_primary_cidr_block
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

  # Peered VPCs (network/vpc-peering): all traffic from and to each, as for
  # this VPC's own CIDR (rules 100/130). Both directions, because NACLs are
  # stateless: e.g. the bastion in vpc/main reaching eks/data's API in
  # vpc/services, and the reply to the bastion's ephemeral port.
  dynamic "ingress" {
    for_each = var.private_network_acl_peer_cidr_blocks
    content {
      protocol   = "-1"
      rule_no    = 200 + ingress.key
      action     = "allow"
      cidr_block = ingress.value
      from_port  = 0
      to_port    = 0
    }
  }

  dynamic "egress" {
    for_each = var.private_network_acl_peer_cidr_blocks
    content {
      protocol   = "-1"
      rule_no    = 200 + egress.key
      action     = "allow"
      cidr_block = egress.value
      from_port  = 0
      to_port    = 0
    }
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
  count      = var.manage_network_acls && length(var.database_subnets) > 0 ? 1 : 0
  vpc_id     = aws_vpc.main.id
  subnet_ids = [for subnet in aws_subnet.database : subnet.id]

  # Allow inbound database traffic from private subnets only
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.ipv4_primary_cidr_block
    from_port  = 5432 # PostgreSQL
    to_port    = 5432
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = var.ipv4_primary_cidr_block
    from_port  = 3306 # MySQL
    to_port    = 3306
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = var.ipv4_primary_cidr_block
    from_port  = 6379 # Redis
    to_port    = 6379
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 130
    action     = "allow"
    cidr_block = var.ipv4_primary_cidr_block
    from_port  = 27017 # MongoDB
    to_port    = 27017
  }

  # Allow ephemeral ports for return traffic: replies to connections this
  # database subnet's own hosts initiate outbound (e.g. the HTTPS/DNS egress
  # rules below), arriving back with a destination port in the standard
  # Linux ephemeral range. This is NOT the leg a VPC-attached Lambda's
  # request to this subnet uses -- that request's destination port is the
  # target service's fixed port (5432/3306/6379/27017, rules 100-130 above),
  # regardless of the Lambda's own source port. See egress rule 100 below
  # for that reply leg, which does need the wider Lambda ephemeral range.
  ingress {
    protocol   = "tcp"
    rule_no    = 140
    action     = "allow"
    cidr_block = var.ipv4_primary_cidr_block
    from_port  = 32768
    to_port    = 65535
  }

  # Allow minimal outbound traffic
  # Database traffic back to application subnets: the reply leg of a
  # connection FROM an application-tier client (including a VPC-attached
  # Lambda, e.g. redis-auth-rotation's testSecret step) TO this database
  # subnet. The destination port here is that client's ephemeral source
  # port, which for a VPC-attached Lambda's Hyperplane ENI can fall anywhere
  # in the documented 1024-65535 range, not only the narrower 32768-65535
  # Linux convention used by the ingress rule above -- so this rule alone
  # needs the wider range (VPC-CIDR-only, so this does not conflict with the
  # no-inbound-/0 rule; Cloud Posse's dynamic-subnets does not restrict NACL
  # ephemeral ranges either).
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.ipv4_primary_cidr_block
    from_port  = 1024
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

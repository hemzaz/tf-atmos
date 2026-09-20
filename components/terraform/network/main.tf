# network - VPC peering connection and cross-VPC routes
#
# Resource naming follows the repository convention:
#
#   "${var.name_prefix}-<resource>"   # name_prefix = tenant-account-environment
#
# Scanner suppressions are always inline and always carry an honest reason:
#
#   #checkov:skip=CKV_AWS_123:<honest reason>   # inside the resource block
#   #trivy:ignore:AWS-0123 <honest reason>      # immediately above the block
#
# NEVER add an entry to .checkov.baseline or .trivyignore.yaml to make a scan
# pass. Those baselines exist to burn findings down, and regenerating them to
# turn a PR green hides the finding instead of fixing it. Only write
# "False positive" when the rule genuinely does not apply to this resource -
# if the risk is real but accepted, say so and say why.

locals {
  enabled     = var.enabled
  name_prefix = var.name_prefix
  peering     = local.enabled && var.create_vpc_peering

  # One aws_route per (route table, destination) pair. The stack supplies the
  # route table ids from each VPC's own state output rather than this component
  # discovering them, so check-dependencies.py can see the vpc -> network edge
  # and order the deployment.
  requester_routes = {
    for pair in flatten([
      for route in var.requester_routes : [
        for rtb in route.route_table_ids : {
          key         = "${rtb}/${route.destination_cidr_block}"
          rtb         = rtb
          destination = route.destination_cidr_block
        }
      ]
    ]) : pair.key => pair
  }

  accepter_routes = {
    for pair in flatten([
      for route in var.accepter_routes : [
        for rtb in route.route_table_ids : {
          key         = "${rtb}/${route.destination_cidr_block}"
          rtb         = rtb
          destination = route.destination_cidr_block
        }
      ]
    ]) : pair.key => pair
  }
}

resource "aws_vpc_peering_connection" "this" {
  count = local.peering ? 1 : 0

  vpc_id      = var.requester_vpc_id
  peer_vpc_id = var.accepter_vpc_id

  # Only valid when both VPCs are in the same account and region, which is what
  # this component is built for. Cross-account peering has to be accepted by the
  # peer through aws_vpc_peering_connection_accepter instead.
  auto_accept = var.auto_accept

  tags = {
    Name = "${local.name_prefix}-peering"
  }
}

# Routes go in both directions: a peering connection carries no traffic until
# each side's route tables point the peer's CIDR at it.
resource "aws_route" "requester" {
  for_each = local.peering ? local.requester_routes : {}

  route_table_id            = each.value.rtb
  destination_cidr_block    = each.value.destination
  vpc_peering_connection_id = aws_vpc_peering_connection.this[0].id
}

resource "aws_route" "accepter" {
  for_each = local.peering ? local.accepter_routes : {}

  route_table_id            = each.value.rtb
  destination_cidr_block    = each.value.destination
  vpc_peering_connection_id = aws_vpc_peering_connection.this[0].id
}

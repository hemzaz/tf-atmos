output "name_prefix" {
  description = "Resource name prefix this component builds its resource names from"
  value       = local.name_prefix
}

output "enabled" {
  description = "Whether this component is creating resources"
  value       = local.enabled
}

output "vpc_peering_connection_id" {
  description = "Id of the peering connection, null when peering is disabled"
  value       = one(aws_vpc_peering_connection.this[*].id)
}

output "vpc_peering_accept_status" {
  description = "Accept status of the peering connection, null when peering is disabled"
  value       = one(aws_vpc_peering_connection.this[*].accept_status)
}

output "route_ids" {
  description = "Ids of the routes created on each side of the peering connection"
  value = {
    requester = [for r in aws_route.requester : r.id]
    accepter  = [for r in aws_route.accepter : r.id]
  }
}

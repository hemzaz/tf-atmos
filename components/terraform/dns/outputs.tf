output "zone_ids" {
  description = "Map of zone names to their IDs"
  value = merge(
    var.create_root_zone ? { "${var.root_domain}" = aws_route53_zone.root_zone[0].zone_id } : {},
    { for k, zone in aws_route53_zone.zones : k => zone.zone_id }
  )
}

output "zone_name_servers" {
  description = "Map of zone names to their name servers"
  value = merge(
    var.create_root_zone ? { "${var.root_domain}" = aws_route53_zone.root_zone[0].name_servers } : {},
    { for k, zone in aws_route53_zone.zones : k => zone.name_servers }
  )
}

output "delegation_set_name_servers" {
  description = "Map of delegation set IDs to their name servers"
  value = {
    for k, ds in aws_route53_delegation_set.delegation_sets : k => ds.name_servers
  }
}

output "records" {
  description = "Map of created record IDs to their attributes"
  value = {
    for k, record in aws_route53_record.records : k => {
      name    = record.name
      type    = record.type
      zone_id = record.zone_id
      fqdn    = record.fqdn
    }
  }
}

output "health_check_ids" {
  description = "Map of health check names to their IDs"
  value = {
    for k, hc in aws_route53_health_check.health_checks : k => hc.id
  }
}

output "traffic_policy_ids" {
  description = "Map of traffic policy names to their IDs"
  value = {
    for k, policy in aws_route53_traffic_policy.traffic_policies : k => policy.id
  }
}

output "root_domain" {
  description = "The root domain used for DNS configuration"
  value       = var.root_domain
}

output "domain_validation_options" {
  description = "Domain validation options for certificates if ACM is integrated"
  value = {
    for k, zone in aws_route53_zone.zones : k => {
      zone_id = zone.zone_id
      name    = zone.name
    }
  }
}

output "private_zone_vpc_associations" {
  description = "Map of private zone VPC associations"
  value = {
    for k, assoc in aws_route53_zone_association.vpc_associations : k => {
      vpc_id  = assoc.vpc_id
      zone_id = assoc.zone_id
    }
  }
}
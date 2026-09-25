output "group_name" {
  description = "The IngressGroup name (alb.ingress.kubernetes.io/group.name)"
  value       = local.enabled ? var.group_name : null
}

output "ingress_name" {
  description = "Name of the kubernetes_ingress_v1 IngressGroup scaffold"
  value       = local.enabled ? kubernetes_ingress_v1.this[0].metadata[0].name : null
}

output "security_group_id" {
  description = "ID of the ALB's frontend security group"
  value       = local.enabled ? aws_security_group.alb[0].id : null
}

output "load_balancer_arn" {
  description = "ARN of the ALB the controller created for this IngressGroup"
  value       = local.enabled ? data.aws_lb.this[0].arn : null
}

output "load_balancer_dns_name" {
  description = "DNS name of the ALB the controller created for this IngressGroup"
  value       = local.enabled ? data.aws_lb.this[0].dns_name : null
}

output "load_balancer_zone_id" {
  description = "Route53 hosted zone ID of the ALB, for an alias record"
  value       = local.enabled ? data.aws_lb.this[0].zone_id : null
}

output "http_listener_arn" {
  description = "ARN of the ALB's HTTP (80) listener"
  value       = local.enabled ? data.aws_lb_listener.http[0].arn : null
}

output "https_listener_arn" {
  description = "ARN of the ALB's HTTPS (443) listener; null unless certificate_arn is set"
  value       = local.tls_enabled ? data.aws_lb_listener.https[0].arn : null
}

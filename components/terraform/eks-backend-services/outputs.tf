# EKS Backend Services Outputs

output "namespace" {
  description = "The namespace where backend services are deployed"
  value       = kubernetes_namespace.backend_services.metadata[0].name
}

output "service_endpoints" {
  description = "Service endpoints for backend services"
  value = {
    for service_name, service in kubernetes_service.backend_services : service_name => {
      name         = service.metadata[0].name
      namespace    = service.metadata[0].namespace
      cluster_ip   = service.spec[0].cluster_ip
      ports        = service.spec[0].port
      service_url  = "http://${service.metadata[0].name}.${service.metadata[0].namespace}.svc.cluster.local:${service.spec[0].port[0].port}"
      metrics_url  = "http://${service.metadata[0].name}.${service.metadata[0].namespace}.svc.cluster.local:${service.spec[0].port[1].port}/metrics"
    }
  }
}

output "deployment_status" {
  description = "Deployment status for backend services"
  value = {
    for service_name, deployment in kubernetes_deployment.backend_services : service_name => {
      name                = deployment.metadata[0].name
      namespace          = deployment.metadata[0].namespace
      replicas           = deployment.spec[0].replicas
      ready_replicas     = deployment.status[0].ready_replicas
      updated_replicas   = deployment.status[0].updated_replicas
      available_replicas = deployment.status[0].available_replicas
    }
  }
}

output "hpa_status" {
  description = "Horizontal Pod Autoscaler status for backend services"
  value = {
    for service_name, hpa in kubernetes_horizontal_pod_autoscaler_v2.backend_services : service_name => {
      name             = hpa.metadata[0].name
      namespace        = hpa.metadata[0].namespace
      min_replicas     = hpa.spec[0].min_replicas
      max_replicas     = hpa.spec[0].max_replicas
      current_replicas = hpa.status[0].current_replicas
      desired_replicas = hpa.status[0].desired_replicas
    }
  }
}

output "pod_disruption_budgets" {
  description = "Pod Disruption Budget configurations"
  value = {
    for service_name, pdb in kubernetes_pod_disruption_budget_v1.backend_services : service_name => {
      name          = pdb.metadata[0].name
      namespace     = pdb.metadata[0].namespace
      min_available = pdb.spec[0].min_available
    }
  }
}

output "service_accounts" {
  description = "Service account information"
  value = {
    for service_name, sa in kubernetes_service_account.backend_services : service_name => {
      name        = sa.metadata[0].name
      namespace   = sa.metadata[0].namespace
      annotations = sa.metadata[0].annotations
    }
  }
}

output "secrets" {
  description = "Secret names (not values) for reference"
  value = {
    database_secret = kubernetes_secret.database_credentials.metadata[0].name
    redis_secret    = kubernetes_secret.redis_credentials.metadata[0].name
  }
  sensitive = true
}

output "config_maps" {
  description = "ConfigMap information"
  value = {
    for service_name, cm in kubernetes_config_map.backend_services_config : service_name => {
      name      = cm.metadata[0].name
      namespace = cm.metadata[0].namespace
    }
  }
}

output "network_policy" {
  description = "Network policy information"
  value = {
    name      = kubernetes_network_policy.backend_services_network_policy.metadata[0].name
    namespace = kubernetes_network_policy.backend_services_network_policy.metadata[0].namespace
  }
}

output "service_urls" {
  description = "Internal service URLs for inter-service communication"
  value = {
    for service_name, service_config in local.backend_services : service_name => {
      internal_url = "http://${service_name}.${kubernetes_namespace.backend_services.metadata[0].name}.svc.cluster.local:${service_config.port}"
      health_url   = "http://${service_name}.${kubernetes_namespace.backend_services.metadata[0].name}.svc.cluster.local:${service_config.port}${service_config.health_check}"
      metrics_url  = "http://${service_name}.${kubernetes_namespace.backend_services.metadata[0].name}.svc.cluster.local:${service_config.metrics_port}/metrics"
    }
  }
}

output "prometheus_service_monitors" {
  description = "Prometheus ServiceMonitor resources"
  value = var.enable_prometheus_monitoring ? {
    for service_name, _ in local.backend_services : service_name => {
      name      = service_name
      namespace = kubernetes_namespace.backend_services.metadata[0].name
      enabled   = true
    }
  } : {}
}

output "resource_quotas" {
  description = "Resource usage and limits for backend services"
  value = {
    total_cpu_requests = sum([
      for service_name, config in local.backend_services : 
      tonumber(replace(replace(config.cpu_request, "m", ""), "Mi", "")) * config.replicas_min
    ])
    total_memory_requests = sum([
      for service_name, config in local.backend_services : 
      tonumber(replace(replace(config.mem_request, "Mi", ""), "Gi", "")) * config.replicas_min
    ])
    total_cpu_limits = sum([
      for service_name, config in local.backend_services : 
      tonumber(replace(replace(config.cpu_limit, "m", ""), "Mi", "")) * config.replicas_max
    ])
    total_memory_limits = sum([
      for service_name, config in local.backend_services : 
      tonumber(replace(replace(config.mem_limit, "Mi", ""), "Gi", "")) * config.replicas_max
    ])
  }
}

output "scaling_recommendations" {
  description = "Scaling recommendations based on environment"
  value = {
    environment = var.tags["Environment"]
    recommendations = {
      for service_name, config in local.backend_services : service_name => {
        current_min_replicas     = config.replicas_min
        current_max_replicas     = config.replicas_max
        recommended_min_replicas = var.tags["Environment"] == "prod" ? max(2, config.replicas_min) : 1
        recommended_max_replicas = var.tags["Environment"] == "prod" ? config.replicas_max * 2 : config.replicas_max
        cpu_request             = config.cpu_request
        memory_request          = config.mem_request
        cpu_limit              = config.cpu_limit
        memory_limit           = config.mem_limit
      }
    }
  }
}
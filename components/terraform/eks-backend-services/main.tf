# EKS Backend Services Architecture Optimization
# This component manages backend services running on EKS for the IDP platform

locals {
  name_prefix = "${var.tags["Environment"]}-backend-services"
  
  # Service configurations with resource requirements and scaling policies
  backend_services = {
    # API Gateway microservice
    api_gateway = {
      image        = var.api_gateway_image
      port         = 8080
      replicas_min = var.environment == "prod" ? 3 : 2
      replicas_max = var.environment == "prod" ? 10 : 5
      cpu_request  = "200m"
      cpu_limit    = "500m"
      mem_request  = "256Mi"
      mem_limit    = "512Mi"
      health_check = "/health"
      metrics_port = 9090
      node_selector = {
        "workload-type" = "platform-services"
      }
      tolerations = [{
        key    = "platform-services"
        value  = "true"
        effect = "NoSchedule"
      }]
    }
    
    # Platform API service
    platform_api = {
      image        = var.platform_api_image
      port         = 8081
      replicas_min = var.environment == "prod" ? 3 : 2
      replicas_max = var.environment == "prod" ? 8 : 4
      cpu_request  = "300m"
      cpu_limit    = "800m"
      mem_request  = "512Mi"
      mem_limit    = "1Gi"
      health_check = "/api/health"
      metrics_port = 9091
      node_selector = {
        "workload-type" = "platform-services"
      }
      tolerations = [{
        key    = "platform-services"
        value  = "true"
        effect = "NoSchedule"
      }]
    }
    
    # Authentication service
    auth_service = {
      image        = var.auth_service_image
      port         = 8082
      replicas_min = var.environment == "prod" ? 2 : 1
      replicas_max = var.environment == "prod" ? 6 : 3
      cpu_request  = "150m"
      cpu_limit    = "400m"
      mem_request  = "256Mi"
      mem_limit    = "512Mi"
      health_check = "/auth/health"
      metrics_port = 9092
      node_selector = {
        "workload-type" = "platform-services"
      }
      tolerations = [{
        key    = "platform-services"
        value  = "true"
        effect = "NoSchedule"
      }]
    }
    
    # Background job processor
    job_processor = {
      image        = var.job_processor_image
      port         = 8083
      replicas_min = var.environment == "prod" ? 2 : 1
      replicas_max = var.environment == "prod" ? 8 : 4
      cpu_request  = "200m"
      cpu_limit    = "1000m"
      mem_request  = "512Mi"
      mem_limit    = "2Gi"
      health_check = "/jobs/health"
      metrics_port = 9093
      node_selector = {
        "workload-type" = "user-workloads"
      }
    }
  }
  
  # Common environment variables for all services
  common_env_vars = [
    {
      name  = "ENVIRONMENT"
      value = var.tags["Environment"]
    },
    {
      name  = "LOG_LEVEL"
      value = var.log_level
    },
    {
      name  = "METRICS_ENABLED"
      value = "true"
    },
    {
      name  = "TRACING_ENABLED"
      value = var.enable_tracing ? "true" : "false"
    },
    {
      name = "DATABASE_URL"
      value_from = {
        secret_key_ref = {
          name = kubernetes_secret.database_credentials.metadata[0].name
          key  = "database_url"
        }
      }
    },
    {
      name = "REDIS_URL"
      value_from = {
        secret_key_ref = {
          name = kubernetes_secret.redis_credentials.metadata[0].name
          key  = "redis_url"
        }
      }
    }
  ]
}

# Namespace for backend services
resource "kubernetes_namespace" "backend_services" {
  metadata {
    name = "backend-services"
    
    labels = {
      "name"                          = "backend-services"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
    
    annotations = {
      "managed-by" = "terraform"
    }
  }
}

# Network policies for service isolation
resource "kubernetes_network_policy" "backend_services_network_policy" {
  metadata {
    name      = "backend-services-network-policy"
    namespace = kubernetes_namespace.backend_services.metadata[0].name
  }

  spec {
    pod_selector {}
    
    policy_types = ["Ingress", "Egress"]
    
    # Allow ingress from istio-gateway
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "istio-system"
          }
        }
      }
      
      # Allow inter-service communication
      from {
        namespace_selector {
          match_labels = {
            name = "backend-services"
          }
        }
      }
      
      ports {
        port     = "8080"
        protocol = "TCP"
      }
      ports {
        port     = "8081"
        protocol = "TCP"
      }
      ports {
        port     = "8082"
        protocol = "TCP"
      }
      ports {
        port     = "8083"
        protocol = "TCP"
      }
    }
    
    # Allow egress to databases and external APIs
    egress {
      # Database access
      to {}
      ports {
        port     = "5432"
        protocol = "TCP"
      }
      ports {
        port     = "6379"
        protocol = "TCP"
      }
    }
    
    # Allow egress to internet for external API calls
    egress {
      to {}
      ports {
        port     = "443"
        protocol = "TCP"
      }
      ports {
        port     = "80"
        protocol = "TCP"
      }
    }
    
    # Allow DNS resolution
    egress {
      to {}
      ports {
        port     = "53"
        protocol = "UDP"
      }
    }
  }
}

# Service accounts for each backend service
resource "kubernetes_service_account" "backend_services" {
  for_each = local.backend_services
  
  metadata {
    name      = "${each.key}-service-account"
    namespace = kubernetes_namespace.backend_services.metadata[0].name
    
    annotations = var.service_account_annotations
  }
  
  automount_service_account_token = true
}

# Secrets management
resource "kubernetes_secret" "database_credentials" {
  metadata {
    name      = "database-credentials"
    namespace = kubernetes_namespace.backend_services.metadata[0].name
  }
  
  type = "Opaque"
  
  data = {
    database_url = var.database_url
    username     = var.database_username
    password     = var.database_password
  }
}

resource "kubernetes_secret" "redis_credentials" {
  metadata {
    name      = "redis-credentials"
    namespace = kubernetes_namespace.backend_services.metadata[0].name
  }
  
  type = "Opaque"
  
  data = {
    redis_url = var.redis_url
    password  = var.redis_password
  }
}

# ConfigMaps for service configuration
resource "kubernetes_config_map" "backend_services_config" {
  for_each = local.backend_services
  
  metadata {
    name      = "${each.key}-config"
    namespace = kubernetes_namespace.backend_services.metadata[0].name
  }
  
  data = merge(var.service_configs[each.key], {
    "service_name" = each.key
    "namespace"    = kubernetes_namespace.backend_services.metadata[0].name
  })
}

# Deployments for backend services
resource "kubernetes_deployment" "backend_services" {
  for_each = local.backend_services
  
  metadata {
    name      = each.key
    namespace = kubernetes_namespace.backend_services.metadata[0].name
    
    labels = {
      app     = each.key
      version = var.service_versions[each.key]
    }
  }
  
  spec {
    replicas = each.value.replicas_min
    
    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "25%"
        max_unavailable = "25%"
      }
    }
    
    selector {
      match_labels = {
        app = each.key
      }
    }
    
    template {
      metadata {
        labels = {
          app     = each.key
          version = var.service_versions[each.key]
        }
        
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = tostring(each.value.metrics_port)
          "prometheus.io/path"   = "/metrics"
        }
      }
      
      spec {
        service_account_name = kubernetes_service_account.backend_services[each.key].metadata[0].name
        
        # Security context
        security_context {
          run_as_non_root        = true
          run_as_user           = 1000
          run_as_group          = 3000
          fs_group              = 2000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        
        # Node selection and tolerations
        dynamic "toleration" {
          for_each = lookup(each.value, "tolerations", [])
          content {
            key      = toleration.value.key
            operator = "Equal"
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }
        
        node_selector = lookup(each.value, "node_selector", {})
        
        # Pod anti-affinity for high availability
        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app"
                    operator = "In"
                    values   = [each.key]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }
        
        # Init container for database migrations (if needed)
        dynamic "init_container" {
          for_each = var.enable_database_migrations && contains(["api_gateway", "platform_api"], each.key) ? [1] : []
          content {
            name  = "db-migrate"
            image = each.value.image
            
            command = ["/bin/sh", "-c"]
            args    = ["echo 'Running database migrations...' && migrate -path /migrations -database $DATABASE_URL up"]
            
            env_from {
              secret_ref {
                name = kubernetes_secret.database_credentials.metadata[0].name
              }
            }
            
            security_context {
              allow_privilege_escalation = false
              run_as_non_root           = true
              run_as_user              = 1000
              capabilities {
                drop = ["ALL"]
              }
            }
          }
        }
        
        # Main container
        container {
          name  = each.key
          image = each.value.image
          
          image_pull_policy = "IfNotPresent"
          
          port {
            name           = "http"
            container_port = each.value.port
            protocol       = "TCP"
          }
          
          port {
            name           = "metrics"
            container_port = each.value.metrics_port
            protocol       = "TCP"
          }
          
          # Resource requirements
          resources {
            requests = {
              cpu    = each.value.cpu_request
              memory = each.value.mem_request
            }
            limits = {
              cpu    = each.value.cpu_limit
              memory = each.value.mem_limit
            }
          }
          
          # Environment variables
          dynamic "env" {
            for_each = local.common_env_vars
            content {
              name = env.value.name
              
              dynamic "value" {
                for_each = lookup(env.value, "value", null) != null ? [env.value.value] : []
                content {
                  value = value.value
                }
              }
              
              dynamic "value_from" {
                for_each = lookup(env.value, "value_from", null) != null ? [env.value.value_from] : []
                content {
                  dynamic "secret_key_ref" {
                    for_each = lookup(value_from.value, "secret_key_ref", null) != null ? [value_from.value.secret_key_ref] : []
                    content {
                      name = secret_key_ref.value.name
                      key  = secret_key_ref.value.key
                    }
                  }
                }
              }
            }
          }
          
          # Configuration from ConfigMap
          env_from {
            config_map_ref {
              name = kubernetes_config_map.backend_services_config[each.key].metadata[0].name
            }
          }
          
          # Health checks
          liveness_probe {
            http_get {
              path = each.value.health_check
              port = each.value.port
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }
          
          readiness_probe {
            http_get {
              path = each.value.health_check
              port = each.value.port
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }
          
          # Startup probe for slower starting services
          startup_probe {
            http_get {
              path = each.value.health_check
              port = each.value.port
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 30
          }
          
          # Security context
          security_context {
            allow_privilege_escalation = false
            run_as_non_root           = true
            run_as_user              = 1000
            capabilities {
              drop = ["ALL"]
            }
          }
          
          # Volume mounts for temporary storage
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }
        
        # Volumes
        volume {
          name = "tmp"
          empty_dir {
            size_limit = "1Gi"
          }
        }
        
        # Image pull secrets if needed
        dynamic "image_pull_secrets" {
          for_each = var.image_pull_secrets
          content {
            name = image_pull_secrets.value
          }
        }
      }
    }
  }
  
  depends_on = [
    kubernetes_secret.database_credentials,
    kubernetes_secret.redis_credentials,
    kubernetes_config_map.backend_services_config
  ]
}

# Services for backend services
resource "kubernetes_service" "backend_services" {
  for_each = local.backend_services
  
  metadata {
    name      = each.key
    namespace = kubernetes_namespace.backend_services.metadata[0].name
    
    labels = {
      app = each.key
    }
    
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = tostring(each.value.metrics_port)
    }
  }
  
  spec {
    selector = {
      app = each.key
    }
    
    port {
      name        = "http"
      port        = each.value.port
      target_port = each.value.port
      protocol    = "TCP"
    }
    
    port {
      name        = "metrics"
      port        = each.value.metrics_port
      target_port = each.value.metrics_port
      protocol    = "TCP"
    }
    
    type = "ClusterIP"
  }
}

# Horizontal Pod Autoscalers
resource "kubernetes_horizontal_pod_autoscaler_v2" "backend_services" {
  for_each = local.backend_services
  
  metadata {
    name      = each.key
    namespace = kubernetes_namespace.backend_services.metadata[0].name
  }
  
  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = each.key
    }
    
    min_replicas = each.value.replicas_min
    max_replicas = each.value.replicas_max
    
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.cpu_target_utilization
        }
      }
    }
    
    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = var.memory_target_utilization
        }
      }
    }
    
    # Scale down behavior
    behavior {
      scale_down {
        stabilization_window_seconds = 300
        policy {
          type  = "Percent"
          value = 25
          period_seconds = 60
        }
      }
      
      scale_up {
        stabilization_window_seconds = 0
        policy {
          type  = "Percent"
          value = 50
          period_seconds = 60
        }
      }
    }
  }
  
  depends_on = [kubernetes_deployment.backend_services]
}

# Pod Disruption Budgets
resource "kubernetes_pod_disruption_budget_v1" "backend_services" {
  for_each = local.backend_services
  
  metadata {
    name      = each.key
    namespace = kubernetes_namespace.backend_services.metadata[0].name
  }
  
  spec {
    min_available = max(1, floor(each.value.replicas_min * 0.5))
    
    selector {
      match_labels = {
        app = each.key
      }
    }
  }
}

# ServiceMonitor for Prometheus scraping
resource "kubernetes_manifest" "service_monitor" {
  for_each = var.enable_prometheus_monitoring ? local.backend_services : {}
  
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = each.key
      namespace = kubernetes_namespace.backend_services.metadata[0].name
      labels = {
        app = each.key
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = each.key
        }
      }
      endpoints = [
        {
          port     = "metrics"
          interval = "30s"
          path     = "/metrics"
        }
      ]
    }
  }
}
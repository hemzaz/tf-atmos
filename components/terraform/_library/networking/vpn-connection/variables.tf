variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "customer_gateway_bgp_asn" {
  description = "BGP ASN of the customer gateway"
  type        = number
  default     = 65000

  validation {
    condition     = var.customer_gateway_bgp_asn >= 1 && var.customer_gateway_bgp_asn <= 2147483647
    error_message = "Customer gateway BGP ASN must be between 1 and 2147483647."
  }
}

variable "customer_gateway_ip_address" {
  description = "Public IP address of the customer gateway"
  type        = string
}

variable "use_transit_gateway" {
  description = "Use Transit Gateway instead of Virtual Private Gateway"
  type        = bool
  default     = false
}

variable "transit_gateway_id" {
  description = "ID of Transit Gateway (required if use_transit_gateway is true)"
  type        = string
  default     = null

  validation {
    condition     = !var.use_transit_gateway || var.transit_gateway_id != null
    error_message = "transit_gateway_id is required when use_transit_gateway is true."
  }
}

variable "vpc_id" {
  description = "VPC ID (required if use_transit_gateway is false)"
  type        = string
  default     = null

  validation {
    condition     = var.use_transit_gateway || var.vpc_id != null
    error_message = "vpc_id is required when use_transit_gateway is false."
  }
}

variable "vpn_gateway_amazon_side_asn" {
  description = "ASN for Amazon side of VPN gateway (for VGW mode)"
  type        = number
  default     = 64512

  validation {
    condition     = (var.vpn_gateway_amazon_side_asn >= 64512 && var.vpn_gateway_amazon_side_asn <= 65534) || (var.vpn_gateway_amazon_side_asn >= 4200000000 && var.vpn_gateway_amazon_side_asn <= 4294967294)
    error_message = "Amazon side ASN must be in range 64512-65534 or 4200000000-4294967294."
  }
}

variable "static_routes_only" {
  description = "Use static routing instead of BGP"
  type        = bool
  default     = false
}

variable "static_routes" {
  description = "Map of static routes (if static_routes_only is true)"
  type        = map(string)
  default     = {}
}

variable "route_table_ids" {
  description = "Map of route table IDs for route propagation (VGW mode only)"
  type        = map(string)
  default     = {}
}

# Tunnel 1 Configuration
variable "tunnel1_inside_cidr" {
  description = "Inside CIDR for tunnel 1 (169.254.x.x/30)"
  type        = string
  default     = null

  validation {
    condition     = var.tunnel1_inside_cidr == null || can(regex("^169\\.254\\.[0-9]{1,3}\\.[0-9]{1,3}/30$", var.tunnel1_inside_cidr))
    error_message = "Tunnel inside CIDR must be a /30 within 169.254.0.0/16."
  }
}

variable "tunnel1_preshared_key" {
  description = "Pre-shared key for tunnel 1"
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.tunnel1_preshared_key == null || can(regex("^[A-Za-z1-9._][A-Za-z0-9._]{7,63}$", var.tunnel1_preshared_key))
    error_message = "Pre-shared key must be 8-64 chars of letters, digits, periods and underscores, and must not start with zero."
  }
}

variable "tunnel1_dpd_timeout_action" {
  description = "DPD timeout action for tunnel 1 (clear, none, restart)"
  type        = string
  default     = "clear"

  validation {
    condition     = contains(["clear", "none", "restart"], var.tunnel1_dpd_timeout_action)
    error_message = "DPD timeout action must be clear, none, or restart."
  }
}

variable "tunnel1_ike_versions" {
  description = "IKE versions for tunnel 1"
  type        = list(string)
  default     = ["ikev2"]

  validation {
    condition     = alltrue([for v in var.tunnel1_ike_versions : contains(["ikev1", "ikev2"], v)])
    error_message = "IKE versions must be ikev1 and/or ikev2."
  }
}

variable "tunnel1_phase1_dh_group_numbers" {
  description = "Diffie-Hellman group numbers for Phase 1 IKE negotiations (tunnel 1)"
  type        = list(number)
  default     = [14, 15, 16, 17, 18, 19, 20, 21]
}

variable "tunnel1_phase1_encryption_algorithms" {
  description = "Encryption algorithms for Phase 1 IKE negotiations (tunnel 1)"
  type        = list(string)
  default     = ["AES256", "AES128"]
}

variable "tunnel1_phase1_integrity_algorithms" {
  description = "Integrity algorithms for Phase 1 IKE negotiations (tunnel 1)"
  type        = list(string)
  default     = ["SHA2-256", "SHA2-384", "SHA2-512"]
}

variable "tunnel1_phase1_lifetime_seconds" {
  description = "Lifetime for Phase 1 IKE negotiations in seconds (tunnel 1)"
  type        = number
  default     = 28800
}

variable "tunnel1_phase2_dh_group_numbers" {
  description = "Diffie-Hellman group numbers for Phase 2 IKE negotiations (tunnel 1)"
  type        = list(number)
  default     = [14, 15, 16, 17, 18, 19, 20, 21]
}

variable "tunnel1_phase2_encryption_algorithms" {
  description = "Encryption algorithms for Phase 2 IKE negotiations (tunnel 1)"
  type        = list(string)
  default     = ["AES256", "AES128"]
}

variable "tunnel1_phase2_integrity_algorithms" {
  description = "Integrity algorithms for Phase 2 IKE negotiations (tunnel 1)"
  type        = list(string)
  default     = ["SHA2-256", "SHA2-384", "SHA2-512"]
}

variable "tunnel1_phase2_lifetime_seconds" {
  description = "Lifetime for Phase 2 IKE negotiations in seconds (tunnel 1)"
  type        = number
  default     = 3600
}

variable "tunnel1_startup_action" {
  description = "Startup action for tunnel 1 (add, start)"
  type        = string
  default     = "add"

  validation {
    condition     = contains(["add", "start"], var.tunnel1_startup_action)
    error_message = "Startup action must be add or start."
  }
}

# Tunnel 2 Configuration
variable "tunnel2_inside_cidr" {
  description = "Inside CIDR for tunnel 2 (169.254.x.x/30)"
  type        = string
  default     = null

  validation {
    condition     = var.tunnel2_inside_cidr == null || can(regex("^169\\.254\\.[0-9]{1,3}\\.[0-9]{1,3}/30$", var.tunnel2_inside_cidr))
    error_message = "Tunnel inside CIDR must be a /30 within 169.254.0.0/16."
  }
}

variable "tunnel2_preshared_key" {
  description = "Pre-shared key for tunnel 2"
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.tunnel2_preshared_key == null || can(regex("^[A-Za-z1-9._][A-Za-z0-9._]{7,63}$", var.tunnel2_preshared_key))
    error_message = "Pre-shared key must be 8-64 chars of letters, digits, periods and underscores, and must not start with zero."
  }
}

variable "tunnel2_dpd_timeout_action" {
  description = "DPD timeout action for tunnel 2 (clear, none, restart)"
  type        = string
  default     = "clear"

  validation {
    condition     = contains(["clear", "none", "restart"], var.tunnel2_dpd_timeout_action)
    error_message = "DPD timeout action must be clear, none, or restart."
  }
}

variable "tunnel2_ike_versions" {
  description = "IKE versions for tunnel 2"
  type        = list(string)
  default     = ["ikev2"]

  validation {
    condition     = alltrue([for v in var.tunnel2_ike_versions : contains(["ikev1", "ikev2"], v)])
    error_message = "IKE versions must be ikev1 and/or ikev2."
  }
}

variable "tunnel2_phase1_dh_group_numbers" {
  description = "Diffie-Hellman group numbers for Phase 1 IKE negotiations (tunnel 2)"
  type        = list(number)
  default     = [14, 15, 16, 17, 18, 19, 20, 21]
}

variable "tunnel2_phase1_encryption_algorithms" {
  description = "Encryption algorithms for Phase 1 IKE negotiations (tunnel 2)"
  type        = list(string)
  default     = ["AES256", "AES128"]
}

variable "tunnel2_phase1_integrity_algorithms" {
  description = "Integrity algorithms for Phase 1 IKE negotiations (tunnel 2)"
  type        = list(string)
  default     = ["SHA2-256", "SHA2-384", "SHA2-512"]
}

variable "tunnel2_phase1_lifetime_seconds" {
  description = "Lifetime for Phase 1 IKE negotiations in seconds (tunnel 2)"
  type        = number
  default     = 28800
}

variable "tunnel2_phase2_dh_group_numbers" {
  description = "Diffie-Hellman group numbers for Phase 2 IKE negotiations (tunnel 2)"
  type        = list(number)
  default     = [14, 15, 16, 17, 18, 19, 20, 21]
}

variable "tunnel2_phase2_encryption_algorithms" {
  description = "Encryption algorithms for Phase 2 IKE negotiations (tunnel 2)"
  type        = list(string)
  default     = ["AES256", "AES128"]
}

variable "tunnel2_phase2_integrity_algorithms" {
  description = "Integrity algorithms for Phase 2 IKE negotiations (tunnel 2)"
  type        = list(string)
  default     = ["SHA2-256", "SHA2-384", "SHA2-512"]
}

variable "tunnel2_phase2_lifetime_seconds" {
  description = "Lifetime for Phase 2 IKE negotiations in seconds (tunnel 2)"
  type        = number
  default     = 3600
}

variable "tunnel2_startup_action" {
  description = "Startup action for tunnel 2 (add, start)"
  type        = string
  default     = "add"

  validation {
    condition     = contains(["add", "start"], var.tunnel2_startup_action)
    error_message = "Startup action must be add or start."
  }
}

# Monitoring
variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for VPN tunnels"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for VPN monitoring"
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arns" {
  description = "List of SNS topic ARNs for alarm notifications"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

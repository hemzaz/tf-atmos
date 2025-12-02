variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
  default     = "example-multiregion"
}

variable "cloudfront_distribution_arns" {
  type        = list(string)
  description = "CloudFront distribution ARNs to protect"
  default     = []
}

variable "us_east_1_resource_arns" {
  type        = list(string)
  description = "US East 1 resource ARNs (ALB, API Gateway, etc.)"
  default     = []
}

variable "us_west_2_resource_arns" {
  type        = list(string)
  description = "US West 2 resource ARNs (ALB, API Gateway, etc.)"
  default     = []
}

variable "eu_west_1_resource_arns" {
  type        = list(string)
  description = "EU West 1 resource ARNs (ALB, API Gateway, etc.)"
  default     = []
}

variable "enable_geo_blocking_eu" {
  type        = bool
  description = "Enable geo-blocking for EU region (allow-list mode)"
  default     = false
}

variable "eu_allowed_countries" {
  type        = list(string)
  description = "Countries allowed to access EU resources (ISO 3166-1 alpha-2)"
  default = [
    "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR",
    "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL",
    "PL", "PT", "RO", "SK", "SI", "ES", "SE", "GB", "US", "CA"
  ]
}

variable "tags" {
  type        = map(string)
  description = "Common tags for all resources"
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
    Example     = "multi-region"
  }
}

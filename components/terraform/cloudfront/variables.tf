variable "region" {
  type        = string
  description = "AWS region of the stack. The distribution is global; its logging v2 delivery resources are always created in us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources; must include Environment (used in resource names)"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

variable "enabled" {
  type        = bool
  description = "Set to false to prevent the component from creating any resources"
  default     = true
}

variable "name" {
  type        = string
  description = "Short name. The distribution's comment and origin access control are named <Environment>-<name> (64 characters at most)"

  validation {
    # No periods: the logging v2 delivery source/destination names allow only [A-Za-z0-9_-].
    condition     = can(regex("^[a-zA-Z0-9_-]{1,40}$", var.name))
    error_message = "name must be 1-40 characters of letters, digits, underscore or hyphen."
  }
}

# Origin. Cloud Posse's origin_bucket is a bucket name; this is the s3
# component's bucket_regional_domain_name output, from which the bucket name
# is derived.
variable "origin_bucket_regional_domain_name" {
  type        = string
  description = "Regional domain name of the origin bucket (<bucket>.s3.<region>.amazonaws.com; the s3 component's bucket_regional_domain_name). The component does not own the bucket: merge s3_origin_policy_json into its policy"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]\\.s3\\.[a-z0-9-]+\\.amazonaws\\.com$", var.origin_bucket_regional_domain_name))
    error_message = "origin_bucket_regional_domain_name must be an S3 bucket regional domain name (<bucket>.s3.<region>.amazonaws.com), not a bucket name, an ARN or a website endpoint."
  }
}

variable "origin_path" {
  type        = string
  description = "Path in the bucket CloudFront requests objects from (Cloud Posse's origin_path): empty, or /<path> without a trailing slash"
  default     = ""
  nullable    = false

  validation {
    condition     = var.origin_path == "" || can(regex("^/[^*?]*[^/]$", var.origin_path))
    error_message = "origin_path must be empty or start with / and not end with /."
  }
}

# Distribution.
variable "distribution_enabled" {
  type        = bool
  description = "Whether the distribution accepts requests (Cloud Posse's distribution_enabled)"
  default     = true
}

variable "comment" {
  type        = string
  description = "Distribution comment; null uses <Environment>-<name>"
  default     = null

  validation {
    condition     = var.comment == null || try(length(var.comment) <= 128, false)
    error_message = "comment must be 128 characters or fewer."
  }
}

variable "default_root_object" {
  type        = string
  description = "Object returned for the root URL, and the page the SPA fallback serves (Cloud Posse default: index.html)"
  default     = "index.html"

  validation {
    condition     = can(regex("^[^/][^\\s]*$", var.default_root_object))
    error_message = "default_root_object must be an object key without a leading slash or spaces (e.g. index.html)."
  }
}

variable "price_class" {
  type        = string
  description = "PriceClass_100 (Cloud Posse's default: North America, Europe, Israel), PriceClass_200 or PriceClass_All"
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "http_version" {
  type        = string
  description = "Highest HTTP version viewers can use: http1.1, http2, http2and3 (default; Cloud Posse: http2) or http3"
  default     = "http2and3"

  validation {
    condition     = contains(["http1.1", "http2", "http2and3", "http3"], var.http_version)
    error_message = "http_version must be http1.1, http2, http2and3 or http3."
  }
}

variable "ipv6_enabled" {
  type        = bool
  description = "Serve over IPv6 too; with dns_alias_enabled, an AAAA record is created next to each A record"
  default     = true
}

variable "wait_for_deployment" {
  type        = bool
  description = "Wait for the distribution to reach Deployed on create and update (Cloud Posse's wait_for_deployment)"
  default     = true
}

# TLS. The ACM certificate must be in us-east-1 whatever the stack's region.
variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate ARN for the aliases, in us-east-1 (the acm component's certificate_arns.<key> in a us-east-1 stack). Null serves only the *.cloudfront.net name with CloudFront's certificate"
  default     = null

  validation {
    condition     = var.acm_certificate_arn == null || can(regex("^arn:aws[a-z-]*:acm:us-east-1:[0-9]{12}:certificate/[0-9a-f-]+$", var.acm_certificate_arn))
    error_message = "acm_certificate_arn must be an ACM certificate ARN in us-east-1 (arn:aws:acm:us-east-1:<account>:certificate/<id>): CloudFront only uses us-east-1 certificates."
  }
}

variable "aliases" {
  type        = list(string)
  description = "Alternate domain names (CNAMEs) served by the distribution (Cloud Posse's aliases). Requires acm_certificate_arn covering them"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.aliases : can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", a))])
    error_message = "Each alias must be a lowercase fully qualified domain name (optionally *.<domain>), without a trailing dot."
  }

  validation {
    condition     = length(var.aliases) == 0 || var.acm_certificate_arn != null
    error_message = "aliases need acm_certificate_arn: CloudFront's default certificate only covers *.cloudfront.net."
  }

  validation {
    condition     = length(distinct(var.aliases)) == length(var.aliases)
    error_message = "aliases must be unique."
  }
}

variable "minimum_protocol_version" {
  type        = string
  description = "Minimum TLS security policy for viewers when acm_certificate_arn is set: TLSv1.2_2021 (default), TLSv1.2_2018, TLSv1.2_2019, TLSv1.2_2025 or TLSv1.3_2025. Older policies (TLSv1, TLSv1_2016, TLSv1.1_2016) are rejected. Ignored with CloudFront's default certificate"
  default     = "TLSv1.2_2021"

  validation {
    condition     = contains(["TLSv1.2_2018", "TLSv1.2_2019", "TLSv1.2_2021", "TLSv1.2_2025", "TLSv1.3_2025"], var.minimum_protocol_version)
    error_message = "minimum_protocol_version must be TLSv1.2_2018, TLSv1.2_2019, TLSv1.2_2021, TLSv1.2_2025 or TLSv1.3_2025."
  }
}

# Default cache behavior.
variable "viewer_protocol_policy" {
  type        = string
  description = "redirect-to-https (default) or https-only. allow-all is not accepted"
  default     = "redirect-to-https"

  validation {
    condition     = contains(["redirect-to-https", "https-only"], var.viewer_protocol_policy)
    error_message = "viewer_protocol_policy must be redirect-to-https or https-only."
  }
}

variable "allowed_methods" {
  type        = list(string)
  description = "Methods CloudFront forwards: [GET, HEAD], [GET, HEAD, OPTIONS] (default) or all seven. Cloud Posse defaults to all seven; an OAC S3 origin is read-only here"
  default     = ["GET", "HEAD", "OPTIONS"]

  validation {
    condition     = contains(["GET,HEAD", "GET,HEAD,OPTIONS", "DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT"], join(",", sort(var.allowed_methods)))
    error_message = "allowed_methods must be [GET, HEAD], [GET, HEAD, OPTIONS] or [DELETE, GET, HEAD, OPTIONS, PATCH, POST, PUT]."
  }
}

variable "cached_methods" {
  type        = list(string)
  description = "Methods whose responses are cached: [GET, HEAD] (default) or [GET, HEAD, OPTIONS]"
  default     = ["GET", "HEAD"]

  validation {
    condition     = contains(["GET,HEAD", "GET,HEAD,OPTIONS"], join(",", sort(var.cached_methods)))
    error_message = "cached_methods must be [GET, HEAD] or [GET, HEAD, OPTIONS]."
  }
}

variable "compress" {
  type        = bool
  description = "Compress objects for viewers that accept gzip or brotli"
  default     = true
}

variable "cache_policy_id" {
  type        = string
  description = "Cache policy: a managed policy name (CachingOptimized, the default; CachingOptimizedForUncompressedObjects, CachingDisabled, UseOriginCacheControlHeaders, UseOriginCacheControlHeaders-QueryStrings) or a policy ID"
  default     = "CachingOptimized"

  validation {
    condition     = contains(["CachingOptimized", "CachingOptimizedForUncompressedObjects", "CachingDisabled", "UseOriginCacheControlHeaders", "UseOriginCacheControlHeaders-QueryStrings"], var.cache_policy_id) || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.cache_policy_id))
    error_message = "cache_policy_id must be a managed cache policy name (CachingOptimized, CachingOptimizedForUncompressedObjects, CachingDisabled, UseOriginCacheControlHeaders, UseOriginCacheControlHeaders-QueryStrings) or a policy ID (UUID)."
  }
}

variable "origin_request_policy_id" {
  type        = string
  description = "Origin request policy: null (default, none), a managed policy name (AllViewer, AllViewerAndCloudFrontHeaders-2022-06, AllViewerExceptHostHeader, CORS-CustomOrigin, CORS-S3Origin, HostHeaderOnly, UserAgentRefererHeaders) or a policy ID"
  default     = null

  validation {
    condition     = var.origin_request_policy_id == null || contains(["AllViewer", "AllViewerAndCloudFrontHeaders-2022-06", "AllViewerExceptHostHeader", "CORS-CustomOrigin", "CORS-S3Origin", "HostHeaderOnly", "UserAgentRefererHeaders"], coalesce(var.origin_request_policy_id, "-")) || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", coalesce(var.origin_request_policy_id, "-")))
    error_message = "origin_request_policy_id must be null, a managed origin request policy name (AllViewer, AllViewerAndCloudFrontHeaders-2022-06, AllViewerExceptHostHeader, CORS-CustomOrigin, CORS-S3Origin, HostHeaderOnly, UserAgentRefererHeaders) or a policy ID (UUID)."
  }
}

variable "response_headers_policy_id" {
  type        = string
  description = "Response headers policy: a managed policy name (SecurityHeadersPolicy, the default; CORS-and-SecurityHeadersPolicy, CORS-With-Preflight, CORS-with-preflight-and-SecurityHeadersPolicy, SimpleCORS), a policy ID, or null for none"
  default     = "SecurityHeadersPolicy"

  validation {
    condition     = var.response_headers_policy_id == null || contains(["SecurityHeadersPolicy", "CORS-and-SecurityHeadersPolicy", "CORS-With-Preflight", "CORS-with-preflight-and-SecurityHeadersPolicy", "SimpleCORS"], coalesce(var.response_headers_policy_id, "-")) || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", coalesce(var.response_headers_policy_id, "-")))
    error_message = "response_headers_policy_id must be null, a managed response headers policy name (SecurityHeadersPolicy, CORS-and-SecurityHeadersPolicy, CORS-With-Preflight, CORS-with-preflight-and-SecurityHeadersPolicy, SimpleCORS) or a policy ID (UUID)."
  }
}

# Error responses.
variable "custom_error_response" {
  type = list(object({
    error_caching_min_ttl = optional(number, null)
    error_code            = number
    response_code         = optional(number, null)
    response_page_path    = optional(string, null)
  }))
  description = "Custom error responses, Cloud Posse's custom_error_response (one per error_code)"
  default     = []
  nullable    = false

  validation {
    condition     = length(distinct([for r in var.custom_error_response : r.error_code])) == length(var.custom_error_response)
    error_message = "Each custom_error_response needs a unique error_code."
  }

  validation {
    condition     = alltrue([for r in var.custom_error_response : contains([400, 403, 404, 405, 414, 416, 500, 501, 502, 503, 504], r.error_code)])
    error_message = "custom_error_response error_code must be one CloudFront can customize: 400, 403, 404, 405, 414, 416, 500, 501, 502, 503 or 504."
  }

  validation {
    condition     = alltrue([for r in var.custom_error_response : r.response_page_path == null || can(regex("^/", coalesce(r.response_page_path, "-"))) && r.response_code != null])
    error_message = "A custom_error_response response_page_path must start with / and needs a response_code."
  }
}

variable "enable_spa_fallback" {
  type        = bool
  description = "Single-page app routing: answer S3's 403 and 404 with 200 and /<default_root_object>, uncached. Cannot be combined with a custom_error_response for 403 or 404"
  default     = false

  validation {
    condition     = !var.enable_spa_fallback || length([for r in var.custom_error_response : r if contains([403, 404], r.error_code)]) == 0
    error_message = "enable_spa_fallback sets the 403 and 404 error responses itself: remove them from custom_error_response."
  }
}

# Protection.
variable "web_acl_id" {
  type        = string
  description = "ARN of a CLOUDFRONT-scope WAFv2 web ACL (the waf component's arn, scope CLOUDFRONT, in us-east-1). Null for none"
  default     = null

  validation {
    condition     = var.web_acl_id == null || can(regex("^arn:aws[a-z-]*:wafv2:us-east-1:[0-9]{12}:global/webacl/[A-Za-z0-9_-]+/[0-9a-f-]+$", var.web_acl_id))
    error_message = "web_acl_id must be a CLOUDFRONT-scope WAFv2 web ACL ARN (arn:aws:wafv2:us-east-1:<account>:global/webacl/<name>/<id>), not a REGIONAL ACL or a WAF Classic ID."
  }
}

variable "geo_restriction_type" {
  type        = string
  description = "none (default), whitelist or blacklist (Cloud Posse's geo_restriction_type)"
  default     = "none"

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], var.geo_restriction_type)
    error_message = "geo_restriction_type must be none, whitelist or blacklist."
  }
}

variable "geo_restriction_locations" {
  type        = list(string)
  description = "ISO 3166-1 alpha-2 country codes for geo_restriction_type whitelist or blacklist; empty for none"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.geo_restriction_locations : can(regex("^[A-Z]{2}$", c))])
    error_message = "geo_restriction_locations must be uppercase ISO 3166-1 alpha-2 country codes (e.g. US, DE)."
  }

  validation {
    condition     = (var.geo_restriction_type == "none") == (length(var.geo_restriction_locations) == 0)
    error_message = "geo_restriction_locations must be empty for geo_restriction_type none and non-empty for whitelist or blacklist."
  }
}

# Logging: standard logging v2 (CloudWatch Logs delivery) to S3.
variable "logging_enabled" {
  type        = bool
  description = "Deliver access logs (standard logging v2) to access_log_bucket_arn"
  default     = false
}

variable "access_log_bucket_arn" {
  type        = string
  description = "ARN of the bucket that receives access logs (logging_enabled). Its policy must let delivery.logs.amazonaws.com write (see README)"
  default     = null

  validation {
    condition     = var.access_log_bucket_arn == null || can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", coalesce(var.access_log_bucket_arn, "-")))
    error_message = "access_log_bucket_arn must be an S3 bucket ARN (arn:aws:s3:::<bucket>)."
  }

  validation {
    condition     = !var.logging_enabled || var.access_log_bucket_arn != null
    error_message = "logging_enabled needs access_log_bucket_arn."
  }
}

variable "log_prefix" {
  type        = string
  description = "Suffix path of the delivered log objects in the bucket (logging v2 s3 suffix_path, at most 256 characters, no leading /); null uses the CloudWatch Logs default"
  default     = null

  validation {
    condition     = var.log_prefix == null || can(regex("^[^/].{0,255}$", coalesce(var.log_prefix, "-")))
    error_message = "log_prefix must be 1-256 characters and must not start with /."
  }
}

variable "log_output_format" {
  type        = string
  description = "Access log format: json (default), w3c, plain or parquet"
  default     = "json"

  validation {
    condition     = contains(["json", "w3c", "plain", "parquet"], var.log_output_format)
    error_message = "log_output_format must be json, w3c, plain or parquet."
  }
}

# DNS: Cloud Posse's dns_alias_enabled / parent_zone_id.
variable "dns_alias_enabled" {
  type        = bool
  description = "Create an A (and with ipv6_enabled an AAAA) alias record to the distribution for each alias in parent_zone_id"
  default     = false
}

variable "parent_zone_id" {
  type        = string
  description = "Route 53 hosted zone ID the alias records go in (a dns instance's zone_ids.<key>); required with dns_alias_enabled"
  default     = null

  validation {
    condition     = var.parent_zone_id == null || can(regex("^Z[A-Z0-9]{1,31}$", coalesce(var.parent_zone_id, "-")))
    error_message = "parent_zone_id must be a Route 53 hosted zone ID (Z...)."
  }

  validation {
    condition     = !var.dns_alias_enabled || var.parent_zone_id != null && length(var.aliases) > 0
    error_message = "dns_alias_enabled needs parent_zone_id and at least one alias."
  }
}

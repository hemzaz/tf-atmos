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

# S3 origin. Cloud Posse's origin_bucket is a bucket name; this is the s3
# component's bucket_regional_domain_name output, from which the bucket name
# is derived. Null for a distribution of custom origins only (upstream always
# has its S3 origin).
variable "origin_bucket_regional_domain_name" {
  type        = string
  description = "Regional domain name of the S3 origin bucket (<bucket>.s3.<region>.amazonaws.com; the s3 component's bucket_regional_domain_name), reached through an origin access control. Null for no S3 origin: custom_origins only, with default_origin_id. The component does not own the bucket: merge s3_origin_policy_json into its policy"
  default     = null

  validation {
    condition     = var.origin_bucket_regional_domain_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]\\.s3\\.[a-z0-9-]+\\.amazonaws\\.com$", coalesce(var.origin_bucket_regional_domain_name, "-")))
    error_message = "origin_bucket_regional_domain_name must be an S3 bucket regional domain name (<bucket>.s3.<region>.amazonaws.com), not a bucket name, an ARN or a website endpoint."
  }
}

variable "origin_path" {
  type        = string
  description = "Path in the S3 origin bucket CloudFront requests objects from (Cloud Posse's origin_path): empty, or /<path> without a trailing slash"
  default     = ""
  nullable    = false

  validation {
    condition     = var.origin_path == "" || can(regex("^/[^*?]*[^/]$", var.origin_path))
    error_message = "origin_path must be empty or start with / and not end with /."
  }
}

# Custom origins: Cloud Posse's custom_origins (ALB, API Gateway, any HTTP
# server). Deviations: custom_origin_config is optional (all its fields have
# defaults), origin_access_control_id and response_completion_timeout are not
# modelled, and custom header values are redacted from plans.
variable "custom_origins" {
  type = list(object({
    domain_name = string
    origin_id   = string
    origin_path = optional(string, "")
    custom_headers = optional(list(object({
      name  = string
      value = string
    })), [])
    custom_origin_config = optional(object({
      http_port                = optional(number, 80)
      https_port               = optional(number, 443)
      origin_protocol_policy   = optional(string, "https-only")
      origin_ssl_protocols     = optional(list(string), ["TLSv1.2"])
      origin_keepalive_timeout = optional(number, 5)
      origin_read_timeout      = optional(number, 30)
    }), {})
    origin_shield = optional(object({
      enabled = optional(bool, false)
      region  = optional(string, null)
    }), null)
  }))
  description = "Custom (non-S3) origins, Cloud Posse's custom_origins: domain_name (a host name, no scheme or path), origin_id (unique; what default_origin_id and ordered_cache target_origin_id name), origin_path, custom_headers (sent to the origin on every request; an ALB origin gets a secret origin-verify header its listener rule requires, see README), custom_origin_config (https-only and TLSv1.2 by default; read timeout 30 s and keepalive 5 s by default, 1-180 s, above 60 s needs a CloudFront quota increase) and origin_shield"
  default     = []
  nullable    = false

  validation {
    condition     = length(distinct([for o in var.custom_origins : o.origin_id])) == length(var.custom_origins) && !contains([for o in var.custom_origins : o.origin_id], "s3-${lookup(var.tags, "Environment", "")}-${var.name}")
    error_message = "custom_origins origin_id values must be unique and must not be the S3 origin's id (s3-<Environment>-<name>)."
  }

  validation {
    condition     = alltrue([for o in var.custom_origins : can(regex("^[A-Za-z0-9_.-]{1,128}$", o.origin_id))])
    error_message = "Each custom_origins origin_id must be 1-128 characters of letters, digits, period, underscore or hyphen."
  }

  validation {
    condition     = alltrue([for o in var.custom_origins : can(regex("^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z]{2,63}$", o.domain_name))])
    error_message = "Each custom_origins domain_name must be a host name (e.g. app.example.com), without a scheme, port, path or trailing dot."
  }

  validation {
    condition     = alltrue([for o in var.custom_origins : o.origin_path == "" || can(regex("^/[^*?]*[^/]$", o.origin_path))])
    error_message = "Each custom_origins origin_path must be empty or start with / and not end with /."
  }

  validation {
    condition     = alltrue([for o in var.custom_origins : contains(["https-only", "http-only", "match-viewer"], o.custom_origin_config.origin_protocol_policy)])
    error_message = "custom_origin_config origin_protocol_policy must be https-only (default), http-only or match-viewer."
  }

  validation {
    condition     = alltrue([for o in var.custom_origins : length(o.custom_origin_config.origin_ssl_protocols) > 0 && length(setsubtract(o.custom_origin_config.origin_ssl_protocols, ["TLSv1", "TLSv1.1", "TLSv1.2"])) == 0])
    error_message = "custom_origin_config origin_ssl_protocols must be a non-empty subset of TLSv1, TLSv1.1 and TLSv1.2 (SSLv3 is rejected); the default is [TLSv1.2]."
  }

  validation {
    condition     = alltrue(flatten([for o in var.custom_origins : [for p in [o.custom_origin_config.http_port, o.custom_origin_config.https_port] : contains([80, 443], p) || (p >= 1024 && p <= 65535)]]))
    error_message = "custom_origin_config http_port and https_port must be 80, 443 or 1024-65535 (the ports CloudFront connects to)."
  }

  validation {
    condition     = alltrue(flatten([for o in var.custom_origins : [for t in [o.custom_origin_config.origin_read_timeout, o.custom_origin_config.origin_keepalive_timeout] : t >= 1 && t <= 180 && floor(t) == t]]))
    error_message = "custom_origin_config origin_read_timeout and origin_keepalive_timeout must be whole seconds from 1 to 180 (above 60 needs a CloudFront quota increase)."
  }

  validation {
    condition     = alltrue([for o in var.custom_origins : !try(o.origin_shield.enabled, false) || can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", o.origin_shield.region))])
    error_message = "An enabled origin_shield needs region, an AWS region name (e.g. us-east-1)."
  }

  validation {
    condition     = alltrue([for o in var.custom_origins : length(o.custom_headers) <= 10 && length(distinct([for h in o.custom_headers : lower(h.name)])) == length(o.custom_headers) && alltrue([for h in o.custom_headers : can(regex("^[A-Za-z0-9-]{1,128}$", h.name))])])
    error_message = "Each custom origin takes at most 10 custom_headers with unique names of letters, digits and hyphens."
  }
}

variable "default_origin_id" {
  type        = string
  description = "Origin the default cache behavior targets: \"\" (default) for the S3 origin, or the origin_id of one of custom_origins (required without an S3 origin)"
  default     = ""
  nullable    = false

  validation {
    condition     = contains(concat(var.origin_bucket_regional_domain_name == null ? [] : [""], [for o in var.custom_origins : o.origin_id]), var.default_origin_id)
    error_message = "default_origin_id must be \"\" for the S3 origin (needs origin_bucket_regional_domain_name) or the origin_id of one of custom_origins."
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
  description = "Object returned for the root URL, and the page the SPA fallback serves. Null (default) uses index.html (Cloud Posse's default) when the default behavior targets the S3 origin, and none when it targets a custom origin, which serves / itself"
  default     = null

  validation {
    condition     = var.default_root_object == null || can(regex("^[^/][^\\s]*$", coalesce(var.default_root_object, "-")))
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

# Edge functions on the default cache behavior (Cloud Posse's
# function_association and lambda_function_association).
variable "function_association" {
  type = list(object({
    event_type   = string
    function_arn = string
  }))
  description = "CloudFront Functions on the default cache behavior: event_type viewer-request or viewer-response (one function each), function_arn arn:aws:cloudfront::<account>:function/<name>"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for f in var.function_association : contains(["viewer-request", "viewer-response"], f.event_type) && can(regex("^arn:aws[a-z-]*:cloudfront::[0-9]{12}:function/[A-Za-z0-9_-]{1,64}$", f.function_arn))])
    error_message = "Each function_association needs event_type viewer-request or viewer-response and a CloudFront Function ARN (arn:aws:cloudfront::<account>:function/<name>)."
  }

  validation {
    condition     = length(distinct([for f in var.function_association : f.event_type])) == length(var.function_association)
    error_message = "function_association takes at most one function per event type (so at most 2)."
  }
}

variable "lambda_function_association" {
  type = list(object({
    event_type   = string
    include_body = optional(bool, false)
    lambda_arn   = string
  }))
  description = "Lambda@Edge functions on the default cache behavior: event_type viewer-request, viewer-response, origin-request or origin-response (one function each, a viewer event not also used by function_association), lambda_arn a version-qualified us-east-1 function ARN (arn:aws:lambda:us-east-1:<account>:function:<name>:<version>, not $LATEST or an alias), include_body for request events"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for l in var.lambda_function_association : contains(["viewer-request", "viewer-response", "origin-request", "origin-response"], l.event_type)])
    error_message = "lambda_function_association event_type must be viewer-request, viewer-response, origin-request or origin-response."
  }

  validation {
    condition     = alltrue([for l in var.lambda_function_association : can(regex("^arn:aws[a-z-]*:lambda:us-east-1:[0-9]{12}:function:[A-Za-z0-9_-]{1,64}:[0-9]+$", l.lambda_arn))])
    error_message = "lambda_function_association lambda_arn must be a version-qualified Lambda function ARN in us-east-1 (arn:aws:lambda:us-east-1:<account>:function:<name>:<version>); $LATEST, aliases and other regions are not accepted by Lambda@Edge."
  }

  validation {
    condition     = length(distinct([for l in var.lambda_function_association : l.event_type])) == length(var.lambda_function_association)
    error_message = "lambda_function_association takes at most one function per event type."
  }

  validation {
    condition     = alltrue([for l in var.lambda_function_association : !l.include_body || endswith(l.event_type, "-request")])
    error_message = "lambda_function_association include_body applies to viewer-request and origin-request only."
  }

  validation {
    condition     = length(setintersection([for l in var.lambda_function_association : l.event_type], [for f in var.function_association : f.event_type])) == 0
    error_message = "A viewer event takes a CloudFront Function or a Lambda@Edge function, not both: an event_type is in both function_association and lambda_function_association."
  }
}

# Ordered cache behaviors: Cloud Posse's ordered_cache, matched in list order
# before the default behavior. Deviations: cache, origin request and response
# headers policies only (no TTLs or forwarded_values, trusted signers, gRPC or
# real-time logs); the defaults match this component's default behavior
# (GET/HEAD/OPTIONS, compress, CachingOptimized, SecurityHeadersPolicy; "" for
# no response headers policy) instead of upstream's (all methods, no
# compression, forwarded_values); viewer_protocol_policy cannot be allow-all.
variable "ordered_cache" {
  type = list(object({
    path_pattern               = string
    target_origin_id           = optional(string, "")
    viewer_protocol_policy     = optional(string, "redirect-to-https")
    allowed_methods            = optional(list(string), ["GET", "HEAD", "OPTIONS"])
    cached_methods             = optional(list(string), ["GET", "HEAD"])
    compress                   = optional(bool, true)
    cache_policy_id            = optional(string, "CachingOptimized")
    origin_request_policy_id   = optional(string, null)
    response_headers_policy_id = optional(string, "SecurityHeadersPolicy")
    function_association = optional(list(object({
      event_type   = string
      function_arn = string
    })), [])
    lambda_function_association = optional(list(object({
      event_type   = string
      include_body = optional(bool, false)
      lambda_arn   = string
    })), [])
  }))
  description = "Ordered cache behaviors (Cloud Posse's ordered_cache), first match wins: path_pattern (unique), target_origin_id (\"\" for the S3 origin, or a custom_origins origin_id), viewer_protocol_policy, allowed_methods, cached_methods, compress, cache_policy_id / origin_request_policy_id / response_headers_policy_id (managed names or IDs, as on the default behavior; response_headers_policy_id \"\" for none), function_association and lambda_function_association (as the top-level variables)"
  default     = []
  nullable    = false

  validation {
    condition     = length(distinct([for c in var.ordered_cache : c.path_pattern])) == length(var.ordered_cache)
    error_message = "ordered_cache path_pattern values must be unique."
  }

  validation {
    condition     = alltrue([for c in var.ordered_cache : can(regex("^[^\\s]{1,255}$", c.path_pattern))])
    error_message = "Each ordered_cache path_pattern must be 1-255 characters without spaces (e.g. /api/*)."
  }

  validation {
    condition     = alltrue([for c in var.ordered_cache : contains(concat(var.origin_bucket_regional_domain_name == null ? [] : [""], [for o in var.custom_origins : o.origin_id]), c.target_origin_id)])
    error_message = "Each ordered_cache target_origin_id must be \"\" for the S3 origin (needs origin_bucket_regional_domain_name) or the origin_id of one of custom_origins."
  }

  validation {
    condition     = alltrue([for c in var.ordered_cache : contains(["redirect-to-https", "https-only"], c.viewer_protocol_policy)])
    error_message = "ordered_cache viewer_protocol_policy must be redirect-to-https (default) or https-only; allow-all is not accepted."
  }

  validation {
    condition     = alltrue([for c in var.ordered_cache : contains(["GET,HEAD", "GET,HEAD,OPTIONS", "DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT"], join(",", sort(c.allowed_methods))) && contains(["GET,HEAD", "GET,HEAD,OPTIONS"], join(",", sort(c.cached_methods)))])
    error_message = "ordered_cache allowed_methods must be [GET, HEAD], [GET, HEAD, OPTIONS] or all seven methods, and cached_methods [GET, HEAD] or [GET, HEAD, OPTIONS]."
  }

  validation {
    condition     = alltrue([for c in var.ordered_cache : contains(["CachingOptimized", "CachingOptimizedForUncompressedObjects", "CachingDisabled", "UseOriginCacheControlHeaders", "UseOriginCacheControlHeaders-QueryStrings"], c.cache_policy_id) || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", c.cache_policy_id))])
    error_message = "ordered_cache cache_policy_id must be a managed cache policy name (CachingOptimized, CachingOptimizedForUncompressedObjects, CachingDisabled, UseOriginCacheControlHeaders, UseOriginCacheControlHeaders-QueryStrings) or a policy ID (UUID)."
  }

  validation {
    condition     = alltrue([for c in var.ordered_cache : c.origin_request_policy_id == null || contains(["AllViewer", "AllViewerAndCloudFrontHeaders-2022-06", "AllViewerExceptHostHeader", "CORS-CustomOrigin", "CORS-S3Origin", "HostHeaderOnly", "UserAgentRefererHeaders"], coalesce(c.origin_request_policy_id, "-")) || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", coalesce(c.origin_request_policy_id, "-")))])
    error_message = "ordered_cache origin_request_policy_id must be null, a managed origin request policy name (AllViewer, AllViewerAndCloudFrontHeaders-2022-06, AllViewerExceptHostHeader, CORS-CustomOrigin, CORS-S3Origin, HostHeaderOnly, UserAgentRefererHeaders) or a policy ID (UUID)."
  }

  validation {
    condition     = alltrue([for c in var.ordered_cache : contains(["", "SecurityHeadersPolicy", "CORS-and-SecurityHeadersPolicy", "CORS-With-Preflight", "CORS-with-preflight-and-SecurityHeadersPolicy", "SimpleCORS"], c.response_headers_policy_id) || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", c.response_headers_policy_id))])
    error_message = "ordered_cache response_headers_policy_id must be \"\" (none), a managed response headers policy name (SecurityHeadersPolicy, CORS-and-SecurityHeadersPolicy, CORS-With-Preflight, CORS-with-preflight-and-SecurityHeadersPolicy, SimpleCORS) or a policy ID (UUID)."
  }

  validation {
    condition     = alltrue(flatten([for c in var.ordered_cache : [for f in c.function_association : contains(["viewer-request", "viewer-response"], f.event_type) && can(regex("^arn:aws[a-z-]*:cloudfront::[0-9]{12}:function/[A-Za-z0-9_-]{1,64}$", f.function_arn))]]))
    error_message = "Each ordered_cache function_association needs event_type viewer-request or viewer-response and a CloudFront Function ARN (arn:aws:cloudfront::<account>:function/<name>)."
  }

  validation {
    condition     = alltrue(flatten([for c in var.ordered_cache : [for l in c.lambda_function_association : contains(["viewer-request", "viewer-response", "origin-request", "origin-response"], l.event_type) && can(regex("^arn:aws[a-z-]*:lambda:us-east-1:[0-9]{12}:function:[A-Za-z0-9_-]{1,64}:[0-9]+$", l.lambda_arn)) && (!l.include_body || endswith(l.event_type, "-request"))]]))
    error_message = "Each ordered_cache lambda_function_association needs an event_type (viewer-request, viewer-response, origin-request, origin-response), a version-qualified us-east-1 Lambda ARN (arn:aws:lambda:us-east-1:<account>:function:<name>:<version>; not $LATEST, an alias or another region), and include_body only on request events."
  }

  validation {
    condition     = alltrue([for c in var.ordered_cache : length(distinct([for f in c.function_association : f.event_type])) == length(c.function_association) && length(distinct([for l in c.lambda_function_association : l.event_type])) == length(c.lambda_function_association) && length(setintersection([for l in c.lambda_function_association : l.event_type], [for f in c.function_association : f.event_type])) == 0])
    error_message = "Each ordered_cache behavior takes at most one function per event type (so at most 2 CloudFront Functions), and a viewer event takes a CloudFront Function or a Lambda@Edge function, not both."
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
  description = "Single-page app routing: answer S3's 403 and 404 with 200 and /<default_root_object>, uncached. Cannot be combined with a custom_error_response for 403 or 404; with a custom default origin it needs default_root_object"
  default     = false

  validation {
    condition     = !var.enable_spa_fallback || length([for r in var.custom_error_response : r if contains([403, 404], r.error_code)]) == 0
    error_message = "enable_spa_fallback sets the 403 and 404 error responses itself: remove them from custom_error_response."
  }

  validation {
    condition     = !var.enable_spa_fallback || var.default_origin_id == "" || var.default_root_object != null
    error_message = "enable_spa_fallback with a custom default origin needs default_root_object (the page it serves)."
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

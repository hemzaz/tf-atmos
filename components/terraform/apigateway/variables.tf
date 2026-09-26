variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "assume_role_arn" {
  type        = string
  description = "ARN of the IAM role to assume"
  default     = null
}

variable "enabled" {
  type        = bool
  description = "Whether to create the resources. Set to false to avoid creating resources"
  default     = true
}

variable "api_name" {
  type        = string
  description = "Name of the API Gateway"
}

variable "api_type" {
  type        = string
  description = "Type of API Gateway to create - REST or HTTP"
  default     = "REST"
  validation {
    condition     = contains(["REST", "HTTP"], var.api_type)
    error_message = "API type must be either 'REST' or 'HTTP'."
  }
}

variable "description" {
  type        = string
  description = "Description of the API Gateway"
  default     = "API Gateway managed by Terraform"
}

variable "endpoint_type" {
  type        = list(string)
  description = "List of endpoint types for the REST API Gateway, for HTTP API Gateway this is always REGIONAL"
  default     = ["REGIONAL"]
  validation {
    condition     = alltrue([for type in var.endpoint_type : contains(["REGIONAL", "EDGE", "PRIVATE"], type)])
    error_message = "Endpoint type must be one of 'REGIONAL', 'EDGE', or 'PRIVATE'."
  }
}

variable "stage_name" {
  type        = string
  description = "Name of the API Gateway stage"
  default     = "v1"
}

variable "auto_deploy" {
  type        = bool
  description = "Whether to automatically deploy the API (HTTP API only)"
  default     = true
}

variable "domain_name" {
  type        = string
  description = "Custom domain name for the API Gateway"
  default     = null
}

variable "certificate_arn" {
  type        = string
  description = "ARN of the ACM certificate for the custom domain name"
  default     = null
}

variable "base_path" {
  type        = string
  description = "Base path mapping for the custom domain"
  default     = null
}

variable "zone_id" {
  type        = string
  description = "Route53 zone ID for the custom domain name"
  default     = null
}

variable "enable_logging" {
  type        = bool
  description = "Whether to enable CloudWatch logging for the API Gateway"
  default     = true
}

variable "log_format" {
  type        = string
  description = "Log format for CloudWatch logs"
  default     = "{ \"requestId\":\"$context.requestId\", \"ip\": \"$context.identity.sourceIp\", \"requestTime\":\"$context.requestTime\", \"httpMethod\":\"$context.httpMethod\", \"routeKey\":\"$context.routeKey\", \"status\":\"$context.status\", \"protocol\":\"$context.protocol\", \"responseLength\":\"$context.responseLength\", \"integrationError\":\"$context.integrationErrorMessage\" }"
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain CloudWatch logs"
  default     = 7
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for CloudWatch logs encryption"
  default     = null
}

variable "cors_configuration" {
  type = object({
    allow_origins     = list(string)
    allow_methods     = list(string)
    allow_headers     = list(string)
    expose_headers    = list(string)
    max_age           = number
    allow_credentials = bool
  })
  description = "CORS configuration for an HTTP API; null for none. REST APIs ignore it"
  default     = null

  # Browsers refuse a credentialed response whose Access-Control-Allow-Origin
  # is "*", and API Gateway rejects the combination on HTTP APIs.
  validation {
    condition     = var.cors_configuration == null ? true : !(var.cors_configuration.allow_credentials && contains(var.cors_configuration.allow_origins, "*"))
    error_message = "cors_configuration cannot set allow_credentials = true with \"*\" in allow_origins; list the origins explicitly."
  }

  validation {
    condition     = var.cors_configuration == null ? true : (var.cors_configuration.max_age >= 0 && var.cors_configuration.max_age <= 86400)
    error_message = "cors_configuration.max_age must be between 0 and 86400 seconds."
  }
}

variable "vpc_link_subnet_ids" {
  type        = list(string)
  description = "Private subnets for an HTTP API VPC link; empty creates no VPC link. REST APIs ignore it"
  default     = []

  validation {
    condition     = alltrue([for s in var.vpc_link_subnet_ids : can(regex("^subnet-[a-f0-9]+$", s))])
    error_message = "vpc_link_subnet_ids must be subnet IDs (subnet-...)."
  }
}

variable "vpc_link_security_group_ids" {
  type        = list(string)
  description = "Security groups for the HTTP API VPC link's network interfaces; required with vpc_link_subnet_ids"
  default     = []

  validation {
    condition     = alltrue([for s in var.vpc_link_security_group_ids : can(regex("^sg-[a-f0-9]+$", s))])
    error_message = "vpc_link_security_group_ids must be security group IDs (sg-...)."
  }

  validation {
    condition     = length(var.vpc_link_subnet_ids) == 0 || length(var.vpc_link_security_group_ids) > 0
    error_message = "vpc_link_security_group_ids is required when vpc_link_subnet_ids is set."
  }
}

variable "minimum_compression_size" {
  type        = number
  description = "Minimum compression size for the REST API"
  default     = -1
}

variable "api_key_source" {
  type        = string
  description = "Source of the API key for REST API requests"
  default     = "HEADER"
  validation {
    condition     = contains(["HEADER", "AUTHORIZER"], var.api_key_source)
    error_message = "API key source must be either 'HEADER' or 'AUTHORIZER'."
  }
}

variable "binary_media_types" {
  type        = list(string)
  description = "List of binary media types supported by the REST API"
  default     = []
}

variable "tracing_enabled" {
  type        = bool
  description = "Whether to enable X-Ray tracing; off by default because X-Ray bills per recorded trace, prod stacks opt in"
  default     = false
}

variable "create_usage_plan" {
  type        = bool
  description = "Whether to create a usage plan for the REST API"
  default     = false
}

variable "usage_plan_quota_limit" {
  type        = number
  description = "Maximum number of requests that can be made in a given time period"
  default     = 1000
}

variable "usage_plan_quota_offset" {
  type        = number
  description = "Number of requests subtracted from the quota limit at the beginning of the period"
  default     = 0
}

variable "usage_plan_quota_period" {
  type        = string
  description = "Time period in which the quota applies"
  default     = "MONTH"
  validation {
    condition     = contains(["DAY", "WEEK", "MONTH"], var.usage_plan_quota_period)
    error_message = "Usage plan quota period must be one of 'DAY', 'WEEK', or 'MONTH'."
  }
}

variable "usage_plan_throttle_burst_limit" {
  type        = number
  description = "Maximum rate at which tokens for usage plans bucket can be used"
  default     = 5
}

variable "usage_plan_throttle_rate_limit" {
  type        = number
  description = "Rate at which tokens for usage plans bucket are added"
  default     = 10
}

variable "create_api_key" {
  type        = bool
  description = "Whether to create an API key for the REST API"
  default     = false
}

variable "authorizer_type" {
  type        = string
  description = "Type of authorizer for the API Gateway"
  default     = null
  validation {
    condition     = var.authorizer_type == null ? true : contains(["COGNITO_USER_POOLS", "TOKEN", "JWT", "REQUEST"], var.authorizer_type)
    error_message = "Authorizer type must be one of 'COGNITO_USER_POOLS', 'TOKEN', 'JWT', or 'REQUEST'."
  }
}

variable "authorizer_identity_source" {
  type        = string
  description = "Source of the identity in an incoming request"
  default     = "method.request.header.Authorization"
}

variable "cognito_user_pool_arns" {
  type        = list(string)
  description = "List of Cognito user pool ARNs for the COGNITO_USER_POOLS authorizer"
  default     = []
}

variable "lambda_authorizer_uri" {
  type        = string
  description = "URI of the Lambda function for the TOKEN or REQUEST authorizer"
  default     = null
}

variable "lambda_authorizer_role_arn" {
  type        = string
  description = "ARN of the IAM role for the Lambda authorizer"
  default     = null
}

variable "jwt_audience" {
  type        = list(string)
  description = "List of allowed audiences for the JWT authorizer"
  default     = []
}

variable "jwt_issuer" {
  type        = string
  description = "Issuer URL for the JWT authorizer"
  default     = null
}

variable "api_resources" {
  type = list(object({
    path_part = string
    parent_id = optional(string)
  }))
  description = "List of resources for the REST API. Each entry becomes the path \"/<path_part>\" that api_methods and api_integrations address; pass parent_id only to hang a resource off an id owned by another component."
  default     = []

  validation {
    condition     = length(distinct([for r in var.api_resources : r.path_part])) == length(var.api_resources)
    error_message = "Each api_resources entry must have a unique path_part, because path_part is what api_methods address."
  }
}

variable "api_methods" {
  type = list(object({
    resource_path      = string
    http_method        = string
    authorization      = optional(string, "NONE")
    authorizer_id      = optional(string)
    api_key_required   = optional(bool, false)
    request_parameters = optional(map(bool), {})
  }))
  description = "List of methods for the REST API. Addressed by resource_path (\"/\" for the API root, \"/<path_part>\" for an api_resources entry) because a stack cannot know this API's resource IDs before apply. Every method needs a matching api_integrations entry with the same resource_path and http_method."
  default     = []

  validation {
    condition     = length(distinct([for m in var.api_methods : "${m.http_method} ${m.resource_path}"])) == length(var.api_methods)
    error_message = "Each api_methods entry must be a unique http_method + resource_path pair."
  }

  validation {
    condition     = alltrue([for m in var.api_methods : contains(["ANY", "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"], m.http_method)])
    error_message = "api_methods[*].http_method must be one of ANY, GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS."
  }

  validation {
    condition     = alltrue([for m in var.api_methods : contains(["NONE", "AWS_IAM", "CUSTOM", "COGNITO_USER_POOLS"], m.authorization)])
    error_message = "api_methods[*].authorization must be one of NONE, AWS_IAM, CUSTOM, COGNITO_USER_POOLS."
  }

  validation {
    condition = alltrue([
      for m in var.api_methods : contains(
        concat(["/"], [for r in var.api_resources : "/${r.path_part}"]),
        m.resource_path
      )
    ])
    error_message = "Every api_methods[*].resource_path must be \"/\" or \"/<path_part>\" of an api_resources entry. Known paths: ${join(", ", concat(["/"], [for r in var.api_resources : "/${r.path_part}"]))}."
  }

  validation {
    condition = alltrue([
      for m in var.api_methods : contains(
        [for i in var.api_integrations : "${i.http_method} ${i.resource_path}"],
        "${m.http_method} ${m.resource_path}"
      )
    ])
    error_message = "Every api_methods entry needs an api_integrations entry with the same http_method and resource_path, otherwise the method is deployed with nothing behind it."
  }

  validation {
    condition = alltrue([
      for m in var.api_methods :
      m.authorizer_id != null || var.authorizer_type == "COGNITO_USER_POOLS"
      if m.authorization == "COGNITO_USER_POOLS"
    ])
    error_message = "A method with authorization COGNITO_USER_POOLS needs either its own authorizer_id or authorizer_type set to COGNITO_USER_POOLS on this component."
  }

  validation {
    condition = alltrue([
      for m in var.api_methods :
      m.authorizer_id != null || var.authorizer_type == "TOKEN"
      if m.authorization == "CUSTOM"
    ])
    error_message = "A method with authorization CUSTOM needs either its own authorizer_id or authorizer_type set to TOKEN on this component."
  }
}

variable "api_integrations" {
  type = list(object({
    resource_path           = string
    http_method             = string
    integration_http_method = string
    type                    = string
    uri                     = optional(string)
    connection_type         = optional(string)
    connection_id           = optional(string)
    timeout_milliseconds    = optional(number, 29000)
    request_parameters      = optional(map(string), {})
    request_templates       = optional(map(string), {})
    lambda_function_name    = optional(string)
  }))
  description = "List of integrations for the REST API, one per api_methods entry, addressed by the same resource_path + http_method pair. An AWS_PROXY entry must also set lambda_function_name so this component can grant API Gateway permission to invoke it."
  default     = []

  validation {
    condition     = length(distinct([for i in var.api_integrations : "${i.http_method} ${i.resource_path}"])) == length(var.api_integrations)
    error_message = "Each api_integrations entry must be a unique http_method + resource_path pair."
  }

  validation {
    condition     = alltrue([for i in var.api_integrations : contains(["AWS", "AWS_PROXY", "HTTP", "HTTP_PROXY", "MOCK"], i.type)])
    error_message = "api_integrations[*].type must be one of AWS, AWS_PROXY, HTTP, HTTP_PROXY, MOCK."
  }

  validation {
    condition = alltrue([
      for i in var.api_integrations : i.uri != null && i.uri != ""
      if contains(["AWS", "AWS_PROXY", "HTTP", "HTTP_PROXY"], i.type)
    ])
    error_message = "An api_integrations entry of type AWS, AWS_PROXY, HTTP or HTTP_PROXY must set uri to the backend it forwards to. Only MOCK integrations may leave uri unset."
  }

  # Without a matching aws_lambda_permission, an AWS_PROXY integration deploys
  # clean and every call returns 500 with AccessDeniedException in the execution
  # log. Requiring the function name here means this component can create that
  # permission itself, so the failure cannot ship silently.
  validation {
    condition = alltrue([
      for i in var.api_integrations :
      i.lambda_function_name != null && i.lambda_function_name != ""
      if i.type == "AWS_PROXY"
    ])
    error_message = "An AWS_PROXY integration must set lambda_function_name. API Gateway cannot invoke a Lambda without a resource policy granting it, and the resulting 500 appears only at request time, not at apply."
  }

  validation {
    condition = alltrue([
      for i in var.api_integrations :
      i.lambda_function_name == null
      if i.type != "AWS_PROXY"
    ])
    error_message = "lambda_function_name only applies to an AWS_PROXY integration; remove it from entries of any other type."
  }
}

variable "http_routes" {
  type = map(object({
    integration_type          = string
    connection_type           = optional(string, "INTERNET")
    connection_id             = optional(string)
    integration_uri           = string
    integration_method        = optional(string, "ANY")
    timeout_milliseconds      = optional(number, 29000)
    lambda_function_name      = optional(string)
    authorization_type        = optional(string, "NONE")
    tls_server_name_to_verify = optional(string)
  }))
  description = "HTTP API routes, keyed by route_key (e.g. \"ANY /{proxy+}\"). HTTP_PROXY integrations typically set connection_type = \"VPC_LINK\" to reach the cluster (integration_uri = the target listener's ARN -- usually the alb-controller-ingress-group component's http_listener_arn/https_listener_arn output); connection_id defaults to this component's own VPC link (var.vpc_link_subnet_ids) when left null, or names a different VPC link explicitly. AWS_PROXY integrations forward to a Lambda (integration_uri = its invoke_arn). HTTP APIs only; a REST API (api_type = \"REST\") ignores it silently, the same way it ignores cors_configuration. tls_server_name_to_verify enables TLS on an HTTP_PROXY + VPC_LINK route to an HTTPS listener (e.g. alb-controller-ingress-group's https_listener_arn) -- the certificate's SAN to verify against; leave null for a plaintext HTTP_PROXY hop (e.g. http_listener_arn)."
  default     = {}

  validation {
    condition     = alltrue([for r in values(var.http_routes) : contains(["HTTP_PROXY", "AWS_PROXY"], r.integration_type)])
    error_message = "http_routes[*].integration_type must be HTTP_PROXY or AWS_PROXY."
  }

  validation {
    condition     = alltrue([for r in values(var.http_routes) : contains(["INTERNET", "VPC_LINK"], r.connection_type)])
    error_message = "http_routes[*].connection_type must be INTERNET or VPC_LINK."
  }

  # connection_id may be left null when this component creates its own VPC
  # link (vpc_link_subnet_ids set): the route then defaults to it (see
  # aws_apigatewayv2_integration.http_route in main.tf). Otherwise it must
  # name one explicitly.
  validation {
    condition = alltrue([
      for r in values(var.http_routes) :
      (r.connection_id != null && r.connection_id != "") || length(var.vpc_link_subnet_ids) > 0
      if r.connection_type == "VPC_LINK"
    ])
    error_message = "http_routes[*].connection_id (the VPC link id) is required when connection_type is VPC_LINK, unless this component creates its own VPC link (vpc_link_subnet_ids set), which routes default to when connection_id is left null."
  }

  # Without a matching aws_lambda_permission, an AWS_PROXY route deploys clean
  # and every call returns 500 with AccessDeniedException, visible only in the
  # execution log -- same reasoning as api_integrations' AWS_PROXY validation
  # above, so it is required here too.
  validation {
    condition = alltrue([
      for r in values(var.http_routes) :
      r.lambda_function_name != null && r.lambda_function_name != ""
      if r.integration_type == "AWS_PROXY"
    ])
    error_message = "http_routes[*] of integration_type AWS_PROXY must set lambda_function_name, so this component can grant it invoke permission."
  }

  validation {
    condition = alltrue([
      for r in values(var.http_routes) :
      r.lambda_function_name == null
      if r.integration_type != "AWS_PROXY"
    ])
    error_message = "lambda_function_name only applies to an AWS_PROXY route; remove it from entries of any other type."
  }

  validation {
    condition     = alltrue([for r in values(var.http_routes) : contains(["JWT", "NONE"], r.authorization_type)])
    error_message = "http_routes[*].authorization_type must be JWT or NONE."
  }

  # A JWT route uses this component's own JWT authorizer (var.authorizer_type
  # = "JWT"); there is no per-route authorizer override.
  validation {
    condition = alltrue([
      for r in values(var.http_routes) :
      var.authorizer_type == "JWT"
      if r.authorization_type == "JWT"
    ])
    error_message = "An http_routes entry with authorization_type JWT requires authorizer_type = \"JWT\" on this component; the route uses this component's own JWT authorizer."
  }

  # tls_config is only meaningful for a private (VPC_LINK) HTTP_PROXY
  # integration into an HTTPS listener; AWS_PROXY targets a Lambda (no TLS
  # hop to verify) and an INTERNET connection_type is already TLS-terminated
  # by API Gateway's own integration_uri (a public HTTPS endpoint), not a
  # private listener whose certificate this component verifies itself.
  validation {
    condition = alltrue([
      for r in values(var.http_routes) :
      r.integration_type == "HTTP_PROXY" && r.connection_type == "VPC_LINK"
      if r.tls_server_name_to_verify != null
    ])
    error_message = "http_routes[*].tls_server_name_to_verify only applies to an HTTP_PROXY route with connection_type = \"VPC_LINK\" (a private integration into an HTTPS listener)."
  }
}

variable "create_dashboard" {
  type        = bool
  description = "Whether to create a CloudWatch dashboard for the API Gateway"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to add to all resources. Environment is required because it is the name prefix for every resource this component creates."
  default     = {}

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

# WAF Configuration Variables
variable "enable_waf" {
  type        = bool
  description = "Whether to enable AWS WAF for the API Gateway"
  default     = false
}

variable "waf_rate_limit" {
  type        = number
  description = "The maximum number of requests per 5 minutes from a single IP"
  default     = 10000
  validation {
    condition     = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 2000000000
    error_message = "WAF rate limit must be between 100 and 2,000,000,000."
  }
}

variable "waf_common_rule_set_action" {
  type        = string
  description = "Action for the AWSManagedRulesCommonRuleSet group. 'block' lets the group apply its own rule actions; 'count' only records matches. Separate from waf_known_bad_inputs_action so soaking one group never silently relaxes the other."
  default     = "block"
  validation {
    condition     = contains(["block", "count"], var.waf_common_rule_set_action)
    error_message = "WAF common rule set action must be either 'block' or 'count'."
  }
}

variable "waf_known_bad_inputs_action" {
  type        = string
  description = "Action for the AWSManagedRulesKnownBadInputsRuleSet group. 'block' lets the group apply its own rule actions; 'count' only records matches, so this group can be soaked against real traffic before it is allowed to reject requests."
  default     = "block"
  validation {
    condition     = contains(["block", "count"], var.waf_known_bad_inputs_action)
    error_message = "WAF known bad inputs action must be either 'block' or 'count'."
  }
}

variable "allowed_countries" {
  type        = list(string)
  description = "List of country codes to allow access (empty list disables geo-blocking)"
  default     = []
  validation {
    condition     = alltrue([for country in var.allowed_countries : can(regex("^[A-Z]{2}$", country))])
    error_message = "Country codes must be 2-letter uppercase ISO country codes."
  }
}

# Caching Configuration Variables
variable "enable_caching" {
  type        = bool
  description = "Whether to enable caching for the API Gateway"
  default     = false
}

variable "cache_ttl_seconds" {
  type        = number
  description = "The time to live (TTL) period for cached responses in seconds"
  default     = 300
  validation {
    condition     = var.cache_ttl_seconds >= 0 && var.cache_ttl_seconds <= 3600
    error_message = "Cache TTL must be between 0 and 3600 seconds."
  }
}

# Throttling Configuration Variables
variable "throttling_rate_limit" {
  type        = number
  description = "The steady-state request rate limit (requests per second): REST method settings and the HTTP stage's default route settings"
  default     = 10000
  validation {
    condition     = var.throttling_rate_limit > 0
    error_message = "Throttling rate limit must be greater than 0."
  }
}

variable "throttling_burst_limit" {
  type        = number
  description = "The burst request rate limit (requests per second): REST method settings and the HTTP stage's default route settings"
  default     = 5000
  validation {
    condition     = var.throttling_burst_limit > 0
    error_message = "Throttling burst limit must be greater than 0."
  }
}

# Logging Configuration Variables
variable "logging_level" {
  type        = string
  description = "The logging level for API Gateway method execution"
  default     = "INFO"
  validation {
    condition     = contains(["OFF", "ERROR", "INFO"], var.logging_level)
    error_message = "Logging level must be one of: OFF, ERROR, INFO."
  }
}

variable "data_trace_enabled" {
  type        = bool
  description = "Whether to enable data trace logging for API Gateway"
  default     = false
}

variable "metrics_enabled" {
  type        = bool
  description = "Whether to enable CloudWatch metrics for API Gateway"
  default     = true
}

# Performance Monitoring Variables
variable "create_performance_alarms" {
  type        = bool
  description = "Whether to create CloudWatch alarms for API performance monitoring"
  default     = false
}

variable "alarm_4xx_threshold" {
  type        = number
  description = "Threshold for 4xx error alarm (number of errors in 5 minutes)"
  default     = 10
}

variable "alarm_5xx_threshold" {
  type        = number
  description = "Threshold for 5xx error alarm (number of errors in 5 minutes)"
  default     = 5
}

variable "alarm_latency_threshold" {
  type        = number
  description = "Threshold for latency alarm in milliseconds"
  default     = 1000
}

variable "sns_topic_arn" {
  type        = string
  description = "SNS topic ARN for sending alarm notifications"
  default     = null
}
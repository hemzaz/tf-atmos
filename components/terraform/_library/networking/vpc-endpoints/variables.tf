variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block (for security group ingress rules)"
  type        = string
}

variable "endpoints" {
  description = "Map of VPC endpoints to create"
  type = map(object({
    type                = string # "Gateway" or "Interface"
    subnet_ids          = optional(list(string), [])
    route_table_ids     = optional(list(string), [])
    security_group_ids  = optional(list(string), [])
    private_dns_enabled = optional(bool, true)
    policy              = optional(string)
    tags                = optional(map(string), {})
  }))

  validation {
    condition = alltrue([
      for k, v in var.endpoints :
      contains(["Gateway", "Interface"], v.type)
    ])
    error_message = "Endpoint type must be either 'Gateway' or 'Interface'."
  }

  validation {
    condition = alltrue([
      for k, v in var.endpoints :
      v.type == "Gateway" ? length(v.route_table_ids) > 0 : true
    ])
    error_message = "Gateway endpoints require route_table_ids."
  }

  validation {
    condition = alltrue([
      for k, v in var.endpoints :
      v.type == "Interface" ? length(v.subnet_ids) > 0 : true
    ])
    error_message = "Interface endpoints require subnet_ids."
  }

  validation {
    condition = alltrue([for k in keys(var.endpoints) : contains([
      "s3", "dynamodb", "ec2", "ec2messages", "ssm", "ssmmessages", "ecr_api", "ecr_dkr", "logs", "kms",
      "secretsmanager", "rds", "sns", "sqs", "lambda", "ecs", "ecs_agent", "ecs_telemetry",
      "elasticloadbalancing", "autoscaling", "athena", "cloudformation", "cloudtrail", "cloudwatch",
      "events", "execute_api", "kinesis_streams", "kinesis_firehose", "sagemaker_api", "sagemaker_runtime",
      "servicecatalog", "sts", "transfer", "glue", "sagemaker_notebook", "elasticache"
    ], k)])
    error_message = "Endpoint keys must be one of the services supported by this module (see local.service_names)."
  }
}

variable "subnet_ids_for_estimation" {
  description = "Subnet IDs used for cost estimation (typically private subnets across AZs)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

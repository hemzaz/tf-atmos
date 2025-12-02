# Additional variables for comprehensive monitoring and alarms

# RDS Monitoring Variables
variable "enable_rds_monitoring" {
  type        = bool
  description = "Enable comprehensive RDS monitoring"
  default     = false
}

variable "rds_storage_threshold" {
  type        = number
  description = "RDS free storage space alarm threshold in bytes"
  default     = 10737418240 # 10GB
}

variable "rds_cpu_threshold" {
  type        = number
  description = "RDS CPU utilization alarm threshold percentage"
  default     = 80
}

# Lambda Monitoring Variables
variable "lambda_throttle_monitoring" {
  type        = bool
  description = "Enable Lambda throttle monitoring"
  default     = false
}

variable "lambda_duration_monitoring" {
  type        = bool
  description = "Enable Lambda duration monitoring"
  default     = false
}

variable "lambda_duration_threshold" {
  type        = number
  description = "Lambda duration alarm threshold in milliseconds"
  default     = 10000
}

# EC2 Monitoring Variables
variable "enable_ec2_monitoring" {
  type        = bool
  description = "Enable EC2 instance monitoring"
  default     = false
}

variable "ec2_instance_ids" {
  type        = list(string)
  description = "List of EC2 instance IDs to monitor"
  default     = []
}

# EKS Monitoring Variables
variable "eks_min_node_count" {
  type        = number
  description = "Minimum healthy EKS node count"
  default     = 2
}

# API Gateway Monitoring Variables
variable "api_gateway_4xx_threshold" {
  type        = number
  description = "API Gateway 4XX error count threshold"
  default     = 100
}

# Network Monitoring Variables
variable "enable_network_monitoring" {
  type        = bool
  description = "Enable network monitoring (NAT Gateway, VPC Flow Logs)"
  default     = false
}

variable "nat_gateway_ids" {
  type        = list(string)
  description = "List of NAT Gateway IDs to monitor"
  default     = []
}

variable "nat_gateway_drop_threshold" {
  type        = number
  description = "NAT Gateway packet drop count threshold"
  default     = 1000
}

# Percentile Monitoring
variable "enable_percentile_alarms" {
  type        = bool
  description = "Enable percentile-based alarms (P95, P99)"
  default     = false
}

variable "alb_p99_response_time_threshold" {
  type        = number
  description = "ALB P99 response time threshold in seconds"
  default     = 2.0
}

# ECS Monitoring Variables
variable "enable_ecs_monitoring" {
  type        = bool
  description = "Enable ECS service monitoring"
  default     = false
}

variable "ecs_services" {
  type = map(object({
    cluster_name = string
    service_name = string
  }))
  description = "Map of ECS services to monitor"
  default     = {}
}

variable "ecs_cpu_threshold" {
  type        = number
  description = "ECS service CPU utilization threshold percentage"
  default     = 80
}

variable "ecs_memory_threshold" {
  type        = number
  description = "ECS service memory utilization threshold percentage"
  default     = 85
}

# DynamoDB Monitoring Variables
variable "enable_dynamodb_monitoring" {
  type        = bool
  description = "Enable DynamoDB table monitoring"
  default     = false
}

variable "dynamodb_tables" {
  type        = list(string)
  description = "List of DynamoDB table names to monitor"
  default     = []
}

variable "dynamodb_throttle_threshold" {
  type        = number
  description = "DynamoDB throttled requests threshold"
  default     = 10
}

# SQS Monitoring Variables
variable "enable_sqs_monitoring" {
  type        = bool
  description = "Enable SQS queue monitoring"
  default     = false
}

variable "sqs_queue_names" {
  type        = list(string)
  description = "List of SQS queue names to monitor"
  default     = []
}

variable "sqs_message_age_threshold" {
  type        = number
  description = "SQS message age threshold in seconds"
  default     = 3600 # 1 hour
}

# Anomaly Detection Variables
variable "anomaly_detection_namespace" {
  type        = string
  description = "CloudWatch namespace for anomaly detection"
  default     = "AWS/ApplicationELB"
}

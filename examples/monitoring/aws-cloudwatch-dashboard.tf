terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-west-2"
}

variable "dashboard_name" {
  type        = string
  description = "Name of the CloudWatch dashboard"
  default     = "system-overview"
}

variable "ec2_instances" {
  type        = list(string)
  description = "List of EC2 instance IDs to monitor"
  default     = []
}

variable "rds_instances" {
  type        = list(string)
  description = "List of RDS instance identifiers to monitor"
  default     = []
}

variable "lambda_functions" {
  type        = list(string)
  description = "List of Lambda function names to monitor"
  default     = []
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.dashboard_name
  
  dashboard_body = jsonencode({
    widgets = concat(
      # EC2 Metrics
      [
        for i, instance_id in var.ec2_instances : {
          type   = "metric"
          x      = (i * 6) % 24
          y      = floor(i / 4) * 6
          width  = 6
          height = 6
          properties = {
            metrics = [
              ["AWS/EC2", "CPUUtilization", "InstanceId", instance_id],
              [".", "NetworkIn", ".", "."],
              [".", "NetworkOut", ".", "."],
              [".", "DiskReadBytes", ".", "."],
              [".", "DiskWriteBytes", ".", "."]
            ]
            period = 300
            stat   = "Average"
            region = var.region
            title  = "EC2 Instance: ${instance_id}"
          }
        }
      ],
      
      # RDS Metrics
      [
        for i, db_identifier in var.rds_instances : {
          type   = "metric"
          x      = (i * 6) % 24
          y      = floor((i + length(var.ec2_instances)) / 4) * 6
          width  = 6
          height = 6
          properties = {
            metrics = [
              ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", db_identifier],
              [".", "DatabaseConnections", ".", "."],
              [".", "FreeStorageSpace", ".", "."],
              [".", "ReadIOPS", ".", "."],
              [".", "WriteIOPS", ".", "."]
            ]
            period = 300
            stat   = "Average"
            region = var.region
            title  = "RDS Instance: ${db_identifier}"
          }
        }
      ],
      
      # Lambda Metrics
      [
        for i, function_name in var.lambda_functions : {
          type   = "metric"
          x      = (i * 6) % 24
          y      = floor((i + length(var.ec2_instances) + length(var.rds_instances)) / 4) * 6
          width  = 6
          height = 6
          properties = {
            metrics = [
              ["AWS/Lambda", "Invocations", "FunctionName", function_name],
              [".", "Errors", ".", "."],
              [".", "Duration", ".", "."],
              [".", "Throttles", ".", "."]
            ]
            period = 300
            stat   = "Sum"
            region = var.region
            title  = "Lambda Function: ${function_name}"
          }
        }
      ],
      
      # System Overview
      [{
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# System Overview Dashboard\nThis dashboard provides a high-level overview of system resources and performance metrics."
        }
      }]
    )
  })
}

# CloudWatch Alarms for EC2 instances
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_high" {
  count               = length(var.ec2_instances)
  alarm_name          = "ec2-cpu-high-${var.ec2_instances[count.index]}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This metric monitors EC2 CPU utilization"
  alarm_actions       = []
  
  dimensions = {
    InstanceId = var.ec2_instances[count.index]
  }
}

# CloudWatch Alarms for RDS instances
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  count               = length(var.rds_instances)
  alarm_name          = "rds-cpu-high-${var.rds_instances[count.index]}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = []
  
  dimensions = {
    DBInstanceIdentifier = var.rds_instances[count.index]
  }
}

# CloudWatch Alarms for Lambda functions
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = length(var.lambda_functions)
  alarm_name          = "lambda-errors-${var.lambda_functions[count.index]}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = []
  
  dimensions = {
    FunctionName = var.lambda_functions[count.index]
  }
}

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${var.dashboard_name}"
}